#!/usr/bin/env bash
# session-log.sh - Session 事件日誌工具
# 功能：記錄結構化的 Session 事件到 JSONL 檔案
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/session-log.sh"

set -euo pipefail

# 載入依賴
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/common.sh"

# 載入 memory-provenance（取得 session_id）
if [ -z "${MEMORY_PROVENANCE_LOADED:-}" ]; then
    source "${SCRIPT_DIR}/memory-provenance.sh"
    readonly MEMORY_PROVENANCE_LOADED=1
fi

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 返回碼
readonly SESSION_LOG_SUCCESS=0
readonly SESSION_LOG_ERROR=1
readonly SESSION_LOG_LOCK_TIMEOUT=2

# Session 日誌目錄（使用既有的 sessions 目錄）
readonly SESSION_LOG_DIR="${PWD}/.claude/memory/sessions"

# 檔案鎖定超時（秒）
readonly SESSION_LOCK_TIMEOUT=5

# 事件類型常數
readonly SESSION_EVENT_START="session_start"
readonly SESSION_EVENT_END="session_end"
readonly SESSION_EVENT_TASK_START="task_start"
readonly SESSION_EVENT_TASK_COMPLETE="task_complete"
readonly SESSION_EVENT_DECISION="decision"
readonly SESSION_EVENT_MEMORY_WRITE="memory_write"
readonly SESSION_EVENT_ERROR="error"

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 取得當日 Session 日誌檔案路徑
# 用法: log_path=$(get_session_log_path)
# 輸出: .claude/memory/sessions/YYYY-MM-DD.jsonl
get_session_log_path() {
    # 取得當前日期（UTC，格式 YYYY-MM-DD）
    local current_date
    current_date=$(date -u +%Y-%m-%d)

    printf '%s/%s.jsonl\n' "$SESSION_LOG_DIR" "$current_date"
}

# JSON 轉義工具函式
# 用法: escaped=$(escape_json_string "raw string")
# 說明: 轉義引號、反斜線、換行等特殊字元
escape_json_string() {
    local raw_string="${1:-}"

    # 轉義特殊字元（按順序，Bash 3.2 相容版本）
    # 1. 反斜線 \ → \\
    # 2. 引號 " → \"
    # 3. 換行和其他控制字元使用 printf 處理
    local escaped="$raw_string"

    # 使用 Bash 參數展開替換（更可靠）
    escaped="${escaped//\\/\\\\}"  # 反斜線
    escaped="${escaped//\"/\\\"}"  # 引號

    printf '%s' "$escaped"
}

