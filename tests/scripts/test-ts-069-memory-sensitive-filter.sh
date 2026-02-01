#!/bin/bash
# test-ts-069-memory-sensitive-filter.sh - 敏感記憶過濾器函式庫測試
# 驗證: hooks/scripts/lib/memory-sensitive-filter.sh 核心功能

echo "=== TS-069: 敏感記憶過濾器函式庫測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_UNDER_TEST="$PROJECT_ROOT/hooks/scripts/lib/memory-sensitive-filter.sh"

# 清理函式
cleanup() {
    # 清理臨時檔案（如果有）
    :
}

trap cleanup EXIT

# ============================================================
# 測試 0: 腳本存在性與語法正確性
# ============================================================

echo "【測試 0】腳本存在性與語法正確性"

if [ ! -f "$SCRIPT_UNDER_TEST" ]; then
    echo "❌ memory-sensitive-filter.sh 不存在，路徑: $SCRIPT_UNDER_TEST"
    exit 1
fi

echo "✓ memory-sensitive-filter.sh 已找到"

# 語法檢查
if bash -n "$SCRIPT_UNDER_TEST" 2>&1; then
    echo "✓ 語法檢查通過"
else
    echo "✗ 語法錯誤"
    exit 1
fi

echo ""

# ============================================================
# 測試 1: 載入函式庫
# ============================================================

echo "【測試 1】載入函式庫"

# 切換到專案根目錄（讓腳本能找到依賴）
cd "$PROJECT_ROOT" || exit 1

# Source 函式庫
if source "$SCRIPT_UNDER_TEST" 2>&1; then
    echo "✓ 函式庫載入成功"
else
    echo "✗ 函式庫載入失敗"
    exit 1
fi

echo ""

# ============================================================
# 測試 2: 常數定義
# ============================================================

echo "【測試 2】常數定義檢查"

TEST2_PASS=true

# 檢查返回碼常數
for const_name in \
    EXIT_SUCCESS \
    EXIT_ERROR \
    EXIT_INVALID_INPUT
do
    const_value="${!const_name}"
    if [ -n "$const_value" ]; then
        echo "  ✓ $const_name = $const_value"
    else
        echo "  ✗ $const_name 未定義"
        TEST2_PASS=false
    fi
done

