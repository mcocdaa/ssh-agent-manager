#!/bin/bash
MY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$MY_ROOT" || exit 1

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查必要命令是否存在
check_dependency() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        log_error "缺少必要命令: $cmd，请先安装"
        exit 1
    fi
}

# 校验用户输入，防止空格、引号或 shell 元字符注入
validate_input() {
    local val=$1
    local field=$2
    local is_alias=${3:-false}
    local unsafe_re='[[:space:]'\''"`;$&|<>()]'

    if [[ -z "$val" ]]; then
        log_error "$field 不能为空"
        exit 1
    fi
    if [[ "$val" =~ $unsafe_re ]]; then
        log_error "$field 包含不安全字符（请勿包含空白字符、引号或 shell 元字符）"
        exit 1
    fi
    if [[ "$is_alias" == "true" ]]; then
        if [[ "$val" == *"/"* || "$val" == *"\\"* || "$val" == "." || "$val" == ".." ]]; then
            log_error "$field 不能包含路径分隔符或 '.' / '..'"
            exit 1
        fi
    fi
}

# 生成SSH密钥对（支持设置密码）
generate_ssh_key() {
    echo "================================================="
    local key_path=$1
    local comment=$2

    if [ -f "$key_path" ]; then
        log_warn "密钥文件 $key_path 已存在"
        read -r -p "是否覆盖? [y/N] " overwrite
        if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
            log_info "保持现有密钥"
            return 0
        fi
    fi

    log_info "生成SSH密钥对: $key_path"
    log_info "推荐设置密码以提高安全性，不设置也可以"

    if ssh-keygen -t ed25519 -f "$key_path" -C "$comment"; then
        if ssh-keygen -y -P "" -f "$key_path" >/dev/null 2>&1; then
            log_warn "已生成无密码的SSH密钥（建议后续使用 ssh-keygen -p 设置密码以提高安全性）"
        else
            log_info "已生成带密码的SSH密钥"
            log_info "提示：在使用此密钥时，您需要输入密码"
        fi
    else
        log_error "密钥生成失败"
        exit 1
    fi

    # 设置严格的文件权限
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"
    log_info "密钥生成成功"
    echo "================================================="
}

# 上传公钥到远程服务器
upload_public_key() {
    echo "================================================="
    local user=$1
    local host=$2
    local pub_key_path=$3

    log_info "上传公钥到 $user@$host"
    if ! ssh-copy-id -i "$pub_key_path" "$user@$host"; then
        log_warn "公钥上传可能失败，尝试手动验证"
        read -r -p "是否继续? [Y/n] " proceed
        if [ "$proceed" = "n" ] || [ "$proceed" = "N" ]; then
            exit 1
        fi
    fi
    echo "================================================="
}

# 配置current_key文件
generate_set_agent_script() {
    echo "================================================="
    local key_path=$1
    log_info "配置current_key文件"

    local current_key_file="$MY_ROOT/.ssh_keys/current_key"
    if [ -f "$current_key_file" ]; then
        mv "$current_key_file" "${current_key_file}.bak"
    fi

    local key_dir key_abs
    key_dir="$(cd "$(dirname "$key_path")" && pwd -P)"
    key_abs="$key_dir/$(basename "$key_path")"
    printf '%s\n' "$key_abs" > "$current_key_file"
    chmod 600 "$current_key_file"

    if [ -f "${current_key_file}.bak" ]; then
        rm -f "${current_key_file}.bak"
    fi
    echo "================================================="
}

# 提供使用指导
provide_usage_guidance() {
    echo "================================================="
    local key_path=$1
    local ssh_user=$2
    local server_host=$3

    log_info "===== 使用指导 ====="
    echo ""
    echo "快速开始:"
    echo "  source setup.sh"
    echo ""

    # 测试连接选项
    read -r -p "是否立即测试SSH连接? [y/N] " test_connection
    if [ "$test_connection" = "y" ] || [ "$test_connection" = "Y" ]; then
        log_info "测试SSH连接到 $server_host..."
        ssh -i "$key_path" "${ssh_user}@${server_host}" "echo 'SSH连接成功!'"
    fi
    echo "================================================="
}

# 主函数
main() {
    log_info "MY_ROOT: $MY_ROOT"
    log_info "===== 开始SSH密钥与配置生成 ====="

    # 检查依赖
    check_dependency "ssh-keygen"
    check_dependency "ssh-copy-id"

    # 获取用户输入
    read -r -p "请输入服务器地址 (IP或域名): " server_host
    validate_input "$server_host" "服务器地址"

    read -r -p "请输入登录用户名: " ssh_user
    validate_input "$ssh_user" "登录用户名"

    read -r -p "请输入SSH别名 (用于标识，空白表示自动生成): " host_alias

    # 设置默认别名
    if [ -z "$host_alias" ]; then
        host_alias="server_${server_host//./_}"
        host_alias="${host_alias//:/_}"
        log_info "未指定别名，自动生成: $host_alias"
    fi
    validate_input "$host_alias" "SSH别名" "true"

    # 在仓库根目录创建ssh_keys文件夹
    local keys_dir="$MY_ROOT/.ssh_keys"
    mkdir -p "$keys_dir"
    chmod 700 "$keys_dir"

    # 定义密钥路径（在仓库根目录下）
    local key_name="${host_alias}_id_ed25519"
    local key_path="$keys_dir/$key_name"
    local pub_key_path="${key_path}.pub"
    local key_comment="${ssh_user}@${server_host} ($host_alias)"

    # 执行配置流程
    generate_ssh_key "$key_path" "$key_comment"
    upload_public_key "$ssh_user" "$server_host" "$pub_key_path"
    generate_set_agent_script "$key_path"
    provide_usage_guidance "$key_path" "$ssh_user" "$server_host"

    log_info "===== 配置完成 ====="
    log_info "密钥位置: $key_path"
    log_info "公钥位置: $pub_key_path"
    log_info ""
    log_info "重要安全提醒:"
    log_info "1. 妥善保管密钥文件，避免泄露"
    log_info "2. 定期轮换密钥以提高安全性"
}

# 启动主函数
main
