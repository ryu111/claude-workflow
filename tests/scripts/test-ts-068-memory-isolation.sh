#!/bin/bash
# test-ts-068-memory-isolation.sh - 記憶專案隔離函式庫測試
# 驗證: hooks/scripts/lib/memory-isolation.sh 核心功能

echo "=== TS-068: 記憶專案隔離函式庫測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_UNDER_TEST="$PROJECT_ROOT/hooks/scripts/lib/memory-isolation.sh"

# 建立臨時測試環境
TEST_DIR=$(mktemp -d)
TEST_PROJECT_DIR="$TEST_DIR/test-project"
TEST_MEMORY_DIR="$TEST_PROJECT_DIR/.claude/memory"

# 清理函式
cleanup() {
    rm -rf "$TEST_DIR"
}

trap cleanup EXIT

# ============================================================
# 測試 0: 腳本存在性與語法正確性
# ============================================================

echo "【測試 0】腳本存在性與語法正確性"

if [ ! -f "$SCRIPT_UNDER_TEST" ]; then
    echo "❌ memory-isolation.sh 不存在，路徑: $SCRIPT_UNDER_TEST"
    exit 1
fi

echo "✓ memory-isolation.sh 已找到"

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

# 建立測試目錄
mkdir -p "$TEST_MEMORY_DIR"

# 切換到專案根目錄（讓腳本能找到依賴）
cd "$PROJECT_ROOT" || exit 1

# Source 函式庫
if source "$SCRIPT_UNDER_TEST" 2>&1; then
    echo "✓ 函式庫載入成功"
else
    echo "✗ 函式庫載入失敗"
    exit 1
fi

# 切換到測試專案目錄（用於後續測試）
cd "$TEST_PROJECT_DIR" || exit 1

echo ""

# ============================================================
# 測試 2: 常數定義
# ============================================================

echo "【測試 2】常數定義檢查"

TEST2_PASS=true

# 檢查返回碼常數
for const_name in \
    ISOLATION_SUCCESS \
    ISOLATION_ERROR \
    ISOLATION_INVALID_PATH
do
    const_value="${!const_name}"
    if [ -n "$const_value" ]; then
        echo "  ✓ $const_name = $const_value"
    else
        echo "  ✗ $const_name 未定義"
        TEST2_PASS=false
    fi
done

# 檢查路徑常數
for const_name in \
    MEMORY_SUBDIR \
    GLOBAL_MEMORY_FLAG \
    GLOBAL_MEMORY_DIR
do
    const_value="${!const_name}"
    if [ -n "$const_value" ]; then
        echo "  ✓ $const_name = $const_value"
    else
        echo "  ✗ $const_name 未定義"
        TEST2_PASS=false
    fi
done

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
    get_project_root \
    get_project_memory_dir \
    validate_memory_path \
    resolve_safe_path \
    is_global_memory_enabled \
    enable_global_memory \
    disable_global_memory \
    show_isolation_help
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
   echo "$HELP_OUTPUT" | grep -q "get_project_root" && \
   echo "$HELP_OUTPUT" | grep -q "安全機制"; then
    echo "  ✓ help 輸出包含預期資訊"
else
    echo "  ✗ help 輸出不完整"
    exit 1
fi

echo ""

# ============================================================
# 測試 5: get_project_root 函式
# ============================================================

echo "【測試 5】get_project_root 函式"

# 在測試專案目錄中執行
cd "$TEST_PROJECT_DIR" || exit 1

PROJECT_ROOT_RESULT=$(get_project_root 2>/dev/null)
EXIT_CODE=$?

if [ $EXIT_CODE -eq $ISOLATION_SUCCESS ]; then
    echo "  ✓ get_project_root 執行成功"
else
    echo "  ✗ get_project_root 執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

# 檢查返回的路徑是否正確
if [ -n "$PROJECT_ROOT_RESULT" ]; then
    echo "  ✓ 取得專案根目錄: $PROJECT_ROOT_RESULT"
else
    echo "  ✗ 專案根目錄為空"
    exit 1
fi

echo ""

# ============================================================
# 測試 6: get_project_memory_dir 函式
# ============================================================

echo "【測試 6】get_project_memory_dir 函式"

MEMORY_DIR_RESULT=$(get_project_memory_dir 2>/dev/null)
EXIT_CODE=$?

if [ $EXIT_CODE -eq $ISOLATION_SUCCESS ]; then
    echo "  ✓ get_project_memory_dir 執行成功"
else
    echo "  ✗ get_project_memory_dir 執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

