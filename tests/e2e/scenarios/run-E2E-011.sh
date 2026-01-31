#!/bin/bash
# run-E2E-011.sh - 獨立執行 E2E-011 測試腳本
# 用途：不依賴 e2e-runner，直接測試 keyword-detector.sh

set -e

# ═══════════════════════════════════════════════════════════════
# 配置
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ═══════════════════════════════════════════════════════════════
# 工具函數
# ═══════════════════════════════════════════════════════════════

log_pass() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_fail() {
    echo -e "${RED}❌ $1${NC}"
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_test() {
    echo -e "${CYAN}🧪 $1${NC}"
}

# ═══════════════════════════════════════════════════════════════
# 測試執行
# ═══════════════════════════════════════════════════════════════

# 設定環境變數
export CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT"
HOOK_SCRIPT="$PROJECT_ROOT/hooks/scripts/keyword-detector.sh"

# 驗證腳本存在
if [ ! -f "$HOOK_SCRIPT" ]; then
  log_fail "找不到 keyword-detector.sh"
  exit 1
fi

# 測試計數器
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_TESTS=8

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           E2E-011: UserPromptSubmit Hook 測試套件              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 1：規劃指令觸發 ARCHITECT
# ═══════════════════════════════════════════════════════════════

log_test "測試 1/8：規劃指令觸發 ARCHITECT"

INPUT='{"userPrompt":"規劃一個計數器功能"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')

if echo "$CONTEXT" | grep -q "ARCHITECT"; then
  log_pass "場景 1 通過：偵測到 ARCHITECT 提示"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_fail "場景 1 失敗：未偵測到 ARCHITECT 提示"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 2：loop 指令觸發
# ═══════════════════════════════════════════════════════════════

log_test "測試 2/8：loop 指令觸發"

INPUT='{"userPrompt":"loop"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')

if echo "$CONTEXT" | grep -q "tasks.md"; then
  log_pass "場景 2 通過：偵測到 loop 提示"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_fail "場景 2 失敗：未偵測到 loop 提示"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 3：無匹配關鍵字
# ═══════════════════════════════════════════════════════════════

log_test "測試 3/8：無匹配關鍵字"

INPUT='{"userPrompt":"這是什麼專案？"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')

if [ -z "$CONTEXT" ]; then
  log_pass "場景 3 通過：無額外注入"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_fail "場景 3 失敗：不應注入內容"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 4：混合關鍵字（優先級）
# ═══════════════════════════════════════════════════════════════

log_test "測試 4/8：混合關鍵字優先級"

INPUT='{"userPrompt":"規劃並設計用戶介面"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')

HAS_ARCHITECT=$(echo "$CONTEXT" | grep -c "ARCHITECT" || true)
HAS_DESIGNER=$(echo "$CONTEXT" | grep -c "DESIGNER" || true)

if [ "$HAS_ARCHITECT" -gt 0 ] && [ "$HAS_DESIGNER" -eq 0 ]; then
  log_pass "場景 4 通過：優先級正確（ARCHITECT > DESIGNER）"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_fail "場景 4 失敗：優先級錯誤"
  log_info "   ARCHITECT: $HAS_ARCHITECT, DESIGNER: $HAS_DESIGNER"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 5：大小寫不敏感
# ═══════════════════════════════════════════════════════════════

log_test "測試 5/8：大小寫不敏感"

INPUT='{"userPrompt":"LOOP"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')

if echo "$CONTEXT" | grep -q "tasks.md"; then
  log_pass "場景 5 通過：大寫 LOOP 被正確識別"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_fail "場景 5 失敗：大小寫不敏感失效"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 6：空字串處理
# ═══════════════════════════════════════════════════════════════

log_test "測試 6/8：空字串處理"

INPUT='{"userPrompt":""}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')

if [ -z "$CONTEXT" ]; then
  log_pass "場景 6 通過：空字串正確處理"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_fail "場景 6 失敗：空字串應返回空內容"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 7：JSON 格式驗證
# ═══════════════════════════════════════════════════════════════

log_test "測試 7/8：JSON 格式驗證"

INPUT='{"userPrompt":"規劃功能"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)

# 驗證 JSON 有效性
if echo "$OUTPUT" | jq empty 2>/dev/null; then
  # 驗證必要欄位
  EVENT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.hookEventName')

  if [ "$EVENT" = "UserPromptSubmit" ]; then
    log_pass "場景 7 通過：JSON 格式正確"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    log_fail "場景 7 失敗：hookEventName 錯誤"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  log_fail "場景 7 失敗：無效的 JSON 輸出"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 8：變數替換
# ═══════════════════════════════════════════════════════════════

log_test "測試 8/8：變數替換"

ORIGINAL_PROMPT="規劃計數器功能"
INPUT="{\"userPrompt\":\"$ORIGINAL_PROMPT\"}"
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')

# 驗證原始 prompt 被替換到範本中
if echo "$CONTEXT" | grep -q "$ORIGINAL_PROMPT"; then
  log_pass "場景 8 通過：變數替換正確"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_fail "場景 8 失敗：變數替換失敗"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試結果摘要
# ═══════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "測試結果摘要"
echo ""
echo "  總計：$TOTAL_TESTS 個測試"
echo -e "  ${GREEN}通過：$PASS_COUNT${NC}"
echo -e "  ${RED}失敗：$FAIL_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
  echo -e "${GREEN}✅ E2E-011 測試完全通過${NC}"
  echo ""
  echo "  驗證項目："
  echo "    ✓ 關鍵字檢測"
  echo "    ✓ 範本載入"
  echo "    ✓ 變數替換"
  echo "    ✓ 優先級排序"
  echo "    ✓ JSON 格式"
  echo "    ✓ 大小寫處理"
  echo "    ✓ 空字串處理"
  echo ""
  exit 0
else
  echo -e "${RED}❌ E2E-011 測試失敗${NC}"
  echo ""
  echo "請檢查失敗的測試案例"
  echo ""
  exit 1
fi
