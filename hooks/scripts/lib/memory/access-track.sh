#!/bin/bash
# memory-access-track.sh - 記憶存取追蹤工具函式庫
# 功能：追蹤記憶的存取次數和最後存取時間
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-access-track.sh"

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 常數定義（使用 MEMTRACK_ 前綴避免衝突）
# 注意：必須在載入其他模組之前定義，避免 readonly 變數衝突
# ═══════════════════════════════════════════════════════════════

# 返回碼
readonly MEMTRACK_SUCCESS=0
readonly MEMTRACK_ERROR=1
readonly MEMTRACK_FILE_NOT_FOUND=2
readonly MEMTRACK_DB_NOT_FOUND=3
readonly MEMTRACK_LOCK_FAILED=4

# 鎖定設定
readonly MEMTRACK_LOCK_TIMEOUT=3

# 記憶體資料庫路徑
readonly MEMTRACK_DB_PATH=".claude/memory/memories.db"

# ═══════════════════════════════════════════════════════════════
# 載入依賴模組
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入共用工具
if [ -f "${SCRIPT_DIR}/common.sh" ]; then
    source "${SCRIPT_DIR}/../core/common.sh"
else
    # 如果 common.sh 不可用，定義最小必要函式
    get_timestamp() {
        date -u +%Y-%m-%dT%H:%M:%SZ
    }
fi

# 載入 yaml-parser（用於處理 frontmatter）
if [ -f "${SCRIPT_DIR}/yaml-parser.sh" ]; then
    source "${SCRIPT_DIR}/../core/yaml-parser.sh"
fi

# 注意：不載入 atomic-write.sh，因為我們只需要 yaml-parser 和 common 的功能
# 檔案寫入由 yaml-parser.sh 的 update_frontmatter 處理

# ═══════════════════════════════════════════════════════════════
# 輔助功能：檔案鎖定
# ═══════════════════════════════════════════════════════════════

# 檢查系統是否支援 flock
# 用法: has_flock
# 返回: 0=支援，1=不支援
has_flock() {
    command -v flock >/dev/null 2>&1
}

# 在鎖定保護下執行操作
# 用法: with_lock "lock_file" "command"
# 返回: 命令的返回碼
with_lock() {
    local lock_file="${1:-}"
    local command="${2:-}"

    if [ -z "$lock_file" ] || [ -z "$command" ]; then
        echo "錯誤：with_lock 需要提供鎖定檔案和命令" >&2
        return $MEMTRACK_ERROR
    fi

    if has_flock; then
        # 使用 flock 進行檔案鎖定
        flock -x -w "$MEMTRACK_LOCK_TIMEOUT" "$lock_file" bash -c "$command"
        return $?
    else
        # flock 不可用，直接執行（無鎖定保護）
        bash -c "$command"
        return $?
    fi
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 1: 更新檔案 frontmatter 的 access_count
# ═══════════════════════════════════════════════════════════════

# 增加檔案 frontmatter 的 access_count
# 用法: increment_access_count "memory_file"
# 參數: memory_file - 記憶檔案路徑
# 動作: 更新檔案 frontmatter 的 access_count
# 返回: 0=成功，1=失敗
increment_access_count() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ]; then
        echo "錯誤：increment_access_count 需要提供檔案路徑" >&2
        return $MEMTRACK_ERROR
    fi

    if [ ! -f "$memory_file" ]; then
        echo "錯誤：檔案不存在: $memory_file" >&2
        return $MEMTRACK_FILE_NOT_FOUND
    fi

    # 檢查是否有 frontmatter
    if ! has_frontmatter "$memory_file" 2>/dev/null; then
        echo "警告：檔案無 frontmatter，無法更新 access_count: $memory_file" >&2
        return $MEMTRACK_ERROR
    fi

    # 取得當前 access_count（如果不存在則為 0）
    local current_count=0
    if current_count=$(parse_frontmatter "$memory_file" "access_count" 2>/dev/null); then
        # 驗證是否為數字
        if ! [[ "$current_count" =~ ^[0-9]+$ ]]; then
            current_count=0
        fi
    fi

    # 計算新的 access_count
    local new_count=$((current_count + 1))

    # 更新 frontmatter
    if ! update_frontmatter "$memory_file" "access_count" "$new_count" 2>/dev/null; then
        echo "錯誤：無法更新 access_count: $memory_file" >&2
        return $MEMTRACK_ERROR
    fi

    return $MEMTRACK_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 2: 更新檔案 frontmatter 的 last_accessed
