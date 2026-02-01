#!/bin/bash
# memory-capacity-check.sh - 記憶容量限制檢查與清理
# 功能：
#   1. 檢查 .claude/memory/ 目錄的總大小
#   2. 取得容量限制（從 config.yaml 讀取，預設 10MB）
#   3. 超過限制時觸發清理（優先清理 .audit、sessions、daily）
#   4. 保留 MEMORY.md 和 experiences/（重要記憶）

set -euo pipefail

# 載入共用工具函式
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/../core/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 記憶目錄
readonly MEMORY_DIR="${PWD}/.claude/memory"
readonly CONFIG_FILE="${MEMORY_DIR}/config.yaml"

# 預設限制
readonly CAPACITY_DEFAULT_LIMIT_MB=10
readonly CAPACITY_DEFAULT_LIMIT_BYTES=$((10 * 1024 * 1024))

# 清理優先級（越低越先清理）
readonly CAPACITY_CLEANUP_PRIORITY_AUDIT=1
readonly CAPACITY_CLEANUP_PRIORITY_SESSIONS=2
readonly CAPACITY_CLEANUP_PRIORITY_DAILY=3

# 返回碼
readonly CAPACITY_OK=0
readonly CAPACITY_EXCEEDED=1
readonly CAPACITY_CHECK_FAILED=2

# 單位換算
readonly CAPACITY_KB=1024
readonly CAPACITY_MB=$((1024 * 1024))

# 保留的重要檔案/目錄（不可刪除）
readonly CAPACITY_PROTECTED_PATTERNS=(
    "MEMORY.md"
    "experiences/"
    "config.yaml"
    ".health"
    ".gitkeep"
)

# ═══════════════════════════════════════════════════════════════
# 工具函式
# ═══════════════════════════════════════════════════════════════

# 取得記憶目錄的總大小（bytes）
# 用法: size=$(get_memory_size)
# 輸出: 目錄大小（bytes）
# 返回: 0=成功，2=失敗
get_memory_size() {
    if [ ! -d "$MEMORY_DIR" ]; then
        printf "錯誤：記憶目錄不存在: %s\n" "$MEMORY_DIR" >&2
        return $CAPACITY_CHECK_FAILED
    fi

    local size_bytes

    # 根據系統類型使用不同命令
    if [ "$(uname)" = "Darwin" ]; then
        # macOS: du -sk 返回 KB，需要乘以 1024
        local size_kb
        size_kb=$(du -sk "$MEMORY_DIR" 2>/dev/null | cut -f1 || printf "0")
        size_bytes=$((size_kb * 1024))
    else
        # Linux: du -sb 直接返回 bytes
        size_bytes=$(du -sb "$MEMORY_DIR" 2>/dev/null | cut -f1 || printf "0")
    fi

    printf "%s\n" "$size_bytes"
    return $CAPACITY_OK
}

# 取得容量限制（bytes）
# 用法: limit=$(get_capacity_limit)
# 輸出: 容量限制（bytes）
# 返回: 0=成功
get_capacity_limit() {
    # 如果 config.yaml 存在，嘗試讀取 memory.capacity_limit_mb
    if [ -f "$CONFIG_FILE" ]; then
        local limit_mb
        # 使用 grep + sed 解析 YAML（避免依賴 yq）
        # 搜尋 capacity_limit_mb: 10 這樣的行
        limit_mb=$(grep -E '^\s*capacity_limit_mb:\s*[0-9]+' "$CONFIG_FILE" 2>/dev/null | sed -E 's/^[^:]*:[[:space:]]*([0-9]+).*/\1/' || printf "")

        # 去除可能的空格
        limit_mb=$(printf "%s" "$limit_mb" | tr -d ' ')

        # 驗證 limit_mb 是否為有效數字
        if [ -n "$limit_mb" ] && [ "$limit_mb" -eq "$limit_mb" ] 2>/dev/null && [ "$limit_mb" -gt 0 ]; then
            printf "%s\n" $((limit_mb * CAPACITY_MB))
            return $CAPACITY_OK
        fi
    fi

    # 使用預設值
    printf "%s\n" "$CAPACITY_DEFAULT_LIMIT_BYTES"
    return $CAPACITY_OK
}

