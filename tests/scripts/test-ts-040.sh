#!/bin/bash
# test-ts-040.sh - /validate-agents 指令驗證
# 驗證: commands/validate-agents.md 檔案與 frontmatter 格式

echo "=== TS-040: /validate-agents 指令驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMAND_FILE="$PROJECT_ROOT/commands/validate-agents.md"
VALIDATION_SCRIPT="$PROJECT_ROOT/scripts/validate-agents.sh"

# 檢查檔案存在
if [ ! -f "$COMMAND_FILE" ]; then
    echo "❌ commands/validate-agents.md 不存在"
    exit 1
fi

echo "✓ 檔案存在: $COMMAND_FILE"
echo ""

# 讀取檔案內容
CONTENT=$(cat "$COMMAND_FILE")
PASS=true

# 1. 檢查 frontmatter 必要欄位
echo "檢查 frontmatter 欄位..."

if ! echo "$CONTENT" | grep -q "^name: validate-agents$"; then
    echo "❌ 缺少或錯誤: name: validate-agents"
    PASS=false
else
    echo "✓ name: validate-agents"
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

if ! echo "$CONTENT" | grep -qi "validate-agents\.sh\|scripts/validate-agents"; then
    echo "❌ 未引用 validate-agents.sh 腳本"
    PASS=false
else
    echo "✓ 引用 validate-agents.sh 腳本"
fi

if ! echo "$CONTENT" | grep -qi "frontmatter"; then
    echo "❌ 未提及 frontmatter 驗證"
    PASS=false
else
    echo "✓ 包含 frontmatter 驗證說明"
fi

if ! echo "$CONTENT" | grep -qi "skills.*引用\|skills.*驗證"; then
    echo "❌ 未提及 Skills 引用驗證"
    PASS=false
else
    echo "✓ 包含 Skills 引用驗證"
fi

if ! echo "$CONTENT" | grep -qi "tools.*配置\|tools.*檢查"; then
    echo "❌ 未提及 Tools 配置檢查"
    PASS=false
else
    echo "✓ 包含 Tools 配置檢查"
fi

echo ""

# 3. 檢查對應的驗證腳本存在
echo "檢查對應的驗證腳本..."

if [ ! -f "$VALIDATION_SCRIPT" ]; then
    echo "❌ scripts/validate-agents.sh 不存在"
    PASS=false
else
    echo "✓ scripts/validate-agents.sh 存在"

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
    echo "✅ TS-040 PASS: /validate-agents 指令驗證通過"
    exit 0
else
    echo "❌ TS-040 FAIL"
    exit 1
fi
