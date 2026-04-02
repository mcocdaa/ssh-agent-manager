# SSH Agent设置脚本 (PowerShell版本)
# 使用方式: . .\ssh-agent.ps1 或 source ssh-agent.ps1

# 获取脚本所在目录
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$SCRIPT_DIR = [System.IO.Path]::GetFullPath($SCRIPT_DIR)

$CURRENT_KEY_FILE = Join-Path $SCRIPT_DIR "../.ssh_keys/current_key"

# 检查密钥文件是否存在
if (-not (Test-Path $CURRENT_KEY_FILE)) {
    Write-Host "错误: 密钥文件不存在: $CURRENT_KEY_FILE, 若是第一次执行，忽略此错误"
    return 1
}

$KEY_PATH = Get-Content $CURRENT_KEY_FILE -First 1

# 检查密钥文件是否存在
if (-not (Test-Path $KEY_PATH)) {
    Write-Host "错误: 密钥文件不存在: $KEY_PATH"
    return 1
}

$AGENT_STARTED = $false

# 检查ssh-agent是否已经在运行
if (-not [string]::IsNullOrEmpty($env:SSH_AUTH_SOCK) -and (Test-Path $env:SSH_AUTH_SOCK)) {
    Write-Host "✓ 使用现有的ssh-agent (PID: $env:SSH_AGENT_PID)"
    $AGENT_STARTED = $false
} else {
    Write-Host "启动ssh-agent..."
    $output = ssh-agent -s
    if ($LASTEXITCODE -eq 0) {
        foreach ($line in $output) {
            if ($line -match 'SSH_AUTH_SOCK=([^;]+);') {
                $env:SSH_AUTH_SOCK = $matches[1]
            }
            if ($line -match 'SSH_AGENT_PID=([^;]+);') {
                $env:SSH_AGENT_PID = $matches[1]
            }
        }
        $AGENT_STARTED = $true
        Write-Host "✓ ssh-agent已启动 (PID: $env:SSH_AGENT_PID)"
    } else {
        Write-Host "✗ 启动ssh-agent失败"
        return 1
    }
}

# 获取目标密钥的指纹
$TARGET_FINGERPRINT = (ssh-keygen -lf $KEY_PATH | Out-String).Trim() -replace '^(\d+)\s+([^\s]+)\s+.*$','$2'
# 获取当前已添加的所有密钥指纹
$ADDED_FINGERPRINTS = ssh-add -l 2>&1 | Out-String

Write-Host "目标密钥指纹: $TARGET_FINGERPRINT"
Write-Host "已添加的密钥指纹: $ADDED_FINGERPRINTS"

# 检查目标指纹是否在已添加列表中
if ($ADDED_FINGERPRINTS | Select-String $TARGET_FINGERPRINT) {
    Write-Host "✓ 密钥 $(Split-Path $KEY_PATH -Leaf) 已添加到ssh-agent，无需重复添加"
} else {
    # 添加密钥到ssh-agent
    Write-Host "添加SSH密钥: $(Split-Path $KEY_PATH -Leaf)"
    ssh-add $KEY_PATH

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ 密钥已成功添加到ssh-agent"
        Write-Host ""
        Write-Host "现在您可以在当前会话中使用SSH而无需重复输入密码:"
        Write-Host "  ssh user@host"
        Write-Host ""

        # 如果是我们启动的agent，提供清理命令
        if ($AGENT_STARTED) {
            Write-Host "提示: 要停止ssh-agent，可以运行:"
            Write-Host "  Stop-Process -Id `$env:SSH_AGENT_PID -Force"
        }
    } else {
        Write-Host "✗ 密钥添加失败"
        return 1
    }
}
