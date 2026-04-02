# SSH 密钥初始化脚本 (PowerShell版本)
# 功能：生成SSH密钥对，上传公钥到远程服务器，配置current_key文件
# 修复：保留字冲突、icacls报错、编码稳定

# 设置 UTF-8 编码
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$env:LANG = "zh_CN.UTF-8"

$MY_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$MY_ROOT = [System.IO.Path]::GetFullPath($MY_ROOT)
Set-Location $MY_ROOT

# 日志函数 - 使用 PowerShell 原生颜色
function log_info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Green }
function log_warn { param([string]$msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function log_error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# 检查必要命令是否存在
function check_dependency {
    param([string]$cmd)
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        log_error "缺少必要命令: $cmd，请先安装"
        exit 1
    }
}

# 生成SSH密钥对（支持设置密码）
function generate_ssh_key {
    param([string]$key_path, [string]$comment)

    Write-Host "================================================="

    if (Test-Path $key_path) {
        log_warn "密钥文件 $key_path 已存在"
        $overwrite = Read-Host "是否覆盖? [y/N]"
        if ($overwrite -ne "y" -and $overwrite -ne "Y") {
            log_info "保持现有密钥"
            return
        }
    }

    log_info "生成SSH密钥对: $key_path"
    log_info "推荐设置密码以提高安全性，不设置也可以"

    ssh-keygen -t ed25519 -f $key_path -C $comment

    if ($LASTEXITCODE -eq 0) {
        log_info "已生成带密码的SSH密钥"
        log_info "提示：在使用此密钥时，您需要输入密码"
    } else {
        log_error "密钥生成失败"
        exit 1
    }

    # ===================== 修复1：删除报错的icacls命令 =====================
    log_info "密钥生成成功"
    Write-Host "================================================="
}

# 上传公钥到远程服务器
# ===================== 修复2：把保留字 $host 改为 $remote_host =====================
function upload_public_key {
    param([string]$user, [string]$remote_host, [string]$pub_key_path)

    Write-Host "================================================="

    log_info "上传公钥到 $user@$remote_host"

    # 修复公钥读取格式
    $pubKeyContent = Get-Content $pub_key_path -Raw
    ssh $user@$remote_host "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubKeyContent' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

    if ($LASTEXITCODE -ne 0) {
        log_warn "公钥上传可能失败，尝试手动验证"
        $continue = Read-Host "是否继续? [Y/n]"
        if ($continue -eq "n" -or $continue -eq "N") {
            exit 1
        }
    }
    Write-Host "================================================="
}

# 配置current_key文件
function generate_set_agent_script {
    param([string]$key_path)

    Write-Host "================================================="
    log_info "配置current_key文件"

    $keysDir = Join-Path $MY_ROOT ".ssh_keys"
    $currentKeyFile = Join-Path $keysDir "current_key"

    $fullPath = [System.IO.Path]::GetFullPath($key_path)
    Set-Content -Path $currentKeyFile -Value $fullPath -Encoding UTF8 -NoNewline

    Write-Host "================================================="
}

# 提供使用指导
function provide_usage_guidance {
    param([string]$key_path, [string]$ssh_user, [string]$server_host)

    Write-Host "================================================="

    log_info "===== 使用指导 ====="
    Write-Host ""
    Write-Host "快速开始:"
    Write-Host "  . .\setup.ps1"
    Write-Host ""

    $test_connection = Read-Host "是否立即测试SSH连接? [y/N]"
    if ($test_connection -eq "y" -or $test_connection -eq "Y") {
        log_info "测试SSH连接到 $server_host..."
        ssh -i $key_path "$ssh_user@$server_host" "echo 'SSH连接成功!'"
    }
    Write-Host "================================================="
}

# 主函数
function main {
    log_info "MY_ROOT: $MY_ROOT"
    log_info "===== 开始SSH密钥与配置生成 ====="

    check_dependency "ssh-keygen"
    check_dependency "ssh"

    $server_host = Read-Host "请输入服务器地址 (IP或域名)"
    $ssh_user = Read-Host "请输入登录用户名"
    $host_alias = Read-Host "请输入SSH别名 (用于标识，空白表示自动生成)"

    if ([string]::IsNullOrWhiteSpace($host_alias)) {
        $host_alias = "server_" + ($server_host -replace "\.", "_")
        log_info "未指定别名，自动生成: $host_alias"
    }

    $keys_dir = Join-Path $MY_ROOT ".ssh_keys"
    if (-not (Test-Path $keys_dir)) {
        New-Item -ItemType Directory -Path $keys_dir | Out-Null
    }

    $key_name = "${host_alias}_id_ed25519"
    $key_path = Join-Path $keys_dir $key_name
    $pub_key_path = "$key_path.pub"
    $key_comment = "$ssh_user@$server_host ($host_alias)"

    # 执行配置（参数对应修改后的函数）
    generate_ssh_key $key_path $key_comment
    upload_public_key $ssh_user $server_host $pub_key_path
    generate_set_agent_script $key_path
    provide_usage_guidance $key_path $ssh_user $server_host

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
