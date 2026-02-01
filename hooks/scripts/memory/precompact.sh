#!/usr/bin/env bash
# memory-precompact.sh - Pre-Compaction Flush Hook
# 功能：在 Context 即將被壓縮時，強制提取並保存當前 Session 的關鍵決策和未完成任務
# 觸發時機：PreCompact Hook
# 使用方式：由 PreCompact Hook 自動觸發，或手動執行測試
# 相容性：Bash 3.2+（macOS 預設版本）

# 注意：不使用 set -e，因為我們需要優雅處理錯誤
set -uo pipefail

# 載入依賴模組
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 載入所有模組
# 注意：許多模組重複定義了相同的 readonly 常數，會產生警告但不影響功能

# 使用 Bash 3.2 相容的方式：先關閉 errexit，然後靜默載入
set +e  # 暫時關閉錯誤中斷
set +u  # 暫時關閉未定義變數檢查

# 載入模組（僅載入必要的，避免 readonly 衝突）
. "${LIB_DIR}/core/common.sh" 2>/dev/null
. "${LIB_DIR}/memory/sanitize.sh" 2>/dev/null

# 其他功能通過 CLI 介面呼叫（避免 readonly 衝突）
# - memory-audit.sh: 呼叫 bash "${LIB_DIR}/memory/audit.sh" audit ...
# - circuit-breaker.sh: 呼叫 bash "${LIB_DIR}/core/circuit-breaker.sh" is-open
# - kill-switch.sh: 呼叫 bash "${LIB_DIR}/core/kill-switch.sh" check

# 恢復 set 選項
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# 常數定義（使用 PRECOMPACT_ 前綴避免與載入模組的常數衝突）
# ═══════════════════════════════════════════════════════════════

# 返回碼（不使用 readonly，避免衝突）
PRECOMPACT_SUCCESS=0
PRECOMPACT_ERROR=1
PRECOMPACT_SKIPPED=2

# Session 記憶目錄
SESSION_MEMORY_DIR="${PWD}/.claude/memory/sessions"

# 預設來源類型（系統自動生成）
PRECOMPACT_SOURCE="system"
PRECOMPACT_AGENT="main"

# ═══════════════════════════════════════════════════════════════
# 內部輔助函式（避免外部依賴）
# ═══════════════════════════════════════════════════════════════

# 取得當前 Session ID（簡化版本）
# 用法: session_id=$(get_current_session_id)
get_current_session_id() {
    local session_id="${CLAUDE_SESSION_ID:-}"

    # Fallback 到 E2E_SESSION_ID（測試環境）
    if [ -z "$session_id" ] || [ "$session_id" = "null" ]; then
        session_id="${E2E_SESSION_ID:-}"
    fi

    # Fallback 到 default
    if [ -z "$session_id" ] || [ "$session_id" = "null" ]; then
        session_id="default"
    fi

    printf '%s\n' "$session_id"
}

# 檢查記憶系統是否禁用（通過 CLI）
# 用法: if is_memory_disabled; then ...
is_memory_disabled() {
    bash "${LIB_DIR}/core/kill-switch.sh" check >/dev/null 2>&1
    local status=$?
    [ $status -eq 1 ]  # 返回碼 1 表示完全禁用
}

# 檢查熔斷器是否開啟（通過 CLI）
# 用法: if is_circuit_breaker_open; then ...
is_circuit_breaker_open() {
    bash "${LIB_DIR}/core/circuit-breaker.sh" is-open >/dev/null 2>&1
}

