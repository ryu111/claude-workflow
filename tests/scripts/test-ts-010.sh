#!/bin/bash
# test-ts-010.sh - /loop 持續執行測試
# 驗證: /loop 指令結構和可用性
# 狀態: 運行時行為需要在 Claude Code 中手動測試

echo "=== TS-010: /loop 持續執行測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOOP_CMD="$PROJECT_ROOT/commands/loop.md"

PASS=true

# Step 1: 檢查 loop.md 存在
echo "Step 1: 檢查 loop.md..."

if [ ! -f "$LOOP_CMD" ]; then
    echo "❌ loop.md 不存在"
    exit 1
fi

echo "✅ loop.md 存在"
echo ""

# Step 2: 檢查 frontmatter
echo "Step 2: 檢查 frontmatter..."

if grep -q "^---" "$LOOP_CMD"; then
    echo "✅ 包含 YAML frontmatter"
else
    echo "⚠️ 未找到 frontmatter"
fi

# Step 3: 檢查關鍵內容
echo ""
echo "Step 3: 檢查關鍵內容..."

if grep -qi "loop\|持續\|執行" "$LOOP_CMD"; then
    echo "✅ 包含 loop 相關指示"
else
    echo "❌ 未找到 loop 相關指示"
    PASS=false
fi

if grep -qi "task\|任務\|openspec" "$LOOP_CMD"; then
    echo "✅ 包含任務執行指示"
else
    echo "⚠️ 未找到任務執行指示"
fi

# Step 4: 顯示 loop.md 內容摘要
echo ""
echo "Step 4: loop.md 內容摘要:"
echo "─────────────────────────────────"
head -50 "$LOOP_CMD"
echo "─────────────────────────────────"

echo ""
echo "⚠️ /loop 運行時行為需要在 Claude Code 中手動測試"
echo ""

# 返回 exit 2 表示需要手動測試
exit 2
