# PowerShell 版本的 setup.sh

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptDir = [System.IO.Path]::GetFullPath($scriptDir)

$env:MY_ROOT = $scriptDir

# 颜色定义
$script:RED = "`e[31m"
$script:GREEN = "`e[32m"
$script:YELLOW = "`e[33m"
$script:NC = "`e[0m"

# 日志函数
function log_info { param([string]$msg) Write-Host "${script:GREEN}[INFO]${script:NC} $msg" }
function log_warn { param([string]$msg) Write-Host "${script:YELLOW}[WARN]${script:NC} $msg" }
function log_error { param([string]$msg) Write-Host "${script:RED}[ERROR]${script:NC} $msg" }

log_info "MY_ROOT: $env:MY_ROOT"

# 导入 ssh-agent.ps1
$agentScript = Join-Path $env:MY_ROOT "tool/ssh-agent.ps1"
if (Test-Path $agentScript) {
    . $agentScript
}

# 清理函数
function cleanup {
    if ($env:SSH_AGENT_PID) {
        Write-Host "`n自动关闭临时 ssh-agent（PID: $env:SSH_AGENT_PID）..."
        try {
            Stop-Process -Id $env:SSH_AGENT_PID -Force -ErrorAction SilentlyContinue
        } catch {}
        Remove-Item Env:SSH_AGENT_PID -ErrorAction SilentlyContinue
        Remove-Item Env:SSH_AUTH_SOCK -ErrorAction SilentlyContinue
    }
}

# 注册退出事件
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { cleanup } | Out-Null
