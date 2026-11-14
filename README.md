[English](README_EN.md) | 简体中文

# SSH Agent Manager

跨平台 SSH 密钥与会话级 Agent 管理工具，支持 Linux、macOS 和 Windows (PowerShell)。

## 功能特性

- **一键生成 SSH 密钥对** - 支持 ed25519 算法、密码保护检测与严格文件权限（私钥 `0600` / 公钥 `0644`）
- **输入校验与安全上传** - 校验主机名、用户名与别名，防止 shell 注入；Linux/macOS 使用 `ssh-copy-id`，Windows 通过 stdin 管道安全写入 `authorized_keys`
- **Agent 自动管理** - 自动检测或启动 `ssh-agent` 并按指纹去重加载密钥
- **非破坏性会话清理** - 仅关闭由本工具临时启动的 `ssh-agent`；若复用现有 Agent 或 Windows 全局 `ssh-agent` 服务，退出时仅卸载本次加载的密钥（`ssh-add -d`），不干扰其他会话
- **跨平台支持** - POSIX/macOS 兼容 Bash 脚本 + Windows PowerShell（无 BOM 写入配置）

## 快速开始

### 1. 初始化（首次使用）

**Linux / macOS:**
```bash
./init.sh
```

**Windows (PowerShell):**
```powershell
.\init.ps1
```

按提示输入服务器地址、登录用户名和别名，脚本会自动：
- 生成 ed25519 SSH 密钥对
- 上传公钥到远程服务器
- 记录当前激活密钥到 `.ssh_keys/current_key`

### 2. 加载密钥到 Agent

**Linux / macOS:**
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

- **Linux / macOS**：若由 `setup.sh` 启动了临时 `ssh-agent`，退出终端时会自动执行 `eval "$(ssh-agent -k)"` 关闭；若复用了已有的 `ssh-agent`，退出时仅执行 `ssh-add -d` 卸载本次加载的密钥。
- **Windows (PowerShell)**：退出会话时自动执行 `ssh-add -d` 卸载本次加载的密钥，不会停止或禁用系统的 `ssh-agent` 服务。

## 项目结构

```
.
├── init.sh / init.ps1      # 初始化脚本：生成密钥、上传公钥
├── setup.sh / setup.ps1    # 环境设置：加载密钥到 Agent 并注册退出清理
├── tool/
│   ├── ssh-agent.sh        # Linux/macOS Agent 管理核心
│   └── ssh-agent.ps1       # Windows Agent 管理核心
├── tests/
│   └── test_scripts.sh     # Bash 单元测试（使用 mock 命令，不触碰真实密钥）
└── .ssh_keys/              # 密钥存储目录（已加入 .gitignore）
```

## 依赖要求

- OpenSSH 客户端 (`ssh`, `ssh-keygen`, `ssh-agent`, `ssh-add`)
- Linux / macOS：`ssh-copy-id`、`bash`
- Windows：Windows 10/11 自带 OpenSSH 客户端与 PowerShell

## 测试验证

```bash
bash -n init.sh setup.sh tool/ssh-agent.sh tests/test_scripts.sh
bash tests/test_scripts.sh
```

## 安全提示

请参阅 [SECURITY.md](SECURITY.md)。

1. 密钥文件存储在 `.ssh_keys/` 目录（权限 `0700`，私钥 `0600`），已加入 `.gitignore` 防止误提交
2. 建议为私钥设置密码以提高安全性
3. 妥善保管私钥文件，避免泄露并定期轮换

## License

[MIT](LICENSE)
