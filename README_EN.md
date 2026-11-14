English | [简体中文](README.md)

# SSH Agent Manager

Cross-platform SSH keypair initializer and scoped `ssh-agent` session manager for Linux, macOS, and Windows (PowerShell).

## Features

- **One-step SSH keypair generation** - Generates ed25519 keys with passphrase detection and strict permissions (`0600` private key, `0644` public key)
- **Input validation & safe key upload** - Rejects unsafe whitespace and shell metacharacters; uses `ssh-copy-id` on Linux/macOS and stdin piping on Windows to avoid remote shell interpolation
- **Automatic Agent management** - Reuses an existing `ssh-agent` or starts a temporary one, checking key fingerprints before adding
- **Non-destructive session cleanup** - Only terminates `ssh-agent` if this session started it; otherwise unloads only the managed key (`ssh-add -d`) without disrupting pre-existing agents or the global Windows `ssh-agent` service
- **Cross-platform** - POSIX/macOS-portable Bash scripts and UTF-8 (no-BOM) PowerShell scripts

## Quick Start

### 1. Initialize (First-Time Setup)

**Linux / macOS:**
```bash
./init.sh
```

**Windows (PowerShell):**
```powershell
.\init.ps1
```

Follow the prompts to enter the server address, login username, and alias. The script will:
- Generate an ed25519 keypair under `.ssh_keys/`
- Upload the public key to the remote server
- Save the active key path to `.ssh_keys/current_key`

### 2. Load Key into `ssh-agent`

**Linux / macOS:**
```bash
source setup.sh
```

**Windows (PowerShell):**
```powershell
. .\setup.ps1
```

Once loaded, you can connect within the current shell session without re-entering your passphrase:
```bash
ssh <user>@<server>
```

### 3. Exit Cleanup

- **Linux / macOS**: If `setup.sh` started a temporary `ssh-agent`, it terminates that agent via `eval "$(ssh-agent -k)"` on shell exit. If it reused an existing `ssh-agent`, it only unloads the key via `ssh-add -d`.
- **Windows (PowerShell)**: On `PowerShell.Exiting`, it unloads only the loaded key via `ssh-add -d` without stopping or disabling the system `ssh-agent` service.

## Project Structure

```
.
├── init.sh / init.ps1      # Keypair creation & public key deployment
├── setup.sh / setup.ps1    # Session loader & exit cleanup hook
├── tool/
│   ├── ssh-agent.sh        # Linux/macOS core agent helper
│   └── ssh-agent.ps1       # Windows core agent helper
├── tests/
│   └── test_scripts.sh     # Mocked Bash test suite
└── .ssh_keys/              # Local key storage (gitignored)
```

## Requirements

- OpenSSH client (`ssh`, `ssh-keygen`, `ssh-agent`, `ssh-add`)
- Linux / macOS: `ssh-copy-id`, `bash`
- Windows: Built-in OpenSSH client (Windows 10/11) and PowerShell

## Verification

```bash
bash -n init.sh setup.sh tool/ssh-agent.sh tests/test_scripts.sh
bash tests/test_scripts.sh
```

## Security

See [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
