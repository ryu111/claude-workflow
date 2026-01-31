#!/bin/bash
# test-ts-038.sh - /loop 指令驗證
# 驗證: commands/loop.md 檔案與 frontmatter 格式

echo "=== TS-038: /loop 指令驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMAND_FILE="$PROJECT_ROOT/commands/loop.md"

# 檢查檔案存在
if [ ! -f "$COMMAND_FILE" ]; then
    echo "❌ commands/loop.md 不存在"
    exit 1
fi

echo "✓ 檔案存在: $COMMAND_FILE"
echo ""

# 讀取檔案內容
CONTENT=$(cat "$COMMAND_FILE")
PASS=true

# 1. 檢查 frontmatter 必要欄位
echo "檢查 frontmatter 欄位..."

if ! echo "$CONTENT" | grep -q "^name: loop$"; then
    echo "❌ 缺少或錯誤: name: loop"
    PASS=false
else
    echo "✓ name: loop"
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

if ! echo "$CONTENT" | grep -qi "迴圈\|loop\|持續執行\|自動完成"; then
    echo "❌ 未提及迴圈/持續執行相關功能"
    PASS=false
else
    echo "✓ 包含迴圈/持續執行相關內容"
fi

if ! echo "$CONTENT" | grep -qi "持續執行模式\|通用模式"; then
    echo "❌ 未提及執行模式說明"
    PASS=false
else
    echo "✓ 包含執行模式說明"
fi

if ! echo "$CONTENT" | grep -qi "while.*任務\|持續.*直到"; then
    echo "❌ 未提及持續執行邏輯"
    PASS=false
else
    echo "✓ 包含持續執行邏輯說明"
fi

if ! echo "$CONTENT" | grep -qi "TodoList\|OpenSpec"; then
    echo "❌ 未提及任務來源"
    PASS=false
else
    echo "✓ 包含任務來源說明"
fi

if ! echo "$CONTENT" | grep -qi "E2E"; then
    echo "❌ 未提及 E2E 測試模式"
    PASS=false
else
    echo "✓ 包含 E2E 測試模式說明"
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-038 PASS: /loop 指令驗證通過"
    exit 0
else
    echo "❌ TS-038 FAIL"
    exit 1
fi
