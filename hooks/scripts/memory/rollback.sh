#!/usr/bin/env bash
# memory-rollback.sh - 記憶回滾工具
# 功能：提供從備份恢復記憶系統的能力（單一檔案或完整回滾）
# 使用方式：memory-rollback.sh <command> [options]
# 相容性：Bash 3.2+（macOS 預設版本）

# 注意：不使用 set -e，因為我們需要優雅處理錯誤
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# 載入依賴模組
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 使用 Bash 3.2 相容的方式：先關閉 errexit，然後靜默載入
set +e  # 暫時關閉錯誤中斷
set +u  # 暫時關閉未定義變數檢查

# 載入必要模組
. "${LIB_DIR}/core/common.sh" 2>/dev/null

# 恢復 set 選項
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# 常數定義（使用 MEMROLL_ 前綴避免衝突）
# ═══════════════════════════════════════════════════════════════

# 返回碼
readonly MEMROLL_SUCCESS=0
readonly MEMROLL_ERROR=1
readonly MEMROLL_BACKUP_NOT_FOUND=2
readonly MEMROLL_INTEGRITY_FAILED=3
readonly MEMROLL_USER_CANCELLED=4

# 記憶目錄
MEMROLL_MEMORY_DIR="${PWD}/.claude/memory"
MEMROLL_BACKUP_DIR="${MEMROLL_MEMORY_DIR}/.backups"
MEMROLL_INSTANT_BACKUP_DIR="${MEMROLL_BACKUP_DIR}/instant"
MEMROLL_DAILY_BACKUP_DIR="${MEMROLL_BACKUP_DIR}/daily"
MEMROLL_ROLLBACK_BACKUP_DIR="${MEMROLL_MEMORY_DIR}/.rollback_backup"
MEMROLL_AUDIT_LOG_DIR="${MEMROLL_MEMORY_DIR}/.audit"

# 審計日誌檔案
MEMROLL_AUDIT_LOG="${MEMROLL_AUDIT_LOG_DIR}/rollback-log.jsonl"

# 最大備份索引（即時備份保留最近 5 個版本）
MEMROLL_MAX_BACKUP_INDEX=4

# ═══════════════════════════════════════════════════════════════
# 內部輔助函式
# ═══════════════════════════════════════════════════════════════

# 取得當前時間戳（複用 common.sh 的 get_timestamp）
# 用法: timestamp=$(memroll_get_timestamp)
memroll_get_timestamp() {
    get_timestamp
}

# 確保目錄存在（複用 common.sh 的 ensure_directory）
# 用法: memroll_ensure_directory "/path/to/dir"
memroll_ensure_directory() {
    ensure_directory "$@"
}

