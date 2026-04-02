# PowerShell 版本的 setup.sh
# 设置 UTF-8 编码
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$env:LANG = "zh_CN.UTF-8"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptDir = [System.IO.Path]::GetFullPath($scriptDir)

$env:MY_ROOT = $scriptDir

# 日志函数 - 使用 PowerShell 原生颜色
function log_info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Green }
function log_warn { param([string]$msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function log_error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

log_info "MY_ROOT: $env:MY_ROOT"

# 导入 ssh-agent.ps1
$agentScript = Join-Path $env:MY_ROOT "tool/ssh-agent.ps1"
if (Test-Path $agentScript) {
    . $agentScript
}

# 清理函数（Windows 服务版，自动关闭+恢复系统默认）
function cleanup {
    Write-Host "`n自动关闭 ssh-agent 服务并复原系统设置..." -ForegroundColor Cyan
    # 静默管理员权限：停止服务 + 恢复禁用（系统默认）
    Start-Process powershell -Verb RunAs -ArgumentList @"
        Stop-Service ssh-agent -Force -ErrorAction SilentlyContinue;
        Set-Service ssh-agent -StartupType Disabled -ErrorAction SilentlyContinue
"@ -WindowStyle Hidden -Wait

    # 清理环境变量
    Remove-Item Env:SSH_AGENT_PID -ErrorAction SilentlyContinue
    Remove-Item Env:SSH_AUTH_SOCK -ErrorAction SilentlyContinue
    Write-Host "✅ ssh-agent 已关闭，系统已恢复默认状态" -ForegroundColor Green
}

# 注册退出事件
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { cleanup } | Out-Null
