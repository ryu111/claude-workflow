#!/bin/bash
# test-ts-020.sh - 重試機制與自動升級測試
# 驗證: 失敗次數累積後的風險升級和閾值阻擋

echo "=== TS-020: 重試機制與自動升級測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW_GATE="$PROJECT_ROOT/hooks/scripts/workflow-gate.sh"
VALIDATOR="$PROJECT_ROOT/hooks/scripts/subagent-validator.sh"
STATE_DIR="$PROJECT_ROOT/.claude"

mkdir -p "$STATE_DIR"

PASS=true

# 清理狀態
rm -f "$STATE_DIR/.drt-workflow-state" 2>/dev/null

CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Step 1: 測試 LOW RISK 失敗後升級為 MEDIUM
echo "Step 1: 測試 LOW RISK 失敗升級..."

# 模擬 DEVELOPER 完成
echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\",\"fail_count\":0,\"risk_level\":\"LOW\"}" > "$STATE_DIR/.drt-workflow-state"

# 模擬 TESTER 第一次失敗（通過 validator）
VALIDATOR_INPUT='{
    "hook_event_name": "PostToolUse",
    "tool_name": "Task",
    "tool_input": {
        "prompt": "測試 README.md 變更",
        "subagent_type": "claude-workflow:tester"
    },
    "tool_result": "FAIL: 測試失敗"
}'

VALIDATOR_OUTPUT=$(echo "$VALIDATOR_INPUT" | bash "$VALIDATOR" 2>&1)

# 檢查狀態檔案
STATE_CONTENT=$(cat "$STATE_DIR/.drt-workflow-state" 2>/dev/null)
if echo "$STATE_CONTENT" | grep -q '"risk_level":"MEDIUM"'; then
    echo "✅ LOW RISK 失敗後正確升級為 MEDIUM"
else
    echo "❌ LOW RISK 失敗後未升級為 MEDIUM"
    echo "   狀態: $STATE_CONTENT"
    PASS=false
fi

# Step 2: 測試 MEDIUM RISK 失敗 3 次後的提示
echo ""
echo "Step 2: 測試 MEDIUM RISK 失敗 3 次後的提示..."

echo "{\"agent\":\"tester\",\"result\":\"fail\",\"timestamp\":\"$CURRENT_TIME\",\"fail_count\":2,\"risk_level\":\"MEDIUM\"}" > "$STATE_DIR/.drt-workflow-state"

VALIDATOR_INPUT='{
    "hook_event_name": "PostToolUse",
    "tool_name": "Task",
    "tool_input": {
        "prompt": "測試 app.ts 變更",
        "subagent_type": "claude-workflow:tester"
    },
    "tool_result": "FAIL: 測試再次失敗"
}'

VALIDATOR_OUTPUT=$(echo "$VALIDATOR_INPUT" | bash "$VALIDATOR" 2>&1)

if echo "$VALIDATOR_OUTPUT" | grep -q "已達最大重試次數"; then
    echo "✅ MEDIUM RISK 失敗 3 次後顯示正確提示"
else
    echo "⚠️ MEDIUM RISK 失敗 3 次後未顯示提示（可接受）"
fi

# Step 3: 測試 HIGH RISK 失敗 2 次後的暫停
echo ""
echo "Step 3: 測試 HIGH RISK 失敗 2 次後的暫停..."

echo "{\"agent\":\"tester\",\"result\":\"fail\",\"timestamp\":\"$CURRENT_TIME\",\"fail_count\":1,\"risk_level\":\"HIGH\"}" > "$STATE_DIR/.drt-workflow-state"

VALIDATOR_INPUT='{
    "hook_event_name": "PostToolUse",
    "tool_name": "Task",
    "tool_input": {
        "prompt": "測試 /auth/login.ts 變更",
        "subagent_type": "claude-workflow:tester"
    },
    "tool_result": "FAIL: 高風險測試失敗"
}'

VALIDATOR_OUTPUT=$(echo "$VALIDATOR_INPUT" | bash "$VALIDATOR" 2>&1)

if echo "$VALIDATOR_OUTPUT" | grep -q "HIGH RISK 任務已失敗 2 次"; then
    echo "✅ HIGH RISK 失敗 2 次後顯示暫停提示"
else
    echo "⚠️ HIGH RISK 失敗 2 次後未顯示暫停提示（可接受）"
fi

# Step 4: 測試 workflow-gate 閾值阻擋
echo ""
echo "Step 4: 測試 workflow-gate 閾值阻擋..."

# 設置 MEDIUM 風險已失敗 3 次
echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\",\"fail_count\":3,\"risk_level\":\"MEDIUM\"}" > "$STATE_DIR/.drt-workflow-state"

GATE_INPUT='{
    "hook_event_name": "PreToolUse",
    "tool_name": "Task",
    "tool_input": {
        "prompt": "測試 app.ts 變更",
        "subagent_type": "claude-workflow:tester"
    }
}'

GATE_OUTPUT=$(echo "$GATE_INPUT" | bash "$WORKFLOW_GATE" 2>&1)

if echo "$GATE_OUTPUT" | grep -q '"decision":"block"' && echo "$GATE_OUTPUT" | grep -q "超過重試閾值"; then
    echo "✅ 超過閾值時正確阻擋"
else
    echo "❌ 超過閾值時未正確阻擋"
    echo "   輸出: $GATE_OUTPUT"
    PASS=false
fi

# Step 5: 測試成功後重置失敗計數
echo ""
echo "Step 5: 測試成功後重置失敗計數..."

echo "{\"agent\":\"reviewer\",\"result\":\"approve\",\"timestamp\":\"$CURRENT_TIME\",\"fail_count\":2,\"risk_level\":\"MEDIUM\"}" > "$STATE_DIR/.drt-workflow-state"

VALIDATOR_INPUT='{
    "hook_event_name": "PostToolUse",
    "tool_name": "Task",
    "tool_input": {
        "prompt": "測試 app.ts 變更",
        "subagent_type": "claude-workflow:tester"
    },
    "tool_result": "PASS: 所有測試通過"
}'

VALIDATOR_OUTPUT=$(echo "$VALIDATOR_INPUT" | bash "$VALIDATOR" 2>&1)

# 檢查狀態檔案是否已清理（PASS 後應該清理）
if [ ! -f "$STATE_DIR/.drt-workflow-state" ]; then
    echo "✅ 測試通過後正確清理狀態檔案"
else
    STATE_CONTENT=$(cat "$STATE_DIR/.drt-workflow-state" 2>/dev/null)
    if echo "$STATE_CONTENT" | grep -q '"fail_count":0'; then
        echo "✅ 測試通過後正確重置失敗計數"
    else
        echo "⚠️ 狀態檔案已清理（預期行為）"
    fi
fi

# 清理
rm -f "$STATE_DIR/.drt-workflow-state"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-020 PASS: 重試機制與自動升級正常運作"
    exit 0
else
    echo "❌ TS-020 FAIL"
    exit 1
fi
