#!/bin/bash
# test-ts-022.sh - Session State Init 測試
# 驗證: session-state-init.sh 正確初始化 Agent 狀態

echo "=== TS-022: Session State Init 測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="$PROJECT_ROOT/hooks/scripts/session-state-init.sh"

# 檢查腳本存在
if [ ! -f "$HOOK_SCRIPT" ]; then
    echo "❌ session-state-init.sh 不存在"
    exit 1
fi

# 設定測試環境
export CLAUDE_SESSION_ID="test-session-$$"
STATE_FILE="/tmp/claude-agent-state-${CLAUDE_SESSION_ID}"

# 清理舊測試檔案
rm -f "$STATE_FILE"

# 執行腳本
echo "執行 session-state-init.sh..."
echo ""

bash "$HOOK_SCRIPT"
EXIT_CODE=$?

echo ""

# 驗證結果
PASS=true

# 1. 檢查是否成功執行
if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ 腳本執行失敗 (exit code: $EXIT_CODE)"
    PASS=false
fi

# 2. 檢查狀態檔是否被建立
if [ ! -f "$STATE_FILE" ]; then
    echo "❌ 狀態檔未被建立: $STATE_FILE"
    PASS=false
fi

# 3. 檢查狀態檔內容是否為 'main'
if [ -f "$STATE_FILE" ]; then
    STATE_CONTENT=$(cat "$STATE_FILE")
    if [ "$STATE_CONTENT" != "main" ]; then
        echo "❌ 狀態檔內容錯誤: 預期 'main'，實際 '$STATE_CONTENT'"
        PASS=false
    else
        echo "✅ 狀態檔內容正確: '$STATE_CONTENT'"
    fi
fi

# 清理測試檔案
rm -f "$STATE_FILE"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-022 PASS: session-state-init.sh 正確初始化狀態"
    exit 0
else
    echo "❌ TS-022 FAIL"
    exit 1
fi