# 計算使用率百分比
# 用法: percentage=$(calculate_usage_percentage current_size limit_size)
# 輸出: 使用率百分比（整數）
calculate_usage_percentage() {
    local current_size="${1:-0}"
    local limit_size="${2:-1}"

    if [ "$limit_size" -eq 0 ]; then
        printf "0\n"
        return $CAPACITY_OK
    fi

    # 避免浮點運算，使用整數運算
    local percentage=$((current_size * 100 / limit_size))
    printf "%s\n" "$percentage"
    return $CAPACITY_OK
}

# 人類可讀的大小格式化
# 用法: readable=$(format_size_human 1048576)
# 輸出: "1.0MB"
format_size_human() {
    local bytes="${1:-0}"

    if [ "$bytes" -lt "$CAPACITY_KB" ]; then
        printf "%dB\n" "$bytes"
    elif [ "$bytes" -lt "$CAPACITY_MB" ]; then
        local kb=$((bytes / CAPACITY_KB))
        printf "%dKB\n" "$kb"
    else
        # 使用整數運算模擬小數點一位
        local mb_int=$((bytes / CAPACITY_MB))
        local mb_frac=$(((bytes % CAPACITY_MB) * 10 / CAPACITY_MB))
        printf "%d.%dMB\n" "$mb_int" "$mb_frac"
    fi
}

# 取得目錄下最舊的 N 個檔案（按修改時間）
# 用法: get_oldest_files <directory> <count>
# 輸出: 檔案路徑列表（每行一個）
get_oldest_files() {
    local directory="${1:-}"
    local count="${2:-10}"

    if [ -z "$directory" ]; then
        printf "錯誤：get_oldest_files 需要提供目錄路徑\n" >&2
        return $CAPACITY_CHECK_FAILED
    fi

    if [ ! -d "$directory" ]; then
        return $CAPACITY_OK
    fi

    # 使用 find + ls -t 取得最舊的檔案
    # -type f: 只找檔案
    # -print0: 處理檔名中的空格
    # xargs -0 ls -t -r: 按修改時間排序（最舊在前）
    # head -n: 取前 N 個
    find "$directory" -type f -print0 2>/dev/null | \
        xargs -0 ls -t -r 2>/dev/null | \
        head -n "$count"
}

# 檢查檔案是否受保護（不可刪除）
# 用法: is_file_protected <file_path>
# 返回: 0=受保護，1=不受保護
is_file_protected() {
    local file_path="${1:-}"

    if [ -z "$file_path" ]; then
        return 1
    fi

    # 取得相對於 MEMORY_DIR 的路徑
    local relative_path="${file_path#$MEMORY_DIR/}"

    # 檢查是否匹配保護模式
    local pattern
    for pattern in "${CAPACITY_PROTECTED_PATTERNS[@]}"; do
        case "$relative_path" in
            $pattern*)
                return 0  # 受保護
                ;;
        esac
    done

    return 1  # 不受保護
}

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 檢查記憶容量是否超過限制
# 用法: check_memory_capacity
# 輸出: 當前大小（bytes）
# 返回: 0=在限制內，1=超過限制，2=檢查失敗
check_memory_capacity() {
    local current_size
    current_size=$(get_memory_size) || return $CAPACITY_CHECK_FAILED

    local limit_size
    limit_size=$(get_capacity_limit)

    # 輸出當前大小到 stdout（供呼叫者使用）
    printf "%s\n" "$current_size"

    # 比較大小
    if [ "$current_size" -gt "$limit_size" ]; then
        return $CAPACITY_EXCEEDED
    else
        return $CAPACITY_OK
    fi
}