# 記錄審計日誌
# 用法: memroll_audit_log action source_backup target status [message]
memroll_audit_log() {
    local action="${1:-unknown}"
    local source_backup="${2:-}"
    local target="${3:-}"
    local status="${4:-success}"
    local message="${5:-}"

    local timestamp
    timestamp=$(memroll_get_timestamp)

    # 轉義 JSON 特殊字元
    local escaped_source=$(printf '%s' "$source_backup" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')
    local escaped_target=$(printf '%s' "$target" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')
    local escaped_message=$(printf '%s' "$message" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')

    # 組裝 JSONL
    local jsonl="{\"timestamp\":\"$timestamp\",\"action\":\"$action\",\"source\":\"$escaped_source\",\"target\":\"$escaped_target\",\"status\":\"$status\",\"message\":\"$escaped_message\"}"

    # 確保審計目錄存在
    memroll_ensure_directory "$MEMROLL_AUDIT_LOG_DIR" || return $MEMROLL_ERROR

    # 追加寫入
    echo "$jsonl" >> "$MEMROLL_AUDIT_LOG" 2>/dev/null || {
        echo "⚠️  無法寫入審計日誌" >&2
        return $MEMROLL_ERROR
    }

    return $MEMROLL_SUCCESS
}

# 顯示錯誤訊息並記錄審計日誌
# 用法: memroll_error action source target message
memroll_error() {
    local action="${1:-}"
    local source="${2:-}"
    local target="${3:-}"
    local message="${4:-Unknown error}"

    echo "❌ 錯誤：$message" >&2
    memroll_audit_log "$action" "$source" "$target" "failure" "$message"
}

# 顯示成功訊息並記錄審計日誌
# 用法: memroll_success action source target message
memroll_success() {
    local action="${1:-}"
    local source="${2:-}"
    local target="${3:-}"
    local message="${4:-Success}"

    echo "✅ $message"
    memroll_audit_log "$action" "$source" "$target" "success" "$message"
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：備份驗證
# ═══════════════════════════════════════════════════════════════

# 驗證備份完整性
# 用法: if verify_backup_integrity "$backup_path"; then ...
# 返回: 0=完整，1=損壞
verify_backup_integrity() {
    local backup_path="${1:-}"

    if [ -z "$backup_path" ]; then
        echo "❌ 錯誤：verify_backup_integrity 需要提供備份路徑" >&2
        return $MEMROLL_ERROR
    fi

    # 檢查備份是否存在
    if [ ! -e "$backup_path" ]; then
        echo "❌ 備份不存在：$backup_path" >&2
        return $MEMROLL_BACKUP_NOT_FOUND
    fi

    # 檢查是檔案還是目錄
    if [ -f "$backup_path" ]; then
        # 檔案：檢查可讀性
        if [ ! -r "$backup_path" ]; then
            echo "❌ 備份檔案不可讀：$backup_path" >&2
            return $MEMROLL_INTEGRITY_FAILED
        fi

        # 檢查檔案大小（至少 1 byte）
        if [ ! -s "$backup_path" ]; then
            echo "❌ 備份檔案為空：$backup_path" >&2
            return $MEMROLL_INTEGRITY_FAILED
        fi
    elif [ -d "$backup_path" ]; then
        # 目錄：檢查可執行性（可進入）
        if [ ! -x "$backup_path" ]; then
            echo "❌ 備份目錄不可進入：$backup_path" >&2
            return $MEMROLL_INTEGRITY_FAILED
        fi

        # 檢查目錄非空
        if [ -z "$(ls -A "$backup_path" 2>/dev/null)" ]; then
            echo "❌ 備份目錄為空：$backup_path" >&2
            return $MEMROLL_INTEGRITY_FAILED
        fi
    else
        echo "❌ 備份既不是檔案也不是目錄：$backup_path" >&2
        return $MEMROLL_INTEGRITY_FAILED
    fi

    echo "✅ 備份完整性驗證通過：$backup_path"
    return $MEMROLL_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：回滾前備份
# ═══════════════════════════════════════════════════════════════

# 備份當前狀態到 .rollback_backup（在回滾前執行）
# 用法: backup_current_state
# 返回: 0=成功，1=失敗
backup_current_state() {
    echo "🔄 備份當前狀態到 .rollback_backup ..."

    # 刪除舊的 rollback_backup（如果存在）
    if [ -d "$MEMROLL_ROLLBACK_BACKUP_DIR" ]; then
        rm -rf "$MEMROLL_ROLLBACK_BACKUP_DIR" || {
            memroll_error "backup_current" "" "$MEMROLL_ROLLBACK_BACKUP_DIR" "無法刪除舊的 rollback_backup"
            return $MEMROLL_ERROR
        }
    fi

    # 建立新的 rollback_backup 目錄
    memroll_ensure_directory "$MEMROLL_ROLLBACK_BACKUP_DIR" || {
        memroll_error "backup_current" "" "$MEMROLL_ROLLBACK_BACKUP_DIR" "無法建立 rollback_backup 目錄"
        return $MEMROLL_ERROR
    }

    # 複製關鍵檔案和目錄
    # MEMORY.md
    if [ -f "${MEMROLL_MEMORY_DIR}/MEMORY.md" ]; then
        cp -p "${MEMROLL_MEMORY_DIR}/MEMORY.md" "$MEMROLL_ROLLBACK_BACKUP_DIR/" || {
            memroll_error "backup_current" "MEMORY.md" "$MEMROLL_ROLLBACK_BACKUP_DIR/MEMORY.md" "無法備份 MEMORY.md"
            return $MEMROLL_ERROR
        }
    fi

    # daily 目錄
    if [ -d "${MEMROLL_MEMORY_DIR}/daily" ]; then
        cp -Rp "${MEMROLL_MEMORY_DIR}/daily" "$MEMROLL_ROLLBACK_BACKUP_DIR/" || {
            memroll_error "backup_current" "daily/" "$MEMROLL_ROLLBACK_BACKUP_DIR/daily/" "無法備份 daily 目錄"
            return $MEMROLL_ERROR
        }
    fi

    # experiences 目錄
    if [ -d "${MEMROLL_MEMORY_DIR}/experiences" ]; then
        cp -Rp "${MEMROLL_MEMORY_DIR}/experiences" "$MEMROLL_ROLLBACK_BACKUP_DIR/" || {
            memroll_error "backup_current" "experiences/" "$MEMROLL_ROLLBACK_BACKUP_DIR/experiences/" "無法備份 experiences 目錄"
            return $MEMROLL_ERROR
        }
    fi

    # sessions 目錄
    if [ -d "${MEMROLL_MEMORY_DIR}/sessions" ]; then
        cp -Rp "${MEMROLL_MEMORY_DIR}/sessions" "$MEMROLL_ROLLBACK_BACKUP_DIR/" || {
            memroll_error "backup_current" "sessions/" "$MEMROLL_ROLLBACK_BACKUP_DIR/sessions/" "無法備份 sessions 目錄"
            return $MEMROLL_ERROR
        }
    fi

    memroll_success "backup_current" "${MEMROLL_MEMORY_DIR}" "$MEMROLL_ROLLBACK_BACKUP_DIR" "當前狀態已備份"
    return $MEMROLL_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：列出可用回滾點
# ═══════════════════════════════════════════════════════════════

# 列出所有可用的回滾點（即時備份 + 每日快照）
# 用法: list_available_rollbacks
# 輸出: 列印所有可用的回滾點
list_available_rollbacks() {
    echo "📋 可用的回滾點："
    echo ""

    # 列出即時備份
    echo "🔸 即時備份（單一檔案）："
    if [ -d "$MEMROLL_INSTANT_BACKUP_DIR" ]; then
        local instant_count=0
        # 找出所有即時備份（格式: MEMORY.md.TIMESTAMP）
        for backup in "$MEMROLL_INSTANT_BACKUP_DIR"/MEMORY.md.*; do
            if [ -f "$backup" ]; then
                local basename
                basename=$(basename "$backup")
                local timestamp_part="${basename#MEMORY.md.}"
                echo "  - 索引 $instant_count: $basename (時間: $timestamp_part)"
                instant_count=$((instant_count + 1))
            fi
        done

        if [ $instant_count -eq 0 ]; then
            echo "  （無可用的即時備份）"
        fi
    else
        echo "  （即時備份目錄不存在）"
    fi

    echo ""

    # 列出每日快照
    echo "🔹 每日快照（完整目錄結構）："
    if [ -d "$MEMROLL_DAILY_BACKUP_DIR" ]; then
        local daily_count=0
        # 找出所有每日快照（格式: YYYY-MM-DD/）
        for snapshot in "$MEMROLL_DAILY_BACKUP_DIR"/*/; do
            if [ -d "$snapshot" ]; then
                local basename
                basename=$(basename "$snapshot")
                echo "  - 日期: $basename"
                daily_count=$((daily_count + 1))
            fi
        done

        if [ $daily_count -eq 0 ]; then
            echo "  （無可用的每日快照）"
        fi
    else
        echo "  （每日快照目錄不存在）"
    fi

    echo ""

    # 列出 rollback_backup（撤銷回滾用）
    echo "🔺 回滾前備份（撤銷回滾用）："
    if [ -d "$MEMROLL_ROLLBACK_BACKUP_DIR" ]; then
        echo "  - .rollback_backup（可使用 'undo' 命令恢復）"
    else
        echo "  （無可用的回滾前備份）"
    fi
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：即時備份回滾（單一檔案）
# ═══════════════════════════════════════════════════════════════

# 從即時備份恢復單一檔案
# 用法: rollback_instant "$file_path" [$backup_index]
# 參數: backup_index - 可選，0=最新，1=次新，...
# 返回: 0=成功，1=失敗
rollback_instant() {
    local file_path="${1:-}"
    local backup_index="${2:-0}"

    if [ -z "$file_path" ]; then
        memroll_error "rollback_instant" "" "" "必須提供檔案路徑"
        return $MEMROLL_ERROR
    fi

    # 驗證 backup_index 為數字
    if ! [[ "$backup_index" =~ ^[0-9]+$ ]]; then
        memroll_error "rollback_instant" "" "" "備份索引必須為非負整數"
        return $MEMROLL_ERROR
    fi

    # 驗證索引範圍
    if [ "$backup_index" -gt "$MEMROLL_MAX_BACKUP_INDEX" ]; then
        memroll_error "rollback_instant" "" "" "備份索引超出範圍（最大 $MEMROLL_MAX_BACKUP_INDEX）"
        return $MEMROLL_ERROR
    fi

    echo "🔄 從即時備份恢復：$file_path (索引: $backup_index)"

    # 取得檔案名稱
    local filename
    filename=$(basename "$file_path")

    # 找出所有該檔案的備份（按時間排序，最新在前）
    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$MEMROLL_INSTANT_BACKUP_DIR" -maxdepth 1 -name "${filename}.*" -type f -print0 | sort -rz)

    # 檢查是否有足夠的備份
    if [ ${#backups[@]} -eq 0 ]; then
        memroll_error "rollback_instant" "" "$file_path" "找不到任何即時備份"
        return $MEMROLL_BACKUP_NOT_FOUND
    fi

    if [ "$backup_index" -ge ${#backups[@]} ]; then
        memroll_error "rollback_instant" "" "$file_path" "備份索引 $backup_index 不存在（僅有 ${#backups[@]} 個備份）"
        return $MEMROLL_BACKUP_NOT_FOUND
    fi

    # 取得目標備份
    local backup_file="${backups[$backup_index]}"

    # 驗證備份完整性
    if ! verify_backup_integrity "$backup_file"; then
        memroll_error "rollback_instant" "$backup_file" "$file_path" "備份完整性驗證失敗"
        return $MEMROLL_INTEGRITY_FAILED
    fi

    # 備份當前狀態
    if ! backup_current_state; then
        memroll_error "rollback_instant" "$backup_file" "$file_path" "無法備份當前狀態"
        return $MEMROLL_ERROR
    fi

    # 恢復檔案（使用原子操作）
    local tmp_file="${file_path}.rollback.tmp"
    if ! cp -p "$backup_file" "$tmp_file"; then
        memroll_error "rollback_instant" "$backup_file" "$file_path" "無法複製備份檔案"
        return $MEMROLL_ERROR
    fi

    if ! mv -f "$tmp_file" "$file_path"; then
        memroll_error "rollback_instant" "$backup_file" "$file_path" "無法恢復檔案"
        rm -f "$tmp_file"
        return $MEMROLL_ERROR
    fi

    memroll_success "rollback_instant" "$backup_file" "$file_path" "即時備份恢復成功"
    return $MEMROLL_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：每日快照回滾（完整目錄結構）
# ═══════════════════════════════════════════════════════════════

# 從每日快照恢復整個目錄結構
# 用法: rollback_daily "$date"
# 參數: date - YYYY-MM-DD 格式的日期
# 返回: 0=成功，1=失敗
rollback_daily() {
    local date="${1:-}"

    if [ -z "$date" ]; then
        memroll_error "rollback_daily" "" "" "必須提供日期（格式：YYYY-MM-DD）"
        return $MEMROLL_ERROR
    fi

    # 驗證日期格式
    if ! [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        memroll_error "rollback_daily" "" "" "日期格式錯誤（應為 YYYY-MM-DD）"
        return $MEMROLL_ERROR
    fi

    echo "🔄 從每日快照恢復：$date"

    local snapshot_dir="${MEMROLL_DAILY_BACKUP_DIR}/${date}"

    # 驗證快照存在
    if [ ! -d "$snapshot_dir" ]; then
        memroll_error "rollback_daily" "$snapshot_dir" "$MEMROLL_MEMORY_DIR" "快照目錄不存在：$date"
        return $MEMROLL_BACKUP_NOT_FOUND
    fi

    # 驗證快照完整性
    if ! verify_backup_integrity "$snapshot_dir"; then
        memroll_error "rollback_daily" "$snapshot_dir" "$MEMROLL_MEMORY_DIR" "快照完整性驗證失敗"
        return $MEMROLL_INTEGRITY_FAILED
    fi

    # 備份當前狀態
    if ! backup_current_state; then
        memroll_error "rollback_daily" "$snapshot_dir" "$MEMROLL_MEMORY_DIR" "無法備份當前狀態"
        return $MEMROLL_ERROR
    fi

    # 恢復快照（使用原子操作）
    local tmp_dir="${MEMROLL_MEMORY_DIR}.rollback.tmp"

    # 刪除舊的臨時目錄（如果存在）
    if [ -d "$tmp_dir" ]; then
        rm -rf "$tmp_dir" || {
            memroll_error "rollback_daily" "$snapshot_dir" "$MEMROLL_MEMORY_DIR" "無法刪除舊的臨時目錄"
            return $MEMROLL_ERROR
        }
    fi

    # 複製快照到臨時目錄
    if ! cp -Rp "$snapshot_dir" "$tmp_dir"; then
        memroll_error "rollback_daily" "$snapshot_dir" "$MEMROLL_MEMORY_DIR" "無法複製快照"
        return $MEMROLL_ERROR
    fi

    # 備份當前記憶目錄
    local old_memory_dir="${MEMROLL_MEMORY_DIR}.old"
    if ! mv "$MEMROLL_MEMORY_DIR" "$old_memory_dir"; then
        memroll_error "rollback_daily" "$snapshot_dir" "$MEMROLL_MEMORY_DIR" "無法備份當前記憶目錄"
        rm -rf "$tmp_dir"
        return $MEMROLL_ERROR
    fi

    # 將臨時目錄移動到記憶目錄
    if ! mv "$tmp_dir" "$MEMROLL_MEMORY_DIR"; then
        memroll_error "rollback_daily" "$snapshot_dir" "$MEMROLL_MEMORY_DIR" "無法恢復記憶目錄"
        # 嘗試恢復舊目錄
        mv "$old_memory_dir" "$MEMROLL_MEMORY_DIR"
        return $MEMROLL_ERROR
    fi

    # 刪除舊的記憶目錄
    rm -rf "$old_memory_dir"

    memroll_success "rollback_daily" "$snapshot_dir" "$MEMROLL_MEMORY_DIR" "每日快照恢復成功"
    return $MEMROLL_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：撤銷回滾
# ═══════════════════════════════════════════════════════════════

# 撤銷上次回滾（從 .rollback_backup 恢復）
# 用法: undo_rollback
# 返回: 0=成功，1=失敗
undo_rollback() {
    echo "🔙 撤銷上次回滾 ..."

    # 驗證 rollback_backup 存在
    if [ ! -d "$MEMROLL_ROLLBACK_BACKUP_DIR" ]; then
        memroll_error "undo_rollback" "$MEMROLL_ROLLBACK_BACKUP_DIR" "$MEMROLL_MEMORY_DIR" "找不到回滾前備份"
        return $MEMROLL_BACKUP_NOT_FOUND
    fi

    # 驗證備份完整性
    if ! verify_backup_integrity "$MEMROLL_ROLLBACK_BACKUP_DIR"; then
        memroll_error "undo_rollback" "$MEMROLL_ROLLBACK_BACKUP_DIR" "$MEMROLL_MEMORY_DIR" "回滾前備份完整性驗證失敗"
        return $MEMROLL_INTEGRITY_FAILED
    fi

    # 恢復關鍵檔案和目錄
    # MEMORY.md
    if [ -f "${MEMROLL_ROLLBACK_BACKUP_DIR}/MEMORY.md" ]; then
        cp -p "${MEMROLL_ROLLBACK_BACKUP_DIR}/MEMORY.md" "${MEMROLL_MEMORY_DIR}/" || {
            memroll_error "undo_rollback" "${MEMROLL_ROLLBACK_BACKUP_DIR}/MEMORY.md" "${MEMROLL_MEMORY_DIR}/MEMORY.md" "無法恢復 MEMORY.md"
            return $MEMROLL_ERROR
        }
    fi

    # daily 目錄
    if [ -d "${MEMROLL_ROLLBACK_BACKUP_DIR}/daily" ]; then
        rm -rf "${MEMROLL_MEMORY_DIR}/daily"
        cp -Rp "${MEMROLL_ROLLBACK_BACKUP_DIR}/daily" "${MEMROLL_MEMORY_DIR}/" || {
            memroll_error "undo_rollback" "${MEMROLL_ROLLBACK_BACKUP_DIR}/daily" "${MEMROLL_MEMORY_DIR}/daily" "無法恢復 daily 目錄"
            return $MEMROLL_ERROR
        }
    fi

    # experiences 目錄
    if [ -d "${MEMROLL_ROLLBACK_BACKUP_DIR}/experiences" ]; then
        rm -rf "${MEMROLL_MEMORY_DIR}/experiences"
        cp -Rp "${MEMROLL_ROLLBACK_BACKUP_DIR}/experiences" "${MEMROLL_MEMORY_DIR}/" || {
            memroll_error "undo_rollback" "${MEMROLL_ROLLBACK_BACKUP_DIR}/experiences" "${MEMROLL_MEMORY_DIR}/experiences" "無法恢復 experiences 目錄"
            return $MEMROLL_ERROR
        }
    fi

    # sessions 目錄
    if [ -d "${MEMROLL_ROLLBACK_BACKUP_DIR}/sessions" ]; then
        rm -rf "${MEMROLL_MEMORY_DIR}/sessions"
        cp -Rp "${MEMROLL_ROLLBACK_BACKUP_DIR}/sessions" "${MEMROLL_MEMORY_DIR}/" || {
            memroll_error "undo_rollback" "${MEMROLL_ROLLBACK_BACKUP_DIR}/sessions" "${MEMROLL_MEMORY_DIR}/sessions" "無法恢復 sessions 目錄"
            return $MEMROLL_ERROR
        }
    fi

    # 刪除 rollback_backup（已經使用過了）
    rm -rf "$MEMROLL_ROLLBACK_BACKUP_DIR"

    memroll_success "undo_rollback" "$MEMROLL_ROLLBACK_BACKUP_DIR" "$MEMROLL_MEMORY_DIR" "回滾已撤銷"
    return $MEMROLL_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：通用回滾介面
# ═══════════════════════════════════════════════════════════════

# 通用回滾函式（恢復指定備份）
# 用法: rollback_to_backup "$backup_path"
# 參數: backup_path - 備份檔案/目錄路徑
# 返回: 0=成功，1=失敗
rollback_to_backup() {
    local backup_path="${1:-}"

    if [ -z "$backup_path" ]; then
        memroll_error "rollback_to_backup" "" "" "必須提供備份路徑"
        return $MEMROLL_ERROR
    fi

    echo "🔄 回滾到備份：$backup_path"

    # 驗證備份存在且有效
    if ! verify_backup_integrity "$backup_path"; then
        memroll_error "rollback_to_backup" "$backup_path" "" "備份驗證失敗"
        return $MEMROLL_INTEGRITY_FAILED
    fi

    # 備份當前狀態到 .rollback_backup
    if ! backup_current_state; then
        memroll_error "rollback_to_backup" "$backup_path" "$MEMROLL_ROLLBACK_BACKUP_DIR" "無法備份當前狀態"
        return $MEMROLL_ERROR
    fi

    # 判斷是檔案還是目錄，使用對應的恢復方式
    if [ -f "$backup_path" ]; then
        # 單一檔案：恢復到對應位置
        local target_file="${MEMROLL_MEMORY_DIR}/MEMORY.md"

        local tmp_file="${target_file}.rollback.tmp"
        if ! cp -p "$backup_path" "$tmp_file"; then
            memroll_error "rollback_to_backup" "$backup_path" "$target_file" "無法複製備份檔案"
            return $MEMROLL_ERROR
        fi

        if ! mv -f "$tmp_file" "$target_file"; then
            memroll_error "rollback_to_backup" "$backup_path" "$target_file" "無法恢復檔案"
            rm -f "$tmp_file"
            return $MEMROLL_ERROR
        fi

        memroll_success "rollback_to_backup" "$backup_path" "$target_file" "檔案恢復成功"
    elif [ -d "$backup_path" ]; then
        # 目錄：恢復整個結構
        local tmp_dir="${MEMROLL_MEMORY_DIR}.rollback.tmp"

        # 刪除舊的臨時目錄
        if [ -d "$tmp_dir" ]; then
            rm -rf "$tmp_dir" || {
                memroll_error "rollback_to_backup" "$backup_path" "$MEMROLL_MEMORY_DIR" "無法刪除舊的臨時目錄"
                return $MEMROLL_ERROR
            }
        fi

        # 複製備份到臨時目錄
        if ! cp -Rp "$backup_path" "$tmp_dir"; then
            memroll_error "rollback_to_backup" "$backup_path" "$MEMROLL_MEMORY_DIR" "無法複製備份"
            return $MEMROLL_ERROR
        fi

        # 備份當前記憶目錄
        local old_memory_dir="${MEMROLL_MEMORY_DIR}.old"
        if ! mv "$MEMROLL_MEMORY_DIR" "$old_memory_dir"; then
            memroll_error "rollback_to_backup" "$backup_path" "$MEMROLL_MEMORY_DIR" "無法備份當前記憶目錄"
            rm -rf "$tmp_dir"
            return $MEMROLL_ERROR
        fi

        # 移動臨時目錄到記憶目錄
        if ! mv "$tmp_dir" "$MEMROLL_MEMORY_DIR"; then
            memroll_error "rollback_to_backup" "$backup_path" "$MEMROLL_MEMORY_DIR" "無法恢復記憶目錄"
            # 嘗試恢復舊目錄
            mv "$old_memory_dir" "$MEMROLL_MEMORY_DIR"
            return $MEMROLL_ERROR
        fi

        # 刪除舊的記憶目錄
        rm -rf "$old_memory_dir"

        memroll_success "rollback_to_backup" "$backup_path" "$MEMROLL_MEMORY_DIR" "目錄恢復成功"
    else
        memroll_error "rollback_to_backup" "$backup_path" "" "備份既不是檔案也不是目錄"
        return $MEMROLL_ERROR
    fi

    return $MEMROLL_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# CLI 介面：使用者確認
# ═══════════════════════════════════════════════════════════════

# 請求使用者確認（除非使用 --force）
# 用法: if confirm_action "訊息" "$force_flag"; then ...
# 返回: 0=確認，1=取消
confirm_action() {
    local message="${1:-確認執行？}"
    local force="${2:-false}"

    # 如果使用 --force，跳過確認
    if [ "$force" = "true" ]; then
        return $MEMROLL_SUCCESS
    fi

    # 請求確認
    echo ""
    echo "⚠️  $message"
    echo -n "確認執行？[y/N] "
    read -r response

    case "$response" in
        [yY]|[yY][eE][sS])
            return $MEMROLL_SUCCESS
            ;;
        *)
            echo "❌ 已取消"
            return $MEMROLL_USER_CANCELLED
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# CLI 介面：主要命令
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_help() {
    cat <<'EOF'
記憶回滾工具 - Memory Rollback

用法:
  memory-rollback.sh <command> [options]

命令:

  list
    列出所有可用的回滾點（即時備份 + 每日快照）

  instant <file_path> [--index N]
    從即時備份回滾單一檔案
    參數:
      file_path - 要恢復的檔案路徑（例如：.claude/memory/MEMORY.md）
      --index N - 可選，備份索引（0=最新，1=次新，預設 0）

  daily <date> [--force]
    從每日快照回滾整個目錄結構
    參數:
      date      - 日期（格式：YYYY-MM-DD）
      --force   - 可選，跳過確認提示

  undo [--force]
    撤銷上次回滾（恢復到回滾前的狀態）
    參數:
      --force   - 可選，跳過確認提示

  verify <backup_path>
    驗證備份完整性
    參數:
      backup_path - 備份檔案或目錄路徑

  help
    顯示此說明

範例:

  # 列出可用回滾點
  memory-rollback.sh list

  # 從最新的即時備份恢復 MEMORY.md
  memory-rollback.sh instant .claude/memory/MEMORY.md

  # 從第 2 個即時備份恢復
  memory-rollback.sh instant .claude/memory/MEMORY.md --index 1

  # 從每日快照恢復（需確認）
  memory-rollback.sh daily 2026-01-31

  # 強制執行（無確認）
  memory-rollback.sh daily 2026-01-31 --force

  # 撤銷上次回滾
  memory-rollback.sh undo

  # 驗證備份
  memory-rollback.sh verify .claude/memory/.backups/daily/2026-01-31

目錄結構:

  .claude/memory/
  ├── MEMORY.md           # 當前狀態
  ├── .rollback_backup/   # 回滾前的備份（自動覆蓋）
  │   ├── MEMORY.md
  │   ├── daily/
  │   └── experiences/
  └── .backups/
      ├── instant/        # 即時備份（單一檔案）
      └── daily/          # 每日快照（完整結構）

安全機制:

  1. 自動備份當前狀態（回滾前）
  2. 驗證備份完整性（檢查檔案存在且可讀）
  3. 審計日誌（記錄所有回滾操作）
  4. 確認提示（CLI 模式下需確認，可用 --force 跳過）
  5. 原子性操作（使用 tmp 目錄 + mv）

審計日誌位置:
  .claude/memory/.audit/rollback-log.jsonl

返回碼:
  0 - 成功
  1 - 錯誤
  2 - 備份不存在
  3 - 完整性驗證失敗
  4 - 使用者取消
EOF
}

# CLI 入口
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        list)
            list_available_rollbacks
            exit $?
            ;;

        instant)
            local file_path="${1:-}"
            local backup_index=0
            shift || true

            # 解析選項
            while [ $# -gt 0 ]; do
                case "$1" in
                    --index)
                        backup_index="${2:-0}"
                        shift 2 || shift
                        ;;
                    *)
                        shift
                        ;;
                esac
            done

            rollback_instant "$file_path" "$backup_index"
            exit $?
            ;;

        daily)
            local date="${1:-}"
            local force=false
            shift || true

            # 解析選項
            while [ $# -gt 0 ]; do
                case "$1" in
                    --force)
                        force=true
                        shift
                        ;;
                    *)
                        shift
                        ;;
                esac
            done

            # 確認操作
            if ! confirm_action "這將恢復整個記憶目錄到 $date 的狀態" "$force"; then
                exit $MEMROLL_USER_CANCELLED
            fi

            rollback_daily "$date"
            exit $?
            ;;

        undo)
            local force=false

            # 解析選項
            while [ $# -gt 0 ]; do
                case "$1" in
                    --force)
                        force=true
                        shift
                        ;;
                    *)
                        shift
                        ;;
                esac
            done

            # 確認操作
            if ! confirm_action "這將撤銷上次回滾操作" "$force"; then
                exit $MEMROLL_USER_CANCELLED
            fi

            undo_rollback
            exit $?
            ;;

        verify)
            local backup_path="${1:-}"
            verify_backup_integrity "$backup_path"
            exit $?
            ;;

        help|--help|-h)
            show_help
            exit $MEMROLL_SUCCESS
            ;;

        *)
            echo "❌ 未知命令：$command" >&2
            echo "使用 'memory-rollback.sh help' 查看說明" >&2
            exit $MEMROLL_ERROR
            ;;
    esac
}

# 執行主函式（僅在直接執行時）
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    main "$@"
fi
