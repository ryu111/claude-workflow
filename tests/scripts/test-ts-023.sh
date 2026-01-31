#!/bin/bash
# test-ts-023.sh - Session State Cleanup 測試
# 驗證: session-state-cleanup.sh 正確清理 Agent 狀態

echo "=== TS-023: Session State Cleanup 測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="$PROJECT_ROOT/hooks/scripts/session-state-cleanup.sh"

# 檢查腳本存在
if [ ! -f "$HOOK_SCRIPT" ]; then
    echo "❌ session-state-cleanup.sh 不存在"
    exit 1
fi

# 設定測試環境
export CLAUDE_SESSION_ID="test-session-$$"
STATE_FILE="/tmp/claude-agent-state-${CLAUDE_SESSION_ID}"

# 建立測試狀態檔
echo "main" > "$STATE_FILE"

# 確認測試檔案存在
if [ ! -f "$STATE_FILE" ]; then
    echo "❌ 測試準備失敗：無法建立測試狀態檔"
    exit 1
fi
echo "✅ 測試狀態檔已建立: $STATE_FILE"
echo ""

# 執行腳本
echo "執行 session-state-cleanup.sh..."
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

# 2. 檢查狀態檔是否被刪除
if [ -f "$STATE_FILE" ]; then
    echo "❌ 狀態檔未被刪除: $STATE_FILE"
    PASS=false
    # 清理殘留檔案
    rm -f "$STATE_FILE"
else
    echo "✅ 狀態檔已成功刪除"
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-023 PASS: session-state-cleanup.sh 正確清理狀態"
    exit 0
else
    echo "❌ TS-023 FAIL"
    exit 1
fi
