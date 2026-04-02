# SSH Agent Manager

跨平台 SSH 密钥和 Agent 管理工具，支持 Linux/macOS 和 Windows。

## 功能特性

- **一键生成 SSH 密钥对** - 支持 ed25519 算法和密码保护
- **自动上传公钥** - 支持 `ssh-copy-id` 自动部署
- **Agent 自动管理** - 自动启动 ssh-agent 并加载密钥
- **会话隔离** - 退出终端时自动清理临时 Agent
- **跨平台支持** - Bash (Linux/macOS) + PowerShell (Windows)

## 快速开始

### 1. 初始化（首次使用）

**Linux/macOS:**
```bash
./init.sh
```

**Windows (PowerShell):**
```powershell
.\init.ps1
```

按提示输入服务器地址、用户名和别名，脚本会自动：
- 生成 SSH 密钥对
- 上传公钥到远程服务器
- 配置当前使用的密钥

### 2. 加载密钥到 Agent

**Linux/macOS:**
```bash
source setup.sh
```

**Windows (PowerShell):**
```powershell
. .\setup.ps1
```

加载成功后，当前会话中可直接免密登录：
```bash
ssh 用户名@服务器地址
```

### 3. 退出清理

Linux/macOS 退出终端时会自动关闭临时 ssh-agent。

Windows 手动关闭：
```powershell
Stop-Service ssh-agent -Force
```

## 项目结构

```
.
├── init.sh / init.ps1      # 初始化脚本：生成密钥、上传公钥
├── setup.sh / setup.ps1    # 环境设置：加载密钥到 Agent
├── tool/
│   ├── ssh-agent.sh        # Linux/macOS Agent 管理核心
│   └── ssh-agent.ps1       # Windows Agent 管理核心
└── .ssh_keys/              # 密钥存储目录（已加入 .gitignore）
```

## 依赖要求

- OpenSSH 客户端 (`ssh`, `ssh-keygen`, `ssh-agent`)
- Linux/macOS: `ssh-copy-id`
- Windows: OpenSSH 客户端（Windows 10/11 自带）

## 安全提示

1. 密钥文件存储在 `.ssh_keys/` 目录，已加入 `.gitignore` 防止误提交
2. 建议为密钥设置密码以提高安全性
3. 妥善保管私钥文件，避免泄露
4. 定期轮换密钥

## License

MIT
