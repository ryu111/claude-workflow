#!/bin/bash
# test-ts-039.sh - /init 指令驗證
# 驗證: commands/init.md 檔案與 frontmatter 格式

echo "=== TS-039: /init 指令驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMAND_FILE="$PROJECT_ROOT/commands/init.md"

# 檢查檔案存在
if [ ! -f "$COMMAND_FILE" ]; then
    echo "❌ commands/init.md 不存在"
    exit 1
fi

echo "✓ 檔案存在: $COMMAND_FILE"
echo ""

# 讀取檔案內容
CONTENT=$(cat "$COMMAND_FILE")
PASS=true

# 1. 檢查 frontmatter 必要欄位
echo "檢查 frontmatter 欄位..."

if ! echo "$CONTENT" | grep -q "^name: init$"; then
    echo "❌ 缺少或錯誤: name: init"
    PASS=false
else
    echo "✓ name: init"
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

if ! echo "$CONTENT" | grep -qi "初始化\|init"; then
    echo "❌ 未提及初始化相關功能"
    PASS=false
else
    echo "✓ 包含初始化相關內容"
fi

if ! echo "$CONTENT" | grep -qi "配置\|設定\|setup"; then
    echo "❌ 未提及配置相關功能"
    PASS=false
else
    echo "✓ 包含配置相關內容"
fi

if ! echo "$CONTENT" | grep -qi "零配置\|自動偵測"; then
    echo "❌ 未提及零配置部署特性"
    PASS=false
else
    echo "✓ 包含零配置部署說明"
fi

if ! echo "$CONTENT" | grep -qi "steering\|\.claude"; then
    echo "❌ 未提及 steering 配置目錄"
    PASS=false
else
    echo "✓ 包含 steering 配置說明"
fi

if ! echo "$CONTENT" | grep -qi "scripts/init.sh"; then
    echo "❌ 未提及 init.sh 腳本"
    PASS=false
else
    echo "✓ 包含 init.sh 腳本參考"
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-039 PASS: /init 指令驗證通過"
    exit 0
else
    echo "❌ TS-039 FAIL"
    exit 1
fi