# ═══════════════════════════════════════════════════════════════

# 更新檔案 frontmatter 的 last_accessed 時間戳
# 用法: update_last_accessed "memory_file"
# 參數: memory_file - 記憶檔案路徑
# 動作: 更新檔案 frontmatter 的 last_accessed
# 返回: 0=成功，1=失敗
update_last_accessed() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ]; then
        echo "錯誤：update_last_accessed 需要提供檔案路徑" >&2
        return $MEMTRACK_ERROR
    fi

    if [ ! -f "$memory_file" ]; then
        echo "錯誤：檔案不存在: $memory_file" >&2
        return $MEMTRACK_FILE_NOT_FOUND
    fi

    # 檢查是否有 frontmatter
    if ! has_frontmatter "$memory_file" 2>/dev/null; then
        echo "警告：檔案無 frontmatter，無法更新 last_accessed: $memory_file" >&2
        return $MEMTRACK_ERROR
    fi

    # 取得當前時間戳
    local timestamp
    timestamp=$(get_timestamp)

    # 更新 frontmatter
    if ! update_frontmatter "$memory_file" "last_accessed" "$timestamp" 2>/dev/null; then
        echo "錯誤：無法更新 last_accessed: $memory_file" >&2
        return $MEMTRACK_ERROR
    fi

    return $MEMTRACK_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 3: 更新資料庫中的存取記錄
# ═══════════════════════════════════════════════════════════════

