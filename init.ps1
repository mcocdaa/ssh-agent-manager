# SSH 密钥初始化脚本 (PowerShell版本)
# 功能：生成SSH密钥对，上传公钥到远程服务器，配置current_key文件
# 修复：保留字冲突、icacls报错、编码稳定

# 设置 UTF-8 编码（无 BOM 输出）
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
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

# 校验用户输入，防止空白字符、引号或 shell 元字符注入
function Assert-SafeInput {
    param([string]$Value, [string]$FieldName, [bool]$IsAlias = $false)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        log_error "$FieldName 不能为空"
        exit 1
    }
    if ($Value -match '[\s''"`;$&|<>()]') {
        log_error "$FieldName 包含不安全字符（请勿包含空白字符、引号或 shell 元字符）"
        exit 1
    }
    if ($IsAlias -and ($Value -match '[/\\]' -or $Value -eq '.' -or $Value -eq '..')) {
        log_error "$FieldName 不能包含路径分隔符或 '.' / '..'"
        exit 1
    }
}

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
        & ssh-keygen -y -P "" -f $key_path 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            log_warn "已生成无密码的SSH密钥（建议后续使用 ssh-keygen -p 设置密码以提高安全性）"
        } else {
            log_info "已生成带密码的SSH密钥"
            log_info "提示：在使用此密钥时，您需要输入密码"
        }
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

    # 通过 stdin 管道传输公钥，避免远程 shell 字符串插值注入并去除 CR
    Get-Content -Path $pub_key_path -Raw | ssh "${user}@${remote_host}" "umask 077; mkdir -p ~/.ssh && chmod 700 ~/.ssh && tr -d '\r' >> ~/.ssh/authorized_keys"

    if ($LASTEXITCODE -ne 0) {
        log_warn "公钥上传可能失败，尝试手动验证"
        $continue = Read-Host "是否继续? [Y/n]"
        if ($continue -eq "n" -or $continue -eq "N") {
            exit 1
        }
    }
    Write-Host "================================================="
}

# 配置current_key文件（无 UTF-8 BOM）
function generate_set_agent_script {
    param([string]$key_path)

    Write-Host "================================================="
    log_info "配置current_key文件"

    $keysDir = Join-Path $MY_ROOT ".ssh_keys"
    $currentKeyFile = Join-Path $keysDir "current_key"

    $fullPath = [System.IO.Path]::GetFullPath($key_path)
    [System.IO.File]::WriteAllText($currentKeyFile, $fullPath, [System.Text.UTF8Encoding]::new($false))

    Write-Host "================================================="
}

# 可选写入 ~/.ssh/config（无 UTF-8 BOM）
function update_ssh_config {
    param([string]$host_alias, [string]$server_host, [string]$ssh_user, [string]$key_path)

    $addConfig = Read-Host "是否将别名 $host_alias 写入 ~/.ssh/config? [y/N]"
    if ($addConfig -ne "y" -and $addConfig -ne "Y") {
        return
    }

    $sshDir = Join-Path $HOME ".ssh"
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir | Out-Null
    }
    $sshConfigFile = Join-Path $sshDir "config"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    if ((Test-Path $sshConfigFile) -and (Select-String -Path $sshConfigFile -Pattern ("^Host\s+" + [regex]::Escape($host_alias) + "\s*$") -Quiet)) {
        log_warn "$sshConfigFile 中已存在 Host $host_alias，跳过写入"
        return
    }

    $fullKeyPath = [System.IO.Path]::GetFullPath($key_path)
    $configEntry = "`nHost $host_alias`n    HostName $server_host`n    User $ssh_user`n    IdentityFile `"$fullKeyPath`"`n"
    [System.IO.File]::AppendAllText($sshConfigFile, $configEntry, $utf8NoBom)
    log_info "已写入 SSH 配置: $sshConfigFile"
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
    Assert-SafeInput $server_host "服务器地址"

    $ssh_user = Read-Host "请输入登录用户名"
    Assert-SafeInput $ssh_user "登录用户名"

    $host_alias = Read-Host "请输入SSH别名 (用于标识，空白表示自动生成)"

    if ([string]::IsNullOrWhiteSpace($host_alias)) {
        $host_alias = "server_" + ($server_host -replace "\.", "_" -replace ":", "_")
        log_info "未指定别名，自动生成: $host_alias"
    }
    Assert-SafeInput $host_alias "SSH别名" $true

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
    update_ssh_config $host_alias $server_host $ssh_user $key_path
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
