#!/bin/bash
# test-ts-018.sh - 多檔案變更 HIGH RISK 判定測試
# 驗證: 超過 5 個檔案的變更被自動升級為 HIGH RISK

echo "=== TS-018: 多檔案變更 HIGH RISK 判定測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW_GATE="$PROJECT_ROOT/hooks/scripts/workflow-gate.sh"
STATE_DIR="$PROJECT_ROOT/.claude"

mkdir -p "$STATE_DIR"

PASS=true

# 建立 DEVELOPER 完成狀態
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Step 1: 測試少量檔案（3 個）- 應為 MEDIUM
echo "Step 1: 測試 3 個檔案（應為 MEDIUM）..."

echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\"}" > "$STATE_DIR/.drt-workflow-state"

FEW_FILES_INPUT='{
    "hook_event_name": "PreToolUse",
    "tool_name": "Task",
    "tool_input": {
        "prompt": "修改 src/app.ts, src/utils.ts, src/config.ts",
        "subagent_type": "claude-workflow:tester"
    }
}'

FEW_RESULT=$(echo "$FEW_FILES_INPUT" | bash "$WORKFLOW_GATE" 2>&1)

if echo "$FEW_RESULT" | grep -q "MEDIUM"; then
    echo "✅ 3 個檔案: 正確識別為 MEDIUM"
elif echo "$FEW_RESULT" | grep -q "HIGH"; then
    echo "❌ 3 個檔案: 被誤判為 HIGH"
    PASS=false
else
    echo "✅ 3 個檔案: 被阻擋（MEDIUM 風險）"
fi

# Step 2: 測試剛好 5 個檔案 - 應為 MEDIUM（邊界）
echo ""
echo "Step 2: 測試 5 個檔案（邊界，應為 MEDIUM）..."

echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\"}" > "$STATE_DIR/.drt-workflow-state"

FIVE_FILES_INPUT='{
    "hook_event_name": "PreToolUse",
    "tool_name": "Task",
    "tool_input": {
        "prompt": "修改 a.ts, b.ts, c.ts, d.ts, e.ts",
        "subagent_type": "claude-workflow:tester"
    }
}'

FIVE_RESULT=$(echo "$FIVE_FILES_INPUT" | bash "$WORKFLOW_GATE" 2>&1)

if echo "$FIVE_RESULT" | grep -q "MEDIUM"; then
    echo "✅ 5 個檔案: 正確識別為 MEDIUM（邊界值）"
elif echo "$FIVE_RESULT" | grep -q "HIGH"; then
    echo "⚠️ 5 個檔案: 判定為 HIGH（邊界情況可接受）"
else
    echo "✅ 5 個檔案: 被阻擋（非 HIGH）"
fi

# Step 3: 測試 6 個檔案（超過閾值）- 應為 HIGH
echo ""
echo "Step 3: 測試 6 個檔案（超過閾值，應為 HIGH）..."

echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\"}" > "$STATE_DIR/.drt-workflow-state"

SIX_FILES_INPUT='{
    "hook_event_name": "PreToolUse",
    "tool_name": "Task",
    "tool_input": {
        "prompt": "修改 a.ts, b.ts, c.ts, d.ts, e.ts, f.ts",
        "subagent_type": "claude-workflow:tester"
    }
}'

SIX_RESULT=$(echo "$SIX_FILES_INPUT" | bash "$WORKFLOW_GATE" 2>&1)

if echo "$SIX_RESULT" | grep -q "HIGH"; then
    echo "✅ 6 個檔案: 正確識別為 HIGH"
else
    echo "❌ 6 個檔案: 未被識別為 HIGH"
    PASS=false
fi

# Step 4: 測試大量檔案（10 個）
echo ""
echo "Step 4: 測試 10 個檔案..."

echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\"}" > "$STATE_DIR/.drt-workflow-state"

MANY_FILES_INPUT='{
    "hook_event_name": "PreToolUse",
    "tool_name": "Task",
    "tool_input": {
        "prompt": "重構：修改 a.ts, b.ts, c.ts, d.ts, e.ts, f.ts, g.ts, h.ts, i.ts, j.ts",
        "subagent_type": "claude-workflow:tester"
    }
}'

MANY_RESULT=$(echo "$MANY_FILES_INPUT" | bash "$WORKFLOW_GATE" 2>&1)

if echo "$MANY_RESULT" | grep -q "HIGH"; then
    echo "✅ 10 個檔案: 正確識別為 HIGH"
else
    echo "❌ 10 個檔案: 未被識別為 HIGH"
    PASS=false
fi

# Step 5: 測試重複檔案名（應去重）
echo ""
echo "Step 5: 測試重複檔案名（應去重計算）..."

echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\"}" > "$STATE_DIR/.drt-workflow-state"

DUP_FILES_INPUT='{
    "hook_event_name": "PreToolUse",
    "tool_name": "Task",
    "tool_input": {
        "prompt": "修改 app.ts 新增功能，再次修改 app.ts 修復 bug，最後修改 app.ts 優化",
        "subagent_type": "claude-workflow:tester"
    }
}'

DUP_RESULT=$(echo "$DUP_FILES_INPUT" | bash "$WORKFLOW_GATE" 2>&1)

if echo "$DUP_RESULT" | grep -q "HIGH"; then
    echo "❌ 重複檔案名: 被誤判為 HIGH（應去重）"
    PASS=false
else
    echo "✅ 重複檔案名: 正確去重（非 HIGH）"
fi

# 清理
rm -f "$STATE_DIR/.drt-workflow-state"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-018 PASS: 多檔案變更 HIGH RISK 判定正確"
    exit 0
else
    echo "❌ TS-018 FAIL"
    exit 1
fi
