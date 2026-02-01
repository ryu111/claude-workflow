#!/bin/bash
# drt-state-cleanup.sh - D→R→T 狀態檔案智能清理
# 功能:
#   1. 刪除 3 天過期的狀態檔案
#   2. 目錄超過 10MB 時按最舊優先刪除
#   3. 立即刪除已完成的狀態 (result: complete/pass)

set -euo pipefail

# 配置參數
STATE_DIR="${PWD}/.drt-state"
STATE_AUTO_DIR="${PWD}/drt-state-auto"
MAX_AGE_DAYS=3
MAX_DIR_SIZE_MB=10
TOTAL_CLEANED=0
TOTAL_SIZE_CLEANED=0

# 常數定義
readonly KB=1024
readonly MB=$((1024 * 1024))

# 顏色輸出
readonly COLOR_RESET='\033[0m'
readonly COLOR_BLUE='\033[34m'
readonly COLOR_GREEN='\033[32m'
readonly COLOR_YELLOW='\033[33m'

# 臨時檔案清理
TEMP_FILES=()
cleanup() {
    # 使用 ${array[@]+"${array[@]}"} 避免空數組在 set -u 下報錯
    for temp_file in ${TEMP_FILES[@]+"${TEMP_FILES[@]}"}; do
        [ -f "$temp_file" ] && rm -f "$temp_file" 2>/dev/null
    done
}
trap cleanup EXIT

log_info() {
    echo -e "${COLOR_BLUE}ℹ️  $1${COLOR_RESET}"
}

log_success() {
    echo -e "${COLOR_GREEN}✅ $1${COLOR_RESET}"
}

log_warning() {
    echo -e "${COLOR_YELLOW}⚠️  $1${COLOR_RESET}"
}

# 檢查目錄是否存在
if [ ! -d "$STATE_DIR" ] && [ ! -d "$STATE_AUTO_DIR" ]; then
    log_info "狀態目錄不存在: $STATE_DIR 和 $STATE_AUTO_DIR"
    exit 0
fi

# 跨平台兼容的檔案大小獲取
get_file_size() {
    local file="$1"
    if [ "$(uname)" = "Darwin" ]; then
        # macOS
        stat -f%z "$file" 2>/dev/null || echo "0"
    else
        # Linux
        stat -c%s "$file" 2>/dev/null || echo "0"
    fi
}

# 跨平台兼容的目錄大小計算（KB）
get_dir_size_kb() {
    local dir="$1"
    # du -sk 在 macOS 和 Linux 行為一致
    du -sk "$dir" 2>/dev/null | cut -f1 || echo "0"
}

# 跨平台兼容的人類可讀大小轉換
human_readable_size() {
    local bytes=$1
    if [ "$bytes" -lt "$KB" ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt "$MB" ]; then
        echo "$((bytes / KB))KB"
    else
        echo "$((bytes / MB))MB"
    fi
}

# 清理單一目錄的完成狀態檔案
clean_completed_in_dir() {
    local dir="$1"
    local temp_stats="${dir}/.cleanup_stats_completed"
    local count=0
    local size=0

    if [ ! -d "$dir" ]; then
        echo "0 0"
        return
    fi

    TEMP_FILES+=("$temp_stats")

    find "$dir" -name "*.json" -type f 2>/dev/null | while IFS= read -r file; do
        if [ -f "$file" ]; then
            # 檢查是否包含 "result":"complete" 或 "result":"pass"
            if grep -q '"result":"complete"' "$file" 2>/dev/null || \
               grep -q '"result":"pass"' "$file" 2>/dev/null; then
                file_size=$(get_file_size "$file")
                rm -f "$file" 2>/dev/null && {
                    count=$((count + 1))
                    size=$((size + file_size))
                    echo "$count $size" > "$temp_stats"
                }
            fi
        fi
    done

    # 讀取統計（由於管道問題，從臨時檔案讀取）
    if [ -f "$temp_stats" ]; then
        read -r count size < "$temp_stats"
    fi

    echo "$count $size"
}

# 1. 清理已完成的狀態檔案（立即刪除）
log_info "檢查已完成的狀態檔案..."

COMPLETED_COUNT=0
COMPLETED_SIZE=0

# 清理 .drt-state
if [ -d "$STATE_DIR" ]; then
    read -r count size < <(clean_completed_in_dir "$STATE_DIR")
    COMPLETED_COUNT=$((COMPLETED_COUNT + count))
    COMPLETED_SIZE=$((COMPLETED_SIZE + size))
fi

# 清理 drt-state-auto
if [ -d "$STATE_AUTO_DIR" ]; then
    read -r count size < <(clean_completed_in_dir "$STATE_AUTO_DIR")
    COMPLETED_COUNT=$((COMPLETED_COUNT + count))
    COMPLETED_SIZE=$((COMPLETED_SIZE + size))
fi

