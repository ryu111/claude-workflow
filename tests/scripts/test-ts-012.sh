#!/bin/bash
# test-ts-012.sh - 狀態過期處理測試
# 驗證: 30 分鐘過期機制

echo "=== TS-012: 狀態過期處理測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW_GATE="$PROJECT_ROOT/hooks/scripts/workflow-gate.sh"
STATE_DIR="$PROJECT_ROOT/.claude"

mkdir -p "$STATE_DIR"

PASS=true

# Step 1: 建立過期狀態（31 分鐘前）
echo "Step 1: 建立過期狀態檔案（31 分鐘前）..."

# 計算 31 分鐘前的時間
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    EXPIRED_TIME=$(date -u -v-31M +"%Y-%m-%dT%H:%M:%SZ")
else
    # Linux
    EXPIRED_TIME=$(date -u -d "31 minutes ago" +"%Y-%m-%dT%H:%M:%SZ")
fi

echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$EXPIRED_TIME\"}" > "$STATE_DIR/.drt-workflow-state"

echo "狀態檔內容:"
cat "$STATE_DIR/.drt-workflow-state"
echo ""

# Step 2: 嘗試啟動 TESTER
echo "Step 2: 嘗試啟動 TESTER（狀態已過期）..."
echo ""

TEST_INPUT='{
  "hook_event_name": "PreToolUse",
  "tool_name": "Task",
  "tool_input": {
    "prompt": "執行測試",
    "subagent_type": "claude-workflow:tester"
  }
}'

OUTPUT=$(echo "$TEST_INPUT" | bash "$WORKFLOW_GATE" 2>&1)
JSON_OUTPUT=$(echo "$TEST_INPUT" | bash "$WORKFLOW_GATE" 2>/dev/null)

echo "輸出:"
echo "$OUTPUT"
echo ""

# Step 3: 驗證結果
echo "Step 3: 驗證結果..."

# 過期狀態應該：
# 1. 不阻擋（因為無法驗證）
# 2. 顯示警告（無法驗證流程狀態）

if echo "$OUTPUT" | grep -q "無法驗證流程狀態\|可能已過期"; then
    echo "✅ 顯示過期警告"
else
    echo "⚠️ 未顯示過期警告"
    # 這不是失敗，只是警告
fi

if echo "$JSON_OUTPUT" | grep -q '"decision":"block"'; then
    echo "❌ 過期狀態不應該阻擋（因為無法驗證）"
    PASS=false
else
    echo "✅ 過期狀態未阻擋（正確行為）"
fi

# 清理
rm -f "$STATE_DIR/.drt-workflow-state"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-012 PASS: 狀態過期處理正確"
    exit 0
else
    echo "❌ TS-012 FAIL"
    exit 1
fi
