#!/usr/bin/env bash
# memory-backup.sh - 記憶系統即時備份工具
# 功能：在寫入前自動備份檔案，保留最新 N 份備份
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-backup.sh"

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 載入依賴
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/../core/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義（使用 MEMBAK_ 前綴避免衝突）
# ═══════════════════════════════════════════════════════════════

# 返回碼
readonly MEMBAK_SUCCESS=0
readonly MEMBAK_ERROR=1
readonly MEMBAK_FILE_NOT_FOUND=2
readonly MEMBAK_RESTORE_FAILED=3

# 備份目錄
readonly MEMBAK_INSTANT_DIR="${PWD}/.claude/memory/.backups/instant"

# 保留備份數量
readonly MEMBAK_KEEP_COUNT=3

# 檔案權限
readonly MEMBAK_FILE_PERMISSION="600"

# ═══════════════════════════════════════════════════════════════
# 輔助函式
# ═══════════════════════════════════════════════════════════════

# 取得檔案的基礎名稱（去除目錄路徑）
# 用法: basename=$(get_backup_basename "/path/to/file.md")
# 輸出: file.md
get_backup_basename() {
    local file_path="${1:-}"

    if [ -z "$file_path" ]; then
        return $MEMBAK_ERROR
    fi

    basename "$file_path"
}

# 產生備份檔案名稱
# 用法: backup_name=$(generate_backup_name "/path/to/file.md")
# 輸出: file.md.2026-02-01T12:00:00Z.bak
generate_backup_name() {
    local file_path="${1:-}"

    if [ -z "$file_path" ]; then
        return $MEMBAK_ERROR
    fi

    local base_name
    base_name=$(get_backup_basename "$file_path")

    local timestamp
    timestamp=$(get_timestamp)

    echo "${base_name}.${timestamp}.bak"
}

