#!/bin/bash
# test-bash-pattern-logic.sh - 單元測試：Bash 命令阻擋邏輯
#
# 測試目標：驗證 global-workflow-guard.sh 的 Bash 命令檢測邏輯
# 原則：v0.7 最小必要阻擋 - 只阻擋檔案寫入（>, >>, tee）

set -euo pipefail

echo "═══════════════════════════════════════════════════════════════"
echo "  Bash 命令阻擋邏輯單元測試"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "測試原則：v0.7 最小必要阻擋"
echo "  ✅ 允許：管道、邏輯運算、命令替換、安全重定向"
echo "  ❌ 阻擋：檔案寫入（>, >>, tee）"
echo ""

# 測試邏輯（與 global-workflow-guard.sh 一致）
test_bash_logic() {
    local name="$1"
    local cmd="$2"
    local expected="$3"

    # Step 1: Sanitize（移除安全的重定向）
    SANITIZED=$(echo "$cmd" | sed -E 's/[0-9]*> *(&[0-9]+|\/dev\/null)//g' | sed -E 's/[0-9]*>> *\/dev\/null//g')

    # Step 2: Pattern match（檔案寫入檢測）
    PATTERN='(^|[;&[:space:]])([0-9]*>>?)[[:space:]]*[^&[:space:]]|[[:space:]]tee[[:space:]]'

    if echo "$SANITIZED" | grep -qE "$PATTERN"; then
        RESULT="BLOCKED"
    else
        RESULT="ALLOWED"
    fi

    if [ "$RESULT" = "$expected" ]; then
        echo "✅ $name"
        return 0
    else
        echo "❌ $name"
        echo "   Command: $cmd"
        echo "   Expected: $expected, Got: $RESULT"
        echo "   Sanitized: $SANITIZED"
        return 1
    fi
}

FAILED=0

echo "【應該允許的命令】："
test_bash_logic "stderr 到 /dev/null" "ls -la 2>/dev/null" "ALLOWED" || ((FAILED++))
test_bash_logic "stderr 和 stdout 合併" "git status 2>&1" "ALLOWED" || ((FAILED++))
test_bash_logic "stdout 到 /dev/null" "cat file.txt >/dev/null" "ALLOWED" || ((FAILED++))
test_bash_logic "find 忽略錯誤" "find . -name '*.ts' 2>/dev/null" "ALLOWED" || ((FAILED++))
test_bash_logic "邏輯 OR 帶 /dev/null" "ls -la /nonexistent 2>/dev/null || echo 'not found'" "ALLOWED" || ((FAILED++))
test_bash_logic "編號的 stdout 到 /dev/null" "cat file.txt 1>/dev/null" "ALLOWED" || ((FAILED++))
test_bash_logic "git diff 靜默" "git diff > /dev/null" "ALLOWED" || ((FAILED++))
test_bash_logic "邏輯 OR" "tail -50 file.log || echo error" "ALLOWED" || ((FAILED++))
test_bash_logic "管道" "git log | head" "ALLOWED" || ((FAILED++))
test_bash_logic "邏輯 AND" "npm install && npm test" "ALLOWED" || ((FAILED++))
test_bash_logic "命令替換 \$()" "echo \$(cat file)" "ALLOWED" || ((FAILED++))
test_bash_logic "命令替換 \`\`" "echo \`whoami\`" "ALLOWED" || ((FAILED++))
test_bash_logic "管道鏈" "cat file | grep test | wc -l" "ALLOWED" || ((FAILED++))

echo ""
echo "【應該阻擋的命令】："
test_bash_logic "覆寫檔案" "echo 'test' > file.txt" "BLOCKED" || ((FAILED++))
test_bash_logic "追加檔案" "ls >> output.log" "BLOCKED" || ((FAILED++))
test_bash_logic "tee 寫入" "cat file.txt | tee backup.txt" "BLOCKED" || ((FAILED++))
test_bash_logic "重定向到實體檔案" "ls -la > /tmp/output.txt" "BLOCKED" || ((FAILED++))
test_bash_logic "stderr 追加到檔案" "command 2>> error.log" "BLOCKED" || ((FAILED++))
test_bash_logic "stderr 寫入到檔案" "command 2> error.log" "BLOCKED" || ((FAILED++))

echo ""
echo "═══════════════════════════════════════════════════════════════"
if [ $FAILED -eq 0 ]; then
    echo "✅ 所有測試通過 (0 failed)"
    echo "═══════════════════════════════════════════════════════════════"
    exit 0
else
    echo "❌ 測試失敗 ($FAILED failed)"
    echo "═══════════════════════════════════════════════════════════════"
    exit 1
fi
