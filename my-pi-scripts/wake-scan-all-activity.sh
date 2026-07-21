#!/usr/bin/env bash
# wake-scan-all-activity.sh — 全盘扫描：对所有含 .wake-project 的项目调用 wake-activity.sh
# 用法: ./wake-scan-all-activity.sh [--rebuild]
#   --rebuild  重新分析已有 activity-llm.json 的项目（默认跳过已完成的）
set -euo pipefail

# ─── 固化配置 ─────────────────────────────────────────────────────────────────
ROOTS=(
  /Users/weikejia/CODE/my-agent-group/.gshare/apps
  /Users/weikejia/CODE/my-agent-group/admin-apps
  /Users/weikejia/CODE/my-agent-group/projects
  /Users/weikejia/CODE/my-agent-group/real-projects
)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANALYZE_SCRIPT="$SCRIPT_DIR/wake-activity.sh"

# 排除目录（不进入）
SKIP_DIRS="node_modules .venv venv __pycache__ target build dist .hg .svn .git"

# ─── 参数 ─────────────────────────────────────────────────────────────────────
FORCE=false
[[ "${1:-}" == "--rebuild" ]] && FORCE=true

# ─── 构建 find prune 表达式 ───────────────────────────────────────────────────
PRUNE=""
for d in $SKIP_DIRS; do
  PRUNE="$PRUNE -name $d -prune -o"
done

# ─── 收集项目列表 ─────────────────────────────────────────────────────────────
echo "→ 扫描项目..."
PROJECTS=()
for ROOT in "${ROOTS[@]}"; do
  [ -d "$ROOT" ] || { echo "  ⊘ 不存在: $ROOT"; continue; }
  FOUND=()
  while IFS= read -r -d '' wp; do
    FOUND+=("$(dirname "$wp")")
  done < <(find "$ROOT" $PRUNE -type d -name ".wake-project" -print0 2>/dev/null)
  echo "  ${ROOT##*/}: ${#FOUND[@]} 个项目"
  PROJECTS+=("${FOUND[@]+"${FOUND[@]}"}")
done

# 排序去重
if [[ ${#PROJECTS[@]} -gt 0 ]]; then
  SORTED=()
  while IFS= read -r p; do
    SORTED+=("$p")
  done < <(printf '%s\n' "${PROJECTS[@]}" | sort -u)
  PROJECTS=("${SORTED[@]}")
fi

TOTAL=${#PROJECTS[@]}
if [[ $TOTAL -eq 0 ]]; then
  echo "✗ 未找到任何含 .wake-project 的项目"
  exit 0
fi
echo "→ 共发现 $TOTAL 个项目"
echo ""

# ─── 逐个分析 ─────────────────────────────────────────────────────────────────
OK=0; SKIP=0; FAIL=0; IDX=0

for proj in "${PROJECTS[@]}"; do
  IDX=$((IDX + 1))
  ACTIVITY="$proj/.wake-project/activity-llm.json"
  NAME="${proj##*/}"

  # 已有结果且非 force 模式则跳过
  if [[ "$FORCE" == "false" && -f "$ACTIVITY" ]]; then
    SKIP=$((SKIP + 1))
    printf "[%d/%d] ⊘ %s (已有)\n" "$IDX" "$TOTAL" "$NAME"
    continue
  fi

  printf "[%d/%d] → %s\n" "$IDX" "$TOTAL" "$NAME"

  T0=$(date +%s)
  RC=0
  "$ANALYZE_SCRIPT" "$proj" >/dev/null 2>&1 || RC=$?
  ELAPSED=$(( $(date +%s) - T0 ))
  case "$RC" in
    0) OK=$((OK + 1));    printf "[%d/%d] ✓ %s (%ds)\n"   "$IDX" "$TOTAL" "$NAME" "$ELAPSED" ;;
    2) SKIP=$((SKIP + 1)); printf "[%d/%d] ⊘ %s 跳过 (%ds)\n" "$IDX" "$TOTAL" "$NAME" "$ELAPSED" ;;
    *) FAIL=$((FAIL + 1)); printf "[%d/%d] ✗ %s 失败 rc=%d (%ds)\n" "$IDX" "$TOTAL" "$NAME" "$RC" "$ELAPSED" ;;
  esac
done

# ─── 汇总 ─────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "  总计: $TOTAL | 成功: $OK | 跳过: $SKIP | 失败: $FAIL"
echo "═══════════════════════════════════════"
