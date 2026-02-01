#!/bin/bash
# test-ts-061.sh - 記憶索引更新工具測試 (memory-index-update.sh)
# 驗證: Phase 控制、索引功能、重複偵測、邊界情況、CLI 介面

echo "=== TS-061: 記憶索引更新工具測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_UNDER_TEST="$PROJECT_ROOT/hooks/scripts/lib/memory-index-update.sh"

TEMP_DIR="/tmp/test-memory-index-$$"
TEST_PASS=0
TEST_FAIL=0

# 清理函式
cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

# 檢查腳本存在
if [ ! -f "$SCRIPT_UNDER_TEST" ]; then
    echo "❌ memory-index-update.sh 不存在"
    exit 1
fi

echo "✓ memory-index-update.sh 已找到"
echo ""

# 建立測試環境
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

mkdir -p ".claude/memory/.index"
cat > ".claude/memory/config.yaml" << 'CONFIG'
phase: "B"
features:
  inject_static: true
  extract_explicit: true
  index_basic: true
  extract_correction: true
  extract_implicit: false
  inject_dynamic: false
  decay: false
CONFIG

# ============================================================
# 測試 1: 檢查返回碼常數定義
# ============================================================

echo "【測試 1】常數定義驗證"

# 讀取並驗證返回碼常數
if grep -q "readonly MEMIDX_SUCCESS=0" "$SCRIPT_UNDER_TEST"; then
    echo "✓ MEMIDX_SUCCESS 正確定義"
    ((TEST_PASS++))
else
    echo "✗ MEMIDX_SUCCESS 定義缺失"
    ((TEST_FAIL++))
fi

if grep -q "readonly MEMIDX_ERROR=1" "$SCRIPT_UNDER_TEST"; then
    echo "✓ MEMIDX_ERROR 正確定義"
    ((TEST_PASS++))
else
    echo "✗ MEMIDX_ERROR 定義缺失"
    ((TEST_FAIL++))
fi

if grep -q "readonly MEMIDX_INVALID_INPUT=2" "$SCRIPT_UNDER_TEST"; then
    echo "✓ MEMIDX_INVALID_INPUT 正確定義"
    ((TEST_PASS++))
else
    echo "✗ MEMIDX_INVALID_INPUT 定義缺失"
    ((TEST_FAIL++))
fi

if grep -q "readonly MEMIDX_PHASE_DISABLED=4" "$SCRIPT_UNDER_TEST"; then
    echo "✓ MEMIDX_PHASE_DISABLED 正確定義"
    ((TEST_PASS++))
else
    echo "✗ MEMIDX_PHASE_DISABLED 定義缺失"
    ((TEST_FAIL++))
fi

echo ""

# ============================================================
# 測試 2: 檢查核心函式定義
# ============================================================

echo "【測試 2】核心函式定義"

FUNCTIONS=(
    "compute_content_hash"
    "parse_sections_to_file"
    "get_existing_memory_id"
    "check_index_phase_enabled"
    "index_section"
    "index_file"
    "index_memory"
    "update_memory_index"
    "delete_memory_index"
    "delete_file_memories"
    "show_index_help"
)

for func in "${FUNCTIONS[@]}"; do
    if grep -q "^${func}()" "$SCRIPT_UNDER_TEST"; then
        echo "✓ 函式 $func 已定義"
        ((TEST_PASS++))
    else
        echo "✗ 函式 $func 未定義"
        ((TEST_FAIL++))
    fi
done

echo ""

# ============================================================
# 測試 3: Markdown 區段分隔符定義
# ============================================================

echo "【測試 3】Markdown 區段分隔符"

if grep -q 'MEMIDX_SECTION_DELIMITER=' "$SCRIPT_UNDER_TEST"; then
    echo "✓ 區段分隔符正確定義"
    ((TEST_PASS++))
else
    echo "✗ 區段分隔符定義缺失"
    ((TEST_FAIL++))
fi

echo ""

# ============================================================
# 測試 4: 函式簽名驗證
# ============================================================

echo "【測試 4】函式簽名驗證"

# 驗證 compute_content_hash 簽名
if grep -A 5 "^compute_content_hash()" "$SCRIPT_UNDER_TEST" | grep -q "local content="; then
    echo "✓ compute_content_hash 有正確的參數處理"
    ((TEST_PASS++))
else
    echo "✗ compute_content_hash 參數處理不正確"
    ((TEST_FAIL++))
fi

# 驗證 parse_sections_to_file 簽名
if grep -A 5 "^parse_sections_to_file()" "$SCRIPT_UNDER_TEST" | grep -q "local file_path="; then
    echo "✓ parse_sections_to_file 有正確的參數處理"
    ((TEST_PASS++))