# 清理指定目錄下的舊檔案（避免刪除受保護檔案）
# 用法: cleanup_directory <directory> <target_size_to_free>
# 輸出: 已釋放的空間（bytes）
# 返回: 0=成功
cleanup_directory() {
    local directory="${1:-}"
    local target_size="${2:-0}"

    if [ -z "$directory" ] || [ ! -d "$directory" ]; then
        printf "0\n"
        return $CAPACITY_OK
    fi

    local freed_size=0
    local files_deleted=0

    # 取得最舊的檔案（取 100 個，足夠清理）
    local old_files
    old_files=$(get_oldest_files "$directory" 100)

    if [ -z "$old_files" ]; then
        printf "0\n"
        return $CAPACITY_OK
    fi

    # 逐個刪除檔案，直到達到目標釋放空間
    while IFS= read -r file; do
        # 檢查是否受保護
        if is_file_protected "$file"; then
            continue
        fi

        # 取得檔案大小
        local file_size
        if [ "$(uname)" = "Darwin" ]; then
            file_size=$(stat -f%z "$file" 2>/dev/null || printf "0")
        else
            file_size=$(stat -c%s "$file" 2>/dev/null || printf "0")
        fi

        # 刪除檔案
        if rm -f "$file" 2>/dev/null; then
            freed_size=$((freed_size + file_size))
            files_deleted=$((files_deleted + 1))

            # 如果已達到目標，停止刪除
            if [ "$freed_size" -ge "$target_size" ]; then
                break
            fi
        fi
    done <<< "$old_files"

    # 輸出統計到 stderr（供日誌記錄）
    if [ "$files_deleted" -gt 0 ]; then
        printf "  刪除 %d 個檔案，釋放 %s\n" "$files_deleted" "$(format_size_human $freed_size)" >&2
    fi

    # 輸出已釋放空間到 stdout
    printf "%s\n" "$freed_size"
    return $CAPACITY_OK
}

# 觸發清理（如果超過限制）
# 用法: trigger_cleanup_if_needed
# 返回: 0=成功（可能執行或跳過清理），1=清理失敗
trigger_cleanup_if_needed() {
    local current_size
    current_size=$(check_memory_capacity)
    local check_result=$?

    if [ "$check_result" -eq "$CAPACITY_CHECK_FAILED" ]; then
        printf "錯誤：無法檢查記憶容量\n" >&2
        return $CAPACITY_CHECK_FAILED
    fi

    if [ "$check_result" -eq "$CAPACITY_OK" ]; then
        # 未超過限制，無需清理
        return $CAPACITY_OK
    fi

    # 超過限制，開始清理
    local limit_size
    limit_size=$(get_capacity_limit)

    local exceed_size=$((current_size - limit_size))

    printf "⚠️  記憶容量超過限制: %s / %s (超過 %s)\n" \
        "$(format_size_human $current_size)" \
        "$(format_size_human $limit_size)" \
        "$(format_size_human $exceed_size)" >&2

    printf "🧹 開始清理...\n" >&2

    local total_freed=0
    local freed

    # 優先級 1: 清理 .audit/ 下的舊日誌
    if [ -d "${MEMORY_DIR}/.audit" ]; then
        printf "  清理 .audit/ ...\n" >&2
        freed=$(cleanup_directory "${MEMORY_DIR}/.audit" "$exceed_size")
        total_freed=$((total_freed + freed))
    fi

    # 檢查是否已達到目標
    if [ "$total_freed" -ge "$exceed_size" ]; then
        printf "✅ 清理完成，已釋放 %s\n" "$(format_size_human $total_freed)" >&2
        return $CAPACITY_OK
    fi

    # 優先級 2: 清理 sessions/ 下的舊記錄
    if [ -d "${MEMORY_DIR}/sessions" ]; then
        printf "  清理 sessions/ ...\n" >&2
        local remaining=$((exceed_size - total_freed))
        freed=$(cleanup_directory "${MEMORY_DIR}/sessions" "$remaining")
        total_freed=$((total_freed + freed))
    fi

    # 檢查是否已達到目標
    if [ "$total_freed" -ge "$exceed_size" ]; then
        printf "✅ 清理完成，已釋放 %s\n" "$(format_size_human $total_freed)" >&2
        return $CAPACITY_OK
    fi

    # 優先級 3: 清理 daily/ 下的舊記錄
    if [ -d "${MEMORY_DIR}/daily" ]; then
        printf "  清理 daily/ ...\n" >&2
        local remaining=$((exceed_size - total_freed))
        freed=$(cleanup_directory "${MEMORY_DIR}/daily" "$remaining")
        total_freed=$((total_freed + freed))
    fi

    # 最終結果
    if [ "$total_freed" -ge "$exceed_size" ]; then
        printf "✅ 清理完成，已釋放 %s\n" "$(format_size_human $total_freed)" >&2
        return $CAPACITY_OK
    else
        printf "⚠️  清理不足，僅釋放 %s / %s\n" \
            "$(format_size_human $total_freed)" \
            "$(format_size_human $exceed_size)" >&2
        printf "提示：請手動清理或增加容量限制\n" >&2
        return $CAPACITY_EXCEEDED
    fi
}

