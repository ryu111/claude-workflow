#!/bin/bash
# test-bash-whitelist-fix.sh - 測試 Bash 白名單修復

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD_SCRIPT="$PROJECT_ROOT/hooks/scripts/global-workflow-guard.sh"

# ═══════════════════════════════════════════════════════════════
# 測試框架
# ═══════════════════════════════════════════════════════════════

PASSED=0
FAILED=0

print_header() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

test_command() {
    local test_name="$1"
    local command="$2"
    local should_allow="$3"  # "allow" or "block"

    echo -n "Testing: $test_name ... "

    # 準備 JSON 輸入
    local json_input=$(cat <<EOF
{
    "tool_name": "Bash",
    "tool_input": {
        "command": "$command",
        "description": "Test command"
    }
}
EOF
    )

    # 執行測試（Main Agent 模式）
    export CLAUDE_SESSION_ID="test-$$"
    rm -f "/tmp/claude-agent-state-test-$$" 2>/dev/null || true

    local output
    local exit_code
    output=$(echo "$json_input" | bash "$GUARD_SCRIPT" 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}

    # 檢查結果
    local decision=$(echo "$output" | jq -r '.decision // "allow"' 2>/dev/null)

    if [ "$should_allow" = "allow" ]; then
        # 應該允許
        if [ "$exit_code" -eq 0 ] && [ "$decision" != "block" ]; then
            echo "✅ PASS (allowed as expected)"
            ((PASSED++))
        else
            echo "❌ FAIL (should allow but was blocked)"
            echo "   Command: $command"
            echo "   Decision: $decision"
            ((FAILED++))
        fi
    else
        # 應該阻擋
        if [ "$decision" = "block" ]; then
            echo "✅ PASS (blocked as expected)"
            ((PASSED++))
        else
            echo "❌ FAIL (should block but was allowed)"
            echo "   Command: $command"
            ((FAILED++))
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# 測試案例
# ═══════════════════════════════════════════════════════════════

print_header "Bash 白名單修復測試"

echo "測試目標：確保安全的重定向不被誤判為危險操作"
echo ""

print_header "✅ 應該允許的命令（安全的重定向）"

test_command \
    "ls with 2>/dev/null" \
    "ls -la 2>/dev/null" \
    "allow"

test_command \
    "git status with 2>&1" \
    "git status 2>&1" \
    "allow"

test_command \
    "cat to /dev/null" \
    "cat file.txt >/dev/null" \
    "allow"

test_command \
    "find with 2>/dev/null" \
    "find . -name '*.ts' 2>/dev/null" \
    "allow"

test_command \
    "ls with || echo and 2>/dev/null" \
    "ls -la /nonexistent 2>/dev/null || echo 'not found'" \
    "allow"

test_command \
    "numbered stdout redirect to /dev/null" \
    "cat file.txt 1>/dev/null" \
    "allow"

test_command \
    "git diff with 2>&1" \
    "git diff --stat 2>&1" \
    "allow"

print_header "❌ 應該阻擋的命令（危險的寫入操作）"

test_command \
    "echo to file" \
    "echo 'test' > file.txt" \
    "block"

test_command \
    "ls append to file" \
    "ls >> output.log" \
    "block"

test_command \
    "cat with tee" \
    "cat file.txt | tee backup.txt" \
    "block"

test_command \
    "redirect to non-dev-null" \
    "ls -la > /tmp/output.txt" \
    "block"

test_command \
    "append with 2>>" \
    "command 2>> error.log" \
    "block"

print_header "✅ 應該允許的命令（v0.7 最小必要阻擋原則）"

test_command \
    "command substitution" \
    "echo \$(cat secrets.txt)" \
    "allow"

test_command \
    "backticks" \
    "echo \`whoami\`" \
    "allow"

test_command \
    "pipe chain" \
    "git log | head | grep test" \
    "allow"

# ═══════════════════════════════════════════════════════════════
# 測試報告
# ═══════════════════════════════════════════════════════════════

print_header "測試結果"

echo "✅ Passed: $PASSED"
echo "❌ Failed: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "🎉 所有測試通過！Bash 白名單修復成功。"
    exit 0
else
    echo "⚠️  有 $FAILED 個測試失敗。需要進一步調整。"
    exit 1
fi
