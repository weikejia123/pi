#!/usr/bin/env bash
# wake-base-llm.sh — 调用 pi agent 分析项目，生成 base-llm.json
# 用法: ./wake-base-llm.sh <project_dir>
set -euo pipefail

# ─── 固化配置（按需修改） ─────────────────────────────────────────────────────
PI_BIN="pi"
MODEL="ollama/qwen3.6:35b"
MAX_RETRIES=3
TOOLS="read,ls,find"
LOG_DIR="/Users/weikejia/.wake/logs"

# ─── 日志 ─────────────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/wake-base-llm.jsonl"

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
BASE_LLM="$WAKE_DIR/base-llm.json"

# ─── 门卫：.wake-project 不存在则跳过 ─────────────────────────────────────────
if [[ ! -d "$WAKE_DIR" ]]; then
  echo "⊘ 跳过: $PROJECT_DIR 无 .wake-project（未扫描）"
  log "skip" "no .wake-project directory"
  exit 0
fi

# ─── Prompt ───────────────────────────────────────────────────────────────────
PROMPT="当前时间: $(date '+%Y-%m-%d %H:%M:%S %Z')

你正在分析位于 ${PROJECT_DIR} 的项目。

该项目有一个 .wake-project/ 目录，里面是程序扫描生成的结构化 JSON 数据（项目元信息、语言分布、依赖列表、关键文件等）。
请先读取 .wake-project/ 下的 JSON 文件，再结合项目目录结构（README、源码布局等），全面理解这个项目。

然后严格按以下 JSON Schema 输出分析结果。只输出纯 JSON，不要 markdown 围栏或任何额外文字：

{
  \"identity\": {
    \"type\": \"web_service|cli_tool|library|mobile_app|data_pipeline|infrastructure\",
    \"confidence\": 0.95,
    \"rationale\": \"分类依据（一句话）\",
    \"one_liner\": \"一句话描述项目\",
    \"purpose_summary\": \"2-3句详细描述项目用途\"
  },
  \"domains\": [\"领域标签，最多5个\"],
  \"tech_summary\": {
    \"natural\": \"人类可读的技术栈概述\",
    \"primary_language\": \"主要编程语言\",
    \"runtime\": \"运行时环境\",
    \"framework\": \"主框架或null\",
    \"key_dependencies\": [\"最多5个关键依赖\"]
  },
  \"critical_paths\": [
    {\"path\": \"相对路径\", \"role\": \"该路径的作用\", \"stability\": \"high|moderate\"}
  ]
}

规则：
- identity.type 必须是枚举值之一
- confidence 为 0-1 浮点数
- critical_paths ≤ 5 个，只列最核心的
- critical_paths 的 role 必须解释为什么这个路径关键，而非描述路径内容
- domains ≤ 5 个，只包含业务领域或功能特征，禁止包含项目结构描述（如 monorepo、microservices、monolith）
- key_dependencies ≤ 5 个，挑最有辨识度的框架级依赖，非 dev 依赖
- purpose_summary 中如果项目是 CLI，应说明安装方式和主要命令
- framework: monorepo 或无明确框架填 null
- 只输出纯 JSON"

# ─── 调用 + 重试 ──────────────────────────────────────────────────────────────
echo "→ 分析: $PROJECT_DIR (model=$MODEL)"

for i in $(seq 1 "$MAX_RETRIES"); do
  RAW="$(cd "$PROJECT_DIR" && "$PI_BIN" -p --model "$MODEL" --tools "$TOOLS" --no-session --no-context-files "$PROMPT" 2>/dev/null)" || {
    echo "⚠ 第${i}次: pi 执行失败" >&2
    log "error" "attempt $i: pi execution failed"
    sleep 2; continue
  }

  # 剥离可能的代码围栏（macOS/Linux 兼容）
  OUTPUT="$(printf '%s\n' "$RAW" | awk '
    NR==1 && /^```[a-zA-Z]*$/ { next }
    { lines[++n] = $0 }
    END { for(i=1;i<=n;i++){ if(i==n && lines[i]~/^```$/) continue; print lines[i] } }
  ')"

  # 校验 JSON + schema
  if echo "$OUTPUT" | jq -e '
    (.identity.type | type == "string") and
    (.identity.one_liner | type == "string") and
    (.identity.confidence | type == "number") and
    (.domains | type == "array") and
    (.tech_summary.primary_language | type == "string") and
    (.critical_paths | type == "array" and length <= 5)
  ' >/dev/null 2>&1; then
    # 补元数据，原子写入
    jq -n --arg ts "$(date '+%Y-%m-%dT%H:%M:%S%z')" --argjson body "$OUTPUT" \
      '$body + {_meta: {schema_version: 1, analyzed_at: $ts}}' > "$BASE_LLM.tmp"
    mv "$BASE_LLM.tmp" "$BASE_LLM"
    echo "✓ 完成: $BASE_LLM"
    log "success" "output: $BASE_LLM"
    exit 0
  fi

  echo "⚠ 第${i}次: 输出无效" >&2
  log "error" "attempt $i: invalid JSON output"
  sleep 2
done

echo "✗ 失败: ${MAX_RETRIES}次均未获得有效输出" >&2
log "error" "all $MAX_RETRIES attempts failed"
exit 1