# 取得指定檔案的所有備份（按時間排序，最新在前）
# 用法: backups=$(get_file_backups "/path/to/file.md")
# 輸出: 備份檔案列表（一行一個）
get_file_backups() {
    local file_path="${1:-}"

    if [ -z "$file_path" ]; then
        return $MEMBAK_ERROR
    fi

    local base_name
    base_name=$(get_backup_basename "$file_path")

    # 確保備份目錄存在
    if [ ! -d "$MEMBAK_INSTANT_DIR" ]; then
        return $MEMBAK_SUCCESS
    fi

    # 列出該檔案的所有備份，按時間排序（最新在前）
    find "$MEMBAK_INSTANT_DIR" -type f -name "${base_name}.*.bak" 2>/dev/null | \
        sort -r || true
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 1: 備份檔案
# ═══════════════════════════════════════════════════════════════

# 在寫入前備份檔案
# 用法: backup_before_write "/path/to/file"
# 參數: file_path - 要備份的檔案路徑
# 動作:
#   1. 檢查檔案是否存在
#   2. 建立備份目錄 .claude/memory/.backups/instant/
#   3. 複製檔案到 <original_name>.<timestamp>.bak
#   4. 清理超過 3 份的舊備份
# 返回: 0=成功，1=失敗，2=檔案不存在（跳過備份）
backup_before_write() {
    local file_path="${1:-}"

    if [ -z "$file_path" ]; then
        echo "錯誤：backup_before_write 需要提供檔案路徑" >&2
        return $MEMBAK_ERROR
    fi

    # 如果檔案不存在，無需備份（這是正常情況，不是錯誤）
    if [ ! -f "$file_path" ]; then
        return $MEMBAK_SUCCESS
    fi

    # 確保備份目錄存在
    if ! ensure_directory "$MEMBAK_INSTANT_DIR"; then
        echo "錯誤：無法建立備份目錄: $MEMBAK_INSTANT_DIR" >&2
        return $MEMBAK_ERROR
    fi

    # 產生備份檔案名稱
    local backup_name
    backup_name=$(generate_backup_name "$file_path") || {
        echo "錯誤：無法產生備份檔案名稱" >&2
        return $MEMBAK_ERROR
    }

    local backup_path="${MEMBAK_INSTANT_DIR}/${backup_name}"

    # 複製檔案（使用 cp -p 保留時間戳和權限）
    if ! cp -p "$file_path" "$backup_path" 2>/dev/null; then
        echo "錯誤：無法備份檔案: $file_path -> $backup_path" >&2
        return $MEMBAK_ERROR
    fi

    # 確保備份檔案權限為 600
    chmod "$MEMBAK_FILE_PERMISSION" "$backup_path" 2>/dev/null || true

    # 清理舊備份
    cleanup_old_backups "$file_path" "$MEMBAK_KEEP_COUNT" || {
        echo "警告：清理舊備份時發生錯誤" >&2
        # 不返回錯誤，因為備份已成功
    }

    return $MEMBAK_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 2: 列出備份
# ═══════════════════════════════════════════════════════════════

# 列出指定檔案的所有備份
# 用法: list_backups "/path/to/file"
# 輸出: 列出該檔案的所有備份（按時間排序，最新在前）
list_backups() {
    local file_path="${1:-}"

    if [ -z "$file_path" ]; then
        echo "錯誤：list_backups 需要提供檔案路徑" >&2
        return $MEMBAK_ERROR
    fi

    local base_name
    base_name=$(get_backup_basename "$file_path") || {
        echo "錯誤：無法取得檔案基礎名稱" >&2
        return $MEMBAK_ERROR
    }

    echo "備份檔案列表 (檔案: $base_name):"
    echo "───────────────────────────────────────"

    local backups
    backups=$(get_file_backups "$file_path")

    if [ -z "$backups" ]; then
        echo "（無備份）"
        return $MEMBAK_SUCCESS
    fi

    local count=0
    while IFS= read -r backup_file; do
        if [ -n "$backup_file" ]; then
            count=$((count + 1))
            local file_size
            file_size=$(du -h "$backup_file" 2>/dev/null | cut -f1 || echo "?")
            echo "$count. $(basename "$backup_file") [$file_size]"
        fi
    done <<< "$backups"

    echo "───────────────────────────────────────"
    echo "總計: $count 個備份"

    return $MEMBAK_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 3: 取得最新備份
# ═══════════════════════════════════════════════════════════════

# 取得指定檔案的最新備份
# 用法: backup=$(get_latest_backup "/path/to/file")
# 輸出: 最新備份的完整路徑（如果無備份則輸出空字串）
get_latest_backup() {
    local file_path="${1:-}"

    if [ -z "$file_path" ]; then
        echo "錯誤：get_latest_backup 需要提供檔案路徑" >&2
        return $MEMBAK_ERROR
    fi

    local backups
    backups=$(get_file_backups "$file_path")

    if [ -z "$backups" ]; then
        return $MEMBAK_SUCCESS
    fi

    # 返回第一個（最新）
    echo "$backups" | head -n 1

    return $MEMBAK_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 4: 從備份恢復
# ═══════════════════════════════════════════════════════════════

# 從備份恢復檔案
# 用法: restore_from_backup "/path/to/backup.bak"
# 動作: 從備份恢復檔案到原始位置
# 返回: 0=成功，1=失敗
restore_from_backup() {
    local backup_path="${1:-}"

    if [ -z "$backup_path" ]; then
        echo "錯誤：restore_from_backup 需要提供備份檔案路徑" >&2
        return $MEMBAK_ERROR
    fi

    if [ ! -f "$backup_path" ]; then
        echo "錯誤：備份檔案不存在: $backup_path" >&2
        return $MEMBAK_FILE_NOT_FOUND
    fi

    # 從備份檔案名稱推導原始檔案名稱
    # 格式: <original_name>.<timestamp>.bak
    local backup_basename
    backup_basename=$(basename "$backup_path")

    # 移除 .TIMESTAMP.bak 後綴
    local original_name
    original_name=$(echo "$backup_basename" | sed -E 's/\.[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\.bak$//')

    if [ -z "$original_name" ] || [ "$original_name" = "$backup_basename" ]; then
        echo "錯誤：無法從備份檔案名稱推導原始檔案名稱" >&2
        echo "  備份檔案: $backup_basename" >&2
        return $MEMBAK_RESTORE_FAILED
    fi

    # 原始檔案路徑（假設在 .claude/memory/ 目錄下）
    local original_path="${PWD}/.claude/memory/${original_name}"

    # 詢問用戶確認（除非設定了 MEMBAK_AUTO_RESTORE）
    if [ "${MEMBAK_AUTO_RESTORE:-0}" != "1" ]; then
        echo "警告：即將恢復備份到:"
        echo "  來源: $backup_path"
        echo "  目標: $original_path"
        read -p "確認恢復？(y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "已取消恢復"
            return $MEMBAK_ERROR
        fi
    fi

    # 確保目標目錄存在
    local target_dir
    target_dir=$(dirname "$original_path")
    if ! ensure_directory "$target_dir"; then
        echo "錯誤：無法建立目標目錄: $target_dir" >&2
        return $MEMBAK_RESTORE_FAILED
    fi

    # 如果目標檔案已存在，先備份
    if [ -f "$original_path" ]; then
        local safety_backup="${original_path}.before-restore.$(date +%s)"
        if ! cp -p "$original_path" "$safety_backup" 2>/dev/null; then
            echo "警告：無法建立安全備份" >&2
        else
            echo "已建立安全備份: $safety_backup"
        fi
    fi

    # 恢復檔案
    if ! cp -p "$backup_path" "$original_path" 2>/dev/null; then
        echo "錯誤：無法恢復檔案: $backup_path -> $original_path" >&2
        return $MEMBAK_RESTORE_FAILED
    fi

    # 確保權限正確
    chmod "$MEMBAK_FILE_PERMISSION" "$original_path" 2>/dev/null || true

    echo "✅ 恢復成功: $original_path"

    return $MEMBAK_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 5: 清理舊備份
# ═══════════════════════════════════════════════════════════════

# 清理舊備份，保留最新 N 份
# 用法: cleanup_old_backups "/path/to/file" $keep_count
# 參數:
#   file_path  - 原始檔案路徑
#   keep_count - 保留數量（預設 3）
# 動作: 保留最新 N 份，刪除其餘備份
# 返回: 0=成功，1=失敗
cleanup_old_backups() {
    local file_path="${1:-}"
    local keep_count="${2:-$MEMBAK_KEEP_COUNT}"

    if [ -z "$file_path" ]; then
        echo "錯誤：cleanup_old_backups 需要提供檔案路徑" >&2
        return $MEMBAK_ERROR
    fi

    # 驗證 keep_count 是否為正整數
    if ! [[ "$keep_count" =~ ^[0-9]+$ ]] || [ "$keep_count" -lt 1 ]; then
        echo "錯誤：keep_count 必須是正整數" >&2
        return $MEMBAK_ERROR
    fi

    local backups
    backups=$(get_file_backups "$file_path")

    if [ -z "$backups" ]; then
        # 沒有備份，無需清理
        return $MEMBAK_SUCCESS
    fi

    # 計算備份數量
    local backup_count
    backup_count=$(echo "$backups" | wc -l | tr -d ' ')

    if [ "$backup_count" -le "$keep_count" ]; then
        # 備份數量未超過限制，無需清理
        return $MEMBAK_SUCCESS
    fi

    # 刪除多餘的舊備份
    local to_delete_count=$((backup_count - keep_count))

    echo "$backups" | tail -n "$to_delete_count" | while IFS= read -r backup_file; do
        if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
            rm -f "$backup_file" 2>/dev/null || {
                echo "警告：無法刪除舊備份: $backup_file" >&2
            }
        fi
    done

    return $MEMBAK_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示備份目錄統計
# 用法: show_backup_stats
show_backup_stats() {
    echo "═══════════════════════════════════════"
    echo "記憶系統即時備份統計"
    echo "═══════════════════════════════════════"
    echo "備份目錄: $MEMBAK_INSTANT_DIR"
    echo "保留數量: $MEMBAK_KEEP_COUNT"
    echo ""

    if [ ! -d "$MEMBAK_INSTANT_DIR" ]; then
        echo "備份目錄不存在"
        echo "═══════════════════════════════════════"
        return $MEMBAK_SUCCESS
    fi

    local total_backups
    total_backups=$(find "$MEMBAK_INSTANT_DIR" -type f -name "*.bak" 2>/dev/null | wc -l | tr -d ' ')

    echo "總備份數: $total_backups"

    if [ "$total_backups" -gt 0 ]; then
        echo ""
        echo "備份大小分布:"
        du -sh "$MEMBAK_INSTANT_DIR" 2>/dev/null || echo "  無法計算"

        echo ""
        echo "最近 5 個備份:"
        find "$MEMBAK_INSTANT_DIR" -type f -name "*.bak" -print0 2>/dev/null | \
            xargs -0 ls -lt 2>/dev/null | head -n 5 | \
            awk '{printf "  %s %s %s [%s]\n", $6, $7, $8, $9}' || echo "  無資料"
    fi

    echo "═══════════════════════════════════════"
}

# 顯示使用說明
show_backup_help() {
    cat <<'EOF'
記憶系統即時備份工具 (Memory Backup)

用法:
  source memory-backup.sh

  或直接執行:
  memory-backup.sh <command> [arguments]

函式:
  backup_before_write <file_path>
    在寫入前備份檔案
    參數: file_path - 要備份的檔案路徑
    返回: 0=成功，1=失敗

  list_backups <file_path>
    列出指定檔案的所有備份
    參數: file_path - 檔案路徑
    輸出: 備份列表（按時間排序）

  get_latest_backup <file_path>
    取得最新備份路徑
    參數: file_path - 檔案路徑
    輸出: 最新備份的完整路徑

  restore_from_backup <backup_path>
    從備份恢復檔案
    參數: backup_path - 備份檔案路徑
    返回: 0=成功，1=失敗

  cleanup_old_backups <file_path> [keep_count]
    清理舊備份
    參數:
      file_path  - 檔案路徑
      keep_count - 保留數量（預設 3）
    返回: 0=成功，1=失敗

  show_backup_stats
    顯示備份統計資訊

CLI 命令:
  backup <file>       - 備份檔案
  list <file>         - 列出備份
  latest <file>       - 取得最新備份
  restore <backup>    - 從備份恢復
  cleanup <file>      - 清理舊備份
  stats               - 顯示統計
  help                - 顯示此說明

範例:
  # 備份檔案
  memory-backup.sh backup .claude/memory/MEMORY.md

  # 列出備份
  memory-backup.sh list .claude/memory/MEMORY.md

  # 取得最新備份
  latest=$(memory-backup.sh latest .claude/memory/MEMORY.md)

  # 從備份恢復（會詢問確認）
  memory-backup.sh restore "$latest"

  # 自動恢復（不詢問）
  MEMBAK_AUTO_RESTORE=1 memory-backup.sh restore "$latest"

  # 清理舊備份（保留 5 份）
  memory-backup.sh cleanup .claude/memory/MEMORY.md 5

  # 顯示統計
  memory-backup.sh stats

備份格式:
  檔案名稱: <original_name>.<timestamp>.bak
  範例: MEMORY.md.2026-02-01T12:00:00Z.bak

備份目錄:
  .claude/memory/.backups/instant/

保留規則:
  - 預設保留最新 3 份
  - 超過數量自動刪除最舊的
  - 每次備份後自動清理

返回碼:
  0 - 成功
  1 - 一般錯誤
  2 - 檔案不存在
  3 - 恢復失敗

環境變數:
  MEMBAK_AUTO_RESTORE=1  - 恢復時不詢問確認
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（CLI）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        backup)
            shift
            backup_before_write "$@"
            exit $?
            ;;
        list)
            shift
            list_backups "$@"
            exit $?
            ;;
        latest)
            shift
            get_latest_backup "$@"
            exit $?
            ;;
        restore)
            shift
            restore_from_backup "$@"
            exit $?
            ;;
        cleanup)
            shift
            cleanup_old_backups "$@"
            exit $?
            ;;
        stats)
            show_backup_stats
            exit 0
            ;;
        help|--help|-h|"")
            show_backup_help
            exit 0
            ;;
        *)
            echo "錯誤：未知命令: $1" >&2
            echo "使用 'memory-backup.sh help' 查看使用說明" >&2
            exit $MEMBAK_ERROR
            ;;
    esac
fi
