#!/bin/bash
# SSH Agent设置脚本
# 使用方式: source tool/ssh-agent.sh

# 获取脚本所在目录（兼容 Linux 与 macOS）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CURRENT_KEY_FILE="$SCRIPT_DIR/../.ssh_keys/current_key"
AGENT_STARTED=false

# 检查 current_key 配置文件是否存在
if [[ ! -f "$CURRENT_KEY_FILE" ]]; then
    echo "错误: 未找到密钥配置文件: $CURRENT_KEY_FILE，请先运行 ./init.sh 初始化"
    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
        return 1
    else
        exit 1
    fi
fi

KEY_PATH="$(head -n 1 "$CURRENT_KEY_FILE")"
KEY_PATH="${KEY_PATH%%$'\r'}"

# 检查密钥文件是否存在
if [[ -z "$KEY_PATH" || ! -f "$KEY_PATH" ]]; then
    echo "错误: 密钥文件不存在: ${KEY_PATH:-<空>}，请重新运行 ./init.sh 初始化"
    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
        return 1
    else
        exit 1
    fi
fi

# 检查ssh-agent是否已经在运行
if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK:-}" ]]; then
    echo "✓ 使用现有的ssh-agent (PID: ${SSH_AGENT_PID:-未知})"
    AGENT_STARTED=false
else
    echo "启动ssh-agent..."
    eval "$(ssh-agent -s)" > /dev/null
    AGENT_STARTED=true
    echo "✓ ssh-agent已启动 (PID: $SSH_AGENT_PID)"
fi

# 停止由本脚本新启动的临时 agent（用于失败回滚）
cleanup_new_agent_on_error() {
    if [[ "$AGENT_STARTED" == "true" ]]; then
        eval "$(ssh-agent -k)" >/dev/null 2>&1 || true
        AGENT_STARTED=false
    fi
}

# 判断密钥是否已添加到ssh-agent
# 1. 获取目标密钥的指纹（格式：密钥长度 指纹 注释）
TARGET_FINGERPRINT="$(ssh-keygen -lf "$KEY_PATH" 2>/dev/null | awk '{print $2}')"
if [[ -z "$TARGET_FINGERPRINT" ]]; then
    echo "错误: 无法获取密钥指纹: $KEY_PATH"
    cleanup_new_agent_on_error
    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
        return 1
    else
        exit 1
    fi
fi

# 2. 获取当前已添加的所有密钥指纹
ADDED_FINGERPRINTS="$(ssh-add -l 2>/dev/null || true)"
echo "目标密钥指纹: $TARGET_FINGERPRINT"
echo "已添加的密钥指纹: $ADDED_FINGERPRINTS"

# 检查目标指纹是否在已添加列表中（使用 -Fq 防止空串或正则元字符误匹配）
if printf '%s\n' "$ADDED_FINGERPRINTS" | grep -Fq -- "$TARGET_FINGERPRINT"; then
    echo "✓ 密钥 $(basename "$KEY_PATH") 已添加到ssh-agent，无需重复添加"
else
    # 添加密钥到ssh-agent
    echo "添加SSH密钥: $(basename "$KEY_PATH")"
    if ssh-add "$KEY_PATH"; then
        echo "✓ 密钥已成功添加到ssh-agent"
        echo ""
        echo "现在您可以在当前会话中使用SSH而无需重复输入密码:"
        echo "  ssh user@host"
        echo ""

        # 如果是我们启动的agent，提供清理命令
        if [[ "$AGENT_STARTED" == "true" ]]; then
            echo "提示: 退出终端时将自动关闭临时 ssh-agent，也可手动运行:"
            echo "  eval \"\$(ssh-agent -k)\""
        fi
    else
        echo "✗ 密钥添加失败"
        cleanup_new_agent_on_error
        if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
            return 1
        else
            exit 1
        fi
    fi
fi

export AGENT_STARTED
export KEY_PATH
