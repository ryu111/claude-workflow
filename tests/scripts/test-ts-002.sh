#!/bin/bash
# test-ts-002.sh - 標準 D→R→T 流程測試
# 驗證: 完整 DEVELOPER → REVIEWER → TESTER 流程
# 備註: 此測試需要模擬完整流程，無法完全自動化

echo "=== TS-002: 標準 D→R→T 流程測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW_GATE="$PROJECT_ROOT/hooks/scripts/workflow-gate.sh"
VALIDATOR="$PROJECT_ROOT/hooks/scripts/subagent-validator.sh"
STATE_DIR="$PROJECT_ROOT/.claude"

mkdir -p "$STATE_DIR"

# 清理狀態
rm -f "$STATE_DIR/.drt-workflow-state"

PASS=true

# Step 1: DEVELOPER 啟動
echo "Step 1: 模擬 DEVELOPER 啟動..."

DEV_INPUT='{
  "hook_event_name": "PreToolUse",
  "tool_name": "Task",
  "tool_input": {
    "prompt": "實作功能",
    "subagent_type": "claude-workflow:developer"
  }
}'

DEV_OUTPUT=$(echo "$DEV_INPUT" | bash "$WORKFLOW_GATE" 2>&1)

if echo "$DEV_OUTPUT" | grep -q "DEVELOPER"; then
    echo "✅ DEVELOPER 啟動成功"
else
    echo "❌ DEVELOPER 啟動失敗"
    PASS=false
fi

# Step 2: DEVELOPER 完成，記錄狀態
echo ""
echo "Step 2: 模擬 DEVELOPER 完成..."

CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\"}" > "$STATE_DIR/.drt-workflow-state"

# Step 3: REVIEWER 啟動
echo ""
echo "Step 3: 模擬 REVIEWER 啟動..."

REV_INPUT='{
  "hook_event_name": "PreToolUse",
  "tool_name": "Task",
  "tool_input": {
    "prompt": "審查程式碼",
    "subagent_type": "claude-workflow:reviewer"
  }
}'

REV_OUTPUT=$(echo "$REV_INPUT" | bash "$WORKFLOW_GATE" 2>&1)

if echo "$REV_OUTPUT" | grep -q "REVIEWER"; then
    echo "✅ REVIEWER 啟動成功"
else
    echo "❌ REVIEWER 啟動失敗"
    PASS=false
fi

# Step 4: REVIEWER APPROVE
echo ""
echo "Step 4: 模擬 REVIEWER APPROVE..."

CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "{\"agent\":\"reviewer\",\"result\":\"approve\",\"timestamp\":\"$CURRENT_TIME\"}" > "$STATE_DIR/.drt-workflow-state"

# Step 5: TESTER 啟動
echo ""
echo "Step 5: 模擬 TESTER 啟動..."

TST_INPUT='{
  "hook_event_name": "PreToolUse",
  "tool_name": "Task",
  "tool_input": {
    "prompt": "執行測試",
    "subagent_type": "claude-workflow:tester"
  }
}'

TST_OUTPUT=$(echo "$TST_INPUT" | bash "$WORKFLOW_GATE" 2>&1)

# 不應被阻擋
if echo "$TST_OUTPUT" | grep -q "block"; then
    echo "❌ TESTER 被錯誤阻擋"
    PASS=false
elif echo "$TST_OUTPUT" | grep -q "TESTER"; then
    echo "✅ TESTER 啟動成功（未被阻擋）"
else
    echo "⚠️ TESTER 輸出異常"
fi

# 清理
rm -f "$STATE_DIR/.drt-workflow-state"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-002 PASS: D→R→T 流程正確執行"
    exit 0
else
    echo "❌ TS-002 FAIL"
    exit 1
fi
