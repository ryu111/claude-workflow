#!/bin/bash
# test-ts-005.sh - TESTER FAIL 測試
# 驗證: FAIL 後正確記錄狀態，提示啟動 DEBUGGER

echo "=== TS-005: TESTER FAIL 測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$PROJECT_ROOT/hooks/scripts/subagent-validator.sh"
STATE_DIR="$PROJECT_ROOT/.claude"
TEST_CHANGE_ID="test-005"
STATE_AUTO_DIR="$PROJECT_ROOT/drt-state-auto"
mkdir -p "$STATE_AUTO_DIR"
STATE_FILE="$STATE_AUTO_DIR/${TEST_CHANGE_ID}.json"

rm -f "$STATE_FILE"

PASS=true

# 模擬 TESTER 輸出包含 FAIL
echo "1. 模擬 TESTER FAIL 輸出..."

FAIL_INPUT='{
  "hook_event_name": "SubagentStop",
  "agent_name": "claude-workflow:tester",
  "output": "執行測試結果 [test-005]：\n\n- test_auth.py: 3 passed, 1 FAIL\n- test_api.py: 5 passed\n\n**Verdict: FAIL**\n\n失敗的測試：\n- test_auth.py::test_login_invalid - AssertionError"
}'

OUTPUT=$(echo "$FAIL_INPUT" | bash "$VALIDATOR" 2>&1)
echo "$OUTPUT"
echo ""

# 驗證狀態檔
echo "2. 驗證狀態檔..."

if [ -f "$STATE_FILE" ]; then
    STATE_CONTENT=$(cat "$STATE_FILE")
    echo "狀態檔內容: $STATE_CONTENT"

    if echo "$STATE_CONTENT" | grep -q '"agent":"tester"'; then
        echo "✅ 記錄了 agent: tester"
    else
        echo "❌ 未記錄 agent"
        PASS=false
    fi

    if echo "$STATE_CONTENT" | grep -q '"result":"fail"'; then
        echo "✅ 記錄了 result: fail"
    else
        echo "❌ 未記錄 result: fail"
        PASS=false
    fi
else
    echo "❌ 狀態檔不存在"
    PASS=false
fi

# 驗證輸出提示
echo ""
echo "3. 驗證輸出提示..."

if echo "$OUTPUT" | grep -q "FAIL"; then
    echo "✅ 輸出包含 FAIL 識別"
else
    echo "❌ 未識別 FAIL"
    PASS=false
fi

if echo "$OUTPUT" | grep -q "DEBUGGER"; then
    echo "✅ 提示啟動 DEBUGGER"
else
    echo "❌ 未提示啟動 DEBUGGER"
    PASS=false
fi

# 清理
rm -f "$STATE_FILE"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-005 PASS: TESTER FAIL 處理正確"
    exit 0
else
    echo "❌ TS-005 FAIL"
    exit 1
fi