# 記錄失敗到熔斷器（通過 CLI）
# 用法: record_failure
record_failure() {
    bash "${LIB_DIR}/core/circuit-breaker.sh" record-failure >/dev/null 2>&1
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：內容提取
# ═══════════════════════════════════════════════════════════════

# 從 Context Summary 提取關鍵決策
# 用法: extract_key_decisions <context_summary>
# 輸出: JSON 陣列格式的關鍵決策
extract_key_decisions() {
    local context_summary="${1:-}"

    if [ -z "$context_summary" ]; then
        echo "[]"
        return $PRECOMPACT_SUCCESS
    fi

    # 簡單的關鍵字匹配提取（未來可擴展為 LLM 提取）
    local decisions=()

    # 提取架構決策
    if echo "$context_summary" | grep -qi "架構\|architecture\|設計\|design"; then
        local arch_decision=$(echo "$context_summary" | grep -i "架構\|architecture\|設計\|design" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$arch_decision" ]; then
            decisions+=("$arch_decision")
        fi
    fi

    # 提取技術選型
    if echo "$context_summary" | grep -qi "選擇\|使用\|採用\|use\|using\|choose"; then
        local tech_decision=$(echo "$context_summary" | grep -i "選擇\|使用\|採用\|use\|using\|choose" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$tech_decision" ]; then
            decisions+=("$tech_decision")
        fi
    fi

    # 提取用戶偏好
    if echo "$context_summary" | grep -qi "偏好\|prefer\|喜歡\|like"; then
        local pref_decision=$(echo "$context_summary" | grep -i "偏好\|prefer\|喜歡\|like" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$pref_decision" ]; then
            decisions+=("$pref_decision")
        fi
    fi

    # 如果沒有提取到任何決策，返回空陣列
    if [ ${#decisions[@]} -eq 0 ]; then
        echo "[]"
        return $PRECOMPACT_SUCCESS
    fi

    # 組裝 JSON 陣列
    echo "["
    local first=true
    for decision in "${decisions[@]}"; do
        # 轉義 JSON 特殊字元
        local escaped_decision=$(printf '%s' "$decision" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')

        if [ "$first" = true ]; then
            printf '  "%s"' "$escaped_decision"
            first=false
        else
            printf ',\n  "%s"' "$escaped_decision"
        fi
    done
    echo ""
    echo "]"
}

# 從 Context Summary 提取未完成任務
# 用法: extract_pending_tasks <current_tasks_json>
# 參數: current_tasks_json - JSON 陣列格式的當前任務
# 輸出: JSON 陣列格式的未完成任務
extract_pending_tasks() {
    local current_tasks_json="${1:-[]}"

    if [ "$current_tasks_json" = "null" ] || [ -z "$current_tasks_json" ]; then
        echo "[]"
        return $PRECOMPACT_SUCCESS
    fi

    # 使用 jq 過濾 in_progress 和 pending 狀態的任務（如果 jq 可用）
    if command -v jq >/dev/null 2>&1; then
        echo "$current_tasks_json" | jq '[.[] | select(.status == "in_progress" or .status == "pending")]' 2>/dev/null || echo "[]"
    else
        # Fallback：簡單的字串處理（假設簡單的 JSON 格式）
        local tasks=()

        # 提取包含 in_progress 或 pending 的行
        while IFS= read -r line; do
            if echo "$line" | grep -q '"status"[[:space:]]*:[[:space:]]*"\(in_progress\|pending\)"'; then
                tasks+=("$line")
            fi
        done <<< "$current_tasks_json"

        if [ ${#tasks[@]} -eq 0 ]; then
            echo "[]"
        else
            echo "["
            printf '  %s' "${tasks[0]}"
            for task in "${tasks[@]:1}"; do
                printf ',\n  %s' "$task"
            done
            echo ""
            echo "]"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：Session 記憶寫入
# ═══════════════════════════════════════════════════════════════

# 格式化 Session 記憶條目
# 用法: format_session_entry <decisions_json> <tasks_json> <summary>
# 輸出: 單行 JSONL 格式
format_session_entry() {
    local decisions_json="${1:-[]}"
    local tasks_json="${2:-[]}"
    local summary="${3:-}"

    # 取得時間戳和 Session ID
    local timestamp=$(get_timestamp)
    local session_id=$(get_current_session_id)

    # 轉義 summary
    local escaped_summary=$(printf '%s' "$summary" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')

    # 組裝 JSONL（單行 JSON）
    # 注意：需要壓縮多行 JSON 成單行
    local compact_decisions=$(echo "$decisions_json" | tr -d '\n' | sed 's/[[:space:]]\+/ /g')
    local compact_tasks=$(echo "$tasks_json" | tr -d '\n' | sed 's/[[:space:]]\+/ /g')

    echo "{\"timestamp\":\"$timestamp\",\"session_id\":\"$session_id\",\"type\":\"precompact_flush\",\"decisions\":$compact_decisions,\"pending_tasks\":$compact_tasks,\"summary\":\"$escaped_summary\"}"
}

# 取得 Session 記憶檔案路徑
# 用法: get_session_memory_file
# 輸出: .claude/memory/sessions/YYYY-MM-DD.jsonl
get_session_memory_file() {
    local date_str=$(date -u +%Y-%m-%d)
    echo "${SESSION_MEMORY_DIR}/${date_str}.jsonl"
}

# 追加寫入 Session 記憶（使用檔案鎖定）
# 用法: append_session_memory <jsonl_entry>
# 返回: 0=成功，1=失敗
append_session_memory() {
    local jsonl_entry="${1:-}"

    if [ -z "$jsonl_entry" ]; then
        echo "錯誤：append_session_memory 需要提供 JSONL 條目" >&2
        return $PRECOMPACT_ERROR
    fi

    # 確保 Session 目錄存在
    ensure_directory "$SESSION_MEMORY_DIR" || {
        echo "錯誤：無法建立 Session 記憶目錄" >&2
        return $PRECOMPACT_ERROR
    }

    local session_file=$(get_session_memory_file)

    # 使用 flock 確保原子性追加（如果可用）
    if command -v flock >/dev/null 2>&1; then
        # 使用檔案鎖定
        local lock_file="${session_file}.lock"
        (
            flock -x 200 || {
                echo "錯誤：無法取得檔案鎖定" >&2
                return $PRECOMPACT_ERROR
            }

            # 追加寫入
            echo "$jsonl_entry" >> "$session_file" 2>/dev/null || {
                echo "錯誤：無法寫入 Session 記憶檔案" >&2
                return $PRECOMPACT_ERROR
            }

        ) 200>"$lock_file"
    else
        # 無 flock，直接追加（可能有競態風險）
        echo "$jsonl_entry" >> "$session_file" 2>/dev/null || {
            echo "錯誤：無法寫入 Session 記憶檔案" >&2
            return $PRECOMPACT_ERROR
        }
    fi

    # 確保檔案權限為 600
    chmod 600 "$session_file" 2>/dev/null || true

    return $PRECOMPACT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 主要功能：Flush Session Memory
# ═══════════════════════════════════════════════════════════════

# 強制提取並保存當前 Session 的記憶
# 用法: flush_session_memory [context_summary] [current_tasks_json]
# 參數:
#   context_summary     - 可選，當前 Context 摘要（從環境變數或參數）
#   current_tasks_json  - 可選，當前任務 JSON（從環境變數或參數）
# 返回: 0=成功，1=失敗，2=跳過（Kill Switch 開啟）
flush_session_memory() {
    local context_summary="${1:-${PRECOMPACT_CONTEXT_SUMMARY:-}}"
    local current_tasks_json="${2:-${PRECOMPACT_CURRENT_TASKS:-[]}}"

    # 檢查 Kill Switch
    if is_memory_disabled; then
        echo "⚠️  記憶系統已禁用，跳過 Pre-Compaction Flush" >&2
        return $PRECOMPACT_SKIPPED
    fi

    # 檢查熔斷器
    if is_circuit_breaker_open; then
        echo "⚠️  熔斷器已開啟，跳過 Pre-Compaction Flush" >&2
        return $PRECOMPACT_SKIPPED
    fi

    # 步驟 1: 提取關鍵決策
    local decisions_json
    decisions_json=$(extract_key_decisions "$context_summary")

    # 步驟 2: 提取未完成任務
    local tasks_json
    tasks_json=$(extract_pending_tasks "$current_tasks_json")

    # 步驟 3: 格式化 Session 條目
    local jsonl_entry
    jsonl_entry=$(format_session_entry "$decisions_json" "$tasks_json" "$context_summary")

    # 步驟 4: 消毒內容（檢查惡意模式）
    if ! contains_malicious_content "$jsonl_entry"; then
        echo "🚫 偵測到惡意模式，拒絕寫入 Session 記憶" >&2

        # 記錄到審計日誌（通過 CLI）
        local session_file=$(get_session_memory_file)
        bash "${LIB_DIR}/memory/audit.sh" audit "blocked" "$session_file" "" "$PRECOMPACT_SOURCE" "$PRECOMPACT_AGENT" "malicious_pattern_detected" >/dev/null 2>&1 || true

        return $PRECOMPACT_ERROR
    fi

    # 步驟 5: 追加寫入
    if ! append_session_memory "$jsonl_entry"; then
        echo "錯誤：無法寫入 Session 記憶" >&2

        # 記錄失敗到熔斷器
        record_failure

        return $PRECOMPACT_ERROR
    fi

    # 步驟 6: 記錄審計日誌（通過 CLI）
    local session_file=$(get_session_memory_file)
    local content_hash=$(bash "${LIB_DIR}/memory/audit.sh" hash "$jsonl_entry" 2>/dev/null || echo "unknown")
    bash "${LIB_DIR}/memory/audit.sh" audit "write" "$session_file" "$content_hash" "$PRECOMPACT_SOURCE" "$PRECOMPACT_AGENT" >/dev/null 2>&1 || true

    echo "✅ Pre-Compaction Flush 完成：Session 記憶已保存到 $session_file" >&2
    return $PRECOMPACT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# Hook 整合介面
# ═══════════════════════════════════════════════════════════════

# PreCompact Hook 入口函式
# 用法: handle_precompact_hook <json_input>
# 參數: json_input - Hook 傳入的 JSON 格式輸入
# 返回: 0=成功，1=失敗，2=跳過
handle_precompact_hook() {
    local json_input="${1:-}"

    # 如果沒有提供 JSON 輸入，從 stdin 讀取
    if [ -z "$json_input" ]; then
        json_input=$(cat)
    fi

    # 解析 JSON（使用 jq 如果可用）
    local context_summary=""
    local current_tasks_json="[]"

    if command -v jq >/dev/null 2>&1; then
        context_summary=$(echo "$json_input" | jq -r '.context_summary // ""' 2>/dev/null || echo "")
        current_tasks_json=$(echo "$json_input" | jq -c '.current_tasks // []' 2>/dev/null || echo "[]")
    else
        # Fallback：簡單的字串提取（假設簡單的 JSON 格式）
        context_summary=$(echo "$json_input" | grep -o '"context_summary"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"context_summary"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/' || echo "")
    fi

    # 直接呼叫 flush_session_memory（容錯執行）
    # 注意：即使失敗也返回成功，確保不阻擋 compaction 流程
    if flush_session_memory "$context_summary" "$current_tasks_json" 2>/dev/null; then
        return $PRECOMPACT_SUCCESS
    else
        echo "⚠️  Pre-Compaction Flush 失敗，但不阻擋 compaction 流程" >&2
        return $PRECOMPACT_SUCCESS  # 返回成功以不阻擋 compaction
    fi
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_help() {
    cat <<'EOF'
Pre-Compaction Flush - 記憶防丟失最後防線

用法:
  # Hook 模式（由 PreCompact Hook 自動觸發）
  echo '{"context_summary":"...","current_tasks":[...]}' | memory-precompact.sh hook

  # 手動測試模式
  memory-precompact.sh flush "摘要內容" '[{"content":"任務","status":"in_progress"}]'

  # 提取決策測試
  memory-precompact.sh extract-decisions "用戶偏好使用 TypeScript，架構採用微服務"

  # 提取任務測試
  memory-precompact.sh extract-tasks '[{"content":"任務1","status":"in_progress"}]'

指令:
  hook                  處理 PreCompact Hook 輸入（從 stdin 讀取 JSON）
  flush <summary> [tasks] 手動執行 Flush（測試用）
  extract-decisions <text> 測試決策提取
  extract-tasks <json>  測試任務提取
  help                  顯示此說明

環境變數:
  PRECOMPACT_CONTEXT_SUMMARY  - Context 摘要
  PRECOMPACT_CURRENT_TASKS    - 當前任務 JSON

輸出位置:
  .claude/memory/sessions/YYYY-MM-DD.jsonl

JSONL 格式:
  {
    "timestamp": "2026-02-01T12:00:00Z",
    "session_id": "abc123",
    "type": "precompact_flush",
    "decisions": ["決策1", "決策2"],
    "pending_tasks": [{"content":"任務","status":"in_progress"}],
    "summary": "Context 摘要"
  }

安全機制:
  - Kill Switch 檢查（.disabled 檔案）
  - 熔斷器檢查（連續失敗自動停用）
  - 惡意模式偵測（memory-sanitize）
  - 檔案鎖定（flock，防止併發寫入）
  - safe_execute 包裝（容錯，不阻擋 compaction）
  - 審計日誌記錄（memory-audit）

返回碼:
  0 - 成功
  1 - 失敗
  2 - 跳過（Kill Switch 或熔斷器）

範例:
  # 模擬 PreCompact Hook
  echo '{"context_summary":"實作記憶系統","current_tasks":[{"content":"3.3 Pre-Compaction Flush","status":"in_progress"}]}' | \
    bash hooks/scripts/memory-precompact.sh hook
EOF
}

# 命令行介面入口
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        hook)
            handle_precompact_hook
            exit $?
            ;;
        flush)
            shift
            flush_session_memory "$@"
            exit $?
            ;;
        extract-decisions)
            shift
            extract_key_decisions "$@"
            exit $?
            ;;
        extract-tasks)
            shift
            extract_pending_tasks "$@"
            exit $?
            ;;
        help|--help|-h|*)
            show_help
            exit 0
            ;;
    esac
fi
