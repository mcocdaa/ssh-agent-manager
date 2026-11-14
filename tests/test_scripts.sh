#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PASS=0
FAIL=0

pass() {
    echo "[PASS] $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "[FAIL] $1" >&2
    FAIL=$((FAIL + 1))
}

# 创建沙箱工作副本，避免触碰真实 .ssh_keys 目录
TMP_DIR="$(mktemp -d)"
cleanup_tmp() {
    rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

setup_sandbox() {
    local sandbox="$1"
    mkdir -p "$sandbox/tool" "$sandbox/bin" "$sandbox/.ssh_keys"
    cp "$REPO_ROOT/init.sh" "$sandbox/init.sh"
    cp "$REPO_ROOT/setup.sh" "$sandbox/setup.sh"
    cp "$REPO_ROOT/tool/ssh-agent.sh" "$sandbox/tool/ssh-agent.sh"
    chmod +x "$sandbox/init.sh" "$sandbox/setup.sh" "$sandbox/tool/ssh-agent.sh"
}

create_unix_socket() {
    local sock_path="$1"
    python3 -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
s.listen(1)
' "$sock_path" &
    # 等待 socket 文件就绪
    local i=0
    while [[ ! -S "$sock_path" && $i -lt 50 ]]; do
        sleep 0.05
        i=$((i + 1))
    done
}

# 1. 验证未初始化（缺少 current_key）时安全退出且不注册 EXIT trap
test_missing_current_key() {
    local sandbox="$TMP_DIR/missing_key"
    setup_sandbox "$sandbox"

    local rc=0
    local out
    out="$(bash -c 'rc=0; source "$1/setup.sh" || rc=$?; echo "TRAPS=$(trap -p EXIT)"; exit "$rc"' _ "$sandbox" 2>&1)" || rc=$?
    if [[ $rc -ne 0 ]] && [[ "$out" == *"未找到密钥配置文件"* ]] && [[ "$out" == *"TRAPS="* ]] && [[ "$out" != *"cleanup"* ]]; then
        pass "missing current_key fails cleanly without registering EXIT trap"
    else
        fail "missing current_key handling unexpected (rc=$rc, out=$out)"
    fi
}

# 2. 验证跨目录（非仓库根 cwd）和 POSIX 路径解析，以及新建临时 agent 的清理行为
test_fresh_agent_and_posix_resolution() {
    local sandbox="$TMP_DIR/fresh_agent"
    setup_sandbox "$sandbox"

    local key_file="$sandbox/.ssh_keys/test_id_ed25519"
    printf 'dummy-key\n' > "$key_file"
    printf 'ssh-ed25519 AAAATEST user@host\n' > "${key_file}.pub"
    printf '%s\n' "$key_file" > "$sandbox/.ssh_keys/current_key"

    local log_file="$sandbox/mock.log"
    local sock_path="$sandbox/new_agent.sock"

    cat > "$sandbox/bin/ssh-agent" <<'EOF'
#!/bin/bash
echo "ssh-agent $*" >> "$MOCK_LOG"
if [[ "${1:-}" == "-s" ]]; then
    echo "SSH_AUTH_SOCK=$MOCK_NEW_SOCK; export SSH_AUTH_SOCK;"
    echo "SSH_AGENT_PID=42424; export SSH_AGENT_PID;"
elif [[ "${1:-}" == "-k" ]]; then
    echo "unset SSH_AUTH_SOCK;"
    echo "unset SSH_AGENT_PID;"
fi
EOF
    cat > "$sandbox/bin/ssh-keygen" <<'EOF'
#!/bin/bash
echo "ssh-keygen $*" >> "$MOCK_LOG"
echo "256 SHA256:MockFingerprintTestKey comment (ED25519)"
EOF
    cat > "$sandbox/bin/ssh-add" <<'EOF'
#!/bin/bash
echo "ssh-add $*" >> "$MOCK_LOG"
if [[ "${1:-}" == "-l" ]]; then
    echo "The agent has no identities." >&2
    exit 1
fi
exit 0
EOF
    chmod +x "$sandbox/bin/ssh-agent" "$sandbox/bin/ssh-keygen" "$sandbox/bin/ssh-add"

    local out
    # shellcheck disable=SC2016
    out="$(cd /tmp && env -u SSH_AUTH_SOCK -u SSH_AGENT_PID \
        PATH="$sandbox/bin:$PATH" MOCK_LOG="$log_file" MOCK_NEW_SOCK="$sock_path" \
        bash -c 'source "$1/setup.sh"; echo "MY_ROOT=$MY_ROOT AGENT_STARTED=$AGENT_STARTED"' _ "$sandbox")"

    local expected_root
    expected_root="$(cd "$sandbox" && pwd -P)"
    if [[ "$out" == *"MY_ROOT=$expected_root AGENT_STARTED=true"* ]] \
        && grep -Fxq "ssh-agent -s" "$log_file" \
        && grep -Fxq "ssh-add $key_file" "$log_file" \
        && grep -Fxq "ssh-agent -k" "$log_file"; then
        pass "POSIX path resolution + fresh agent starts and cleans up with ssh-agent -k"
    else
        fail "fresh agent test failed (out=$out, log=$(cat "$log_file" 2>/dev/null || true))"
    fi
}

# 3. 验证已有 ssh-agent 时保持 AGENT_STARTED=false，退出时仅卸载密钥 (ssh-add -d)，不杀 agent
test_existing_agent_non_destructive_cleanup() {
    local sandbox="$TMP_DIR/existing_agent"
    setup_sandbox "$sandbox"

    local key_file="$sandbox/.ssh_keys/test_id_ed25519"
    printf 'dummy-key\n' > "$key_file"
    printf '%s\n' "$key_file" > "$sandbox/.ssh_keys/current_key"

    local sock_path="$sandbox/existing.sock"
    create_unix_socket "$sock_path"

    local log_file="$sandbox/mock.log"
    cat > "$sandbox/bin/ssh-agent" <<'EOF'
#!/bin/bash
echo "ssh-agent $*" >> "$MOCK_LOG"
EOF
    cat > "$sandbox/bin/ssh-keygen" <<'EOF'
#!/bin/bash
echo "256 SHA256:ExistingAgentKeyFingerprint comment (ED25519)"
EOF
    cat > "$sandbox/bin/ssh-add" <<'EOF'
#!/bin/bash
echo "ssh-add $*" >> "$MOCK_LOG"
if [[ "${1:-}" == "-l" ]]; then
    echo "256 SHA256:AnotherKey other (ED25519)"
    exit 0
fi
exit 0
EOF
    chmod +x "$sandbox/bin/ssh-agent" "$sandbox/bin/ssh-keygen" "$sandbox/bin/ssh-add"

    local out
    out="$(PATH="$sandbox/bin:$PATH" MOCK_LOG="$log_file" \
        SSH_AUTH_SOCK="$sock_path" SSH_AGENT_PID="99999" \
        bash -c 'source "$1/setup.sh"; echo "AGENT_STARTED=$AGENT_STARTED"' _ "$sandbox")"

    if [[ "$out" == *"AGENT_STARTED=false"* ]] \
        && ! grep -q "ssh-agent" "$log_file" \
        && grep -Fxq "ssh-add $key_file" "$log_file" \
        && grep -Fxq "ssh-add -d $key_file" "$log_file"; then
        pass "existing agent preserved (AGENT_STARTED=false, ssh-add -d used, no ssh-agent -k)"
    else
        fail "existing agent cleanup failed (out=$out, log=$(cat "$log_file" 2>/dev/null || true))"
    fi
}

# 4. 验证空指纹不误判为已添加，且有效指纹已存在时跳过重复 ssh-add
test_fingerprint_matching_safety() {
    local sandbox="$TMP_DIR/fp_safety"
    setup_sandbox "$sandbox"

    local key_file="$sandbox/.ssh_keys/test_id_ed25519"
    printf 'dummy-key\n' > "$key_file"
    printf '%s\n' "$key_file" > "$sandbox/.ssh_keys/current_key"

    local sock_path="$sandbox/fp.sock"
    create_unix_socket "$sock_path"

    local log_file="$sandbox/mock.log"
    cat > "$sandbox/bin/ssh-keygen" <<'EOF'
#!/bin/bash
# 返回空指纹，模拟异常密钥
exit 0
EOF
    cat > "$sandbox/bin/ssh-add" <<'EOF'
#!/bin/bash
echo "ssh-add $*" >> "$MOCK_LOG"
echo "256 SHA256:SomeKey comment (ED25519)"
EOF
    chmod +x "$sandbox/bin/ssh-keygen" "$sandbox/bin/ssh-add"

    local rc=0
    PATH="$sandbox/bin:$PATH" MOCK_LOG="$log_file" SSH_AUTH_SOCK="$sock_path" \
        bash -c 'source "$1/tool/ssh-agent.sh"' _ "$sandbox" >/dev/null 2>&1 || rc=$?
    if [[ $rc -ne 0 ]] && [[ ! -f "$log_file" ]]; then
        pass "empty fingerprint rejected without false match"
    else
        fail "empty fingerprint was not rejected (rc=$rc)"
    fi

    # 测试有效指纹已存在时不重复执行 ssh-add <key>
    cat > "$sandbox/bin/ssh-keygen" <<'EOF'
#!/bin/bash
echo "256 SHA256:ExactMatchFP comment (ED25519)"
EOF
    cat > "$sandbox/bin/ssh-add" <<'EOF'
#!/bin/bash
echo "ssh-add $*" >> "$MOCK_LOG"
if [[ "${1:-}" == "-l" ]]; then
    echo "256 SHA256:ExactMatchFP comment (ED25519)"
fi
EOF
    chmod +x "$sandbox/bin/ssh-keygen" "$sandbox/bin/ssh-add"
    rm -f "$log_file"

    PATH="$sandbox/bin:$PATH" MOCK_LOG="$log_file" SSH_AUTH_SOCK="$sock_path" \
        bash -c 'source "$1/tool/ssh-agent.sh"' _ "$sandbox" >/dev/null
    if grep -Fxq "ssh-add -l" "$log_file" && ! grep -Fxq "ssh-add $key_file" "$log_file"; then
        pass "already-loaded fingerprint skips duplicate ssh-add"
    else
        fail "duplicate ssh-add check failed (log=$(cat "$log_file" 2>/dev/null || true))"
    fi
}

# 5. 验证 init.sh 输入校验、权限 (0600/0644) 与无密码提示
test_init_validation_and_permissions() {
    local sandbox="$TMP_DIR/init_test"
    setup_sandbox "$sandbox"

    cat > "$sandbox/bin/ssh-keygen" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "-y" ]]; then
    # 模拟无密码密钥（-P "" 成功）
    exit 0
