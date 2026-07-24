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
#   ./deploy-local.sh verify    # 仅验证
#   ./deploy-local.sh help      # 显示帮助
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

# 委托给 my-scripts 下的 deploy.sh，传递所有参数
exec "$SCRIPT_DIR/my-scripts/deploy.sh" "$@"