# 檢查返回的路徑包含 .claude/memory
if echo "$MEMORY_DIR_RESULT" | grep -q ".claude/memory"; then
    echo "  ✓ 記憶目錄路徑正確: $MEMORY_DIR_RESULT"
else
    echo "  ✗ 記憶目錄路徑錯誤: $MEMORY_DIR_RESULT"
    exit 1
fi

echo ""

# ============================================================
# 測試 7: validate_memory_path 函式 - 合法路徑
# ============================================================

echo "【測試 7】validate_memory_path 函式 - 合法路徑"

# 建立測試檔案
VALID_PATH="$TEST_MEMORY_DIR/test-memory.md"
touch "$VALID_PATH"

if validate_memory_path "$VALID_PATH" 2>/dev/null; then
    echo "  ✓ 合法路徑驗證通過: $VALID_PATH"
else
    echo "  ✗ 合法路徑驗證失敗"
    exit 1
fi

echo ""

# ============================================================
# 測試 8: validate_memory_path 函式 - 非法路徑
# ============================================================

echo "【測試 8】validate_memory_path 函式 - 非法路徑"

# 測試不在記憶目錄內的路徑
INVALID_PATH="/tmp/not-in-memory.md"
touch "$INVALID_PATH"

if ! validate_memory_path "$INVALID_PATH" 2>/dev/null; then
    echo "  ✓ 非法路徑驗證正確拒絕: $INVALID_PATH"
else
    echo "  ✗ 非法路徑驗證失敗（應該拒絕）"
    exit 1
fi

rm -f "$INVALID_PATH"

echo ""

# ============================================================
# 測試 9: resolve_safe_path 函式 - 相對路徑
# ============================================================

echo "【測試 9】resolve_safe_path 函式 - 相對路徑"

# 建立測試檔案
RELATIVE_FILE="sessions/test-session.jsonl"
FULL_PATH="$TEST_MEMORY_DIR/$RELATIVE_FILE"
mkdir -p "$(dirname "$FULL_PATH")"
touch "$FULL_PATH"

RESOLVED_PATH=$(resolve_safe_path "$RELATIVE_FILE" 2>/dev/null)
EXIT_CODE=$?

if [ $EXIT_CODE -eq $ISOLATION_SUCCESS ]; then
    echo "  ✓ 相對路徑解析成功"
else
    echo "  ✗ 相對路徑解析失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

if [ -n "$RESOLVED_PATH" ]; then
    echo "  ✓ 解析後路徑: $RESOLVED_PATH"
else
    echo "  ✗ 解析路徑為空"
    exit 1
fi

echo ""

# ============================================================
# 測試 10: resolve_safe_path 函式 - 阻擋路徑穿越
# ============================================================

echo "【測試 10】resolve_safe_path 函式 - 阻擋路徑穿越"

# 測試包含 .. 的路徑
TRAVERSAL_PATH="../../../etc/passwd"

if ! resolve_safe_path "$TRAVERSAL_PATH" 2>/dev/null; then
    echo "  ✓ 路徑穿越攻擊正確阻擋: $TRAVERSAL_PATH"
else
    echo "  ✗ 路徑穿越攻擊未阻擋"
    exit 1
fi

echo ""

# ============================================================
# 測試 11: is_global_memory_enabled 函式
# ============================================================

echo "【測試 11】is_global_memory_enabled 函式"

# 確保全域記憶未啟用（清理）
disable_global_memory 2>/dev/null

if ! is_global_memory_enabled 2>/dev/null; then
    echo "  ✓ 全域記憶預設為禁用"
else
    echo "  ✗ 全域記憶狀態錯誤"
    exit 1
fi

echo ""

# ============================================================
# 測試 12: enable_global_memory 函式
# ============================================================

echo "【測試 12】enable_global_memory 函式"

if enable_global_memory 2>/dev/null; then
    echo "  ✓ 啟用全域記憶成功"
else
    echo "  ✗ 啟用全域記憶失敗"
    exit 1
fi

# 驗證已啟用
if is_global_memory_enabled 2>/dev/null; then
    echo "  ✓ 全域記憶狀態驗證通過"
else
    echo "  ✗ 全域記憶狀態驗證失敗"
    exit 1
fi

echo ""

# ============================================================
# 測試 13: disable_global_memory 函式
# ============================================================

echo "【測試 13】disable_global_memory 函式"

if disable_global_memory 2>/dev/null; then
    echo "  ✓ 禁用全域記憶成功"
else
    echo "  ✗ 禁用全域記憶失敗"
    exit 1
fi

# 驗證已禁用
if ! is_global_memory_enabled 2>/dev/null; then
    echo "  ✓ 全域記憶狀態驗證通過"
else
    echo "  ✗ 全域記憶狀態驗證失敗"
    exit 1