# 檢查敏感標籤陣列
if [ ${#SENSITIVE_TAGS[@]} -gt 0 ]; then
    echo "  ✓ SENSITIVE_TAGS = (${SENSITIVE_TAGS[*]})"
else
    echo "  ✗ SENSITIVE_TAGS 未定義"
    TEST2_PASS=false
fi

# 檢查預設權限常數
if [ -n "$DEFAULT_SENSITIVE_ACCESS_AGENTS" ]; then
    echo "  ✓ DEFAULT_SENSITIVE_ACCESS_AGENTS = $DEFAULT_SENSITIVE_ACCESS_AGENTS"
else
    echo "  ✗ DEFAULT_SENSITIVE_ACCESS_AGENTS 未定義"
    TEST2_PASS=false
fi

echo ""

if [ "$TEST2_PASS" = false ]; then
    echo "❌ 常數定義檢查失敗"
    exit 1
fi

# ============================================================
# 測試 3: 核心函式定義檢查
# ============================================================

echo "【測試 3】核心函式定義檢查"

TEST3_PASS=true

# 檢查必要函式是否定義
for func_name in \
    load_sensitive_access_config \
    get_sensitive_tags \
    is_sensitive_memory \
    has_sensitive_access \
    filter_sensitive_memories \
    show_sensitive_access_config \
    show_sensitive_filter_help
do
    if declare -f "$func_name" >/dev/null 2>&1; then
        echo "  ✓ 函式 '$func_name' 已定義"
    else
        echo "  ✗ 函式 '$func_name' 未定義"
        TEST3_PASS=false
    fi
done

echo ""

if [ "$TEST3_PASS" = false ]; then
    echo "❌ 核心函式定義檢查失敗"
    exit 1
fi

# ============================================================
# 測試 4: CLI 命令測試 - help
# ============================================================

echo "【測試 4】CLI 命令測試 - help"

HELP_OUTPUT=$(bash "$SCRIPT_UNDER_TEST" help 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✓ help 命令執行成功"
else
    echo "  ✗ help 命令執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

# 檢查輸出包含關鍵資訊
if echo "$HELP_OUTPUT" | grep -q "用法" && \
   echo "$HELP_OUTPUT" | grep -q "filter_sensitive_memories" && \
   echo "$HELP_OUTPUT" | grep -q "敏感標籤"; then
    echo "  ✓ help 輸出包含預期資訊"
else
    echo "  ✗ help 輸出不完整"
    exit 1
fi

echo ""

# ============================================================
# 測試 5: load_sensitive_access_config 函式
# ============================================================

echo "【測試 5】load_sensitive_access_config 函式"

if load_sensitive_access_config 2>/dev/null; then
    echo "  ✓ 載入配置成功（使用預設配置）"
else
    echo "  ✗ 載入配置失敗"
    exit 1
fi

# 檢查已載入的配置
if [ -n "$SENSITIVE_ACCESS_AGENTS" ]; then
    echo "  ✓ SENSITIVE_ACCESS_AGENTS = $SENSITIVE_ACCESS_AGENTS"
else
    echo "  ✗ 配置未載入"
    exit 1
fi

echo ""

# ============================================================
# 測試 6: get_sensitive_tags 函式
# ============================================================

echo "【測試 6】get_sensitive_tags 函式"

TAGS=$(get_sensitive_tags)

if [ -n "$TAGS" ]; then
    echo "  ✓ 取得敏感標籤列表: $TAGS"
else
    echo "  ✗ 敏感標籤列表為空"
    exit 1
fi

# 檢查是否包含預期的標籤
if echo "$TAGS" | grep -q "sensitive" && \
   echo "$TAGS" | grep -q "secret"; then
    echo "  ✓ 標籤列表包含預期標籤"
else
    echo "  ✗ 標籤列表不完整"
    exit 1
fi

echo ""

# ============================================================
# 測試 7: is_sensitive_memory 函式 - 敏感記憶
# ============================================================

echo "【測試 7】is_sensitive_memory 函式 - 敏感記憶"

# 測試包含 sensitive 標籤的記憶
SENSITIVE_MEMORY='{"id":1,"tags":"sensitive,project","content":"secret data"}'

if is_sensitive_memory "$SENSITIVE_MEMORY"; then
    echo "  ✓ 正確識別敏感記憶（sensitive 標籤）"
else
    echo "  ✗ 敏感記憶識別失敗"
    exit 1
fi

# 測試包含 secret 標籤的記憶
SECRET_MEMORY='{"id":2,"tags":"secret,internal","content":"confidential"}'

if is_sensitive_memory "$SECRET_MEMORY"; then
    echo "  ✓ 正確識別敏感記憶（secret 標籤）"
else
    echo "  ✗ 敏感記憶識別失敗"
    exit 1
fi

# 測試包含 private 標籤的記憶
PRIVATE_MEMORY='{"id":3,"tags":"private","content":"personal data"}'

if is_sensitive_memory "$PRIVATE_MEMORY"; then
    echo "  ✓ 正確識別敏感記憶（private 標籤）"
else
    echo "  ✗ 敏感記憶識別失敗"
    exit 1
fi

echo ""

# ============================================================
# 測試 8: is_sensitive_memory 函式 - 非敏感記憶
# ============================================================

echo "【測試 8】is_sensitive_memory 函式 - 非敏感記憶"

# 測試不包含敏感標籤的記憶
PUBLIC_MEMORY='{"id":4,"tags":"public,general","content":"public info"}'

if ! is_sensitive_memory "$PUBLIC_MEMORY"; then
    echo "  ✓ 正確識別非敏感記憶"
else
    echo "  ✗ 非敏感記憶識別失敗"
    exit 1
fi

# 測試無標籤的記憶
NO_TAGS_MEMORY='{"id":5,"content":"no tags"}'

if ! is_sensitive_memory "$NO_TAGS_MEMORY"; then
    echo "  ✓ 正確處理無標籤記憶"
else
    echo "  ✗ 無標籤記憶處理失敗"
    exit 1
fi

echo ""

# ============================================================
# 測試 9: has_sensitive_access 函式 - 有權限
# ============================================================

echo "【測試 9】has_sensitive_access 函式 - 有權限"

# 測試 main agent（預設有權限）
if has_sensitive_access "main"; then
    echo "  ✓ main agent 有權限"
else
    echo "  ✗ main agent 權限檢查失敗"
    exit 1
fi

# 測試大小寫不敏感
if has_sensitive_access "MAIN"; then
    echo "  ✓ 大小寫不敏感（MAIN）"
else
    echo "  ✗ 大小寫處理失敗"
    exit 1
fi

echo ""

# ============================================================
# 測試 10: has_sensitive_access 函式 - 無權限
# ============================================================

echo "【測試 10】has_sensitive_access 函式 - 無權限"

# 測試沒有權限的 agent
if ! has_sensitive_access "developer"; then
    echo "  ✓ developer agent 無權限"
else
    echo "  ✗ developer agent 權限檢查失敗"
    exit 1
fi

if ! has_sensitive_access "reviewer"; then
    echo "  ✓ reviewer agent 無權限"
else
    echo "  ✗ reviewer agent 權限檢查失敗"
    exit 1
fi

echo ""

# ============================================================
# 測試 11: filter_sensitive_memories 函式 - 有權限不過濾
# ============================================================

echo "【測試 11】filter_sensitive_memories 函式 - 有權限不過濾"

# 建立測試 JSON
TEST_JSON='{
  "results": [
    {"id":1,"tags":"sensitive,project","content":"secret"},
    {"id":2,"tags":"public","content":"public info"}
  ],
  "query": "test"
}'

# main agent 應該不過濾
FILTERED=$(filter_sensitive_memories "$TEST_JSON" "main" 2>/dev/null)
EXIT_CODE=$?

if [ $EXIT_CODE -eq $EXIT_SUCCESS ]; then
    echo "  ✓ filter_sensitive_memories 執行成功"
else
    echo "  ✗ filter_sensitive_memories 執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

# 檢查是否包含原始內容
if echo "$FILTERED" | grep -q '"id":1' && \
   echo "$FILTERED" | grep -q '"id":2'; then
    echo "  ✓ main agent 不過濾敏感記憶"
else
    echo "  ✗ main agent 過濾錯誤"
    exit 1
fi

echo ""

# ============================================================
# 測試 12: filter_sensitive_memories 函式 - 無權限過濾
# ============================================================

echo "【測試 12】filter_sensitive_memories 函式 - 無權限過濾"

# developer agent 應該過濾
FILTERED=$(filter_sensitive_memories "$TEST_JSON" "developer" 2>/dev/null)
EXIT_CODE=$?

if [ $EXIT_CODE -eq $EXIT_SUCCESS ]; then
    echo "  ✓ filter_sensitive_memories 執行成功"
else
    echo "  ✗ filter_sensitive_memories 執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

# 檢查是否移除敏感記憶
if ! echo "$FILTERED" | grep -q '"id":1'; then
    echo "  ✓ 正確移除敏感記憶（id:1）"
else
    echo "  ✗ 敏感記憶未移除"
    exit 1
fi

# 檢查是否保留非敏感記憶
if echo "$FILTERED" | grep -q '"id":2'; then
    echo "  ✓ 保留非敏感記憶（id:2）"
else
    echo "  ✗ 非敏感記憶錯誤移除"
    exit 1
fi

# 檢查 filtered 標記
if echo "$FILTERED" | grep -q '"filtered":true'; then
    echo "  ✓ 包含 filtered 標記"
else
    echo "  ✗ 缺少 filtered 標記"
    exit 1
fi

echo ""

# ============================================================
# 測試 13: filter_sensitive_memories 函式 - 空輸入驗證
# ============================================================

echo "【測試 13】filter_sensitive_memories 函式 - 空輸入驗證"

# 測試空字串輸入
filter_sensitive_memories "" "developer" 2>/dev/null
EXIT_CODE=$?

if [ $EXIT_CODE -eq $EXIT_INVALID_INPUT ]; then
    echo "  ✓ 正確拒絕空輸入"
else
    echo "  ✗ 空輸入驗證失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

echo ""

# ============================================================
# 測試 14: filter_sensitive_memories 函式 - 無效 JSON
# ============================================================

echo "【測試 14】filter_sensitive_memories 函式 - 無效 JSON"

# 測試無效 JSON
INVALID_JSON='{"invalid":"json"}'

filter_sensitive_memories "$INVALID_JSON" "developer" 2>/dev/null
EXIT_CODE=$?

if [ $EXIT_CODE -eq $EXIT_INVALID_INPUT ]; then
    echo "  ✓ 正確拒絕無效 JSON（缺少 results）"
else
    echo "  ✗ 無效 JSON 驗證失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

echo ""

# ============================================================
# 測試 15: CLI 命令測試 - tags
# ============================================================

echo "【測試 15】CLI 命令測試 - tags"

CLI_OUTPUT=$(bash "$SCRIPT_UNDER_TEST" tags 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✓ tags 命令執行成功"
else
    echo "  ✗ tags 命令執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

if echo "$CLI_OUTPUT" | grep -q "sensitive" && \
   echo "$CLI_OUTPUT" | grep -q "secret"; then
    echo "  ✓ tags 輸出包含預期標籤"
else
    echo "  ✗ tags 輸出錯誤"
    exit 1
fi

echo ""

# ============================================================
# 測試 16: CLI 命令測試 - check-memory
# ============================================================

echo "【測試 16】CLI 命令測試 - check-memory"

# 測試敏感記憶
bash "$SCRIPT_UNDER_TEST" check-memory "$SENSITIVE_MEMORY" 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✓ check-memory 正確識別敏感記憶"
else
    echo "  ✗ check-memory 識別失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

# 測試非敏感記憶
bash "$SCRIPT_UNDER_TEST" check-memory "$PUBLIC_MEMORY" 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 1 ]; then
    echo "  ✓ check-memory 正確識別非敏感記憶"
else
    echo "  ✗ check-memory 識別失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

echo ""

# ============================================================
# 測試 17: CLI 命令測試 - check-agent
# ============================================================

echo "【測試 17】CLI 命令測試 - check-agent"

# 測試有權限的 agent
bash "$SCRIPT_UNDER_TEST" check-agent "main" 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✓ check-agent 正確識別有權限 agent"
else
    echo "  ✗ check-agent 識別失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

# 測試無權限的 agent
bash "$SCRIPT_UNDER_TEST" check-agent "developer" 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 1 ]; then
    echo "  ✓ check-agent 正確識別無權限 agent"
else
    echo "  ✗ check-agent 識別失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

echo ""

# ============================================================
# 測試 18: CLI 命令測試 - config
# ============================================================

echo "【測試 18】CLI 命令測試 - config"

CLI_OUTPUT=$(bash "$SCRIPT_UNDER_TEST" config 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✓ config 命令執行成功"
else
    echo "  ✗ config 命令執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

if echo "$CLI_OUTPUT" | grep -q "敏感標籤列表" && \
   echo "$CLI_OUTPUT" | grep -q "敏感存取權限"; then
    echo "  ✓ config 輸出包含預期資訊"
else
    echo "  ✗ config 輸出錯誤"
    exit 1
fi

echo ""

# ============================================================
# 測試 19: show_sensitive_access_config 函式
# ============================================================

echo "【測試 19】show_sensitive_access_config 函式"

CONFIG_OUTPUT=$(show_sensitive_access_config 2>&1)

if echo "$CONFIG_OUTPUT" | grep -q "敏感標籤列表" && \
   echo "$CONFIG_OUTPUT" | grep -q "main"; then
    echo "  ✓ 配置顯示功能正常"
else
    echo "  ✗ 配置顯示錯誤"
    exit 1
fi

echo ""

# ============================================================
# 總結
# ============================================================

echo "═══════════════════════════════════════════════════"
echo "測試摘要"
echo "═══════════════════════════════════════════════════"
echo ""

echo "✓ 基礎檢查："
echo "  - 腳本存在: PASS"
echo "  - 語法正確: PASS"
echo "  - 函式庫載入: PASS"
echo ""

echo "✓ 組件驗證："
echo "  - 常數定義: PASS (3 個返回碼 + 敏感標籤陣列 + 預設權限)"
echo "  - 核心函式: PASS (7 個核心函式)"
echo "  - CLI 命令: PASS (help, tags, check-memory, check-agent, config)"
echo ""

echo "✓ 功能測試："
echo "  - load_sensitive_access_config: PASS"
echo "  - get_sensitive_tags: PASS"
echo "  - is_sensitive_memory: PASS (敏感 + 非敏感)"
echo "  - has_sensitive_access: PASS (有權限 + 無權限)"
echo "  - filter_sensitive_memories: PASS (過濾 + 不過濾)"
echo "  - 輸入驗證: PASS (空輸入 + 無效 JSON)"
echo "  - 大小寫不敏感: PASS"
echo ""

echo "✅ TS-069 PASS: 敏感記憶過濾器函式庫功能正確"
exit 0
