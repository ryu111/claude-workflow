#!/bin/bash
# loop-precheck.sh - Loop 啟動前狀態預檢
# 功能:
#   1. 掃描 .drt-state/ 和 drt-state-auto/ 目錄中的狀態檔案
#   2. 從狀態檔案提取 change_id（JSON 內容或檔名）
#   3. 偵測孤兒狀態檔案：
#      - 無對應 OpenSpec（openspec/changes/{change_id}/tasks.md 不存在）
#      - OpenSpec 已完成（Status: COMPLETED）
#   4. 顯示掃描結果和清理建議
#   5. 支援 --auto-clean 參數自動清理孤兒檔案

set -euo pipefail

# ========================================
# 配置參數
# ========================================
STATE_DIR="${PWD}/.drt-state"
STATE_AUTO_DIR="${PWD}/drt-state-auto"
OPENSPEC_CHANGES_DIR="${PWD}/openspec/changes"
OPENSPEC_ARCHIVE_DIR="${PWD}/openspec/archive"

# ========================================
# 顏色定義
# ========================================
readonly COLOR_RESET='\033[0m'
readonly COLOR_BLUE='\033[34m'
readonly COLOR_GREEN='\033[32m'
readonly COLOR_YELLOW='\033[33m'
readonly COLOR_RED='\033[0;31m'

# ========================================
# 日誌函數
# ========================================

log_info() {
    echo -e "${COLOR_BLUE}ℹ️  $1${COLOR_RESET}"
}

log_success() {
    echo -e "${COLOR_GREEN}✅ $1${COLOR_RESET}"
}

log_warning() {
    echo -e "${COLOR_YELLOW}⚠️  $1${COLOR_RESET}"
}

# ========================================
# 提取 change_id 從狀態檔案
# ========================================

# 從 JSON 檔案內容提取 change_id
# 參數: $1 - JSON 檔案路徑
# 輸出: change_id 或空字串
extract_change_id_from_json() {
    local file="$1"

    if [ ! -f "$file" ]; then
        echo ""
        return
    fi

    # 嘗試從 JSON 提取 change_id 欄位（支援冒號後有或無空格）
    local change_id=""
    change_id=$(grep -oE '"change_id"\s*:\s*"[^"]+' "$file" 2>/dev/null | head -1 | sed 's/"change_id"\s*:\s*"//' || echo "")

    # 如果 JSON 中沒有，嘗試從檔名提取（格式: xxx.json）
    if [ -z "$change_id" ]; then
        change_id=$(basename "$file" .json)
    fi

    echo "$change_id"
}

# ========================================
# 檢查 OpenSpec 狀態
# ========================================

# 檢查 OpenSpec 狀態
# 參數: $1 - change_id
# 輸出: "active" | "completed" | "archived" | "no_openspec"
check_openspec_status() {
    local change_id="$1"
    local tasks_file_changes="${OPENSPEC_CHANGES_DIR}/${change_id}/tasks.md"
    local tasks_file_archive="${OPENSPEC_ARCHIVE_DIR}/${change_id}/tasks.md"

    # 檢查 archive 目錄
    if [ -f "$tasks_file_archive" ]; then
        echo "archived"
        return 0
    fi

    # 檢查 changes 目錄
    if [ ! -f "$tasks_file_changes" ]; then
        echo "no_openspec"
        return 0
    fi

    # 檢查 Status 欄位
    if grep -q "^- Status: COMPLETED" "$tasks_file_changes" 2>/dev/null; then
        echo "completed"
    else
        echo "active"
    fi
}

# ========================================
# 掃描狀態檔案
# ========================================

