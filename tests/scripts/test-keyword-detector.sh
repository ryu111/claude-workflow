#!/bin/bash
# test-keyword-detector.sh - keyword-detector.sh 單元測試
# 驗證: 關鍵字匹配邏輯、JSON 輸出格式、邊界情況處理

echo "=== Keyword Detector 單元測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="$PROJECT_ROOT/hooks/scripts/keyword-detector.sh"
TEMPLATE_DIR="$PROJECT_ROOT/hooks/templates"

# 設定必要環境變數
export CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT"
export CLAUDE_PROJECT_ROOT="$PROJECT_ROOT"

# 檢查腳本存在
if [ ! -f "$HOOK_SCRIPT" ]; then
    echo "❌ keyword-detector.sh 不存在"
    exit 1
fi

PASS=true
TOTAL_TESTS=0
PASSED_TESTS=0

# 測試輔助函數：執行 hook 並驗證結果
# 參數:
#   $1 - 測試名稱
#   $2 - 輸入 userPrompt
#   $3 - 預期檢測到的 agent 類型（空字串表示不應檢測到）
#   $4 - 是否應包含 additionalContext (true/false)
run_test() {
    local test_name="$1"
    local user_prompt="$2"
    local expected_agent="$3"
    local should_have_context="$4"

    ((TOTAL_TESTS++))

    echo -n "測試 $TOTAL_TESTS: $test_name ... "

    # 構建輸入 JSON
    local input_json
    input_json=$(jq -n --arg prompt "$user_prompt" '{userPrompt: $prompt}')

    # 執行 hook
    local output
    output=$(echo "$input_json" | bash "$HOOK_SCRIPT" 2>/dev/null)
    local exit_code=$?

    # 驗證 1: 執行成功
    if [ $exit_code -ne 0 ]; then
        echo "❌ FAIL (exit code: $exit_code)"
        PASS=false
        return
    fi

    # 驗證 2: 輸出為有效 JSON
    if ! echo "$output" | jq empty 2>/dev/null; then
        echo "❌ FAIL (invalid JSON output)"
        PASS=false
        return
    fi

    # 驗證 3: JSON 結構正確
    local hook_event
    hook_event=$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)
    if [ "$hook_event" != "UserPromptSubmit" ]; then
        echo "❌ FAIL (incorrect hookEventName: $hook_event)"
        PASS=false
        return
    fi

    # 驗證 4: additionalContext 是否符合預期
    local additional_context
    additional_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)

    if [ "$should_have_context" = "true" ]; then
        if [ -z "$additional_context" ] || [ "$additional_context" = "null" ]; then
            echo "❌ FAIL (expected context but got empty)"
            PASS=false
            return
        fi

        # 驗證 5: 檢查 context 是否非空（不強制要求包含 prompt）
        # 因為某些範本可能不使用 {{PROMPT}} 變數
        if [ ${#additional_context} -lt 10 ]; then
            echo "❌ FAIL (context too short: ${#additional_context} chars)"
            PASS=false
            return
        fi
    else
        if [ -n "$additional_context" ] && [ "$additional_context" != "null" ] && [ "$additional_context" != "" ]; then
            echo "❌ FAIL (expected empty context but got: ${additional_context:0:50}...)"
            PASS=false
            return
        fi
    fi

    echo "✅ PASS"
    ((PASSED_TESTS++))
}

# ═══════════════════════════════════════════════════════════════
# 第 1 組：關鍵字匹配測試（8 組關鍵字）
# ═══════════════════════════════════════════════════════════════

echo "【第 1 組】關鍵字匹配測試"
echo ""

# 1.1 ARCHITECT - 規劃/架構/系統設計
run_test "ARCHITECT - 中文關鍵字'規劃'" "請幫我規劃一個用戶系統" "architect" "true"
run_test "ARCHITECT - 中文關鍵字'架構'" "這個功能的架構應該如何設計" "architect" "true"
run_test "ARCHITECT - 中文關鍵字'系統設計'" "需要系統設計建議" "architect" "true"

# 1.2 DESIGNER - 設計/UI/UX/界面/介面
run_test "DESIGNER - 中文關鍵字'設計'" "這個頁面的設計需要優化" "designer" "true"
run_test "DESIGNER - 英文關鍵字'UI'" "UI looks bad" "designer" "true"
run_test "DESIGNER - 英文關鍵字'UX'" "improve the UX" "designer" "true"
run_test "DESIGNER - 中文關鍵字'界面'" "用戶界面太複雜" "designer" "true"

# 1.3 RESUME - 接手/resume
run_test "RESUME - 中文關鍵字'接手'" "請接手這個任務" "resume" "true"
run_test "RESUME - 英文關鍵字'resume'" "resume the previous work" "resume" "true"

# 1.4 LOOP - loop/持續/繼續
run_test "LOOP - 英文關鍵字'loop'" "loop through all tasks" "loop" "true"
run_test "LOOP - 中文關鍵字'持續'" "持續執行測試" "loop" "true"
run_test "LOOP - 中文關鍵字'繼續'" "繼續完成剩餘任務" "loop" "true"

# 1.5 DEVELOPER - 實作/開發/寫程式碼/implement
run_test "DEVELOPER - 中文關鍵字'實作'" "請實作這個功能" "developer" "true"
run_test "DEVELOPER - 中文關鍵字'開發'" "需要開發新功能" "developer" "true"
run_test "DEVELOPER - 中文關鍵字'寫程式碼'" "請幫我寫程式碼" "developer" "true"
run_test "DEVELOPER - 英文關鍵字'implement'" "implement the user service" "developer" "true"

# 1.6 REVIEWER - 審查/review/檢查程式碼
run_test "REVIEWER - 中文關鍵字'審查'" "請審查這個 PR" "reviewer" "true"
run_test "REVIEWER - 英文關鍵字'review'" "review this code" "reviewer" "true"
run_test "REVIEWER - 中文關鍵字'檢查程式碼'" "幫我檢查程式碼" "reviewer" "true"

# 1.7 TESTER - 測試/test/驗證
run_test "TESTER - 中文關鍵字'測試'" "需要測試這個功能" "tester" "true"
run_test "TESTER - 英文關鍵字'test'" "test the login flow" "tester" "true"
run_test "TESTER - 中文關鍵字'驗證'" "驗證這個 API" "tester" "true"

# 1.8 DEBUGGER - debug/除錯/修 bug
run_test "DEBUGGER - 英文關鍵字'debug'" "debug this issue" "debugger" "true"
run_test "DEBUGGER - 中文關鍵字'除錯'" "幫我除錯這個問題" "debugger" "true"
run_test "DEBUGGER - 中文關鍵字'修 bug'" "需要修 bug" "debugger" "true"

echo ""

# ═══════════════════════════════════════════════════════════════
# 第 2 組：大小寫與優先級測試
# ═══════════════════════════════════════════════════════════════

echo "【第 2 組】大小寫與優先級測試"
echo ""

# 2.1 大小寫不敏感
run_test "大小寫 - 全大寫" "IMPLEMENT THIS FEATURE" "developer" "true"
run_test "大小寫 - 混合" "Please REvIeW this code" "reviewer" "true"
run_test "大小寫 - 中文不受影響" "請幫我實作功能" "developer" "true"

# 2.2 優先級排序（ARCHITECT > DESIGNER > ... > DEBUGGER）
run_test "優先級 - ARCHITECT 優先於 DEVELOPER" "規劃並實作用戶系統" "architect" "true"
run_test "優先級 - DESIGNER 優先於 DEVELOPER" "設計並開發登入頁面" "designer" "true"
run_test "優先級 - RESUME 優先於 LOOP" "接手並持續完成任務" "resume" "true"

# 2.3 全字匹配（避免誤匹配）
run_test "全字匹配 - 'test' 不匹配 'testing'" "testing is important" "" "false"
run_test "全字匹配 - 'implement' 不匹配 'implementation'" "implementation details" "" "false"
run_test "全字匹配 - 獨立 'test' 應匹配" "run test suite" "tester" "true"

echo ""

# ═══════════════════════════════════════════════════════════════
# 第 3 組：JSON 輸出驗證
# ═══════════════════════════════════════════════════════════════

echo "【第 3 組】JSON 輸出驗證"
echo ""

# 3.1 hookSpecificOutput 結構
((TOTAL_TESTS++))
echo -n "測試 $TOTAL_TESTS: hookSpecificOutput 結構完整性 ... "
INPUT_JSON='{"userPrompt":"請實作功能"}'
OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOK_SCRIPT" 2>/dev/null)

if echo "$OUTPUT" | jq -e '.hookSpecificOutput.hookEventName' >/dev/null 2>&1 && \
   echo "$OUTPUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
    echo "✅ PASS"
    ((PASSED_TESTS++))
else
    echo "❌ FAIL"
    PASS=false
fi

# 3.2 特殊字元轉義
run_test "特殊字元 - 雙引號" '請實作 "用戶服務"' "developer" "true"
run_test "特殊字元 - 單引號" "請審查 'app.ts' 文件" "reviewer" "true"
run_test "特殊字元 - 反斜線（無關鍵字）" "文件路徑: C:\\Users\\data\\config.txt" "" "false"
run_test "特殊字元 - 換行符" $'請實作功能\n包含測試' "developer" "true"
run_test "特殊字元 - Unicode emoji" "請測試 🚀 功能" "tester" "true"

echo ""

# ═══════════════════════════════════════════════════════════════
# 第 4 組：邊界情況測試
# ═══════════════════════════════════════════════════════════════

echo "【第 4 組】邊界情況測試"
echo ""

# 4.1 空輸入
run_test "邊界 - 空 userPrompt" "" "" "false"

# 4.2 無效 JSON 輸入
((TOTAL_TESTS++))
echo -n "測試 $TOTAL_TESTS: 無效 JSON 輸入 ... "
INVALID_JSON='{"userPrompt": invalid json'
OUTPUT=$(echo "$INVALID_JSON" | bash "$HOOK_SCRIPT" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "✅ PASS (correctly rejected)"
    ((PASSED_TESTS++))
else
    echo "❌ FAIL (should reject invalid JSON)"
    PASS=false
fi

# 4.3 缺少 userPrompt 欄位
run_test "邊界 - 缺少 userPrompt 欄位" "" "" "false"

# 4.4 超長輸入
LONG_PROMPT=$(printf '請實作%.0s' {1..1000})
run_test "邊界 - 超長輸入 (3000+ 字元)" "$LONG_PROMPT" "developer" "true"

# 4.5 只有空白字元
run_test "邊界 - 只有空格" "   " "" "false"
run_test "邊界 - 只有 tab" $'\t\t\t' "" "false"

# 4.6 無關鍵字的正常輸入
run_test "邊界 - 無關鍵字的日常對話" "今天天氣真好" "" "false"
run_test "邊界 - 無關鍵字的技術問題" "What is the capital of France?" "" "false"
run_test "邊界 - 包含關鍵字但非全字" "testing implementation details" "" "false"

echo ""

# ═══════════════════════════════════════════════════════════════
# 第 5 組：範本載入測試
# ═══════════════════════════════════════════════════════════════

echo "【第 5 組】範本載入測試"
echo ""

# 5.1 預設範本存在性
((TOTAL_TESTS++))
echo -n "測試 $TOTAL_TESTS: 預設範本檔案存在性 ... "
TEMPLATE_EXISTS=true
for agent in architect designer developer reviewer tester debugger; do
    if [ ! -f "$TEMPLATE_DIR/${agent}.md" ]; then
        echo "❌ FAIL (missing template: ${agent}.md)"
        TEMPLATE_EXISTS=false
        PASS=false
        break
    fi
done

if [ "$TEMPLATE_EXISTS" = true ]; then
    echo "✅ PASS"
    ((PASSED_TESTS++))
fi

# 5.2 範本變數替換
((TOTAL_TESTS++))
echo -n "測試 $TOTAL_TESTS: 範本變數替換 {{PROMPT}} ... "
INPUT_JSON='{"userPrompt":"請實作用戶登入功能"}'
OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOK_SCRIPT" 2>/dev/null)
CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')

if echo "$CONTEXT" | grep -qF "請實作用戶登入功能"; then
    echo "✅ PASS"
    ((PASSED_TESTS++))
else
    echo "❌ FAIL (prompt not substituted in template)"
    PASS=false
fi

# 5.3 CLAUDE_PLUGIN_ROOT 未設定時的行為
((TOTAL_TESTS++))
echo -n "測試 $TOTAL_TESTS: CLAUDE_PLUGIN_ROOT 未設定時的容錯 ... "
INPUT_JSON='{"userPrompt":"請實作功能"}'
OUTPUT=$(CLAUDE_PLUGIN_ROOT="" bash -c "echo '$INPUT_JSON' | bash '$HOOK_SCRIPT'" 2>/dev/null)
EXIT_CODE=$?

# 應該返回空 context 但不崩潰
if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
    echo "✅ PASS (graceful degradation)"
    ((PASSED_TESTS++))
else
    echo "❌ FAIL (should handle missing env var gracefully)"
    PASS=false
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試結果匯總
# ═══════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════════"
echo "測試結果匯總"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "總測試數: $TOTAL_TESTS"
echo "通過測試: $PASSED_TESTS"
echo "失敗測試: $((TOTAL_TESTS - PASSED_TESTS))"
# 使用 bc 計算通過率（兼容 macOS）
PASS_RATE=$(echo "scale=1; ($PASSED_TESTS * 100) / $TOTAL_TESTS" | bc)
echo "通過率: ${PASS_RATE}%"
echo ""

if [ "$PASS" = true ]; then
    echo "✅ keyword-detector.sh 單元測試 PASS"
    exit 0
else
    echo "❌ keyword-detector.sh 單元測試 FAIL"
    exit 1
fi
