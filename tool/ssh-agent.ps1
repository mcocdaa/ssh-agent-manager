# SSH Agent设置脚本 (PowerShell版本)
# 使用方式: . .\ssh-agent.ps1

# UTF8编码
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$env:LANG = "zh_CN.UTF-8"

# 路径配置（匹配你的仓库结构）
$SCRIPT_DIR = $PSScriptRoot
$CURRENT_KEY_FILE = Join-Path $SCRIPT_DIR "../.ssh_keys/current_key"
$script:SSH_AGENT_READY = $false

# 校验密钥文件
if (-not (Test-Path $CURRENT_KEY_FILE)) {
    Write-Host "[ERROR] 密钥配置文件不存在: $CURRENT_KEY_FILE" -ForegroundColor Red
    Write-Host "[INFO] 请先运行根目录的 init.ps1" -ForegroundColor Cyan
    return
}
$KEY_PATH = (Get-Content $CURRENT_KEY_FILE -First 1)
if ($null -ne $KEY_PATH) {
    $KEY_PATH = $KEY_PATH.Trim()
}
if ([string]::IsNullOrWhiteSpace($KEY_PATH) -or -not (Test-Path $KEY_PATH)) {
    Write-Host "[ERROR] 私钥不存在: $KEY_PATH" -ForegroundColor Red
    return
}

# ===================== 终极修复：自动解决 Windows 1058 错误 =====================
function Start-WindowsSshAgent {
    # 检查服务状态
    $service = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "[ERROR] 未安装 Windows OpenSSH 客户端" -ForegroundColor Red
        return $false
    }

    # 服务禁用 → 自动改为手动
    if ($service.StartType -eq 'Disabled') {
        Write-Host "[INFO] 自动修复 ssh-agent 服务(禁用→手动)..." -ForegroundColor Cyan
        Start-Process powershell -ArgumentList "-Command","Set-Service ssh-agent -StartupType Manual" -Verb RunAs -Wait
        $service.Refresh()
    }

    # 启动服务
    if ($service.Status -ne 'Running') {
        Write-Host "[INFO] 启动 ssh-agent 服务..." -ForegroundColor Cyan
        Start-Service ssh-agent
        $service.Refresh()
    }

    return $service.Status -eq 'Running'
}

# 启动ssh-agent服务
if (-not (Start-WindowsSshAgent)) {
    Write-Host "[ERROR] ssh-agent 启动失败" -ForegroundColor Red
    return
}

Write-Host "[INFO] ssh-agent 服务运行中" -ForegroundColor Green

# ===================== 加载密钥 =====================
$TARGET_FINGERPRINT = ((ssh-keygen -lf $KEY_PATH 2>$null) -split '\s+' | Select-Object -Index 1)
if ([string]::IsNullOrWhiteSpace($TARGET_FINGERPRINT)) {
    Write-Host "[ERROR] 无法获取密钥指纹: $KEY_PATH" -ForegroundColor Red
    return
}
$ADDED = (ssh-add -l 2>&1 | Out-String)

if ($ADDED -match [regex]::Escape($TARGET_FINGERPRINT)) {
    Write-Host "[INFO] 密钥已加载，无需重复操作" -ForegroundColor Green
}
else {
    Write-Host "[INFO] 加载密钥: $(Split-Path $KEY_PATH -Leaf)" -ForegroundColor Cyan
    ssh-add $KEY_PATH
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[INFO] 密钥加载成功 ✅" -ForegroundColor Green
        Write-Host "[INFO] 现在可以直接免密登录：ssh 用户名@服务器IP" -ForegroundColor Yellow
    }
    else {
        Write-Host "[ERROR] 密钥加载失败" -ForegroundColor Red
        return
    }
}

$script:SSH_AGENT_READY = $true

# 清理提示
Write-Host "`n[INFO] 手动卸载当前密钥命令：ssh-add -d `"$KEY_PATH`"" -ForegroundColor Gray
