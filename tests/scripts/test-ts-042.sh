#!/bin/bash
# test-ts-042.sh - /validate-hooks 指令驗證
# 驗證: commands/validate-hooks.md 檔案與 frontmatter 格式

echo "=== TS-042: /validate-hooks 指令驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMAND_FILE="$PROJECT_ROOT/commands/validate-hooks.md"
VALIDATION_SCRIPT="$PROJECT_ROOT/scripts/validate-hooks.sh"

# 檢查檔案存在
if [ ! -f "$COMMAND_FILE" ]; then
    echo "❌ commands/validate-hooks.md 不存在"
    exit 1
fi

echo "✓ 檔案存在: $COMMAND_FILE"
echo ""

# 讀取檔案內容
CONTENT=$(cat "$COMMAND_FILE")
PASS=true

# 1. 檢查 frontmatter 必要欄位
echo "檢查 frontmatter 欄位..."

if ! echo "$CONTENT" | grep -q "^name: validate-hooks$"; then
    echo "❌ 缺少或錯誤: name: validate-hooks"
    PASS=false
else
    echo "✓ name: validate-hooks"
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

if ! echo "$CONTENT" | grep -qi "validate-hooks\.sh\|scripts/validate-hooks"; then
    echo "❌ 未引用 validate-hooks.sh 腳本"
    PASS=false
else
    echo "✓ 引用 validate-hooks.sh 腳本"
fi

if ! echo "$CONTENT" | grep -qi "hooks\.json"; then
    echo "❌ 未提及 hooks.json 配置檔"
    PASS=false
else
    echo "✓ 包含 hooks.json 配置說明"
fi

if ! echo "$CONTENT" | grep -qi "SessionStart\|PreToolUse\|SubagentStop"; then
    echo "❌ 未列出支援的 Hook 事件"
    PASS=false
else
    echo "✓ 包含支援的 Hook 事件列表"
fi

if ! echo "$CONTENT" | grep -qi "腳本.*存在\|執行權限\|路徑變數"; then
    echo "❌ 未提及腳本驗證項目"
    PASS=false
else
    echo "✓ 包含腳本驗證項目說明"
fi

echo ""

# 3. 檢查對應的驗證腳本存在
echo "檢查對應的驗證腳本..."

if [ ! -f "$VALIDATION_SCRIPT" ]; then
    echo "❌ scripts/validate-hooks.sh 不存在"
    PASS=false
else
    echo "✓ scripts/validate-hooks.sh 存在"

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
    echo "✅ TS-042 PASS: /validate-hooks 指令驗證通過"
    exit 0
else
    echo "❌ TS-042 FAIL"
    exit 1
fi
