#!/bin/bash

MY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export MY_ROOT

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_info "MY_ROOT: $MY_ROOT"

# shellcheck source=tool/ssh-agent.sh
# shellcheck disable=SC1091
if ! source "$MY_ROOT/tool/ssh-agent.sh"; then
    log_error "SSH Agent 初始化失败，跳过退出清理钩子注册"
    return 1 2>/dev/null || exit 1
fi

# 添加 shell 退出钩子：仅当本脚本新启动了临时 agent 时关闭它；否则仅卸载本次密钥
cleanup() {
    local exit_code=$?

    if [[ "${AGENT_STARTED:-false}" == "true" ]]; then
        if [[ -n "${SSH_AGENT_PID:-}" ]]; then
            echo -e "\n自动关闭临时 ssh-agent（PID: $SSH_AGENT_PID）..."
            eval "$(ssh-agent -k)" >/dev/null 2>&1 || true
        fi
    elif [[ -n "${KEY_PATH:-}" ]]; then
        ssh-add -d "$KEY_PATH" >/dev/null 2>&1 || true
    fi

    exit "$exit_code"
}

trap cleanup EXIT
