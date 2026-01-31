#!/bin/bash
# validate-utils.sh - 共用驗證工具函式庫
# 用途：提供驗證腳本共用的輔助函式

# ========================================
# 顏色定義
# ========================================
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# ========================================
# 輸出格式化函式
# ========================================

# 顯示標題框
# 參數: $1 - 標題文字
print_header() {
    local title="$1"
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    printf "║  %-60s  ║\n" "$title"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

# 顯示分區標題
# 參數: $1 - 分區文字
print_section() {
    local section="$1"
    echo ""
    echo "### $section"
}

# 輸出成功訊息（綠色勾）
# 參數: $1 - 訊息內容
log_pass() {
    local msg="$1"
    echo -e "   ${GREEN}✓${NC} $msg"
}

# 輸出失敗訊息（紅色叉）
# 參數: $1 - 訊息內容
log_fail() {
    local msg="$1"
    echo -e "   ${RED}✗${NC} $msg"
}

# 輸出警告訊息（黃色警告）
# 參數: $1 - 訊息內容
log_warn() {
    local msg="$1"
    echo -e "   ${YELLOW}⚠${NC} $msg"
}

# 輸出資訊訊息（藍色箭頭）
# 參數: $1 - 訊息內容
log_info() {
    local msg="$1"
    echo -e "   ${BLUE}▸${NC} $msg"
}

# ========================================
# 摘要輸出函式
# ========================================

# 顯示驗證摘要
# 參數:
#   $1 - 總數
#   $2 - 通過數
#   $3 - 失敗數
#   $4 - 項目名稱（如 "Skills", "Agents"）
print_summary() {
    local total="$1"
    local passed="$2"
    local failed="$3"
    local item_name="$4"

    print_section "總結"
    echo "- ${item_name} 總數：$total"
    echo "- 驗證通過：$passed"
    echo "- 驗證失敗：$failed"
}

# 顯示最終狀態
# 參數:
#   $1 - 失敗數量
#   $2 - （可選）額外錯誤訊息
print_final_status() {
    local failed="$1"
    local extra_msg="${2:-}"

    echo ""
    if [ "$failed" -gt 0 ] || [ -n "$extra_msg" ]; then
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo -e "║              ${YELLOW}⚠️  發現問題，請檢查上方詳情${NC}                  ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        return 1
    else
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo -e "║              ${GREEN}✅ 所有驗證通過${NC}                               ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        return 0
    fi
}

# ========================================
# 檔案檢查函式
# ========================================

# 檢查檔案是否存在
# 參數: $1 - 檔案路徑
# 回傳: 0 存在, 1 不存在
check_file_exists() {
    local file_path="$1"
    [ -f "$file_path" ]
}

# 檢查目錄是否存在
# 參數: $1 - 目錄路徑
# 回傳: 0 存在, 1 不存在
check_dir_exists() {
    local dir_path="$1"
    [ -d "$dir_path" ]
}

# 檢查檔案是否可執行
# 參數: $1 - 檔案路徑
# 回傳: 0 可執行, 1 不可執行
check_file_executable() {
    local file_path="$1"
    [ -x "$file_path" ]
}

# ========================================
# YAML Frontmatter 檢查函式
# ========================================

# 檢查檔案是否有 YAML frontmatter
# 參數: $1 - 檔案路徑
# 回傳: 0 有, 1 沒有
check_frontmatter() {
    local file_path="$1"

    if ! check_file_exists "$file_path"; then
        return 1
    fi

    # 檢查第一行是否為 ---
    head -1 "$file_path" | grep -q "^---$"
}

# 檢查 frontmatter 是否包含指定欄位
# 參數:
#   $1 - 檔案路徑
#   $2 - 欄位名稱（如 "name", "description"）
# 回傳: 0 包含, 1 不包含
check_frontmatter_field() {
    local file_path="$1"
    local field_name="$2"

    if ! check_file_exists "$file_path"; then
        return 1
    fi

    grep -q "^${field_name}:" "$file_path"
}

# 提取 frontmatter 區塊
# 參數: $1 - 檔案路徑
# 輸出: frontmatter 內容
extract_frontmatter() {
    local file_path="$1"

    if ! check_file_exists "$file_path"; then
        return 1
    fi

    # 從第一個 --- 到第二個 ---（macOS 相容）
    awk '/^---$/{if(++c==2)exit}c==1' "$file_path"
}

# ========================================
# Markdown 連結檢查函式
# ========================================

# 提取檔案中的所有 markdown 連結
# 參數: $1 - 檔案路徑
# 輸出: 連結清單（每行一個）
extract_markdown_links() {
    local file_path="$1"

    if ! check_file_exists "$file_path"; then
        return 1
    fi

    grep -oE '\]\([a-zA-Z0-9_/.~-]+\)' "$file_path" 2>/dev/null | sed 's/](\(.*\))/\1/' || true
}

# 檢查 markdown 連結是否為外部連結
# 參數: $1 - 連結 URL
# 回傳: 0 是外部, 1 是內部
is_external_link() {
    local link="$1"
    [[ "$link" == http* ]] || [[ "$link" == "#"* ]]
}

# ========================================
# 表格輸出輔助
# ========================================

# 建立 markdown 表格分隔線
# 參數: $1 - 欄位數量
print_table_separator() {
    local cols="$1"
    local sep="|"
    for ((i=0; i<cols; i++)); do
        sep="$sep-------|"
    done
    echo "$sep"
}

# ========================================
# 路徑處理
# ========================================

# 取得腳本所在目錄的絕對路徑
# 回傳: 絕對路徑
get_script_dir() {
    cd "$(dirname "${BASH_SOURCE[1]}")" && pwd
}

# 取得 plugin 根目錄
# 回傳: plugin 根目錄絕對路徑
get_plugin_dir() {
    local script_dir="$(get_script_dir)"
    dirname "$script_dir"
}
