#!/bin/bash
# test-ts-015.sh - Agent 狀態顯示測試
# 驗證: SubagentStart hook (agent-status-display.sh) 正確執行

echo "=== TS-015: Agent 狀態顯示測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="$PROJECT_ROOT/hooks/scripts/agent-status-display.sh"

# 檢查腳本存在
if [ ! -f "$HOOK_SCRIPT" ]; then
    echo "❌ agent-status-display.sh 不存在"
    exit 1
fi

# 建立測試 JSON 輸入（模擬 SubagentStart 事件）
TEST_JSON='{
  "agent_type": "claude-workflow:developer",
  "agent_description": "實作新功能",
  "session_id": "test-session-123"
}'

# 執行腳本
echo "執行 agent-status-display.sh..."
echo "測試輸入: $TEST_JSON"
echo ""

OUTPUT=$(echo "$TEST_JSON" | bash "$HOOK_SCRIPT" 2>&1)
EXIT_CODE=$?

echo "$OUTPUT"
echo ""

# 驗證結果
PASS=true

# 1. 檢查是否成功執行
if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ 腳本執行失敗 (exit code: $EXIT_CODE)"
    PASS=false
fi

# 2. 檢查輸出是否為有效 JSON
if ! echo "$OUTPUT" | jq empty 2>/dev/null; then
    echo "❌ 輸出不是有效的 JSON"
    PASS=false
fi

# 3. 檢查 JSON 結構
if echo "$OUTPUT" | jq empty 2>/dev/null; then
    # 檢查 hookEventName
    HOOK_EVENT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.hookEventName // empty')
    if [ "$HOOK_EVENT" != "SubagentStart" ]; then
        echo "❌ hookEventName 不正確: $HOOK_EVENT"
        PASS=false
    fi

    # 檢查 additionalContext
    CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext // empty')
    if ! echo "$CONTEXT" | grep -q "developer"; then
        echo "❌ additionalContext 未包含 agent 名稱"
        PASS=false
    fi

    # 檢查 statusIndicator
    STATUS_TEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.statusIndicator.text // empty')
    if ! echo "$STATUS_TEXT" | grep -q "DEVELOPER"; then
        echo "❌ statusIndicator.text 不正確: $STATUS_TEXT"
        PASS=false
    fi
fi

# 4. 檢查狀態檔案是否被建立
AGENT_STATE_FILE="/tmp/claude-agent-state-test-session-123"
if [ ! -f "$AGENT_STATE_FILE" ]; then
    echo "❌ Agent 狀態檔案未建立: $AGENT_STATE_FILE"
    PASS=false
else
    AGENT_NAME=$(cat "$AGENT_STATE_FILE")
    if [ "$AGENT_NAME" != "developer" ]; then
        echo "❌ Agent 狀態檔案內容不正確: $AGENT_NAME"
        PASS=false
    fi
    # 清理測試檔案
    rm -f "$AGENT_STATE_FILE"
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-015 PASS: SubagentStart hook 正確執行"
    exit 0
else
    echo "❌ TS-015 FAIL"
    exit 1
fi
