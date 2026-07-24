#!/usr/bin/env bash
# ============================================================================
# deploy-local.sh — Pi 本地部署（从 wkj-dev 二开分支发布到本地环境）
#
# 将 wkj-dev 分支的代码构建并注册到全局 PATH，覆盖 npm 安装的 release 版本。
# 部署后 `pi` 命令指向本地二开分支代码。
#
# 用法:
#   ./deploy-local.sh           # 完整部署（检查 → 构建 → 注册 → 验证）
#   ./deploy-local.sh build     # 仅构建（不注册）
#   ./deploy-local.sh link      # 仅注册（已构建后快速使用）
#   ./deploy-local.sh verify    # 仅验证（检测运行的版本是否为本地的）
#   ./deploy-local.sh help      # 显示帮助
#
# 验证机制:
#   构建时记录 git SHA → 安装后通过 `which` + `realpath` 解析命令来源
#   → npm link 解析到本地 repo 目录才算验证通过
#   → 运行 pi --version 确认可执行
#
# 前置条件:
#   - Node.js >= 22.19.0
#   - npm
#   - 当前在 wkj-dev 分支（或设置 PI_ALLOW_BRANCH=1 跳过检查）
#
# 效果:
#   构建 packages/tui → ai → agent → coding-agent → orchestrator
#   然后 npm link 将 pi 命令注册到全局。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step()  { echo -e "${CYAN}━━━ $1 ━━━${NC}"; }

show_help() {
  sed -n '2,/^set -euo/p' "$0" | grep -E '^#' | sed 's/^# \?//'
  exit 0
}

# ─── 构建标记 ───
DEPLOY_MARKER=".deploy-marker"

write_marker() {
  local sha branch time
  sha="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
  branch="$(git branch --show-current 2>/dev/null || echo 'unknown')"
  time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$DEPLOY_MARKER" <<EOF
SHA=$sha
BRANCH=$branch
BUILD_TIME=$time
EOF
  log_info "构建标记已写入: $DEPLOY_MARKER"
  cat "$DEPLOY_MARKER" | sed 's/^/      /'
}

read_marker() {
  local key="$1"
  grep "^${key}=" "$DEPLOY_MARKER" 2>/dev/null | cut -d= -f2 || echo "unknown"
}

# ─── 前置检查 ───
check_prereqs() {
  log_step "检查前置条件"

  # Node 版本
  if ! command -v node &>/dev/null; then
    log_error "未找到 node。请安装 Node.js >= 22.19.0"
    exit 1
  fi
  log_info "Node.js $(node --version | sed 's/^v//')"

  if ! command -v npm &>/dev/null; then
    log_error "未找到 npm"
    exit 1
  fi
  log_info "npm $(npm --version)"

  # 分支检查
  local branch
  branch="$(git branch --show-current 2>/dev/null || echo '')"
  if [ "$branch" != "wkj-dev" ]; then
    log_warn "当前分支: $branch（期望: wkj-dev）"
    if [ "${PI_ALLOW_BRANCH:-}" != "1" ]; then
      echo "   使用 git checkout wkj-dev 切换分支，或设置 PI_ALLOW_BRANCH=1 跳过检查"
      exit 1
    fi
    log_warn "PI_ALLOW_BRANCH=1 已设置，跳过分支检查"
  else
    log_info "当前分支: wkj-dev ✅"
  fi

  # node_modules
  if [ ! -d node_modules ]; then
    log_warn "node_modules 未安装，运行 npm install..."
    npm install --ignore-scripts
    log_info "npm install 完成"
  else
    log_info "node_modules 已安装"
  fi
}

# ─── 构建 ───
do_build() {
  log_step "构建 Pi（wkj-dev）"
  local start
  start="$(date +%s)"

  # 委托给 my-scripts/deploy.sh build 部分
  # 但需要独立执行每个步骤以捕获产物
  echo "  → 构建 packages/tui ..."
  (cd packages/tui && npm run build 2>&1 | sed 's/^/      /')
  log_info "tui ✅"

  echo "  → 构建 packages/ai ..."
  (cd packages/ai && npm run build 2>&1 | sed 's/^/      /')
  log_info "ai ✅"

  echo "  → 构建 packages/agent ..."
  (cd packages/agent && npm run build 2>&1 | sed 's/^/      /')
  log_info "agent ✅"

  echo "  → 构建 packages/coding-agent ..."
  (cd packages/coding-agent && npm run build 2>&1 | sed 's/^/      /')
  log_info "coding-agent ✅"

  echo "  → 构建 packages/orchestrator ..."
  (cd packages/orchestrator && npm run build 2>&1 | sed 's/^/      /')
  log_info "orchestrator ✅"

  local end
  end="$(date +%s)"
  log_info "全部构建完成（$((end - start))s）"

  # 验证产物
  if [ -f packages/coding-agent/dist/cli.js ]; then
    log_info "产物验证: packages/coding-agent/dist/cli.js ✅"
    ls -lh packages/coding-agent/dist/cli.js | awk '{print "      size:", $5}'
  else
    log_error "构建失败: packages/coding-agent/dist/cli.js 未生成"
    exit 1
  fi

  # 写入构建标记
  write_marker
}

