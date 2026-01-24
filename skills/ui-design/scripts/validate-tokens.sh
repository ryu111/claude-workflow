#!/bin/bash
# validate-tokens.sh - 驗證 Design Tokens 的完整性和一致性

set -e

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🎨 Design Tokens 驗證工具"
echo "========================="
echo ""

# 預設檔案路徑
CSS_FILE="${1:-src/styles/tokens.css}"
ERRORS=0
WARNINGS=0

# 檢查檔案是否存在
if [ ! -f "$CSS_FILE" ]; then
    echo -e "${YELLOW}⚠️  找不到 CSS 檔案: $CSS_FILE${NC}"
    echo "使用方式: ./validate-tokens.sh [css-file-path]"
    exit 1
fi

echo "檢查檔案: $CSS_FILE"
echo ""

# 1. 檢查必要的 tokens
echo "📋 檢查必要的 tokens..."

REQUIRED_TOKENS=(
    "--color-primary"
    "--color-success"
    "--color-warning"
    "--color-error"
    "--space-1"
    "--space-2"
    "--space-4"
    "--font-size-sm"
    "--font-size-md"
    "--font-size-lg"
)

for token in "${REQUIRED_TOKENS[@]}"; do
    if grep -q "$token" "$CSS_FILE"; then
        echo -e "  ${GREEN}✅ $token${NC}"
    else
        echo -e "  ${RED}❌ $token (缺失)${NC}"
        ((ERRORS++))
    fi
done

echo ""

# 2. 檢查顏色格式
echo "🎨 檢查顏色格式..."

# 檢查是否使用有效的顏色格式 (hex, rgb, hsl)
COLOR_LINES=$(grep -E "color.*:" "$CSS_FILE" || true)
if [ -n "$COLOR_LINES" ]; then
    while IFS= read -r line; do
        if echo "$line" | grep -qE "#[0-9A-Fa-f]{3,8}|rgb\(|rgba\(|hsl\(|hsla\("; then
            :  # 有效格式
        elif echo "$line" | grep -qE "var\(--"; then
            :  # 使用變數引用，也是有效的
        else
            echo -e "  ${YELLOW}⚠️  可能無效的顏色值: $line${NC}"
            ((WARNINGS++))
        fi
    done <<< "$COLOR_LINES"
    echo -e "  ${GREEN}✅ 顏色格式檢查完成${NC}"
fi

echo ""

# 3. 檢查間距系統一致性
echo "📐 檢查間距系統..."

# 檢查間距是否使用 4 的倍數
SPACE_VALUES=$(grep -oE "space-[0-9]+: [0-9]+px" "$CSS_FILE" || true)
if [ -n "$SPACE_VALUES" ]; then
    while IFS= read -r line; do
        value=$(echo "$line" | grep -oE "[0-9]+px" | grep -oE "[0-9]+")
        if [ $((value % 4)) -eq 0 ]; then
            echo -e "  ${GREEN}✅ $line (4的倍數)${NC}"
        else
            echo -e "  ${YELLOW}⚠️  $line (建議使用 4 的倍數)${NC}"
            ((WARNINGS++))
        fi
    done <<< "$SPACE_VALUES"
fi

echo ""

# 4. 檢查未使用的 tokens (如果有對應的 usage 檔案)
echo "🔍 檢查未使用的 tokens..."

# 定義所有 token
ALL_TOKENS=$(grep -oE "--[a-z0-9-]+" "$CSS_FILE" | sort -u)

# 簡單檢查：在同一檔案中是否有被引用
UNUSED_COUNT=0
for token in $ALL_TOKENS; do
    # 計算出現次數（定義 + 使用）
    count=$(grep -c "$token" "$CSS_FILE" || echo "0")
    if [ "$count" -le 1 ]; then
        echo -e "  ${YELLOW}⚠️  $token 可能未被使用${NC}"
        ((UNUSED_COUNT++))
    fi
done

if [ $UNUSED_COUNT -eq 0 ]; then
    echo -e "  ${GREEN}✅ 所有 tokens 都有被使用${NC}"
fi

echo ""

# 5. 統計資訊
echo "📊 統計資訊"
echo "==========="
TOKEN_COUNT=$(echo "$ALL_TOKENS" | wc -l | tr -d ' ')
COLOR_COUNT=$(echo "$ALL_TOKENS" | grep -c "color" || echo "0")
SPACE_COUNT=$(echo "$ALL_TOKENS" | grep -c "space" || echo "0")
FONT_COUNT=$(echo "$ALL_TOKENS" | grep -c "font" || echo "0")

echo "  總 tokens 數: $TOKEN_COUNT"
echo "  顏色 tokens: $COLOR_COUNT"
echo "  間距 tokens: $SPACE_COUNT"
echo "  字體 tokens: $FONT_COUNT"

echo ""

# 6. 結果摘要
echo "📝 驗證結果"
echo "==========="
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}❌ 發現 $ERRORS 個錯誤${NC}"
fi
if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  發現 $WARNINGS 個警告${NC}"
fi
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ 所有檢查通過！${NC}"
fi

echo ""

# 返回錯誤碼
exit $ERRORS
