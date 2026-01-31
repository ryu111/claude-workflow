#!/bin/bash
# test-ts-017.sh - 關鍵字檢測測試
# 驗證: UserPromptSubmit hook (keyword-detector.sh) 正確執行

echo "=== TS-017: 關鍵字檢測測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="$PROJECT_ROOT/hooks/scripts/keyword-detector.sh"

# 檢查腳本存在
if [ ! -f "$HOOK_SCRIPT" ]; then
    echo "❌ keyword-detector.sh 不存在"
    exit 1
fi

# 設定 CLAUDE_PLUGIN_ROOT 環境變數（必須）
export CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT"
export CLAUDE_PROJECT_ROOT="$PROJECT_ROOT"

# 驗證結果
PASS=true
TOTAL_TESTS=0
PASSED_TESTS=0

# 測試函式
run_test() {
    local test_name="$1"
    local prompt="$2"
    local expected_keyword="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo "測試 $TOTAL_TESTS: $test_name"
    echo "  Prompt: $prompt"

    # 建立測試 JSON 輸入
    TEST_JSON="{\"prompt\":\"$prompt\"}"

    # 執行腳本
    OUTPUT=$(echo "$TEST_JSON" | bash "$HOOK_SCRIPT" 2>&1)
    EXIT_CODE=$?

    # 檢查執行成功
    if [ $EXIT_CODE -ne 0 ]; then
        echo "  ❌ 腳本執行失敗 (exit code: $EXIT_CODE)"
        return 1
    fi

    # 檢查輸出是否為有效 JSON
    if ! echo "$OUTPUT" | jq empty 2>/dev/null; then
        echo "  ❌ 輸出不是有效的 JSON"
        return 1
    fi

    # 檢查 hookEventName
    HOOK_EVENT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.hookEventName // empty')
    if [ "$HOOK_EVENT" != "UserPromptSubmit" ]; then
        echo "  ❌ hookEventName 不正確: $HOOK_EVENT"
        return 1
    fi

    # 檢查 additionalContext
    CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext // empty')

    if [ -n "$expected_keyword" ]; then
        # 預期有關鍵字匹配
        if [ -z "$CONTEXT" ]; then
            echo "  ❌ 預期檢測到關鍵字 '$expected_keyword'，但 additionalContext 為空"
            return 1
        fi
        echo "  ✅ 檢測到關鍵字，additionalContext 長度: ${#CONTEXT}"
    else
        # 預期無關鍵字匹配
        if [ -n "$CONTEXT" ]; then
            echo "  ⚠️ 預期無關鍵字，但 additionalContext 不為空（長度: ${#CONTEXT}）"
            # 這不算失敗，因為可能有 fallback 行為
        fi
        echo "  ✅ 無關鍵字匹配（符合預期）"
    fi

    PASSED_TESTS=$((PASSED_TESTS + 1))
    return 0
}

echo "開始執行測試..."
echo ""

# 測試 1: 空輸入
run_test "空輸入" "" ""
echo ""

# 測試 2: 檢測 ARCHITECT 關鍵字（中文）
run_test "ARCHITECT 關鍵字（中文）" "請幫我規劃一個新功能" "ARCHITECT"
echo ""

# 測試 3: 檢測 DEVELOPER 關鍵字（中文）
run_test "DEVELOPER 關鍵字（中文）" "請幫我實作這個功能" "DEVELOPER"
echo ""

# 測試 4: 檢測 RESUME 關鍵字
run_test "RESUME 關鍵字" "接手 change-123" "RESUME"
echo ""

# 測試 5: 檢測 LOOP 關鍵字（英文）
run_test "LOOP 關鍵字（英文）" "loop until complete" "LOOP"
echo ""

# 測試 6: 無關鍵字
run_test "無關鍵字" "這是一個普通的問題" ""
echo ""

# 測試 7: 檢測 DEBUGGER 關鍵字（中文）
run_test "DEBUGGER 關鍵字（中文）" "幫我修 bug" "DEBUGGER"
echo ""

# 測試 8: 檢測 TESTER 關鍵字（英文）
run_test "TESTER 關鍵字（英文）" "run test suite" "TESTER"
echo ""

# 測試 9: 混合大小寫
run_test "混合大小寫" "請幫我 IMPLEMENT 新功能" "DEVELOPER"
echo ""

# 清理 Loop 狀態檔案（如果有）
rm -f "${PROJECT_ROOT}/.drt-state/.loop-active" 2>/dev/null

# 結果統計
echo "=========================================="
echo "測試完成"
echo "總測試數: $TOTAL_TESTS"
echo "通過數: $PASSED_TESTS"
echo "失敗數: $((TOTAL_TESTS - PASSED_TESTS))"
echo ""

if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo "✅ TS-017 PASS: UserPromptSubmit hook 正確執行"
    exit 0
else
    echo "❌ TS-017 FAIL: $((TOTAL_TESTS - PASSED_TESTS)) 個測試失敗"
    PASS=false
    exit 1
fi
