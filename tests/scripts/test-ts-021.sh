#!/bin/bash
# test-ts-021.sh - HIGH RISK 人工確認步驟測試
# 驗證: HIGH RISK 測試通過後需要人工確認

echo "=== TS-021: HIGH RISK 人工確認步驟測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$PROJECT_ROOT/hooks/scripts/subagent-validator.sh"
STATE_DIR="$PROJECT_ROOT/.claude"

mkdir -p "$STATE_DIR"

PASS=true

# 清理狀態
rm -f "$STATE_DIR/.drt-workflow-state" 2>/dev/null

CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Step 1: 測試 HIGH RISK 測試通過後的人工確認提示
echo "Step 1: 測試 HIGH RISK 測試通過後的人工確認提示..."

# 設置 HIGH RISK 狀態
echo "{\"agent\":\"reviewer\",\"result\":\"approve\",\"timestamp\":\"$CURRENT_TIME\",\"fail_count\":0,\"risk_level\":\"HIGH\"}" > "$STATE_DIR/.drt-workflow-state"

VALIDATOR_INPUT='{
    "hook_event_name": "PostToolUse",
    "tool_name": "Task",
    "tool_input": {
        "prompt": "測試 /auth/login.ts 變更",
        "subagent_type": "claude-workflow:tester"
    },
    "tool_result": "PASS: 所有安全測試通過"
}'

VALIDATOR_OUTPUT=$(echo "$VALIDATOR_INPUT" | bash "$VALIDATOR" 2>&1)

if echo "$VALIDATOR_OUTPUT" | grep -q "HIGH RISK - 需要人工確認"; then
    echo "✅ HIGH RISK 測試通過後顯示人工確認提示"
else
    echo "❌ HIGH RISK 測試通過後未顯示人工確認提示"
    echo "   輸出: $VALIDATOR_OUTPUT"
    PASS=false
fi

if echo "$VALIDATOR_OUTPUT" | grep -q "安全性影響已評估"; then
    echo "✅ 顯示確認清單"
else
    echo "❌ 未顯示確認清單"
    PASS=false
fi

# 檢查狀態是否為 pending_confirmation
STATE_CONTENT=$(cat "$STATE_DIR/.drt-workflow-state" 2>/dev/null)
if echo "$STATE_CONTENT" | grep -q '"result":"pending_confirmation"'; then
    echo "✅ 狀態正確記錄為 pending_confirmation"
else
    echo "❌ 狀態未記錄為 pending_confirmation"
    echo "   狀態: $STATE_CONTENT"
    PASS=false
fi

# Step 2: 測試 MEDIUM RISK 測試通過後直接完成（無需確認）
echo ""
echo "Step 2: 測試 MEDIUM RISK 測試通過後直接完成..."

echo "{\"agent\":\"reviewer\",\"result\":\"approve\",\"timestamp\":\"$CURRENT_TIME\",\"fail_count\":0,\"risk_level\":\"MEDIUM\"}" > "$STATE_DIR/.drt-workflow-state"

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

if echo "$VALIDATOR_OUTPUT" | grep -q "任務完成"; then
    echo "✅ MEDIUM RISK 測試通過後直接完成"
else
    echo "❌ MEDIUM RISK 測試通過後未顯示完成訊息"
    PASS=false
fi

if echo "$VALIDATOR_OUTPUT" | grep -q "需要人工確認"; then
    echo "❌ MEDIUM RISK 不應要求人工確認"
    PASS=false
else
    echo "✅ MEDIUM RISK 不要求人工確認"
fi

# Step 3: 測試 LOW RISK 測試通過後直接完成（無需確認）
echo ""
echo "Step 3: 測試 LOW RISK 測試通過後直接完成..."

echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\",\"fail_count\":0,\"risk_level\":\"LOW\"}" > "$STATE_DIR/.drt-workflow-state"

VALIDATOR_INPUT='{
    "hook_event_name": "PostToolUse",
    "tool_name": "Task",
    "tool_input": {
        "prompt": "測試 README.md 變更",
        "subagent_type": "claude-workflow:tester"
    },
    "tool_result": "PASS: 文檔驗證通過"
}'

VALIDATOR_OUTPUT=$(echo "$VALIDATOR_INPUT" | bash "$VALIDATOR" 2>&1)

if echo "$VALIDATOR_OUTPUT" | grep -q "任務完成"; then
    echo "✅ LOW RISK 測試通過後直接完成"
else
    echo "❌ LOW RISK 測試通過後未顯示完成訊息"
    PASS=false
fi

if echo "$VALIDATOR_OUTPUT" | grep -q "需要人工確認"; then
    echo "❌ LOW RISK 不應要求人工確認"
    PASS=false
else
    echo "✅ LOW RISK 不要求人工確認"
fi

# 清理
rm -f "$STATE_DIR/.drt-workflow-state"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-021 PASS: HIGH RISK 人工確認步驟正常運作"
    exit 0
else
    echo "❌ TS-021 FAIL"
    exit 1
fi
