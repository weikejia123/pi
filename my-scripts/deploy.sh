#!/usr/bin/env bash
# ============================================================================
# Pi — 从 wkj-dev 分支构建并部署到本地
#
# 用法:
#   ./my-scripts/deploy.sh           # 构建 + 全局链接 (npm link)
#   ./my-scripts/deploy.sh link      # 仅全局链接 (已构建后快速使用)
#   ./my-scripts/deploy.sh build     # 仅构建
#   ./my-scripts/deploy.sh help      # 显示帮助
#
# 前置条件:
#   - Node.js >= 22.19.0
#   - npm
#   - 当前在 wkj-dev 分支
#
# 效果:
#   构建全部 5 个子包后，通过 npm link 将 pi 命令注册到全局。
#   部署后可在任意目录执行 `pi` 运行 wkj-dev 分支的版本。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NODE_MIN_VERSION="22.19.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# --- 帮助 ---
show_help() {
  sed -n '2,/^set -euo/p' "$0" | head -n -1
  exit 0
}

# --- 版本比较 ---
version_ge() {
  # 比较两个 semver 版本: 如果 $1 >= $2 返回 0
  [ "$(printf '%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

# --- 检查前置条件 ---
check_prereqs() {
  echo "━━━ 检查前置条件 ━━━"

  # Node 版本
  if ! command -v node &>/dev/null; then
    log_error "未找到 node。请安装 Node.js >= $NODE_MIN_VERSION"
    exit 1
  fi
  local node_ver
  node_ver="$(node --version | sed 's/^v//')"
  if version_ge "$node_ver" "$NODE_MIN_VERSION"; then
    log_info "Node.js $node_ver (>= $NODE_MIN_VERSION)"
  else
    log_error "Node.js $node_ver < $NODE_MIN_VERSION，请升级"
    exit 1
  fi

  # npm
  if ! command -v npm &>/dev/null; then
    log_error "未找到 npm"
    exit 1
  fi
  log_info "npm $(npm --version)"

  # 分支检查
  local current_branch
  current_branch="$(cd "$PI_DIR" && git branch --show-current 2>/dev/null || echo '')"
  if [ "$current_branch" != "wkj-dev" ]; then
    log_warn "当前分支: $current_branch (期望: wkj-dev)"
    echo "   使用 git checkout wkj-dev 切换到 wkj-dev 分支后重试。"
    echo "   或设置 PI_ALLOW_BRANCH=1 环境变量跳过此检查。"
    if [ "${PI_ALLOW_BRANCH:-}" != "1" ]; then
      exit 1
    fi
    log_warn "PI_ALLOW_BRANCH=1 已设置，跳过分支检查"
  else
    log_info "当前分支: wkj-dev ✅"
  fi

  # package.json 存在
  if [ ! -f "$PI_DIR/package.json" ]; then
    log_error "未找到 $PI_DIR/package.json，请确认在正确的项目目录中"
    exit 1
  fi
  log_info "项目目录: $PI_DIR"

  # node_modules 检查
  if [ ! -d "$PI_DIR/node_modules" ]; then
    log_warn "node_modules 未安装，运行 npm install..."
    (cd "$PI_DIR" && npm install --ignore-scripts)
    log_info "npm install 完成"
  else
    log_info "node_modules 已安装"
  fi
}

# --- 构建 ---
do_build() {
  echo ""
  echo "━━━ 构建 Pi (wkj-dev) ━━━"

  cd "$PI_DIR"

  # 构建所有包 (按依赖顺序: tui → ai → agent → coding-agent → orchestrator)
  local build_start
  build_start="$(date +%s)"

  echo "  → 构建 packages/tui ..."
  (cd packages/tui && npm run build 2>&1 | sed 's/^/      /')
  log_info "tui 构建完成"

  echo "  → 构建 packages/ai ..."
  (cd packages/ai && npm run build 2>&1 | sed 's/^/      /')
  log_info "ai 构建完成"

  echo "  → 构建 packages/agent ..."
  (cd packages/agent && npm run build 2>&1 | sed 's/^/      /')
  log_info "agent 构建完成"

  echo "  → 构建 packages/coding-agent ..."
  (cd packages/coding-agent && npm run build 2>&1 | sed 's/^/      /')
  log_info "coding-agent 构建完成"

  echo "  → 构建 packages/orchestrator ..."
  (cd packages/orchestrator && npm run build 2>&1 | sed 's/^/      /')
  log_info "orchestrator 构建完成"

  local build_end
  build_end="$(date +%s)"
  log_info "全部构建完成 ($((build_end - build_start))s)"

  # 验证产物
  if [ -f "$PI_DIR/packages/coding-agent/dist/cli.js" ]; then
    log_info "产物验证: coding-agent/dist/cli.js ✅"
  else
    log_error "构建失败: coding-agent/dist/cli.js 未生成"
    exit 1
  fi
}

# --- 全局链接 ---
do_link() {
  echo ""
  echo "━━━ 注册 pi 命令到全局 ━━━"

  cd "$PI_DIR/packages/coding-agent"

  # 先用 npm unlink 清理旧链接，再重新 link
  npm unlink --global @earendil-works/pi-coding-agent 2>/dev/null || true
  npm link 2>&1 | sed 's/^/      /'

  # 验证
  if command -v pi &>/dev/null; then
    local pi_path
    pi_path="$(which pi)"
    log_info "pi 命令已注册: $pi_path"
    log_info "版本: $(pi --version 2>/dev/null || echo 'N/A')"
    echo ""
    echo "  ✅ 部署完成！现在可以在任意目录执行 'pi' 命令"
    echo "     当前使用的正是 wkj-dev 分支的代码"
    echo ""
    echo "  注意: 修改代码后需重新运行 ./my-scripts/deploy.sh"
  else
    log_error "pi 命令注册失败"
    exit 1
  fi
}

# --- 验证 ---
do_verify() {
  echo ""
  echo "━━━ 部署验证 ━━━"
  echo "  分支:     $(cd "$PI_DIR" && git branch --show-current)"
  echo "  pi 路径:  $(which pi 2>/dev/null || echo '未安装')"
  echo "  dist:     $(ls packages/coding-agent/dist/cli.js 2>/dev/null || echo '未构建')"
  echo "  node:     $(node --version)"
  echo ""
  echo "  试运行: pi --help"
  echo "  或运行: pi 直接进入交互模式"
}

# --- 主流程 ---
main() {
  local cmd="${1:-full}"

  case "$cmd" in
    full)
      check_prereqs
      do_build
      do_link
      do_verify
      ;;
    build)
      check_prereqs
      do_build
      do_verify
      ;;
    link)
      do_link
      do_verify
      ;;
    verify)
      do_verify
      ;;
    help|--help|-h)
      show_help
      ;;
    *)
      log_error "未知命令: $cmd"
      echo "可用命令: full (默认), build, link, verify, help"
      exit 1
      ;;
  esac
}

main "$@"