# ═══════════════════════════════════════════════════════════════
# 查詢功能
# ═══════════════════════════════════════════════════════════════

# 顯示容量狀態
# 用法: show_capacity_status
show_capacity_status() {
    if [ ! -d "$MEMORY_DIR" ]; then
        printf "錯誤：記憶目錄不存在: %s\n" "$MEMORY_DIR" >&2
        return $CAPACITY_CHECK_FAILED
    fi

    local current_size
    current_size=$(get_memory_size) || return $CAPACITY_CHECK_FAILED

    local limit_size
    limit_size=$(get_capacity_limit)

    local usage_pct
    usage_pct=$(calculate_usage_percentage "$current_size" "$limit_size")

    printf "═══════════════════════════════════════\n"
    printf "記憶容量狀態\n"
    printf "═══════════════════════════════════════\n"
    printf "當前大小: %s\n" "$(format_size_human $current_size)"
    printf "容量限制: %s\n" "$(format_size_human $limit_size)"
    printf "使用率:   %d%%\n" "$usage_pct"
    printf "\n"

    # 狀態圖示
    if [ "$usage_pct" -lt 70 ]; then
        printf "狀態: 🟢 正常\n"
    elif [ "$usage_pct" -lt 90 ]; then
        printf "狀態: 🟡 警告（建議清理）\n"
    else
        printf "狀態: 🔴 超過限制（需要清理）\n"
    fi

    printf "\n"

    # 顯示各子目錄大小
    printf "子目錄分布:\n"
    local subdir
    for subdir in .audit .backups .index daily experiences sessions; do
        if [ -d "${MEMORY_DIR}/${subdir}" ]; then
            local subdir_size
            if [ "$(uname)" = "Darwin" ]; then
                local size_kb
                size_kb=$(du -sk "${MEMORY_DIR}/${subdir}" 2>/dev/null | cut -f1 || printf "0")
                subdir_size=$((size_kb * 1024))
            else
                subdir_size=$(du -sb "${MEMORY_DIR}/${subdir}" 2>/dev/null | cut -f1 || printf "0")
            fi
            printf "  %-12s: %s\n" "$subdir" "$(format_size_human $subdir_size)"
        fi
    done

    printf "═══════════════════════════════════════\n"
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_capacity_help() {
    cat <<'EOF'
記憶容量檢查與清理工具

用法: $0 <command> [options]

指令:
  check              檢查容量是否超過限制
                     返回碼: 0=正常, 1=超過限制, 2=檢查失敗
                     輸出: 當前大小（bytes）

  get-size           取得記憶目錄大小（bytes）

  get-limit          取得容量限制（bytes）

  status             顯示容量狀態（人類可讀格式）

  cleanup            執行清理（僅在超過限制時）

  help               顯示此說明

範例:
  # 檢查容量
  $0 check
  echo $?  # 0=正常, 1=超過限制

  # 取得大小
  $0 get-size

  # 取得限制
  $0 get-limit

  # 顯示狀態
  $0 status

  # 執行清理
  $0 cleanup

配置:
  容量限制可在 config.yaml 中設定:
    memory:
      capacity_limit_mb: 10

  預設值: 10MB

清理策略:
  1. 優先清理 .audit/ 下的舊日誌
  2. 然後清理 sessions/ 下的舊記錄
  3. 最後清理 daily/ 下的舊記錄
  4. 保留 MEMORY.md 和 experiences/（重要記憶）

返回碼:
  0 - 成功 / 在限制內
  1 - 超過限制
  2 - 檢查失敗
EOF
}

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        check)
            check_memory_capacity >/dev/null
            exit $?
            ;;
        get-size)
            get_memory_size
            exit $?
            ;;
        get-limit)
            get_capacity_limit
            exit $?
            ;;
        status)
            show_capacity_status
            exit $?
            ;;
        cleanup)
            trigger_cleanup_if_needed
            exit $?
            ;;
        help|--help|-h|*)
            show_capacity_help
            exit 0
            ;;
    esac
fi
