#!/bin/bash
# test-ts-036.sh - /plan 指令驗證
# 驗證: commands/plan.md 檔案與 frontmatter 格式

echo "=== TS-036: /plan 指令驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMAND_FILE="$PROJECT_ROOT/commands/plan.md"

# 檢查檔案存在
if [ ! -f "$COMMAND_FILE" ]; then
    echo "❌ commands/plan.md 不存在"
    exit 1
fi

echo "✓ 檔案存在: $COMMAND_FILE"
echo ""

# 讀取檔案內容
CONTENT=$(cat "$COMMAND_FILE")
PASS=true

# 1. 檢查 frontmatter 必要欄位
echo "檢查 frontmatter 欄位..."

if ! echo "$CONTENT" | grep -q "^name: plan$"; then
    echo "❌ 缺少或錯誤: name: plan"
    PASS=false
else
    echo "✓ name: plan"
fi

if ! echo "$CONTENT" | grep -q "^description:"; then
    echo "❌ 缺少: description"
    PASS=false
else
    echo "✓ description 欄位存在"
fi

if ! echo "$CONTENT" | grep -q "^user-invocable: true$"; then
    echo "❌ 缺少或錯誤: user-invocable: true"
    PASS=false
else
    echo "✓ user-invocable: true"
fi

echo ""

# 2. 檢查特定內容
echo "檢查關鍵內容..."

if ! echo "$CONTENT" | grep -qi "ARCHITECT"; then
    echo "❌ 未提及 ARCHITECT"
    PASS=false
else
    echo "✓ 包含 ARCHITECT"
fi

if ! echo "$CONTENT" | grep -qi "OpenSpec"; then
    echo "❌ 未提及 OpenSpec"
    PASS=false
else
    echo "✓ 包含 OpenSpec"
fi

if ! echo "$CONTENT" | grep -qi "規劃\|plan"; then
    echo "❌ 未提及規劃相關功能"
    PASS=false
else
    echo "✓ 包含規劃相關內容"
fi

if ! echo "$CONTENT" | grep -qi "proposal.md\|tasks.md"; then
    echo "❌ 未提及 OpenSpec 檔案結構"
    PASS=false
else
    echo "✓ 包含 OpenSpec 檔案結構說明"
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-036 PASS: /plan 指令驗證通過"
    exit 0
else
    echo "❌ TS-036 FAIL"
    exit 1
fi
