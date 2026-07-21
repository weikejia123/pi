#!/usr/bin/env bash
# wake-state-agent.sh — 调用 pi agent 生成项目动态状态分析 agent.json
# 用法: ./wake-state-agent.sh <project_dir>
#
# 前置条件:
#   - .wake-project/ 目录存在（已扫描）
#   - .wake-project/base-llm.json 存在（已有项目身份分析）
#
# 输出: .wake-project/agent.json
set -euo pipefail

# ─── 固化配置 ─────────────────────────────────────────────────────────────────
PI_BIN="pi"
MODEL="ollama/qwen3.6:35b"
MAX_RETRIES=3
TOOLS="read,ls,find"
LOG_DIR="/Users/weikejia/.wake/logs"

# ─── 日志 ─────────────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/wake-state-agent.jsonl"

log() {
  local event="$1" detail="${2:-}"
  jq -cn \
    --arg ts "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
    --arg event "$event" \
    --arg project "${PROJECT_DIR:-}" \
    --arg model "$MODEL" \
    --arg detail "$detail" \
    '{ts: $ts, event: $event, project: $project, model: $model} + (if $detail != "" then {detail: $detail} else {} end)' \
    >> "$LOG_FILE"
}

# ─── 参数 ─────────────────────────────────────────────────────────────────────
PROJECT_DIR="${1:-}"
if [[ -z "$PROJECT_DIR" ]]; then
  echo "用法: $0 <project_dir>" >&2
  exit 1
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
WAKE_DIR="$PROJECT_DIR/.wake-project"
AGENT_JSON="$WAKE_DIR/agent.json"
BASE_LLM="$WAKE_DIR/base-llm.json"

# ─── 门卫 ─────────────────────────────────────────────────────────────────────
if [[ ! -d "$WAKE_DIR" ]]; then
  echo "⊘ 跳过: 无 .wake-project（未扫描）"
  log "skip" "no .wake-project directory"
  exit 0
fi
if [[ ! -f "$BASE_LLM" ]]; then
  echo "⊘ 跳过: 无 base-llm.json（未进行项目身份分析）"
  log "skip" "no base-llm.json"
  exit 0
fi

# ─── 归属标识：project_id 源自 project.json，scan_id 引用当前 scan.json ───────
PROJECT_ID="$(jq -r '.project_id // ""' "$WAKE_DIR/project.json" 2>/dev/null || true)"
SCAN_ID="$(jq -r '.scan_id // ""' "$WAKE_DIR/scan.json" 2>/dev/null || true)"

# ─── 采集动态上下文（注入 prompt） ────────────────────────────────────────────
GIT_LOG="$(cd "$PROJECT_DIR" && git log --oneline -10 2>/dev/null || echo '(非 git 仓库或无提交)')"
GIT_STATUS="$(cd "$PROJECT_DIR" && git diff --stat 2>/dev/null | tail -5 || echo '')"
GIT_HEAD="$(cd "$PROJECT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

# ─── Prompt ───────────────────────────────────────────────────────────────────
PROMPT="当前时间: $(date '+%Y-%m-%d %H:%M:%S %Z')

你正在分析位于 ${PROJECT_DIR} 的项目的当前动态状态。

该项目有：
- .wake-project/scan.json: 程序扫描事实
- .wake-project/base-llm.json: 项目身份与技术栈分析

当前 git HEAD: ${GIT_HEAD}
最近 10 次提交:
${GIT_LOG}

当前未提交变更:
${GIT_STATUS}

请读取 .wake-project/ 下的 scan.json 和 base-llm.json，结合上面的 git 信息，分析该项目当前的动态状态。

严格按以下 JSON Schema 输出，只输出纯 JSON，不要 markdown 围栏或额外文字：

{
  \"activity\": {
    \"focus\": \"一句话概括当前最重要的事\",
    \"evidence\": \"引用具体文件或提交作为依据\",
    \"theme\": \"近期活动的整体叙事（1-2句）\"
  },
  \"context_hint\": {
    \"workflow_stage\": \"early-exploration|mid-implementation|review-and-polish|maintenance\",
    \"likely_next_step\": \"基于当前状态推断的下一步\"
  },
  \"attention_points\": [
    {
      \"severity\": \"warning|info\",
      \"message\": \"需要关注的点\",
      \"evidence\": \"具体依据（文件/提交/模式）\"
    }
  ]
}

规则：
- activity.focus 必须非空，一句话说清当前焦点
- activity.evidence 必须引用具体文件路径或提交 hash
- workflow_stage 必须是枚举值之一
- attention_points 每条必须有 evidence，无依据则不输出
- attention_points 最多 3 个，只列真正需要关注的
- 如果项目近期无活动（无最近提交、无变更），activity.focus 写"无近期活动"，attention_points 为空数组
- 只输出纯 JSON"

# ─── 调用 + 重试 ──────────────────────────────────────────────────────────────
echo "→ 状态分析: $PROJECT_DIR (model=$MODEL)"

for i in $(seq 1 "$MAX_RETRIES"); do
  RAW="$(cd "$PROJECT_DIR" && "$PI_BIN" -p --model "$MODEL" --tools "$TOOLS" --no-session --no-context-files "$PROMPT" 2>/dev/null)" || {
    echo "⚠ 第${i}次: pi 执行失败" >&2
    log "error" "attempt $i: pi execution failed"
    sleep 2; continue
  }

  # 剥离代码围栏（macOS/Linux 兼容）
  OUTPUT="$(printf '%s\n' "$RAW" | awk '
    NR==1 && /^```[a-zA-Z]*$/ { next }
    { lines[++n] = $0 }
    END { for(i=1;i<=n;i++){ if(i==n && lines[i]~/^```$/) continue; print lines[i] } }
  ')"

  # 校验 JSON + schema
  if echo "$OUTPUT" | jq -e '
    (.activity.focus | type == "string" and length > 0) and
    (.context_hint.workflow_stage | type == "string") and
    (.attention_points | type == "array" and length <= 3)
  ' >/dev/null 2>&1; then
    # 补元数据，原子写入；based_on 记录本分析基于哪个项目的哪次扫描
    jq -n \
      --arg ts "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
      --arg head "$GIT_HEAD" \
      --arg pid "$PROJECT_ID" \
      --arg sid "$SCAN_ID" \
      --argjson body "$OUTPUT" \
      '$body + {schema_version: 1, generated_at: $ts, based_on: {head: $head, project_id: $pid, scan_id: $sid}}' \
      > "$AGENT_JSON.tmp"
    mv "$AGENT_JSON.tmp" "$AGENT_JSON"
    echo "✓ 完成: $AGENT_JSON"
    log "success" "output: $AGENT_JSON"
    exit 0
  fi

  echo "⚠ 第${i}次: 输出无效" >&2
  log "error" "attempt $i: invalid JSON output"
  sleep 2
done

echo "✗ 失败: ${MAX_RETRIES}次均未获得有效输出" >&2
log "error" "all $MAX_RETRIES attempts failed"
exit 1
