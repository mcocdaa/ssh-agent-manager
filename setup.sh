#!/bin/bash

export MY_ROOT=$(dirname $(readlink -e ${BASH_SOURCE[0]}))

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

source $MY_ROOT/tool/ssh-agent.sh

# 添加 shell 退出钩子：shell 退出时自动关闭此 ssh-agent
cleanup() {
    local exit_code=$?

    if [ -n "$SSH_AGENT_PID" ]; then
        echo -e "\n自动关闭临时 ssh-agent（PID: $SSH_AGENT_PID）..."
        ssh-agent -k >/dev/null 2>&1
    fi

    exit $exit_code
}

trap cleanup EXIT
