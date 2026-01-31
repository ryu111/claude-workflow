#!/bin/bash
# test-ts-041.sh - /validate-skills 指令驗證
# 驗證: commands/validate-skills.md 檔案與 frontmatter 格式

echo "=== TS-041: /validate-skills 指令驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMAND_FILE="$PROJECT_ROOT/commands/validate-skills.md"
VALIDATION_SCRIPT="$PROJECT_ROOT/scripts/validate-skills.sh"

# 檢查檔案存在
if [ ! -f "$COMMAND_FILE" ]; then
    echo "❌ commands/validate-skills.md 不存在"
    exit 1
fi

echo "✓ 檔案存在: $COMMAND_FILE"
echo ""

# 讀取檔案內容
CONTENT=$(cat "$COMMAND_FILE")
PASS=true

# 1. 檢查 frontmatter 必要欄位
echo "檢查 frontmatter 欄位..."

if ! echo "$CONTENT" | grep -q "^name: validate-skills$"; then
    echo "❌ 缺少或錯誤: name: validate-skills"
    PASS=false
else
    echo "✓ name: validate-skills"
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

if ! echo "$CONTENT" | grep -q "^disable-model-invocation: true$"; then
    echo "❌ 缺少或錯誤: disable-model-invocation: true"
    PASS=false
else
    echo "✓ disable-model-invocation: true"
fi

echo ""

# 2. 檢查特定內容
echo "檢查關鍵內容..."

if ! echo "$CONTENT" | grep -qi "validate-skills\.sh\|scripts/validate-skills"; then
    echo "❌ 未引用 validate-skills.sh 腳本"
    PASS=false
else
    echo "✓ 引用 validate-skills.sh 腳本"
fi

if ! echo "$CONTENT" | grep -qi "SKILL\.md"; then
    echo "❌ 未提及 SKILL.md 檔案"
    PASS=false
else
    echo "✓ 包含 SKILL.md 檔案說明"
fi

if ! echo "$CONTENT" | grep -qi "引用.*驗證\|references.*templates"; then
    echo "❌ 未提及引用檔案驗證"
    PASS=false
else
    echo "✓ 包含引用檔案驗證"
fi

if ! echo "$CONTENT" | grep -qi "腳本.*權限\|\.sh.*權限"; then
    echo "❌ 未提及腳本權限檢查"
    PASS=false
else
    echo "✓ 包含腳本權限檢查"
fi

echo ""

# 3. 檢查對應的驗證腳本存在
echo "檢查對應的驗證腳本..."

if [ ! -f "$VALIDATION_SCRIPT" ]; then
    echo "❌ scripts/validate-skills.sh 不存在"
    PASS=false
else
    echo "✓ scripts/validate-skills.sh 存在"

    # 檢查腳本是否可執行
    if [ ! -x "$VALIDATION_SCRIPT" ]; then
        echo "⚠️  腳本無執行權限（但可自動修復）"
    else
        echo "✓ 腳本具有執行權限"
    fi
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-041 PASS: /validate-skills 指令驗證通過"
    exit 0
else
    echo "❌ TS-041 FAIL"
    exit 1
fi
