#!/bin/bash
# test-ts-037.sh - /resume 指令驗證
# 驗證: commands/resume.md 檔案與 frontmatter 格式

echo "=== TS-037: /resume 指令驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMAND_FILE="$PROJECT_ROOT/commands/resume.md"

# 檢查檔案存在
if [ ! -f "$COMMAND_FILE" ]; then
    echo "❌ commands/resume.md 不存在"
    exit 1
fi

echo "✓ 檔案存在: $COMMAND_FILE"
echo ""

# 讀取檔案內容
CONTENT=$(cat "$COMMAND_FILE")
PASS=true

# 1. 檢查 frontmatter 必要欄位
echo "檢查 frontmatter 欄位..."

if ! echo "$CONTENT" | grep -q "^name: resume$"; then
    echo "❌ 缺少或錯誤: name: resume"
    PASS=false
else
    echo "✓ name: resume"
fi

if ! echo "$CONTENT" | grep -q "^description:"; then
    echo "❌ 缺少: description"
    PASS=false
else
    echo "✓ description 欄位存在"
fi

# resume 是口語觸發，所以 user-invocable: false
if ! echo "$CONTENT" | grep -q "^user-invocable: false$"; then
    echo "❌ 缺少或錯誤: user-invocable: false"
    PASS=false
else
    echo "✓ user-invocable: false"
fi

echo ""

# 2. 檢查特定內容
echo "檢查關鍵內容..."

if ! echo "$CONTENT" | grep -qi "接手\|resume\|恢復"; then
    echo "❌ 未提及接手/恢復相關功能"
    PASS=false
else
    echo "✓ 包含接手/恢復相關內容"
fi

if ! echo "$CONTENT" | grep -qi "OpenSpec\|change-id"; then
    echo "❌ 未提及 OpenSpec 或 change-id"
    PASS=false
else
    echo "✓ 包含 OpenSpec/change-id 說明"
fi

if ! echo "$CONTENT" | grep -qi "單步\|繼續"; then
    echo "❌ 未提及單步執行模式"
    PASS=false
else
    echo "✓ 包含單步執行說明"
fi

if ! echo "$CONTENT" | grep -qi "D→R→T\|tasks.md"; then
    echo "❌ 未提及 D→R→T 流程或 tasks.md"
    PASS=false
else
    echo "✓ 包含 D→R→T 流程說明"
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-037 PASS: /resume 指令驗證通過"
    exit 0
else
    echo "❌ TS-037 FAIL"
    exit 1
fi