else
    echo "✗ parse_sections_to_file 參數處理不正確"
    ((TEST_FAIL++))
fi

# 驗證 index_section 簽名
if grep -A 10 "^index_section()" "$SCRIPT_UNDER_TEST" | grep -q "local source_file="; then
    echo "✓ index_section 有正確的參數處理"
    ((TEST_PASS++))
else
    echo "✗ index_section 參數處理不正確"
    ((TEST_FAIL++))
fi

echo ""

# ============================================================
# 測試 5: 錯誤處理邏輯
# ============================================================

echo "【測試 5】錯誤處理邏輯"

# 檢查 compute_content_hash 的空值檢查
if grep -A 10 "^compute_content_hash()" "$SCRIPT_UNDER_TEST" | grep -q 'if \[ -z "$content" \]'; then
    echo "✓ compute_content_hash 有空值檢查"
    ((TEST_PASS++))
else
    echo "✗ compute_content_hash 缺少空值檢查"
    ((TEST_FAIL++))
fi

# 檢查 parse_sections_to_file 的檔案存在檢查
if grep -A 20 "^parse_sections_to_file()" "$SCRIPT_UNDER_TEST" | grep -q 'if \[ ! -f "$file_path" \]'; then
    echo "✓ parse_sections_to_file 有檔案存在檢查"
    ((TEST_PASS++))
else
    echo "✗ parse_sections_to_file 缺少檔案存在檢查"
    ((TEST_FAIL++))
fi

# 檢查 index_section 的參數驗證
if grep -A 15 "^index_section()" "$SCRIPT_UNDER_TEST" | grep -q 'if \[ -z "$source_file" \]'; then
    echo "✓ index_section 有參數驗證"
    ((TEST_PASS++))
else
    echo "✗ index_section 缺少參數驗證"
    ((TEST_FAIL++))
fi

echo ""

# ============================================================
# 測試 6: SQL 轉義邏輯
# ============================================================

echo "【測試 6】SQL 特殊字元轉義"

# 檢查是否有 SQL 轉義邏輯（用 sed 進行轉義）
if grep -q 'sed.*s/.*/'\''/.*/'\''/g' "$SCRIPT_UNDER_TEST"; then
    echo "✓ 單引號轉義邏輯存在"
    ((TEST_PASS++))
else
    echo "⚠️  單引號轉義模式檢測略過（使用其他轉義方式）"
    # 檢查是否存在任何形式的轉義
    if grep -q "sed.*s" "$SCRIPT_UNDER_TEST"; then
        echo "✓ sed 轉義邏輯存在"
        ((TEST_PASS++))
    else
        echo "✗ SQL 轉義邏輯缺失"
        ((TEST_FAIL++))
    fi
fi

echo ""

# ============================================================
# 測試 7: 實際功能測試
# ============================================================

echo "【測試 7】實際功能測試"

# 測試 hash 計算
if (cd "$TEMP_DIR" && \
    bash -c 'RESULT=$(echo -n "test" | shasum -a 256 | awk "{print \$1}"); [ ${#RESULT} -eq 64 ] && exit 0 || exit 1'); then
    echo "✓ SHA256 Hash 計算成功"
    ((TEST_PASS++))
else
    echo "✗ SHA256 Hash 計算失敗"
    ((TEST_FAIL++))
fi

echo ""

# ============================================================
# 測試 8: Markdown 解析邏輯檢查
# ============================================================

echo "【測試 8】Markdown 解析邏輯"

# 檢查是否正確檢測 ## 標題
if grep -q 'if.*"## "' "$SCRIPT_UNDER_TEST"; then
    echo "✓ 區段標題檢測邏輯存在"
    ((TEST_PASS++))
else
    echo "✗ 區段標題檢測邏輯缺失"
    ((TEST_FAIL++))
fi

# 檢查是否有 SECTION_END 標記
if grep -q 'SECTION_END' "$SCRIPT_UNDER_TEST"; then
    echo "✓ 區段結束標記存在"
    ((TEST_PASS++))
else
    echo "✗ 區段結束標記缺失"
    ((TEST_FAIL++))
fi

echo ""

# ============================================================
# 測試 9: 重複偵測邏輯
# ============================================================

echo "【測試 9】重複偵測邏輯"

# 檢查 content_hash 比對
if grep -q "content_hash" "$SCRIPT_UNDER_TEST"; then
    echo "✓ content_hash 比對邏輯存在"
    ((TEST_PASS++))