# 更新 SQLite 資料庫中的存取記錄
# 用法: update_db_access "memory_id"
# 參數: memory_id - 記憶的資料庫 ID 或檔案路徑
# 動作: 更新資料庫中的 access_count 和 last_accessed
# 返回: 0=成功，1=失敗
update_db_access() {
    local memory_id="${1:-}"

    if [ -z "$memory_id" ]; then
        echo "錯誤：update_db_access 需要提供記憶 ID 或檔案路徑" >&2
        return $MEMTRACK_ERROR
    fi

    # 檢查資料庫是否存在
    local db_path="${PWD}/${MEMTRACK_DB_PATH}"
    if [ ! -f "$db_path" ]; then
        echo "警告：資料庫不存在，跳過資料庫更新: $db_path" >&2
        return $MEMTRACK_DB_NOT_FOUND
    fi

    # 檢查 sqlite3 是否可用
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo "警告：sqlite3 不可用，跳過資料庫更新" >&2
        return $MEMTRACK_ERROR
    fi

    # 取得當前時間戳
    local timestamp
    timestamp=$(get_timestamp)

    # 判斷 memory_id 是數字 ID 還是檔案路徑
    local sql_query
    if [[ "$memory_id" =~ ^[0-9]+$ ]]; then
        # 數字 ID - 直接使用 ID 查詢
        sql_query="UPDATE memories SET access_count = access_count + 1, last_accessed = '$timestamp' WHERE id = $memory_id;"
    else
        # 檔案路徑 - 使用 source_file 查詢
        sql_query="UPDATE memories SET access_count = access_count + 1, last_accessed = '$timestamp' WHERE source_file = '$memory_id';"
    fi

    # 執行 SQL 更新
    if ! sqlite3 "$db_path" "$sql_query" 2>/dev/null; then
        echo "錯誤：無法更新資料庫存取記錄: $memory_id" >&2
        return $MEMTRACK_ERROR
    fi

    return $MEMTRACK_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 4: 統一追蹤介面
# ═══════════════════════════════════════════════════════════════

# 追蹤記憶的存取
# 用法: track_access "memory_id"
# 參數: memory_id - 記憶的唯一識別碼（SQLite ID 或檔案路徑）
# 動作:
#   1. 更新 access_count + 1
#   2. 更新 last_accessed 時間戳
#   3. 如果是檔案路徑，同時更新檔案 frontmatter 和資料庫
# 返回: 0=成功，1=失敗
track_access() {
    local memory_id="${1:-}"

    if [ -z "$memory_id" ]; then
        echo "錯誤：track_access 需要提供記憶 ID 或檔案路徑" >&2
        return $MEMTRACK_ERROR
    fi

    # 判斷是檔案路徑還是資料庫 ID
    if [ -f "$memory_id" ]; then
        # 檔案路徑 - 更新檔案和資料庫
        local lock_file="${memory_id}.lock"

        # 使用鎖定保護（如果可用）
        if has_flock; then
            (
                # 鎖定檔案
                exec 200>"$lock_file"
                if ! flock -x -w "$MEMTRACK_LOCK_TIMEOUT" 200; then
                    echo "錯誤：無法取得檔案鎖定: $memory_id" >&2
                    exit $MEMTRACK_LOCK_FAILED
                fi

                # 更新 access_count
                if ! increment_access_count "$memory_id"; then
                    exit $MEMTRACK_ERROR
                fi

                # 更新 last_accessed
                if ! update_last_accessed "$memory_id"; then
                    exit $MEMTRACK_ERROR
                fi

                # 嘗試更新資料庫（失敗不影響整體結果）
                update_db_access "$memory_id" 2>/dev/null || true

                exit $MEMTRACK_SUCCESS
            )
            local result=$?
            rm -f "$lock_file" 2>/dev/null || true
            return $result
        else
            # 無 flock，直接更新（無鎖定保護）
            increment_access_count "$memory_id" || return $?
            update_last_accessed "$memory_id" || return $?
            update_db_access "$memory_id" 2>/dev/null || true
            return $MEMTRACK_SUCCESS
        fi
    else
        # 資料庫 ID - 只更新資料庫
        update_db_access "$memory_id"
        return $?
    fi
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 5: 取得存取統計
# ═══════════════════════════════════════════════════════════════

# 取得記憶的存取統計
# 用法: stats=$(get_access_stats "memory_id")
# 參數: memory_id - 記憶的唯一識別碼（SQLite ID 或檔案路徑）
# 輸出: JSON 格式統計
# 範例: {"access_count":5,"last_accessed":"2026-02-01T12:00:00Z"}
# 返回: 0=成功，1=失敗
get_access_stats() {
    local memory_id="${1:-}"

    if [ -z "$memory_id" ]; then
        echo "錯誤：get_access_stats 需要提供記憶 ID 或檔案路徑" >&2
        return $MEMTRACK_ERROR
    fi

    # 判斷是檔案路徑還是資料庫 ID
    if [ -f "$memory_id" ]; then
        # 檔案路徑 - 從 frontmatter 讀取
        if ! has_frontmatter "$memory_id" 2>/dev/null; then
            echo '{"access_count":0,"last_accessed":null}'
            return $MEMTRACK_SUCCESS
        fi

        local access_count=0
        local last_accessed="null"

        # 讀取 access_count
        if access_count=$(parse_frontmatter "$memory_id" "access_count" 2>/dev/null); then
            if ! [[ "$access_count" =~ ^[0-9]+$ ]]; then
                access_count=0
            fi
        fi

        # 讀取 last_accessed
        if last_accessed=$(parse_frontmatter "$memory_id" "last_accessed" 2>/dev/null); then
            # 加上引號（JSON 字串）
            last_accessed="\"$last_accessed\""
        else
            last_accessed="null"
        fi

        # 輸出 JSON
        echo "{\"access_count\":$access_count,\"last_accessed\":$last_accessed}"
        return $MEMTRACK_SUCCESS
    else
        # 資料庫 ID - 從資料庫讀取
        local db_path="${PWD}/${MEMTRACK_DB_PATH}"
        if [ ! -f "$db_path" ]; then
            echo '{"access_count":0,"last_accessed":null}'
            return $MEMTRACK_DB_NOT_FOUND
        fi

        if ! command -v sqlite3 >/dev/null 2>&1; then
            echo '{"access_count":0,"last_accessed":null}'
            return $MEMTRACK_ERROR
        fi

        # 構建 SQL 查詢
        local sql_query
        if [[ "$memory_id" =~ ^[0-9]+$ ]]; then
            sql_query="SELECT access_count, last_accessed FROM memories WHERE id = $memory_id;"
        else
            sql_query="SELECT access_count, last_accessed FROM memories WHERE source_file = '$memory_id';"
        fi

        # 執行查詢
        local result
        result=$(sqlite3 "$db_path" "$sql_query" 2>/dev/null | head -1)

        if [ -z "$result" ]; then
            echo '{"access_count":0,"last_accessed":null}'
            return $MEMTRACK_SUCCESS
        fi

        # 解析結果（格式：count|timestamp）
        local access_count
        local last_accessed
        access_count=$(echo "$result" | cut -d'|' -f1)
        last_accessed=$(echo "$result" | cut -d'|' -f2)

        # 處理空值
        if [ -z "$access_count" ]; then
            access_count=0
        fi

        if [ -z "$last_accessed" ] || [ "$last_accessed" = "" ]; then
            last_accessed="null"
        else
            last_accessed="\"$last_accessed\""
        fi

        # 輸出 JSON
        echo "{\"access_count\":$access_count,\"last_accessed\":$last_accessed}"
        return $MEMTRACK_SUCCESS
    fi
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_memory_access_track_help() {
    cat <<'EOF'
記憶存取追蹤工具

用法:
  source memory-access-track.sh

主要函式:
  track_access <memory_id>
    追蹤記憶的存取
    參數:
      memory_id - 記憶的唯一識別碼（SQLite ID 或檔案路徑）
    動作:
      1. 更新 access_count + 1
      2. 更新 last_accessed 時間戳

  get_access_stats <memory_id>
    取得記憶的存取統計
    參數:
      memory_id - 記憶的唯一識別碼（SQLite ID 或檔案路徑）
    輸出:
      JSON 格式統計
      範例: {"access_count":5,"last_accessed":"2026-02-01T12:00:00Z"}

輔助函式:
  increment_access_count <memory_file>
    更新檔案 frontmatter 的 access_count

  update_last_accessed <memory_file>
    更新檔案 frontmatter 的 last_accessed

  update_db_access <memory_id>
    更新 SQLite 資料庫中的存取記錄

範例:
  # 追蹤檔案存取
  track_access ".claude/memory/MEMORY.md"

  # 追蹤資料庫記憶存取
  track_access "123"

  # 取得存取統計
  stats=$(get_access_stats ".claude/memory/MEMORY.md")
  echo "$stats"

CLI 介面:
  # 追蹤存取
  memory-access-track.sh track .claude/memory/MEMORY.md

  # 取得統計
  memory-access-track.sh stats .claude/memory/MEMORY.md

  # 幫助
  memory-access-track.sh help

返回碼:
  0 - 成功
  1 - 一般錯誤
  2 - 檔案不存在
  3 - 資料庫不存在
  4 - 鎖定失敗

功能:
  - 原子性更新（使用 flock 檔案鎖定）
  - 同時更新檔案 frontmatter 和資料庫
  - 支援檔案路徑和資料庫 ID
  - 優雅降級（flock 不可用時仍可運作）
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試和直接使用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        track)
            shift
            track_access "$@"
            exit $?
            ;;
        stats)
            shift
            get_access_stats "$@"
            exit $?
            ;;
        increment)
            shift
            increment_access_count "$@"
            exit $?
            ;;
        update-time)
            shift
            update_last_accessed "$@"
            exit $?
            ;;
        update-db)
            shift
            update_db_access "$@"
            exit $?
            ;;
        help|--help|-h|"")
            show_memory_access_track_help
            exit 0
            ;;
        *)
            echo "錯誤：未知命令: $1" >&2
            echo "使用 'memory-access-track.sh help' 查看使用說明" >&2
            exit $MEMTRACK_ERROR
            ;;
    esac
fi
