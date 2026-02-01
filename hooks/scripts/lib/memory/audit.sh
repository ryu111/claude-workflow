#!/usr/bin/env bash
# memory-audit.sh - 記憶寫入審計工具
# 功能：記錄所有記憶系統的寫入操作，提供審計追蹤
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-audit.sh"

set -euo pipefail

# 載入依賴
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/../core/common.sh"

# 載入 memory-provenance（取得 session_id）
if [ -z "${MEMORY_PROVENANCE_LOADED:-}" ]; then
    source "${SCRIPT_DIR}/memory-provenance.sh"
    readonly MEMORY_PROVENANCE_LOADED=1
fi

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 返回碼
readonly AUDIT_SUCCESS=0
readonly AUDIT_ERROR=1

# 審計日誌檔案
readonly AUDIT_LOG_DIR="${PWD}/.claude/memory/.audit"
readonly AUDIT_LOG_FILE="${AUDIT_LOG_DIR}/write-log.jsonl"

# 操作類型
readonly ACTION_WRITE="write"
readonly ACTION_UPDATE="update"
readonly ACTION_DELETE="delete"
readonly ACTION_BLOCKED="blocked"

# 來源類型（對應 memory-provenance.sh）
readonly AUDIT_SOURCE_USER="user"
readonly AUDIT_SOURCE_AGENT_IMPLICIT="agent_implicit"
readonly AUDIT_SOURCE_SYSTEM="system"

# 審計日誌保留期限（天）
readonly AUDIT_RETENTION_DAYS=90

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 計算內容雜湊（sha256，取前 16 字元）
# 用法: compute_content_hash "content"
# 輸出: 16 字元的 sha256 雜湊值
compute_content_hash() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        echo "0000000000000000"
        return $AUDIT_SUCCESS
    fi

    # 使用 shasum -a 256（與 atomic-write.sh 一致）
    local hash
    hash=$(printf '%s' "$content" | shasum -a 256 | awk '{print $1}' | cut -c1-16)

    printf '%s\n' "$hash"
}

# 記錄審計日誌（內部函式）
# 用法: _write_audit_log json_line
# 返回: 0=成功，1=失敗
_write_audit_log() {
    local json_line="${1:-}"

    if [ -z "$json_line" ]; then
        echo "錯誤：_write_audit_log 需要提供 JSON 內容" >&2
        return $AUDIT_ERROR
    fi

    # 確保審計目錄存在
    ensure_directory "$AUDIT_LOG_DIR" || return $AUDIT_ERROR

    # 追加寫入 JSONL（每行一個 JSON）
    if ! echo "$json_line" >> "$AUDIT_LOG_FILE" 2>/dev/null; then
        echo "錯誤：無法寫入審計日誌: $AUDIT_LOG_FILE" >&2
        return $AUDIT_ERROR
    fi

    # 確保審計日誌檔案權限為 600
    chmod 600 "$AUDIT_LOG_FILE" 2>/dev/null || true

    return $AUDIT_SUCCESS
}