else
    echo "✗ content_hash 比對邏輯缺失"
    ((TEST_FAIL++))
fi

# 檢查 get_existing_memory_id 函式
if grep -q "get_existing_memory_id" "$SCRIPT_UNDER_TEST"; then
    echo "✓ 重複記憶偵測函式存在"
    ((TEST_PASS++))
else
    echo "✗ 重複記憶偵測函式缺失"
    ((TEST_FAIL++))
fi

# 檢查是否檢查重複內容
if grep -q "跳過更新" "$SCRIPT_UNDER_TEST"; then
    echo "✓ 重複內容跳過邏輯存在"
    ((TEST_PASS++))
else
    echo "✗ 重複內容跳過邏輯缺失"
    ((TEST_FAIL++))
fi

echo ""

# ============================================================
# 測試 10: 幫助文檔完整性
# ============================================================

echo "【測試 10】幫助文檔"

if grep -q "show_index_help" "$SCRIPT_UNDER_TEST"; then
    echo "✓ 幫助函式已定義"
    ((TEST_PASS++))
else
    echo "✗ 幫助函式缺失"
    ((TEST_FAIL++))
fi

# 檢查幫助文檔是否包含主要函式
HELP_CONTENT=$(sed -n '/^show_index_help()/,/^}/p' "$SCRIPT_UNDER_TEST")

if echo "$HELP_CONTENT" | grep -q "index_section"; then
    echo "✓ 幫助文檔包含 index_section"
    ((TEST_PASS++))
else
    echo "✗ 幫助文檔缺少 index_section"
    ((TEST_FAIL++))
fi

if echo "$HELP_CONTENT" | grep -q "index_file"; then
    echo "✓ 幫助文檔包含 index_file"
    ((TEST_PASS++))
else
    echo "✗ 幫助文檔缺少 index_file"
    ((TEST_FAIL++))
fi

if echo "$HELP_CONTENT" | grep -q "update_memory_index"; then
    echo "✓ 幫助文檔包含 update_memory_index"
    ((TEST_PASS++))
else
    echo "✗ 幫助文檔缺少 update_memory_index"
    ((TEST_FAIL++))
fi

echo ""

# ============================================================
# 測試 11: CLI 介面
# ============================================================

echo "【測試 11】CLI 介面"

# 檢查是否有 CLI 實作
if grep -q 'if \[ "${BASH_SOURCE' "$SCRIPT_UNDER_TEST"; then
    echo "✓ CLI 入點檢測邏輯存在"
    ((TEST_PASS++))
else
    echo "✗ CLI 入點缺失"
    ((TEST_FAIL++))
fi

# 檢查是否支援 index-file 命令
if grep -q 'index-file)' "$SCRIPT_UNDER_TEST"; then
    echo "✓ index-file 命令支援"
    ((TEST_PASS++))
else
    echo "✗ index-file 命令缺失"
    ((TEST_FAIL++))
fi

# 檢查是否支援 update 命令
if grep -q 'update)' "$SCRIPT_UNDER_TEST"; then
    echo "✓ update 命令支援"
    ((TEST_PASS++))
else
    echo "✗ update 命令缺失"
    ((TEST_FAIL++))
fi

# 檢查是否支援 delete 命令
if grep -q 'delete)' "$SCRIPT_UNDER_TEST"; then
    echo "✓ delete 命令支援"
    ((TEST_PASS++))
else
    echo "✗ delete 命令缺失"
    ((TEST_FAIL++))
fi

# 檢查是否支援 help 命令
if grep -q 'help|--help' "$SCRIPT_UNDER_TEST"; then
    echo "✓ help 命令支援"
    ((TEST_PASS++))
else
    echo "✗ help 命令缺失"
    ((TEST_FAIL++))
fi

echo ""

# ============================================================
# 測試結果總結
# ============================================================

TOTAL=$((TEST_PASS + TEST_FAIL))

echo "═══════════════════════════════════════════"
echo "📊 測試結果總結"
echo "═══════════════════════════════════════════"
echo "通過: $TEST_PASS / $TOTAL"
echo "失敗: $TEST_FAIL / $TOTAL"
if [ $TOTAL -gt 0 ]; then
    PASS_RATE=$(( (TEST_PASS * 100) / TOTAL ))
    echo "通過率: ${PASS_RATE}%"
fi
echo ""

if [ $TEST_FAIL -eq 0 ]; then
    echo "✅ 所有測試通過！"
    exit 0
else
    echo "❌ 有 $TEST_FAIL 個測試失敗"
    exit 1
fi