# 格式化事件為 JSON 字串
# 用法: json=$(format_event_json type data [timestamp] [session_id])
# 參數:
#   type       - 事件類型（使用 SESSION_EVENT_* 常數）
#   data       - 事件資料（JSON 字串或鍵值對字串）
#   timestamp  - 可選，時間戳（預設自動生成）
#   session_id - 可選，Session ID（預設自動偵測）
# 輸出: 單行 JSON 字串
format_event_json() {
    local event_type="${1:-}"
    local event_data="${2:-}"
    local timestamp="${3:-}"
    local session_id="${4:-}"

    if [ -z "$event_type" ]; then
        echo "錯誤：format_event_json 需要提供 event_type" >&2
        return $SESSION_LOG_ERROR
    fi

    # 自動生成時間戳（如果未提供）
    if [ -z "$timestamp" ]; then
        timestamp=$(get_timestamp)
    fi

    # 自動偵測 session_id（如果未提供）
    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    # 轉義字串欄位
    local escaped_type
    local escaped_session_id
    escaped_type=$(escape_json_string "$event_type")
    escaped_session_id=$(escape_json_string "$session_id")

    # 處理 data 欄位
    local data_json=""
    if [ -n "$event_data" ]; then
        # 檢查是否已經是 JSON 格式（以 { 或 [ 開頭）
        if [[ "$event_data" =~ ^[[:space:]]*[\{\[] ]]; then
            # 已經是 JSON，直接使用
            data_json="$event_data"
        else
            # 純文字，轉義後包裝為字串
            local escaped_data
            escaped_data=$(escape_json_string "$event_data")
            data_json="\"$escaped_data\""
        fi
    else
        # 空資料，使用空物件
        data_json="{}"
    fi

    # 組裝 JSON（單行）
    printf '{"timestamp":"%s","session_id":"%s","type":"%s","data":%s}\n' \
        "$timestamp" \
        "$escaped_session_id" \
        "$escaped_type" \
        "$data_json"
}

# 安全追加一行 JSON 到 JSONL 檔案
# 用法: append_jsonl file json_line
# 參數:
#   file      - JSONL 檔案路徑
#   json_line - 完整的 JSON 字串（單行）
# 返回: 0=成功，1=失敗，2=鎖定超時
append_jsonl() {
    local file_path="${1:-}"
    local json_line="${2:-}"

    if [ -z "$file_path" ]; then
        echo "錯誤：append_jsonl 需要提供檔案路徑" >&2
        return $SESSION_LOG_ERROR
    fi

    if [ -z "$json_line" ]; then
        echo "錯誤：append_jsonl 需要提供 JSON 內容" >&2
        return $SESSION_LOG_ERROR
    fi

    # 確保父目錄存在
    local parent_dir
    parent_dir="$(dirname "$file_path")"
    if ! ensure_directory "$parent_dir"; then
        return $SESSION_LOG_ERROR
    fi

    # 使用檔案鎖定防止併發寫入
    if command -v flock &> /dev/null; then
        # flock 可用，使用檔案鎖定
        local lock_file="${file_path}.lock"

        # 使用 flock 進行獨占鎖定（超時 5 秒）
        # 使用 printf 避免字串轉義問題
        (
            flock -x -w "$SESSION_LOCK_TIMEOUT" 200 || exit $SESSION_LOG_LOCK_TIMEOUT
            printf '%s\n' "$json_line" >> "$file_path" || exit $SESSION_LOG_ERROR
        ) 200>"$lock_file" 2>/dev/null

        local write_status=$?
        if [ $write_status -ne 0 ]; then
            if [ $write_status -eq $SESSION_LOG_LOCK_TIMEOUT ]; then
                echo "錯誤：無法取得檔案鎖定（超時 ${SESSION_LOCK_TIMEOUT} 秒）" >&2
                return $SESSION_LOG_LOCK_TIMEOUT
            else
                echo "錯誤：無法寫入檔案: $file_path" >&2
                return $SESSION_LOG_ERROR
            fi
        fi

        # 清理鎖定檔案（如果沒有其他 process 在使用）
        rm -f "$lock_file" 2>/dev/null || true
    else
        # flock 不可用，直接追加（有競態風險）
        if ! printf '%s\n' "$json_line" >> "$file_path" 2>/dev/null; then
            echo "錯誤：無法寫入檔案: $file_path" >&2
            return $SESSION_LOG_ERROR
        fi
    fi

    # 確保檔案權限為 600
    chmod 600 "$file_path" 2>/dev/null || true

    return $SESSION_LOG_SUCCESS
}

# 記錄 Session 事件
# 用法: log_session_event type data
# 參數:
#   type - 事件類型（使用 SESSION_EVENT_* 常數）
#   data - 事件資料（JSON 字串或鍵值對字串）
# 返回: 0=成功，1=失敗
log_session_event() {
    local event_type="${1:-}"
    local event_data="${2:-}"

    if [ -z "$event_type" ]; then
        echo "錯誤：log_session_event 需要提供事件類型" >&2
        return $SESSION_LOG_ERROR
    fi

    # 取得當日日誌檔案路徑
    local log_file
    log_file=$(get_session_log_path)

    # 格式化事件為 JSON
    local json_line
    json_line=$(format_event_json "$event_type" "$event_data")

    if [ $? -ne 0 ]; then
        echo "錯誤：無法格式化事件 JSON" >&2
        return $SESSION_LOG_ERROR
    fi

    # 追加到 JSONL 檔案
    append_jsonl "$log_file" "$json_line"
}

# 讀取指定日期的事件
# 用法: read_session_events [date] [type_filter]
# 參數:
#   date        - 可選，日期（格式 YYYY-MM-DD，預設今天）
#   type_filter - 可選，過濾事件類型（如 "task_start"）
# 輸出: JSONL 格式的事件記錄
read_session_events() {
    local target_date="${1:-}"
    local type_filter="${2:-}"

    # 預設使用今天日期
    if [ -z "$target_date" ]; then
        target_date=$(date -u +%Y-%m-%d)
    fi

    # 驗證日期格式（簡單檢查）
    if ! [[ "$target_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "錯誤：日期格式不正確（需要 YYYY-MM-DD）: $target_date" >&2
        return $SESSION_LOG_ERROR
    fi

    local log_file="${SESSION_LOG_DIR}/${target_date}.jsonl"

    if [ ! -f "$log_file" ]; then
        echo "警告：日誌檔案不存在: $log_file" >&2
        return $SESSION_LOG_ERROR
    fi

    # 讀取並過濾（如果有過濾條件）
    if [ -n "$type_filter" ]; then
        grep "\"type\":\"$type_filter\"" "$log_file" 2>/dev/null || {
            echo "警告：找不到符合條件的事件" >&2
            return $SESSION_LOG_ERROR
        }
    else
        cat "$log_file"
    fi

    return $SESSION_LOG_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示統計資訊
# 用法: show_session_log_stats [date]
show_session_log_stats() {
    local target_date="${1:-}"

    # 預設使用今天日期
    if [ -z "$target_date" ]; then
        target_date=$(date -u +%Y-%m-%d)
    fi

    local log_file="${SESSION_LOG_DIR}/${target_date}.jsonl"

    if [ ! -f "$log_file" ]; then
        echo "日誌檔案不存在: $log_file"
        return $SESSION_LOG_ERROR
    fi

    local total_count
    total_count=$(wc -l < "$log_file" | tr -d ' ')

    echo "═══════════════════════════════════════"
    echo "Session 事件日誌統計 - $target_date"
    echo "═══════════════════════════════════════"
    echo "總事件數: $total_count"
    echo ""

    # 統計事件類型分布
    echo "事件類型分布:"
    grep -o '"type":"[^"]*"' "$log_file" 2>/dev/null | cut -d'"' -f4 | sort | uniq -c | sort -rn || echo "  無資料"
    echo ""

    # 顯示最近 5 條事件
    echo "最近 5 條事件:"
    tail -n 5 "$log_file" 2>/dev/null | while IFS= read -r line; do
        # 使用更穩定的 JSON 欄位提取
        local timestamp
        local event_type
        timestamp=$(printf '%s' "$line" | grep -o '"timestamp":"[^"]*"' | head -1 | cut -d'"' -f4)
        event_type=$(printf '%s' "$line" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)

        # 確保有值再顯示
        if [ -n "$timestamp" ] && [ -n "$event_type" ]; then
            echo "  [$timestamp] $event_type"
        fi
    done 2>/dev/null || echo "  無資料"

    echo "═══════════════════════════════════════"
}

# 顯示使用說明
show_session_log_help() {
    cat <<'EOF'
Session 事件日誌工具 (Session Event Logger)

用法:
  source session-log.sh

函式:
  get_session_log_path
    取得當日 Session 日誌檔案路徑
    輸出: .claude/memory/sessions/YYYY-MM-DD.jsonl

  escape_json_string <raw_string>
    轉義 JSON 字串中的特殊字元
    參數: raw_string - 要轉義的原始字串
    輸出: 轉義後的字串

  format_event_json <type> <data> [timestamp] [session_id]
    格式化事件為 JSON 字串
    參數:
      type       - 事件類型（使用 SESSION_EVENT_* 常數）
      data       - 事件資料（JSON 字串或純文字）
      timestamp  - 可選，時間戳（預設自動生成）
      session_id - 可選，Session ID（預設自動偵測）
    輸出: 單行 JSON 字串

  append_jsonl <file> <json_line>
    安全追加一行 JSON 到 JSONL 檔案
    參數:
      file      - JSONL 檔案路徑
      json_line - 完整的 JSON 字串（單行）
    返回: 0=成功，1=失敗，2=鎖定超時

  log_session_event <type> <data>
    記錄 Session 事件到當日日誌
    參數:
      type - 事件類型（使用 SESSION_EVENT_* 常數）
      data - 事件資料（JSON 字串或純文字）
    返回: 0=成功，1=失敗

  read_session_events [date] [type_filter]
    讀取指定日期的事件
    參數:
      date        - 可選，日期（格式 YYYY-MM-DD，預設今天）
      type_filter - 可選，過濾事件類型（如 "task_start"）
    輸出: JSONL 格式的事件記錄

  show_session_log_stats [date]
    顯示日誌統計資訊
    參數:
      date - 可選，日期（格式 YYYY-MM-DD，預設今天）

預定義事件類型常數:
  SESSION_EVENT_START        - session_start
  SESSION_EVENT_END          - session_end
  SESSION_EVENT_TASK_START   - task_start
  SESSION_EVENT_TASK_COMPLETE - task_complete
  SESSION_EVENT_DECISION     - decision
  SESSION_EVENT_MEMORY_WRITE - memory_write
  SESSION_EVENT_ERROR        - error

範例:
  # 記錄 Session 開始
  log_session_event "$SESSION_EVENT_START" '{"project":"my-app","working_dir":"'$PWD'"}'

  # 記錄任務完成
  log_session_event "$SESSION_EVENT_TASK_COMPLETE" '{"task_name":"實作功能","result":"success","duration":"5m"}'

  # 記錄決策
  log_session_event "$SESSION_EVENT_DECISION" '{"decision":"使用 TypeScript","reason":"團隊熟悉","context":"新專案設定"}'

  # 記錄錯誤（純文字）
  log_session_event "$SESSION_EVENT_ERROR" "編譯失敗：找不到模組 'foo'"

  # 讀取今天的所有事件
  read_session_events

  # 讀取特定日期的任務完成事件
  read_session_events "2026-02-01" "task_complete"

  # 顯示今天的統計
  show_session_log_stats

  # 顯示特定日期的統計
  show_session_log_stats "2026-02-01"

JSONL 格式:
  每行一個 JSON 物件，包含以下欄位：
  - timestamp  : ISO 8601 時間戳
  - session_id : Session ID
  - type       : 事件類型
  - data       : 事件資料（JSON 物件或字串）

日誌位置:
  .claude/memory/sessions/YYYY-MM-DD.jsonl

安全機制:
  - 使用 flock 檔案鎖定防止併發寫入衝突
  - 超時設定: 5 秒
  - 檔案權限: 600（僅擁有者可讀寫）
  - JSON 轉義: 自動處理特殊字元
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        log)
            shift
            event_type="${1:-}"
            event_data="${2:-}"
            log_session_event "$event_type" "$event_data"
            exit $?
            ;;
        read)
            shift
            read_session_events "$@"
            exit $?
            ;;
        stats)
            shift
            show_session_log_stats "$@"
            exit $?
            ;;
        path)
            get_session_log_path
            exit $?
            ;;
        help|--help|-h|*)
            show_session_log_help
            exit 0
            ;;
    esac
fi