# 掃描單一目錄
# 參數:
#   $1 - 目錄路徑
#   $2 - 目錄顯示名稱
# 輸出: 全域陣列 ORPHAN_FILES 和 VALID_FILES
scan_state_dir() {
    local dir="$1"
    local dir_name="$2"

    if [ ! -d "$dir" ]; then
        return
    fi

    log_info "掃描 ${dir_name}..."

    # 查找所有 JSON 檔案
    find "$dir" -name "*.json" -type f 2>/dev/null | while IFS= read -r file; do
        local change_id=$(extract_change_id_from_json "$file")

        if [ -z "$change_id" ]; then
            log_warning "無法提取 change_id: $file"
            continue
        fi

        # 檢查 OpenSpec 狀態
        local status=$(check_openspec_status "$change_id")
        local is_orphan=false
        local reason=""

        case "$status" in
            "no_openspec")
                is_orphan=true
                reason="無對應 OpenSpec"
                ;;
            "completed")
                is_orphan=true
                reason="OpenSpec 已完成"
                ;;
            "archived")
                is_orphan=true
                reason="OpenSpec 已歸檔"
                ;;
            "active")
                is_orphan=false
                ;;
        esac

        # 記錄結果
        if [ "$is_orphan" = true ]; then
            log_warning "孤兒: $(basename "$file") ($reason: $change_id)"
            echo "$file" >> "${TEMP_DIR}/orphan_files.txt"
        else
            log_success "有效: $(basename "$file") ($change_id)"
            echo "$file" >> "${TEMP_DIR}/valid_files.txt"
        fi
    done
}

# ========================================
# 清理孤兒檔案
# ========================================

# 清理孤兒檔案
# 參數: 無（從 TEMP_DIR/orphan_files.txt 讀取）
clean_orphan_files() {
    local orphan_file="${TEMP_DIR}/orphan_files.txt"

    if [ ! -f "$orphan_file" ]; then
        log_info "無孤兒檔案需要清理"
        return
    fi

    local count=0

    while IFS= read -r file; do
        if [ -f "$file" ]; then
            rm -f "$file" 2>/dev/null && {
                count=$((count + 1))
                log_success "已刪除: $(basename "$file")"
            }
        fi
    done < "$orphan_file"

    if [ "$count" -gt 0 ]; then
        log_success "總共刪除 $count 個孤兒檔案"
    fi
}

# ========================================
# 主流程
# ========================================

# 臨時目錄
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

# 初始化臨時檔案
touch "${TEMP_DIR}/orphan_files.txt"
touch "${TEMP_DIR}/valid_files.txt"

# 顯示標題
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    🔍 Loop 預檢                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 檢查參數
AUTO_CLEAN=false
if [ "${1:-}" = "--auto-clean" ]; then
    AUTO_CLEAN=true
fi

# 掃描狀態目錄
scan_state_dir "$STATE_DIR" ".drt-state"
scan_state_dir "$STATE_AUTO_DIR" "drt-state-auto"

# 統計結果
ORPHAN_COUNT=$(wc -l < "${TEMP_DIR}/orphan_files.txt" | tr -d ' ')
VALID_COUNT=$(wc -l < "${TEMP_DIR}/valid_files.txt" | tr -d ' ')
TOTAL_COUNT=$((ORPHAN_COUNT + VALID_COUNT))

# 顯示分隔線
echo ""
echo "────────────────────────────────────────────────────────────────"

# 顯示摘要
echo "📊 掃描結果: 總計 ${TOTAL_COUNT} 個狀態檔案, 孤兒 ${ORPHAN_COUNT} 個"
echo ""

# 處理清理
if [ "$ORPHAN_COUNT" -gt 0 ]; then
    if [ "$AUTO_CLEAN" = true ]; then
        echo "🧹 自動清理模式..."
        echo ""
        clean_orphan_files
    else
        echo "🧹 清理建議:"
        echo "   bash hooks/scripts/loop-precheck.sh --auto-clean"
        echo ""
        echo "   或使用狀態清理腳本:"
        echo "   bash hooks/scripts/drt-state-cleanup.sh"
    fi
else
    log_success "無孤兒檔案，狀態健康"
fi

echo ""

exit 0
