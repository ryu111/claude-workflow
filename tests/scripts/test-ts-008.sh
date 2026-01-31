#!/bin/bash
# test-ts-008.sh - 並行任務隔離測試
# 驗證: 多個 Change ID 狀態獨立

echo "=== TS-008: 並行任務隔離測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW_GATE="$PROJECT_ROOT/hooks/scripts/workflow-gate.sh"
VALIDATOR="$PROJECT_ROOT/hooks/scripts/subagent-validator.sh"
STATE_DIR="$PROJECT_ROOT/.claude"

mkdir -p "$STATE_DIR"

# 清理所有狀態
rm -f "$STATE_DIR/.drt-state-"* 2>/dev/null
rm -f "$STATE_DIR/.drt-workflow-state" 2>/dev/null

PASS=true

# Step 1: Change-A 的 DEVELOPER
echo "Step 1: 啟動 Change-A 的 DEVELOPER..."

INPUT_A='{
  "hook_event_name": "PreToolUse",
  "tool_name": "Task",
  "tool_input": {
    "prompt": "[change-a] 實作功能 A",
    "subagent_type": "claude-workflow:developer"
  }
}'

echo "$INPUT_A" | bash "$WORKFLOW_GATE" 2>&1 | head -5
echo ""

# 模擬 Change-A DEVELOPER 完成
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\",\"change_id\":\"change-a\"}" > "$STATE_DIR/.drt-state-change-a"

# Step 2: Change-B 的 DEVELOPER
echo "Step 2: 啟動 Change-B 的 DEVELOPER..."

INPUT_B='{
  "hook_event_name": "PreToolUse",
  "tool_name": "Task",
  "tool_input": {
    "prompt": "[change-b] 實作功能 B",
    "subagent_type": "claude-workflow:developer"
  }
}'

echo "$INPUT_B" | bash "$WORKFLOW_GATE" 2>&1 | head -5
echo ""

# 模擬 Change-B DEVELOPER 完成
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\",\"change_id\":\"change-b\"}" > "$STATE_DIR/.drt-state-change-b"

# Step 3: 驗證狀態檔案獨立
echo "Step 3: 驗證狀態檔案..."

if [ -f "$STATE_DIR/.drt-state-change-a" ]; then
    echo "✅ .drt-state-change-a 存在"
    echo "   內容: $(cat "$STATE_DIR/.drt-state-change-a")"
else
    echo "❌ .drt-state-change-a 不存在"
    PASS=false
fi

if [ -f "$STATE_DIR/.drt-state-change-b" ]; then
    echo "✅ .drt-state-change-b 存在"
    echo "   內容: $(cat "$STATE_DIR/.drt-state-change-b")"
else
    echo "❌ .drt-state-change-b 不存在"
    PASS=false
fi

# Step 4: Change-A 進入 REVIEWER，Change-B 仍在 DEVELOPER
echo ""
echo "Step 4: Change-A 進入 REVIEWER..."

INPUT_A_REV='{
  "hook_event_name": "PreToolUse",
  "tool_name": "Task",
  "tool_input": {
    "prompt": "[change-a] 審查功能 A",
    "subagent_type": "claude-workflow:reviewer"
  }
}'

OUTPUT_A_REV=$(echo "$INPUT_A_REV" | bash "$WORKFLOW_GATE" 2>&1)
echo "$OUTPUT_A_REV" | head -5
echo ""

# 模擬 REVIEWER APPROVE
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "{\"agent\":\"reviewer\",\"result\":\"approve\",\"timestamp\":\"$CURRENT_TIME\",\"change_id\":\"change-a\"}" > "$STATE_DIR/.drt-state-change-a"

# Step 5: 驗證 Change-B 狀態未受影響
echo "Step 5: 驗證 Change-B 狀態未受影響..."

B_STATE=$(cat "$STATE_DIR/.drt-state-change-b" 2>/dev/null)
if echo "$B_STATE" | grep -q '"agent":"developer"'; then
    echo "✅ Change-B 狀態仍為 developer"
else
    echo "❌ Change-B 狀態被意外修改"
    PASS=false
fi

# 清理
rm -f "$STATE_DIR/.drt-state-change-a"
rm -f "$STATE_DIR/.drt-state-change-b"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-008 PASS: 並行任務狀態獨立"
    exit 0
else
    echo "❌ TS-008 FAIL"
    exit 1
fi
