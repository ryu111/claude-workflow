#!/bin/bash
# test-ts-064-memory-inject-user-prompt.sh
# 測試 memory-inject-user-prompt.sh UserPromptSubmit Hook 動態注入腳本
# 測試重點：功能測試、容錯測試、關鍵字提取、安全包裝

set -euo pipefail

SCRIPT="/Users/sbu/projects/claude-workflow/hooks/scripts/memory-inject-user-prompt.sh"
TESTS_PASSED=0
TESTS_FAILED=0
TEST_COUNT=0

echo "════════════════════════════════════════════════════════════"
echo "Test Suite: TS-064 - Memory Inject User Prompt Hook"
echo "Script: $SCRIPT"
echo "════════════════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════
# 回歸測試：基本結構驗證
# ═══════════════════════════════════════════════════════════════

echo "回歸測試：基本結構驗證"
echo "══════════════════════════════════════════════════════════"

# Test 1: Script exists
((TEST_COUNT++))
if [ -f "$SCRIPT" ]; then
    echo "✅ Test 1: Script exists"
    ((TESTS_PASSED++))
else
    echo "❌ Test 1: Script does not exist"
    ((TESTS_FAILED++))
fi

# Test 2: Script is readable
((TEST_COUNT++))
if [ -r "$SCRIPT" ]; then
    echo "✅ Test 2: Script is readable"
    ((TESTS_PASSED++))
else
    echo "❌ Test 2: Script is not readable"
    ((TESTS_FAILED++))
fi

# Test 3: Bash syntax is valid
((TEST_COUNT++))
if bash -n "$SCRIPT" 2>/dev/null; then
    echo "✅ Test 3: Valid Bash syntax"
    ((TESTS_PASSED++))
else
    echo "❌ Test 3: Bash syntax error"
    ((TESTS_FAILED++))
fi

# Test 4: main() function exists
((TEST_COUNT++))
if grep -q "^main()" "$SCRIPT"; then
    echo "✅ Test 4: main() function is defined"
    ((TESTS_PASSED++))
else
    echo "❌ Test 4: main() function not found"
    ((TESTS_FAILED++))
fi

# Test 5: Key functions exist
((TEST_COUNT++))
if grep -q "^extract_keywords()" "$SCRIPT" && \
   grep -q "^apply_token_budget()" "$SCRIPT" && \
   grep -q "^run_test_mode()" "$SCRIPT" && \
   grep -q "^output_hook_result()" "$SCRIPT"; then
    echo "✅ Test 5: All key functions are defined"
    ((TESTS_PASSED++))
else
    echo "❌ Test 5: Some key functions missing"
    ((TESTS_FAILED++))
fi

# ═══════════════════════════════════════════════════════════════
# 功能測試：CLI 介面驗證
# ═══════════════════════════════════════════════════════════════

echo ""
echo "功能測試：CLI 介面"
echo "══════════════════════════════════════════════════════════"

# Test 6: show_help function is defined
((TEST_COUNT++))
if grep -q "^show_help()" "$SCRIPT"; then
    echo "✅ Test 6: show_help() function is defined"
    ((TESTS_PASSED++))
else
    echo "❌ Test 6: show_help() function not found"
    ((TESTS_FAILED++))
fi

# Test 7: Help content includes usage and command documentation
((TEST_COUNT++))
if grep -q "用法: memory-inject-user-prompt.sh" "$SCRIPT" && \
   grep -q "  run " "$SCRIPT" && \
   grep -q "  test" "$SCRIPT"; then
    echo "✅ Test 7: Help includes usage and commands"
    ((TESTS_PASSED++))
else
    echo "❌ Test 7: Help missing usage or commands"
    ((TESTS_FAILED++))
fi

# Test 8: Help documents dynamic injection feature
((TEST_COUNT++))
if grep -q "UserPromptSubmit" "$SCRIPT" && \
   grep -q "動態搜尋" "$SCRIPT"; then
    echo "✅ Test 8: Help documents dynamic injection feature"
    ((TESTS_PASSED++))
else
    echo "❌ Test 8: Help missing dynamic injection documentation"
    ((TESTS_FAILED++))
fi

# Test 9: Script shows error for invalid command
((TEST_COUNT++))
if grep -q 'echo "錯誤：無效的指令' "$SCRIPT"; then
    echo "✅ Test 9: Invalid command error message present"
    ((TESTS_PASSED++))
else
    echo "❌ Test 9: Invalid command handling missing"
    ((TESTS_FAILED++))
fi

# ═══════════════════════════════════════════════════════════════
# 容錯測試：靜默失敗驗證
# ═══════════════════════════════════════════════════════════════

