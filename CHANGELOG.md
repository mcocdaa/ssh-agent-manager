# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-14

### Added
- Automated Bash test suite (`tests/test_scripts.sh`) covering path resolution, uninitialized `current_key` handling, input validation, fingerprint matching, and non-destructive cleanup.
- GitHub Actions CI workflow (`.github/workflows/ci.yml`) running `bash -n`, `shellcheck`, and `tests/test_scripts.sh` on Ubuntu and macOS.
- Dependabot configuration (`.github/dependabot.yml`), bilingual documentation (`README.md` / `README_EN.md`), `SECURITY.md`, and `CHANGELOG.md`.

### Changed
- Replaced GNU-only `readlink -e` / `realpath` usage in `init.sh`, `setup.sh`, and `tool/ssh-agent.sh` with POSIX/macOS-compatible path resolution and set executable permissions.
- Updated `setup.sh` cleanup to kill `ssh-agent` only when `AGENT_STARTED=true` and otherwise unload only the session key via `ssh-add -d`.
- Updated `setup.ps1` and `tool/ssh-agent.ps1` to unload only the managed key on exit without stopping or disabling the global Windows `ssh-agent` service.
- Replaced `gitlab.cern.ch` mirror in `.pre-commit-config.yaml` with `https://github.com/pre-commit/pre-commit-hooks` and removed unused Python hooks.

### Fixed
- Fixed command injection risk in `init.ps1` public key upload by streaming over stdin instead of remote shell string interpolation, and added input validation in `init.sh` and `init.ps1`.
- Fixed UTF-8 BOM issues when writing `.ssh_keys/current_key` and optional `~/.ssh/config` entries from `init.ps1`.
- Fixed empty fingerprint false-match bug and missing `current_key` handling in `tool/ssh-agent.sh`.
- Fixed `init.sh` public key permissions (`0644`) and empty-passphrase warning message.

### Removed
- Removed empty `AGENTS.md`.