if [ "$COMPLETED_COUNT" -gt 0 ]; then
    log_success "清理已完成狀態: $COMPLETED_COUNT 個檔案 ($(human_readable_size $COMPLETED_SIZE))"
    TOTAL_CLEANED=$((TOTAL_CLEANED + COMPLETED_COUNT))
    TOTAL_SIZE_CLEANED=$((TOTAL_SIZE_CLEANED + COMPLETED_SIZE))
fi

# 清理單一目錄的過期檔案
clean_expired_in_dir() {
    local dir="$1"
    local temp_stats="${dir}/.cleanup_stats_expired"
    local count=0
    local size=0

    if [ ! -d "$dir" ]; then
        echo "0 0"
        return
    fi

    TEMP_FILES+=("$temp_stats")

    # 跨平台兼容的 find -mtime
    find "$dir" -name "*.json" -type f -mtime "+${MAX_AGE_DAYS}" 2>/dev/null | while IFS= read -r file; do
        if [ -f "$file" ]; then
            file_size=$(get_file_size "$file")
            rm -f "$file" 2>/dev/null && {
                count=$((count + 1))
                size=$((size + file_size))
                echo "$count $size" > "$temp_stats"
            }
        fi
    done

    # 讀取統計
    if [ -f "$temp_stats" ]; then
        read -r count size < "$temp_stats"
    fi

    echo "$count $size"
}

# 2. 清理超過 3 天的狀態檔案
log_info "檢查超過 ${MAX_AGE_DAYS} 天的狀態檔案..."

EXPIRED_COUNT=0
EXPIRED_SIZE=0

# 清理 .drt-state
if [ -d "$STATE_DIR" ]; then
    read -r count size < <(clean_expired_in_dir "$STATE_DIR")
    EXPIRED_COUNT=$((EXPIRED_COUNT + count))
    EXPIRED_SIZE=$((EXPIRED_SIZE + size))
fi

# 清理 drt-state-auto
if [ -d "$STATE_AUTO_DIR" ]; then
    read -r count size < <(clean_expired_in_dir "$STATE_AUTO_DIR")
    EXPIRED_COUNT=$((EXPIRED_COUNT + count))
    EXPIRED_SIZE=$((EXPIRED_SIZE + size))
fi

if [ "$EXPIRED_COUNT" -gt 0 ]; then
    log_success "清理過期狀態: $EXPIRED_COUNT 個檔案 ($(human_readable_size $EXPIRED_SIZE))"
    TOTAL_CLEANED=$((TOTAL_CLEANED + EXPIRED_COUNT))
    TOTAL_SIZE_CLEANED=$((TOTAL_SIZE_CLEANED + EXPIRED_SIZE))
fi

# 清理單一目錄的過大檔案（僅執行清理，不輸出日誌）
clean_oversized_in_dir() {
    local dir="$1"
    local temp_stats="${dir}/.cleanup_stats_size"
    local count=0
    local size=0

    if [ ! -d "$dir" ]; then
        echo "0 0 0 0"  # count size dir_size_kb max_size_kb
        return
    fi

    TEMP_FILES+=("$temp_stats")

    local dir_size_kb=$(get_dir_size_kb "$dir")
    local max_size_kb=$((MAX_DIR_SIZE_MB * KB))

    # 只有超過限制才清理
    if [ "$dir_size_kb" -gt "$max_size_kb" ]; then
        # 按修改時間排序（最舊在前），逐個刪除直到目錄大小降到限制以下
        find "$dir" -name "*.json" -type f -print0 2>/dev/null | \
            xargs -0 ls -t -r 2>/dev/null | \
            while IFS= read -r file; do
                # 重新計算目錄大小
                current_size_kb=$(get_dir_size_kb "$dir")

                if [ "$current_size_kb" -le "$max_size_kb" ]; then
                    # 已降到限制以下，停止刪除
                    break
                fi

                if [ -f "$file" ]; then
                    file_size=$(get_file_size "$file")
                    rm -f "$file" 2>/dev/null && {
                        count=$((count + 1))
                        size=$((size + file_size))
                        echo "$count $size" > "$temp_stats"
                    }
                fi
            done

        # 讀取統計
        if [ -f "$temp_stats" ]; then
            read -r count size < "$temp_stats"
        fi
    fi

    # 輸出格式: count size dir_size_kb max_size_kb
    echo "$count $size $dir_size_kb $max_size_kb"
}

# 3. 檢查目錄大小，超過 10MB 則按最舊優先刪除
log_info "檢查目錄大小限制..."

SIZE_REDUCED_COUNT=0
SIZE_REDUCED_SIZE=0

