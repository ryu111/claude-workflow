#!/bin/bash
# test-ts-004.sh - REVIEWER REJECT 測試
# 驗證: REJECT 後正確記錄狀態，提示返回 DEVELOPER

echo "=== TS-004: REVIEWER REJECT 測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$PROJECT_ROOT/hooks/scripts/subagent-validator.sh"
STATE_DIR="$PROJECT_ROOT/.claude"
TEST_CHANGE_ID="test-004"
STATE_AUTO_DIR="$PROJECT_ROOT/drt-state-auto"
STATE_FILE="$STATE_AUTO_DIR/${TEST_CHANGE_ID}.json"

mkdir -p "$STATE_AUTO_DIR"
rm -f "$STATE_FILE"

PASS=true

# 模擬 REVIEWER 輸出包含 REJECT
echo "1. 模擬 REVIEWER REJECT 輸出..."

REJECT_INPUT='{
  "hook_event_name": "SubagentStop",
  "agent_name": "claude-workflow:reviewer",
  "output": "審查 [test-004] - 發現以下問題需要修改：\n1. 缺少錯誤處理\n2. 命名不符合規範\n\n**Verdict: REJECT**\n\n請 DEVELOPER 修復上述問題後重新提交。"
}'

OUTPUT=$(echo "$REJECT_INPUT" | bash "$VALIDATOR" 2>&1)
echo "$OUTPUT"
echo ""

# 驗證狀態檔
echo "2. 驗證狀態檔..."

if [ -f "$STATE_FILE" ]; then
    STATE_CONTENT=$(cat "$STATE_FILE")
    echo "狀態檔內容: $STATE_CONTENT"

    if echo "$STATE_CONTENT" | grep -q '"agent":"reviewer"'; then
        echo "✅ 記錄了 agent: reviewer"
    else
        echo "❌ 未記錄 agent"
        PASS=false
    fi

    if echo "$STATE_CONTENT" | grep -q '"result":"reject"'; then
        echo "✅ 記錄了 result: reject"
    else
        echo "❌ 未記錄 result: reject"
        PASS=false
    fi
else
    echo "❌ 狀態檔不存在"
    PASS=false
fi

# 驗證輸出提示
echo ""
echo "3. 驗證輸出提示..."

if echo "$OUTPUT" | grep -q "REQUEST CHANGES\|REJECT"; then
    echo "✅ 輸出包含 REJECT 識別"
else
    echo "❌ 未識別 REJECT"
    PASS=false
fi

if echo "$OUTPUT" | grep -q "DEVELOPER"; then
    echo "✅ 提示返回 DEVELOPER"
else
    echo "❌ 未提示返回 DEVELOPER"
    PASS=false
fi

# 清理
rm -f "$STATE_FILE"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-004 PASS: REVIEWER REJECT 處理正確"
    exit 0
else
    echo "❌ TS-004 FAIL"
    exit 1
fi
