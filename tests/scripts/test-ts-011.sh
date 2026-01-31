#!/bin/bash
# test-ts-011.sh - Session 結束報告測試
# 驗證: SessionEnd hook 腳本可執行
# 狀態: 實際觸發需要 Session 結束

echo "=== TS-011: Session 結束報告測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_SCRIPT="$PROJECT_ROOT/hooks/scripts/session-cleanup-report.sh"

PASS=true

# Step 1: 檢查腳本存在
echo "Step 1: 檢查 session-cleanup-report.sh..."

if [ ! -f "$CLEANUP_SCRIPT" ]; then
    echo "❌ session-cleanup-report.sh 不存在"
    exit 1
fi

echo "✅ session-cleanup-report.sh 存在"

# Step 2: 檢查腳本可執行
echo ""
echo "Step 2: 測試腳本執行..."

# 提供空輸入測試腳本
OUTPUT=$(echo '{}' | bash "$CLEANUP_SCRIPT" 2>&1) || true

if [ -n "$OUTPUT" ]; then
    echo "✅ 腳本可執行"
    echo ""
    echo "輸出預覽:"
    echo "─────────────────────────────────"
    echo "$OUTPUT" | head -20
    echo "─────────────────────────────────"
else
    echo "⚠️ 腳本輸出為空（可能正常）"
fi

# Step 3: 檢查腳本內容
echo ""
echo "Step 3: 檢查腳本內容..."

if grep -qi "report\|統計\|summary" "$CLEANUP_SCRIPT"; then
    echo "✅ 包含報告生成邏輯"
else
    echo "⚠️ 未找到報告生成邏輯"
fi

echo ""
echo "⚠️ SessionEnd hook 只在 Session 結束時觸發"
echo "   需要手動驗證實際報告生成"
echo ""

# 返回 exit 2 表示需要手動測試
exit 2