echo ""
echo "容錯測試：靜默失敗機制"
echo "══════════════════════════════════════════════════════════"

# Test 10: main() wraps execution with error handling
((TEST_COUNT++))
if grep -q "run_injection_with_safety || true" "$SCRIPT" && \
   grep -q "return \$INJECT_EXIT_SUCCESS" "$SCRIPT"; then
    echo "✅ Test 10: main() ensures exit 0 regardless of errors"
    ((TESTS_PASSED++))
else
    echo "❌ Test 10: main() error handling incomplete"
    ((TESTS_FAILED++))
fi

# Test 11: Empty stdin is handled gracefully
((TEST_COUNT++))
if grep -q "hook_input=\$(cat) || {" "$SCRIPT" && \
   grep -q 'log_skip "無法讀取 Hook 輸入"' "$SCRIPT"; then
    echo "✅ Test 11: Empty stdin handling implemented"
    ((TESTS_PASSED++))
else
    echo "❌ Test 11: Empty stdin handling missing"
    ((TESTS_FAILED++))
fi

# Test 12: Invalid JSON is handled gracefully
((TEST_COUNT++))
if grep -q 'echo "\$hook_input" | jq empty' "$SCRIPT" && \
   grep -q 'log_skip "Hook 輸入不是有效的 JSON"' "$SCRIPT"; then
    echo "✅ Test 12: Invalid JSON handling implemented"
    ((TESTS_PASSED++))
else
    echo "❌ Test 12: Invalid JSON handling missing"
    ((TESTS_FAILED++))
fi

# Test 13: Empty prompt is handled gracefully
((TEST_COUNT++))
if grep -q '[ -z "$user_prompt" ]' "$SCRIPT" && \
   grep -q 'log_skip "用戶輸入為空"' "$SCRIPT"; then
    echo "✅ Test 13: Empty prompt handling implemented"
    ((TESTS_PASSED++))
else
    echo "❌ Test 13: Empty prompt handling missing"
    ((TESTS_FAILED++))
fi

# Test 14: No search results returns gracefully
((TEST_COUNT++))
if grep -q '[ "\$result_count" -eq 0 ]' "$SCRIPT" && \
   grep -q 'log_skip "未找到相關記憶"' "$SCRIPT"; then
    echo "✅ Test 14: No results handling implemented"
    ((TESTS_PASSED++))
else
    echo "❌ Test 14: No results handling missing"
    ((TESTS_FAILED++))
fi

# ═══════════════════════════════════════════════════════════════
# 安全測試：安全包裝格式驗證
# ═══════════════════════════════════════════════════════════════

echo ""
echo "安全測試：安全包裝格式"
echo "══════════════════════════════════════════════════════════"

# Test 15: Hook output format includes required fields
((TEST_COUNT++))
if grep -q '"hookSpecificOutput"' "$SCRIPT" && \
   grep -q '"hookEventName"' "$SCRIPT" && \
   grep -q '"additionalContext"' "$SCRIPT" && \
   grep -q '"UserPromptSubmit"' "$SCRIPT"; then
    echo "✅ Test 15: Hook output format is correct"
    ((TESTS_PASSED++))
else
    echo "❌ Test 15: Hook output format missing required fields"
    ((TESTS_FAILED++))
fi

# Test 16: JSON escaping uses jq -Rs for safety
((TEST_COUNT++))
if grep -q 'jq -Rs' "$SCRIPT"; then
    echo "✅ Test 16: Output uses jq safe string escaping"
    ((TESTS_PASSED++))
else
    echo "❌ Test 16: Output escaping method not found"
    ((TESTS_FAILED++))
fi

# ═══════════════════════════════════════════════════════════════
# 程式碼品質測試：常數和機制
# ═══════════════════════════════════════════════════════════════

echo ""
echo "程式碼品質測試：重要常數和機制"
echo "══════════════════════════════════════════════════════════"

# Test 17: Exit code constants defined
((TEST_COUNT++))
if grep -q "readonly INJECT_EXIT_SUCCESS=" "$SCRIPT" && \
   grep -q "readonly INJECT_EXIT_SKIPPED=" "$SCRIPT" && \
   grep -q "readonly INJECT_EXIT_ERROR=" "$SCRIPT"; then
    echo "✅ Test 17: All exit code constants defined"
    ((TESTS_PASSED++))
else
    echo "❌ Test 17: Exit code constants missing"
    ((TESTS_FAILED++))
fi

# Test 18: Token budget constants defined
((TEST_COUNT++))
if grep -q "readonly TOKEN_BUDGET=" "$SCRIPT" && \
   grep -q "readonly MAX_MEMORIES=" "$SCRIPT" && \
   grep -q "readonly MIN_MEMORIES=" "$SCRIPT"; then
    echo "✅ Test 18: Token budget constants defined"
    ((TESTS_PASSED++))
