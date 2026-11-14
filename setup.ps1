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
$script:SSH_AGENT_READY = $false
$agentScript = Join-Path $env:MY_ROOT "tool/ssh-agent.ps1"
if (Test-Path $agentScript) {
    . $agentScript
} else {
    log_error "未找到脚本: $agentScript"
    return
}

# 仅在加载成功时注册退出事件：卸载本次加载的密钥，不关闭或禁用系统 ssh-agent 服务
if ($script:SSH_AGENT_READY -and -not [string]::IsNullOrWhiteSpace($KEY_PATH)) {
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -MessageData $KEY_PATH -Action {
        $keyToUnload = $Event.MessageData
        if (-not [string]::IsNullOrWhiteSpace($keyToUnload)) {
            & ssh-add -d $keyToUnload 2>$null | Out-Null
        }
    } | Out-Null
    log_info "已注册会话退出钩子：退出时将自动卸载密钥 $(Split-Path $KEY_PATH -Leaf)"
}
