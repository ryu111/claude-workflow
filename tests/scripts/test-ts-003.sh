#!/bin/bash
# test-ts-003.sh - 違規阻擋測試（跳過 REVIEWER）
# 驗證: PreToolUse hook 正確阻擋違規操作

echo "=== TS-003: 違規阻擋測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW_GATE="$PROJECT_ROOT/hooks/scripts/workflow-gate.sh"
STATE_DIR="$PROJECT_ROOT/.claude"
TEST_CHANGE_ID="test-003"
STATE_AUTO_DIR="$PROJECT_ROOT/drt-state-auto"
mkdir -p "$STATE_AUTO_DIR"
STATE_FILE="$STATE_AUTO_DIR/${TEST_CHANGE_ID}.json"

# 建立 DEVELOPER 完成狀態（使用當前時間，不會過期）
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\",\"change_id\":\"$TEST_CHANGE_ID\"}" > "$STATE_FILE"

echo "1. 狀態檔已建立:"
cat "$STATE_FILE"
echo ""

# 嘗試直接啟動 TESTER（應被阻擋）
echo "2. 嘗試直接啟動 TESTER（跳過 REVIEWER）..."
echo ""

TEST_INPUT='{
  "hook_event_name": "PreToolUse",
  "tool_name": "Task",
  "tool_input": {
    "prompt": "執行測試 [test-003]",
    "subagent_type": "claude-workflow:tester"
  }
}'

# 捕獲 stdout（JSON decision）和 stderr（用戶訊息）分開
RESULT_JSON=$(echo "$TEST_INPUT" | bash "$WORKFLOW_GATE" 2>/dev/null)
RESULT_STDERR=$(echo "$TEST_INPUT" | bash "$WORKFLOW_GATE" 2>&1 >/dev/null)

echo "用戶訊息:"
echo "$RESULT_STDERR"
echo ""

echo "JSON 輸出:"
echo "$RESULT_JSON"
echo ""

# 驗證阻擋
echo "3. 驗證阻擋:"

PASS=true

# 檢查 JSON 是否包含 block decision
if echo "$RESULT_JSON" | grep -q '"decision":"block"'; then
    echo "✅ JSON 包含 block decision"
else
    echo "❌ JSON 未包含 block decision"
    PASS=false
fi

# 檢查用戶訊息
if echo "$RESULT_STDERR" | grep -q "不允許跳過 REVIEWER"; then
    echo "✅ 顯示正確的錯誤訊息"
else
    echo "❌ 未顯示預期的錯誤訊息"
    PASS=false
fi

# 清理
rm -f "$STATE_FILE"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-003 PASS: 違規操作被正確阻擋"
    exit 0
else
    echo "❌ TS-003 FAIL"
    exit 1
fi