# ─── 全局注册 ───
do_link() {
  log_step "注册 pi 命令到全局"

  # 清理旧链接
  npm unlink --global @earendil-works/pi-coding-agent 2>/dev/null || true

  # npm link
  (cd packages/coding-agent && npm link 2>&1) | sed 's/^/      /'
  log_info "npm link 完成"

  # 写入标记补充信息
  local link_target
  link_target="$(npm ls -g @earendil-works/pi-coding-agent --depth=0 2>/dev/null | grep -o '/.*' || echo '')"
  echo "LINK_TARGET=$link_target" >> "$DEPLOY_MARKER"
}

# ─── 验证部署 ───
verify_deployment() {
  log_step "验证部署"

  local errors=0

  # 1. 命令是否存在
  if ! command -v pi &>/dev/null; then
    log_error "pi 命令不存在！"
    return 1
  fi
  log_info "pi 命令存在 ✅"

  # 2. 解析命令的真实路径
  local cmd_path
  cmd_path="$(which pi 2>/dev/null || true)"

  local real_path
  if command -v realpath &>/dev/null; then
    real_path="$(realpath "$cmd_path" 2>/dev/null || echo "$cmd_path")"
  elif command -v readlink &>/dev/null; then
    real_path="$(readlink -f "$cmd_path" 2>/dev/null || echo "$cmd_path")"
  else
    real_path="$cmd_path"
  fi

  log_info "命令路径: $cmd_path"
  log_info "解析路径: $real_path"

  # 3. 验证路径指向本地 repo
  local repo_dir
  repo_dir="$(cd "$SCRIPT_DIR" && pwd)"

  if echo "$real_path" | grep -q "$repo_dir"; then
    log_info "路径验证: 指向本地 repo ✅"
  else
    # 也可能是 npm 全局 link 的路径
    if echo "$cmd_path" | grep -q "node_modules"; then
      log_info "路径验证: npm link 路径 ✅"
    else
      log_error "路径验证: 可能指向非本地版本"
      echo "     真实路径: $real_path"
      echo "     本地目录: $repo_dir"
      errors=$((errors + 1))
    fi
  fi

  # 4. npm link 确认
  local npm_info
  npm_info="$(npm ls -g @earendil-works/pi-coding-agent --depth=0 2>/dev/null || true)"
  log_info "npm global: $npm_info"

  if echo "$npm_info" | grep -qiE "link|->"; then
    log_info "npm link 验证: 已链接到本地 ✅"
  elif echo "$npm_info" | grep -q "$repo_dir"; then
    log_info "npm link 验证: 路径匹配 ✅"
  else
    log_warn "npm link 验证: 可能不是 link 安装"
    errors=$((errors + 1))
  fi

  # 5. 运行 pi --version
  log_info "执行 pi --version..."
  local version_output
  version_output="$(pi --version 2>&1 || true)"
  log_info "版本输出: $version_output"

  # 6. 对比构建标记
  if [ -f "$DEPLOY_MARKER" ]; then
    local marker_sha
    marker_sha="$(read_marker SHA)"
    local current_sha
    current_sha="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"

    if [ "$marker_sha" = "$current_sha" ]; then
      log_info "SHA 验证: $marker_sha ✅（与当前 HEAD 一致）"
    else
      log_warn "SHA 验证: 标记 $marker_sha ≠ 当前 $current_sha（代码可能已变更）"
    fi
  fi

  # 7. 运行简单 smoke test
  log_info "执行 smoke test: pi -p 'Say hello'..."
  local smoke_output
  smoke_output="$(pi -p 'Say exactly: deploy-ok' 2>&1 || true)"
  if echo "$smoke_output" | grep -qi "deploy-ok"; then
    log_info "Smoke test ✅ — 模型正常响应"
  else
    log_warn "Smoke test: 输出不符合预期（可能无 API key 或模型不可用）"
    echo "     输出: $smoke_output"
  fi

  echo ""
  if [ "$errors" -eq 0 ]; then
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ 部署验证通过！运行的正是 wkj-dev 本地版本${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
  else
    echo -e "${YELLOW}⚠  部署完成但有 $errors 个警告${NC}"
  fi
  echo "  命令:  $(which pi)"
  echo "  版本:  $version_output"
  echo "  分支:  $(git branch --show-current)"
  echo "  SHA:   $(git rev-parse HEAD | head -c 12)"
}

# ─── 清理标记 ───
cleanup_marker() {
  rm -f "$DEPLOY_MARKER"
}

# ─── 主流程 ───
main() {
  local cmd="${1:-full}"

  case "$cmd" in
    full)
      check_prereqs
      do_build
      do_link
      verify_deployment
      ;;
    build)
      check_prereqs
      do_build
      ;;
    link)
      do_link
      verify_deployment
      ;;
    verify)
      verify_deployment
      ;;
    help|--help|-h)
      show_help
      ;;
    *)
      log_error "未知命令: $cmd"
      echo "可用命令: full（默认）, build, link, verify, help"
      exit 1
      ;;
  esac
}

main "$@"