# 記錄記憶寫入操作
# 用法: audit_memory_write action file [content_hash] [source] [agent] [blocked_reason]
# 參數:
#   action         - 操作類型 (write|update|delete|blocked)
#   file           - 被操作的檔案路徑
#   content_hash   - 可選，內容雜湊（如果為空則自動計算）
#   source         - 可選，來源 (user|agent_implicit|system，預設 user)
#   agent          - 可選，執行的 Agent（預設 main）
#   blocked_reason - 可選，被阻擋的原因（僅 action=blocked 時使用）
# 返回: 0=成功，1=失敗
audit_memory_write() {
    local action="${1:-}"
    local file="${2:-}"
    local content_hash="${3:-}"
    local source="${4:-$AUDIT_SOURCE_USER}"
    local agent="${5:-main}"
    local blocked_reason="${6:-}"

    # 驗證必填參數
    if [ -z "$action" ]; then
        echo "錯誤：audit_memory_write 需要提供 action" >&2
        return $AUDIT_ERROR
    fi

    if [ -z "$file" ]; then
        echo "錯誤：audit_memory_write 需要提供 file" >&2
        return $AUDIT_ERROR
    fi

    # 驗證 action
    case "$action" in
        "$ACTION_WRITE"|"$ACTION_UPDATE"|"$ACTION_DELETE"|"$ACTION_BLOCKED")
            # 合法
            ;;
        *)
            echo "錯誤：不合法的 action: $action" >&2
            echo "  合法值: $ACTION_WRITE, $ACTION_UPDATE, $ACTION_DELETE, $ACTION_BLOCKED" >&2
            return $AUDIT_ERROR
            ;;
    esac

    # 如果沒有提供 content_hash，使用空字串的雜湊
    if [ -z "$content_hash" ]; then
        content_hash=$(compute_content_hash "")
    fi

    # 取得時間戳
    local timestamp
    timestamp=$(get_timestamp)

    # 取得 Session ID（複用 memory-provenance.sh）
    local session_id
    session_id=$(get_current_session_id)

    # 轉義檔案路徑中的特殊字元
    local escaped_file
    escaped_file=$(printf '%s' "$file" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

    # 轉義 blocked_reason（如果有）
    local escaped_reason=""
    if [ -n "$blocked_reason" ]; then
        escaped_reason=$(printf '%s' "$blocked_reason" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    fi

    # 組裝 JSONL（單行 JSON）
    local json_line
    if [ -n "$blocked_reason" ]; then
        # 包含 blocked_reason
        json_line='{"timestamp":"'"$timestamp"'","action":"'"$action"'","file":"'"$escaped_file"'","content_hash":"'"$content_hash"'","source":"'"$source"'","agent":"'"$agent"'","blocked_reason":"'"$escaped_reason"'","session_id":"'"$session_id"'"}'
    else
        # 不包含 blocked_reason（減少檔案大小）
        json_line='{"timestamp":"'"$timestamp"'","action":"'"$action"'","file":"'"$escaped_file"'","content_hash":"'"$content_hash"'","source":"'"$source"'","agent":"'"$agent"'","session_id":"'"$session_id"'"}'
    fi

    # 寫入審計日誌
    _write_audit_log "$json_line"
}

# 取得審計記錄
# 用法: get_audit_log [limit] [filter]
# 參數:
#   limit  - 可選，限制返回數量（預設 100）
#   filter - 可選，過濾條件（grep pattern）
# 輸出: JSONL 格式的審計記錄
get_audit_log() {
    local limit="${1:-100}"
    local filter="${2:-}"

    if [ ! -f "$AUDIT_LOG_FILE" ]; then
        echo "審計日誌檔案不存在: $AUDIT_LOG_FILE" >&2
        return $AUDIT_ERROR
    fi

    # 如果有過濾條件
    if [ -n "$filter" ]; then
        if command -v grep >/dev/null 2>&1; then
            grep "$filter" "$AUDIT_LOG_FILE" 2>/dev/null | tail -n "$limit"
        else
            tail -n "$limit" "$AUDIT_LOG_FILE"
        fi
    else
        tail -n "$limit" "$AUDIT_LOG_FILE"
    fi

    return $AUDIT_SUCCESS
}

# 清理過期審計記錄（保留最近 90 天）
# 用法: cleanup_old_audit_logs
# 返回: 0=成功，1=失敗
cleanup_old_audit_logs() {
    if [ ! -f "$AUDIT_LOG_FILE" ]; then
        # 沒有審計日誌，無需清理
        return $AUDIT_SUCCESS
    fi

    # 計算 90 天前的時間戳（Unix 時間）
    local cutoff_time
    cutoff_time=$(date -u -v-${AUDIT_RETENTION_DAYS}d +%s 2>/dev/null || date -u -d "${AUDIT_RETENTION_DAYS} days ago" +%s 2>/dev/null)

    if [ -z "$cutoff_time" ]; then
        echo "警告：無法計算過期時間，跳過清理" >&2
        return $AUDIT_ERROR
    fi

    # 暫存檔案
    local temp_file="${AUDIT_LOG_FILE}.tmp"

    # 過濾保留最近的記錄
    while IFS= read -r line; do
        # 提取 timestamp 欄位（簡單的字串解析）
        local timestamp
        timestamp=$(echo "$line" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)

        if [ -z "$timestamp" ]; then
            # 無法解析時間戳，保留該行（安全策略）
            echo "$line" >> "$temp_file"
            continue
        fi

        # 轉換 ISO 8601 為 Unix 時間戳
        local record_time
        record_time=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null || date -u -d "$timestamp" +%s 2>/dev/null)

        if [ -z "$record_time" ]; then
            # 無法轉換，保留該行（安全策略）
            echo "$line" >> "$temp_file"
            continue
        fi

        # 如果記錄時間 >= 過期時間，保留
        if [ "$record_time" -ge "$cutoff_time" ]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$AUDIT_LOG_FILE"

    # 替換原檔案
    if [ -f "$temp_file" ]; then
        mv "$temp_file" "$AUDIT_LOG_FILE" || {
            echo "錯誤：無法更新審計日誌" >&2
            rm -f "$temp_file"
            return $AUDIT_ERROR
        }

        # 確保權限正確
        chmod 600 "$AUDIT_LOG_FILE" 2>/dev/null || true

        echo "審計日誌清理完成（保留 ${AUDIT_RETENTION_DAYS} 天內的記錄）"
    fi

    return $AUDIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示審計統計
# 用法: show_audit_stats
show_audit_stats() {
    if [ ! -f "$AUDIT_LOG_FILE" ]; then
        echo "無審計記錄"
        return $AUDIT_SUCCESS
    fi

    local total_count
    total_count=$(wc -l < "$AUDIT_LOG_FILE" | tr -d ' ')

    echo "═══════════════════════════════════════"
    echo "記憶寫入審計統計"
    echo "═══════════════════════════════════════"
    echo "總記錄數: $total_count"
    echo ""

    # 統計各操作類型
    echo "操作類型分布:"
    grep -o '"action":"[^"]*"' "$AUDIT_LOG_FILE" 2>/dev/null | cut -d'"' -f4 | sort | uniq -c | sort -rn || echo "  無資料"
    echo ""

    # 統計來源分布
    echo "來源分布:"
    grep -o '"source":"[^"]*"' "$AUDIT_LOG_FILE" 2>/dev/null | cut -d'"' -f4 | sort | uniq -c | sort -rn || echo "  無資料"
    echo ""

    # 統計被阻擋的操作
    local blocked_count
    blocked_count=$(grep -c '"action":"blocked"' "$AUDIT_LOG_FILE" 2>/dev/null || echo "0")
    echo "被阻擋操作: $blocked_count"
    echo ""

    # 顯示最近 5 條記錄
    echo "最近 5 條記錄:"
    tail -n 5 "$AUDIT_LOG_FILE" 2>/dev/null | while IFS= read -r line; do
        local timestamp action file
        timestamp=$(echo "$line" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
        action=$(echo "$line" | grep -o '"action":"[^"]*"' | cut -d'"' -f4)
        file=$(echo "$line" | grep -o '"file":"[^"]*"' | cut -d'"' -f4)
        echo "  [$timestamp] $action - $file"
    done || echo "  無資料"

    echo "═══════════════════════════════════════"
}

# 顯示使用說明
show_audit_help() {
    cat <<'EOF'
記憶寫入審計工具 (Memory Write Audit)

用法:
  source memory-audit.sh

函式:
  compute_content_hash <content>
    計算內容的 sha256 雜湊（前 16 字元）
    參數: content - 要計算雜湊的內容
    輸出: 16 字元的雜湊值

  audit_memory_write <action> <file> [content_hash] [source] [agent] [blocked_reason]
    記錄記憶寫入操作
    參數:
      action         - 操作類型 (write|update|delete|blocked)
      file           - 被操作的檔案路徑
      content_hash   - 可選，內容雜湊（如果為空則自動計算）
      source         - 可選，來源 (user|agent_implicit|system，預設 user)
      agent          - 可選，執行的 Agent（預設 main）
      blocked_reason - 可選，被阻擋的原因（僅 action=blocked 時使用）
    返回: 0=成功，1=失敗

  get_audit_log [limit] [filter]
    取得審計記錄
    參數:
      limit  - 可選，限制返回數量（預設 100）
      filter - 可選，過濾條件（grep pattern）
    輸出: JSONL 格式的審計記錄

  cleanup_old_audit_logs
    清理過期審計記錄（保留最近 90 天）
    返回: 0=成功，1=失敗

  show_audit_stats
    顯示審計統計資訊

範例:
  # 記錄成功寫入
  hash=$(compute_content_hash "記憶內容")
  audit_memory_write "write" "MEMORY.md" "$hash" "user" "main"

  # 記錄更新操作
  audit_memory_write "update" "sessions/2024-01-01.jsonl" "$hash" "agent_implicit" "developer"

  # 記錄被阻擋的操作
  audit_memory_write "blocked" "MEMORY.md" "$hash" "user" "main" "pii_detected"

  # 取得最近 50 條記錄
  get_audit_log 50

  # 取得包含 "blocked" 的記錄
  get_audit_log 100 "blocked"

  # 清理過期記錄
  cleanup_old_audit_logs

  # 顯示統計
  show_audit_stats

操作類型:
  - write   : 新建檔案
  - update  : 更新現有檔案
  - delete  : 刪除檔案
  - blocked : 操作被阻擋

來源類型:
  - user           : 用戶明確觸發
  - agent_implicit : Agent 自動執行
  - system         : 系統自動執行

審計日誌格式 (JSONL):
  每行一個 JSON 物件，包含以下欄位：
  - timestamp      : ISO 8601 時間戳
  - action         : 操作類型
  - file           : 檔案路徑
  - content_hash   : 內容雜湊（前 16 字元）
  - source         : 來源類型
  - agent          : 執行的 Agent
  - blocked_reason : 被阻擋原因（僅 action=blocked）
  - session_id     : Session ID

審計日誌位置:
  .claude/memory/.audit/write-log.jsonl

保留期限:
  90 天（超過自動清理）
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        hash)
            shift
            compute_content_hash "$@"
            exit $?
            ;;
        audit)
            shift
            audit_memory_write "$@"
            exit $?
            ;;
        get)
            shift
            get_audit_log "$@"
            exit $?
            ;;
        cleanup)
            cleanup_old_audit_logs
            exit $?
            ;;
        stats)
            show_audit_stats
            exit 0
            ;;
        help|--help|-h|*)
            show_audit_help
            exit 0
            ;;
    esac
fi
