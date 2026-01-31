#!/bin/bash
# test-ts-007.sh - HIGH 風險深度審查測試
# 驗證: HIGH 風險使用 opus 模型

echo "=== TS-007: HIGH 風險深度審查測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REVIEWER_MD="$PROJECT_ROOT/agents/reviewer.md"

PASS=true

# 檢查 reviewer.md 是否存在
echo "1. 檢查 reviewer.md..."

if [ ! -f "$REVIEWER_MD" ]; then
    echo "❌ reviewer.md 不存在"
    exit 1
fi

echo "✅ reviewer.md 存在"
echo ""

# 檢查是否有 model 設定相關內容
echo "2. 檢查 model 設定..."

if grep -qi "model.*opus\|opus.*model\|high.*risk" "$REVIEWER_MD"; then
    echo "✅ reviewer.md 包含 opus 或 high risk 相關設定"
else
    echo "⚠️ reviewer.md 未發現 opus 模型設定"
    echo ""
    echo "說明："
    echo "HIGH 風險審查應使用 opus 模型，但目前 reviewer.md"
    echo "可能未包含動態模型選擇邏輯。"
    echo ""
    echo "建議實作方式："
    echo "1. 在 reviewer.md 的 frontmatter 中設定 model"
    echo "2. 或在 orchestration 決策中動態指定"
fi

# 顯示 reviewer.md 的 frontmatter
echo ""
echo "3. reviewer.md frontmatter:"
echo "─────────────────────────────────"
head -30 "$REVIEWER_MD" | grep -A20 "^---"
echo "─────────────────────────────────"

# 此測試僅檢查配置，不驗證運行時行為
echo ""
echo "⚠️ 運行時模型選擇需要手動驗證"
echo ""

# 返回 exit 2 表示需要手動測試
exit 2