fi
key_out=""
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-f" ]]; then
        key_out="$2"
        shift 2
    else
        shift
    fi
done
printf 'PRIVATE\n' > "$key_out"
printf 'ssh-ed25519 AAAATEST test@example\n' > "${key_out}.pub"
EOF
    cat > "$sandbox/bin/ssh-copy-id" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$sandbox/bin/ssh-keygen" "$sandbox/bin/ssh-copy-id"

    # 测试拒绝含空格或引号的非法输入
    local bad_rc=0
    local bad_out
    bad_out="$(printf 'bad host;rm -rf\nuser\nalias\n' | PATH="$sandbox/bin:$PATH" bash "$sandbox/init.sh" 2>&1)" || bad_rc=$?
    if [[ $bad_rc -ne 0 ]] && [[ "$bad_out" == *"包含不安全字符"* ]]; then
        pass "init.sh rejects unsafe whitespace/shell metacharacters"
    else
        fail "init.sh failed to reject unsafe server_host (rc=$bad_rc, out=$bad_out)"
    fi

    # 测试合法输入生成密钥权限与无密码提示
    local good_out
    good_out="$(printf '10.0.0.5\nubuntu\nmybox\nn\n' | PATH="$sandbox/bin:$PATH" bash "$sandbox/init.sh" 2>&1)"
    local priv="$sandbox/.ssh_keys/mybox_id_ed25519"
    local pub="${priv}.pub"
    local priv_mode pub_mode
    if stat --version >/dev/null 2>&1; then
        priv_mode="$(stat -c '%a' "$priv")"
        pub_mode="$(stat -c '%a' "$pub")"
    else
        priv_mode="$(stat -f '%Lp' "$priv")"
        pub_mode="$(stat -f '%Lp' "$pub")"
    fi

    if [[ "$priv_mode" == "600" && "$pub_mode" == "644" ]] \
        && [[ "$good_out" == *"已生成无密码的SSH密钥"* ]] \
        && [[ "$(cat "$sandbox/.ssh_keys/current_key")" == "$(cd "$sandbox/.ssh_keys" && pwd -P)/mybox_id_ed25519" ]]; then
        pass "init.sh sets 0600/0644 permissions, warns on empty passphrase, writes current_key"
    else
        fail "init.sh permissions or output check failed (priv=$priv_mode, pub=$pub_mode, out=$good_out)"
    fi
}

test_missing_current_key
test_fresh_agent_and_posix_resolution
test_existing_agent_non_destructive_cleanup
test_fingerprint_matching_safety
test_init_validation_and_permissions

echo ""
echo "Summary: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