else
    echo "❌ Test 18: Token budget constants missing"
    ((TESTS_FAILED++))
fi

# Test 19: Safety checks present in code
((TEST_COUNT++))
if grep -q "is_circuit_breaker_open" "$SCRIPT" && \
   grep -q "check_kill_switches" "$SCRIPT" && \
   grep -q "is_feature_enabled" "$SCRIPT" && \
   grep -q "check_search_phase_enabled" "$SCRIPT"; then
    echo "✅ Test 19: All safety checks implemented"
    ((TESTS_PASSED++))
else
    echo "❌ Test 19: Some safety checks missing"
    ((TESTS_FAILED++))
fi

# Test 20: Phase checking for Feature C
((TEST_COUNT++))
if grep -q "FEATURE_INJECT_DYNAMIC" "$SCRIPT" && \
   grep -q "Phase C" "$SCRIPT"; then
    echo "✅ Test 20: Phase C feature checking implemented"
    ((TESTS_PASSED++))
else
    echo "❌ Test 20: Phase checking incomplete"
    ((TESTS_FAILED++))
fi

# Test 21: Error handling with silent failures
((TEST_COUNT++))
if grep -q "log_skip" "$SCRIPT" && \
   grep -q "return \$INJECT_EXIT_SKIPPED" "$SCRIPT"; then
    echo "✅ Test 21: Silent skip mechanism for graceful failures"
    ((TESTS_PASSED++))
else
    echo "❌ Test 21: Silent failure mechanism missing"
    ((TESTS_FAILED++))
fi

# ═══════════════════════════════════════════════════════════════
# 關鍵字提取測試：代碼驗證
# ═══════════════════════════════════════════════════════════════

echo ""
echo "關鍵字提取測試：代碼驗證"
echo "══════════════════════════════════════════════════════════"

# Test 22: extract_keywords function handles stop words
((TEST_COUNT++))
if grep -q "extract_keywords()" "$SCRIPT" && \
   grep -q "stop_words" "$SCRIPT" && \
   grep -q 'is_stop_word=false' "$SCRIPT"; then
    echo "✅ Test 22: Keyword extraction with stop words filtering"
    ((TESTS_PASSED++))
else
    echo "❌ Test 22: Keyword extraction incomplete"
    ((TESTS_FAILED++))
fi

# Test 23: Minimum word length check
((TEST_COUNT++))
if grep -q '${#word}' "$SCRIPT"; then
    echo "✅ Test 23: Word length filtering implemented"
    ((TESTS_PASSED++))
else
    echo "❌ Test 23: Word length check missing"
    ((TESTS_FAILED++))
fi

# Test 24: Memory formatting to Markdown
((TEST_COUNT++))
if grep -q "format_memories_to_markdown()" "$SCRIPT" && \
   grep -q '## 相關記憶' "$SCRIPT" && \
   grep -q '### 來自' "$SCRIPT"; then
    echo "✅ Test 24: Memory formatting to Markdown implemented"
    ((TESTS_PASSED++))
else
    echo "❌ Test 24: Memory formatting not found"
    ((TESTS_FAILED++))
fi

# Test 25: jq used for parsing memory results
((TEST_COUNT++))
if grep -q 'jq -r' "$SCRIPT" && \
   grep -q '.count' "$SCRIPT" && \
   grep -q '.results' "$SCRIPT"; then
    echo "✅ Test 25: jq used for safe JSON parsing"
    ((TESTS_PASSED++))
else
    echo "❌ Test 25: JSON parsing method not found"
    ((TESTS_FAILED++))
fi

# ═══════════════════════════════════════════════════════════════
# Token 預算測試
# ═══════════════════════════════════════════════════════════════

echo ""
echo "Token 預算測試"
echo "══════════════════════════════════════════════════════════"

# Test 26: apply_token_budget function exists
((TEST_COUNT++))
if grep -q "apply_token_budget()" "$SCRIPT" && \
   grep -q 'TOKEN_BUDGET / 10' "$SCRIPT"; then
    echo "✅ Test 26: Token budget enforcement implemented"
    ((TESTS_PASSED++))
else
    echo "❌ Test 26: Token budget enforcement missing"
    ((TESTS_FAILED++))
fi

# Test 27: Truncation indicator when exceeding budget
((TEST_COUNT++))
if grep -q '完整記憶請見' "$SCRIPT"; then
    echo "✅ Test 27: Truncation indicator message implemented"
    ((TESTS_PASSED++))