# 檢查 .drt-state
if [ -d "$STATE_DIR" ]; then
    read -r count size dir_size_kb max_size_kb < <(clean_oversized_in_dir "$STATE_DIR")
    dir_name=$(basename "$STATE_DIR")
    dir_size_mb=$((dir_size_kb / KB))
    max_size_mb=$((max_size_kb / KB))

    if [ "$dir_size_kb" -gt "$max_size_kb" ]; then
        log_warning "[$dir_name] 目錄大小超過限制: ${dir_size_mb}MB > ${max_size_mb}MB"
        if [ "$count" -gt 0 ]; then
            final_size_kb=$(get_dir_size_kb "$STATE_DIR")
            final_size_mb=$((final_size_kb / KB))
            log_success "[$dir_name] 縮減目錄大小: 刪除 $count 個檔案 ($(human_readable_size $size))"
            log_info "[$dir_name] 目錄大小: ${dir_size_mb}MB → ${final_size_mb}MB"
        fi
    else
        log_success "[$dir_name] 目錄大小正常: ${dir_size_mb}MB / ${max_size_mb}MB"
    fi

    SIZE_REDUCED_COUNT=$((SIZE_REDUCED_COUNT + count))
    SIZE_REDUCED_SIZE=$((SIZE_REDUCED_SIZE + size))
fi

# 檢查 drt-state-auto
if [ -d "$STATE_AUTO_DIR" ]; then
    read -r count size dir_size_kb max_size_kb < <(clean_oversized_in_dir "$STATE_AUTO_DIR")
    dir_name=$(basename "$STATE_AUTO_DIR")
    dir_size_mb=$((dir_size_kb / KB))
    max_size_mb=$((max_size_kb / KB))

    if [ "$dir_size_kb" -gt "$max_size_kb" ]; then
        log_warning "[$dir_name] 目錄大小超過限制: ${dir_size_mb}MB > ${max_size_mb}MB"
        if [ "$count" -gt 0 ]; then
            final_size_kb=$(get_dir_size_kb "$STATE_AUTO_DIR")
            final_size_mb=$((final_size_kb / KB))
            log_success "[$dir_name] 縮減目錄大小: 刪除 $count 個檔案 ($(human_readable_size $size))"
            log_info "[$dir_name] 目錄大小: ${dir_size_mb}MB → ${final_size_mb}MB"
        fi
    else
        log_success "[$dir_name] 目錄大小正常: ${dir_size_mb}MB / ${max_size_mb}MB"
    fi

    SIZE_REDUCED_COUNT=$((SIZE_REDUCED_COUNT + count))
    SIZE_REDUCED_SIZE=$((SIZE_REDUCED_SIZE + size))
fi

if [ "$SIZE_REDUCED_COUNT" -gt 0 ]; then
    TOTAL_CLEANED=$((TOTAL_CLEANED + SIZE_REDUCED_COUNT))
    TOTAL_SIZE_CLEANED=$((TOTAL_SIZE_CLEANED + SIZE_REDUCED_SIZE))
fi

# 4. 輸出總結
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    🧹 清理完成                                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"

if [ "$TOTAL_CLEANED" -gt 0 ]; then
    echo ""
    log_success "總共刪除: $TOTAL_CLEANED 個檔案"
    log_success "釋放空間: $(human_readable_size $TOTAL_SIZE_CLEANED)"
else
    echo ""
    log_info "無需清理，狀態目錄健康"
fi

# 顯示剩餘檔案統計
REMAINING_COUNT=0
REMAINING_SIZE_KB=0
STATE_COUNT=0
STATE_SIZE_KB=0
AUTO_COUNT=0
AUTO_SIZE_KB=0

if [ -d "$STATE_DIR" ]; then
    STATE_COUNT=$(find "$STATE_DIR" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    STATE_SIZE_KB=$(get_dir_size_kb "$STATE_DIR")
    REMAINING_COUNT=$((REMAINING_COUNT + STATE_COUNT))
    REMAINING_SIZE_KB=$((REMAINING_SIZE_KB + STATE_SIZE_KB))
fi

if [ -d "$STATE_AUTO_DIR" ]; then
    AUTO_COUNT=$(find "$STATE_AUTO_DIR" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    AUTO_SIZE_KB=$(get_dir_size_kb "$STATE_AUTO_DIR")
    REMAINING_COUNT=$((REMAINING_COUNT + AUTO_COUNT))
    REMAINING_SIZE_KB=$((REMAINING_SIZE_KB + AUTO_SIZE_KB))
fi

REMAINING_SIZE_MB=$((REMAINING_SIZE_KB / KB))

echo ""
echo "📊 目前狀態:"
echo "   • 剩餘檔案: $REMAINING_COUNT 個"
echo "   • 目錄大小: ${REMAINING_SIZE_MB}MB"
if [ -d "$STATE_DIR" ] && [ -d "$STATE_AUTO_DIR" ]; then
    STATE_SIZE_MB=$((STATE_SIZE_KB / KB))
    AUTO_SIZE_MB=$((AUTO_SIZE_KB / KB))
    echo "     - .drt-state: $STATE_COUNT 個 (${STATE_SIZE_MB}MB)"
    echo "     - drt-state-auto: $AUTO_COUNT 個 (${AUTO_SIZE_MB}MB)"
fi
echo ""

exit 0