fi

echo ""

# ============================================================
# 測試 14: CLI 命令測試 - get-project-root
# ============================================================

echo "【測試 14】CLI 命令測試 - get-project-root"

CLI_OUTPUT=$(cd "$TEST_PROJECT_DIR" && bash "$SCRIPT_UNDER_TEST" get-project-root 2>/dev/null)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✓ get-project-root 命令執行成功"
else
    echo "  ✗ get-project-root 命令執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

if [ -n "$CLI_OUTPUT" ]; then
    echo "  ✓ CLI 輸出: $CLI_OUTPUT"
else
    echo "  ✗ CLI 輸出為空"
    exit 1
fi

echo ""

# ============================================================
# 測試 15: CLI 命令測試 - get-memory-dir
# ============================================================

echo "【測試 15】CLI 命令測試 - get-memory-dir"

CLI_OUTPUT=$(cd "$TEST_PROJECT_DIR" && bash "$SCRIPT_UNDER_TEST" get-memory-dir 2>/dev/null)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✓ get-memory-dir 命令執行成功"
else
    echo "  ✗ get-memory-dir 命令執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

if echo "$CLI_OUTPUT" | grep -q ".claude/memory"; then
    echo "  ✓ CLI 輸出包含 .claude/memory"
else
    echo "  ✗ CLI 輸出錯誤"
    exit 1
fi

echo ""

# ============================================================
# 測試 16: CLI 命令測試 - validate
# ============================================================

echo "【測試 16】CLI 命令測試 - validate"

# 測試合法路徑
cd "$TEST_PROJECT_DIR" || exit 1
bash "$SCRIPT_UNDER_TEST" validate "$VALID_PATH" 2>/dev/null
EXIT_CODE=$?

if [ $EXIT_CODE -eq $ISOLATION_SUCCESS ]; then
    echo "  ✓ validate 命令驗證合法路徑通過"
else
    echo "  ✗ validate 命令驗證失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

# 測試非法路徑
bash "$SCRIPT_UNDER_TEST" validate "/tmp/illegal.md" 2>/dev/null
EXIT_CODE=$?

if [ $EXIT_CODE -eq $ISOLATION_INVALID_PATH ]; then
    echo "  ✓ validate 命令正確拒絕非法路徑"
else
    echo "  ✗ validate 命令錯誤處理失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

echo ""

# ============================================================
# 測試 17: CLI 命令測試 - resolve
# ============================================================

echo "【測試 17】CLI 命令測試 - resolve"

CLI_OUTPUT=$(cd "$TEST_PROJECT_DIR" && bash "$SCRIPT_UNDER_TEST" resolve "$RELATIVE_FILE" 2>/dev/null)
EXIT_CODE=$?

if [ $EXIT_CODE -eq $ISOLATION_SUCCESS ]; then
    echo "  ✓ resolve 命令執行成功"
else
    echo "  ✗ resolve 命令執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

if [ -n "$CLI_OUTPUT" ]; then
    echo "  ✓ CLI 解析路徑: $CLI_OUTPUT"
else
    echo "  ✗ CLI 解析路徑為空"
    exit 1
fi

echo ""

# ============================================================
# 測試 18: CLI 命令測試 - check-global
# ============================================================

echo "【測試 18】CLI 命令測試 - check-global"

# 禁用全域記憶
disable_global_memory 2>/dev/null

CLI_OUTPUT=$(bash "$SCRIPT_UNDER_TEST" check-global 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 1 ]; then
    echo "  ✓ check-global 正確返回未啟用狀態"
else
    echo "  ✗ check-global 狀態錯誤 (exit code: $EXIT_CODE)"
    exit 1
fi

if echo "$CLI_OUTPUT" | grep -q "未啟用"; then
    echo "  ✓ CLI 輸出包含狀態訊息"
else
    echo "  ✗ CLI 輸出錯誤"
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
echo "  - 常數定義: PASS (3 個返回碼 + 3 個路徑常數)"
echo "  - 核心函式: PASS (8 個核心函式)"
echo "  - CLI 命令: PASS (help, get-project-root, get-memory-dir, validate, resolve, check-global)"
echo ""

echo "✓ 功能測試："
echo "  - get_project_root: PASS"
echo "  - get_project_memory_dir: PASS"
echo "  - validate_memory_path: PASS"
echo "  - resolve_safe_path: PASS"
echo "  - 路徑穿越阻擋: PASS"
echo "  - 全域記憶管理: PASS (is_enabled, enable, disable)"
echo ""

echo "✅ TS-068 PASS: 記憶專案隔離函式庫功能正確"
exit 0