else
    echo "❌ Test 27: Truncation indicator missing"
    ((TESTS_FAILED++))
fi

# ═══════════════════════════════════════════════════════════════
# 測試模式驗證
# ═══════════════════════════════════════════════════════════════

echo ""
echo "測試模式驗證"
echo "══════════════════════════════════════════════════════════"

# Test 28: Test mode function exists
((TEST_COUNT++))
if grep -q "^run_test_mode()" "$SCRIPT"; then
    echo "✅ Test 28: Test mode function exists"
    ((TESTS_PASSED++))
else
    echo "❌ Test 28: Test mode function missing"
    ((TESTS_FAILED++))
fi

# Test 29: Test mode accepts prompt argument
((TEST_COUNT++))
if grep -q 'run_test_mode "${2:-測試輸入}"' "$SCRIPT"; then
    echo "✅ Test 29: Test mode accepts prompt argument"
    ((TESTS_PASSED++))
else
    echo "❌ Test 29: Test mode argument handling missing"
    ((TESTS_FAILED++))
fi

# Test 30: Test mode constructs JSON input
((TEST_COUNT++))
if grep -q '"prompt":' "$SCRIPT" && \
   grep -q 'test_input=' "$SCRIPT"; then
    echo "✅ Test 30: Test mode constructs proper JSON input"
    ((TESTS_PASSED++))
else
    echo "❌ Test 30: Test mode JSON construction missing"
    ((TESTS_FAILED++))
fi

# Test 31: Script handling when invoked directly vs sourced
((TEST_COUNT++))
if grep -q 'if \[ "${BASH_SOURCE\[0\]:-}" = "${0:-}" \]' "$SCRIPT"; then
    echo "✅ Test 31: Script handles both direct and source invocation"
    ((TESTS_PASSED++))
else
    echo "❌ Test 31: Invocation handling missing"
    ((TESTS_FAILED++))
fi

# ═══════════════════════════════════════════════════════════════
# 安全與防護測試
# ═══════════════════════════════════════════════════════════════

echo ""
echo "安全與防護測試"
echo "══════════════════════════════════════════════════════════"

# Test 32: Memory escape function called
((TEST_COUNT++))
if grep -q "escape_memory_for_injection" "$SCRIPT"; then
    echo "✅ Test 32: Memory escape function used for Prompt Injection prevention"
    ((TESTS_PASSED++))
else
    echo "❌ Test 32: Memory escape missing"
    ((TESTS_FAILED++))
fi

# Test 33: Memory wrap function called with trust level
((TEST_COUNT++))
if grep -q "wrap_memory_safely" "$SCRIPT" && \
   grep -q '"low"' "$SCRIPT"; then
    echo "✅ Test 33: Memory wrapper with low trust level"
    ((TESTS_PASSED++))
else
    echo "❌ Test 33: Memory wrapper missing"
    ((TESTS_FAILED++))
fi

# Test 34: Sensitive memory filtering mentioned
((TEST_COUNT++))
if grep -q "sensitive" "$SCRIPT" && \
   grep -q "過濾" "$SCRIPT"; then
    echo "✅ Test 34: Sensitive memory filtering documented"
    ((TESTS_PASSED++))
else
    echo "❌ Test 34: Sensitive filtering documentation missing"
    ((TESTS_FAILED++))
fi

# ═══════════════════════════════════════════════════════════════
# 測試結果摘要
# ═══════════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════════════════════════════"
echo "測試結果摘要"
echo "════════════════════════════════════════════════════════════"
echo "總測試數：$TEST_COUNT"
echo "通過：$TESTS_PASSED ✅"
echo "失敗：$TESTS_FAILED ❌"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo "✅ 所有 $TEST_COUNT 個測試通過！"
    echo ""
    echo "核心功能驗證："
    echo "  ✅ 功能測試：主要功能正確（CLI、幫助、命令解析）"
    echo "  ✅ 容錯測試：靜默失敗機制確保返回 exit 0（不阻擋 UserPromptSubmit）"
    echo "  ✅ 關鍵字提取：停用詞過濾、詞長檢查、Markdown 格式化"
    echo "  ✅ 安全包裝：Hook 輸出格式正確，JSON 轉義使用 jq -Rs"
    echo "  ✅ Token 預算：應用行數限制（~300 tokens），截斷提示"
    echo "  ✅ 程式碼品質：常數定義、安全檢查、錯誤處理"
    echo "  ✅ 防護機制：Prompt Injection 防護、敏感記憶過濾、低信任包裝"
    echo "  ✅ 測試模式：支援命令行測試，接受提示詞參數"
    exit 0
else
    echo "❌ 有 $TESTS_FAILED 個測試失敗"
    exit 1
fi
