#!/bin/bash
# test-ts-001.sh - Session 啟動測試
# 驗證: SessionStart hook (plugin-status-display.sh) 正確執行

echo "=== TS-001: Session 啟動測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="$PROJECT_ROOT/hooks/scripts/plugin-status-display.sh"

# 檢查腳本存在
if [ ! -f "$HOOK_SCRIPT" ]; then
    echo "❌ plugin-status-display.sh 不存在"
    exit 1
fi

# 執行腳本
echo "執行 plugin-status-display.sh..."
echo ""

OUTPUT=$(bash "$HOOK_SCRIPT" 2>&1)
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

# 2. 檢查輸出包含關鍵資訊
if ! echo "$OUTPUT" | grep -qi "D→R→T\|workflow\|plugin"; then
    echo "❌ 輸出未包含預期的 Plugin 資訊"
    PASS=false
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-001 PASS: SessionStart hook 正確執行"
    exit 0
else
    echo "❌ TS-001 FAIL"
    exit 1
fi
