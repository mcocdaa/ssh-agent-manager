#!/bin/bash
# SSH Agent设置脚本
# 使用方式: source set_agent.sh

# 获取脚本所在目录
SCRIPT_DIR=$(dirname "$(readlink -e ${BASH_SOURCE[0]})")
KEY_PATH=$( head -n 1 "$SCRIPT_DIR/../.ssh_keys/current_key" )

# 检查密钥文件是否存在
if [ ! -f "$KEY_PATH" ]; then
    echo "错误: 密钥文件不存在: $KEY_PATH, 若是第一次执行，忽略此错误"
    return 1 2>/dev/null || exit 1
fi

# SSH_AUTH_SOCK=""
# 检查ssh-agent是否已经在运行
if [ -n "$SSH_AUTH_SOCK" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    echo "✓ 使用现有的ssh-agent (PID: $SSH_AGENT_PID)"
    AGENT_STARTED=false
else
    echo "启动ssh-agent..."
    eval "$(ssh-agent -s)" > /dev/null
    AGENT_STARTED=true
    echo "✓ ssh-agent已启动 (PID: $SSH_AGENT_PID)"
fi

# 判断密钥是否已添加到ssh-agent
# 1. 获取目标密钥的指纹（格式：密钥长度 指纹 注释）
TARGET_FINGERPRINT=$(ssh-keygen -lf "$KEY_PATH" | awk '{print $2}')
# 2. 获取当前已添加的所有密钥指纹
ADDED_FINGERPRINTS=$(ssh-add -l 2>/dev/null)
echo "目标密钥指纹: $TARGET_FINGERPRINT"
echo "已添加的密钥指纹: $ADDED_FINGERPRINTS"
# 检查目标指纹是否在已添加列表中
if echo "$ADDED_FINGERPRINTS" | grep -q "$TARGET_FINGERPRINT"; then
    echo "✓ 密钥 $(basename "$KEY_PATH") 已添加到ssh-agent，无需重复添加"
else
    # 添加密钥到ssh-agent
    echo "添加SSH密钥: $(basename "$KEY_PATH")"
    ssh-add "$KEY_PATH"

    if [ $? -eq 0 ]; then
        echo "✓ 密钥已成功添加到ssh-agent"
        echo ""
        echo "现在您可以在当前会话中使用SSH而无需重复输入密码:"
        echo "  ssh user@host"
        echo ""

        # 如果是我们启动的agent，提供清理命令
        if [ "$AGENT_STARTED" = true ]; then
            echo "提示: 要停止ssh-agent，可以运行:"
            echo "  pkill ssh-agent"
            echo "  或者保存PID然后使用: kill $SSH_AGENT_PID"
        fi
    else
        echo "✗ 密钥添加失败"
        return 1 2>/dev/null || exit 1
    fi
fi
