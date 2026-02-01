#!/usr/bin/env bash
# memory-daily-summary.sh - Daily Summary Generator
# 功能：彙總當日所有 Session 的 JSONL 記錄，生成 Markdown 格式的日報
# Hook: SessionEnd
# 使用方式：由 SessionEnd Hook 自動觸發，或手動執行測試
# 相容性：Bash 3.2+（macOS 預設版本）

# 注意：不使用 set -e，因為我們需要優雅處理錯誤
set -uo pipefail

# 載入依賴模組
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 使用 Bash 3.2 相容的方式：先關閉 errexit，然後靜默載入
set +e  # 暫時關閉錯誤中斷
set +u  # 暫時關閉未定義變數檢查

# 載入模組（stderr 導向 /dev/null 忽略 readonly 警告）
. "${LIB_DIR}/core/common.sh" 2>/dev/null
. "${LIB_DIR}/core/session-log.sh" 2>/dev/null

# 其他功能通過 CLI 介面呼叫（避免 readonly 衝突）
# - circuit-breaker.sh: 呼叫 bash "${LIB_DIR}/core/circuit-breaker.sh" is-open
# - kill-switch.sh: 呼叫 bash "${LIB_DIR}/core/kill-switch.sh" check
# - safe-execute.sh: 通過環境變數控制

# 恢復 set 選項
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# 常數定義（使用 DAILY_ 前綴避免與載入模組的常數衝突）
# ═══════════════════════════════════════════════════════════════

# 返回碼
DAILY_SUCCESS=0
DAILY_ERROR=1
DAILY_SKIPPED=2

# 目錄路徑
DAILY_SESSION_DIR="${PWD}/.claude/memory/sessions"
DAILY_OUTPUT_DIR="${PWD}/.claude/memory/daily"

# ═══════════════════════════════════════════════════════════════
# 內部輔助函式
# ═══════════════════════════════════════════════════════════════

# 檢查記憶系統是否禁用（通過 CLI）
# 用法: if is_daily_memory_disabled; then ...
is_daily_memory_disabled() {
    bash "${LIB_DIR}/core/kill-switch.sh" check >/dev/null 2>&1
    local status=$?
    [ $status -eq 1 ]  # 返回碼 1 表示完全禁用
}

# 檢查熔斷器是否開啟（通過 CLI）
# 用法: if is_daily_circuit_breaker_open; then ...
is_daily_circuit_breaker_open() {
    bash "${LIB_DIR}/core/circuit-breaker.sh" is-open >/dev/null 2>&1
}

# 記錄失敗到熔斷器（通過 CLI）
# 用法: record_daily_failure
record_daily_failure() {
    bash "${LIB_DIR}/core/circuit-breaker.sh" record-failure >/dev/null 2>&1
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：JSONL 彙總
# ═══════════════════════════════════════════════════════════════

# 彙總 JSONL 檔案中的事件統計
# 用法: aggregate_session_events <jsonl_file>
# 輸出: 多行格式的統計資訊（用於內部處理）
#   event_count=42
#   decisions=["決策1","決策2"]
#   tasks=["任務1","任務2"]
#   errors=["錯誤1"]
aggregate_session_events() {
    local jsonl_file="${1:-}"

    if [ -z "$jsonl_file" ]; then
        echo "錯誤：aggregate_session_events 需要提供 JSONL 檔案路徑" >&2
        return $DAILY_ERROR
    fi

    if [ ! -f "$jsonl_file" ]; then
        echo "錯誤：JSONL 檔案不存在: $jsonl_file" >&2
        return $DAILY_ERROR
    fi

    # 統計總事件數
    local event_count
    event_count=$(wc -l < "$jsonl_file" | tr -d ' ')

    # 使用臨時檔案收集資料（避免子 shell 問題）
    local temp_decisions="${TMPDIR:-/tmp}/daily_decisions_$$.txt"
    local temp_tasks="${TMPDIR:-/tmp}/daily_tasks_$$.txt"
    local temp_errors="${TMPDIR:-/tmp}/daily_errors_$$.txt"

    # 清空臨時檔案
    > "$temp_decisions"
    > "$temp_tasks"
    > "$temp_errors"

    # 逐行處理 JSONL
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue

        # 提取事件類型
        local event_type
        event_type=$(echo "$line" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)

        # 根據事件類型處理
        case "$event_type" in
            precompact_flush)
                # precompact_flush 格式：直接提取 decisions 欄位
                # 示例："decisions":["決策1","決策2"]
                local decision_array
                decision_array=$(echo "$line" | grep -o '"decisions":\[[^]]*\]' | sed 's/"decisions"://')
                if [ -n "$decision_array" ] && [ "$decision_array" != "[]" ]; then
                    # 提取陣列中的字串元素並追加到檔案
                    echo "$decision_array" | grep -o '"[^"]*"' | sed 's/^"//;s/"$//' | while read -r dec; do
                        [ -n "$dec" ] && echo "$dec" >> "$temp_decisions"
                    done
                fi
                ;;
            decision)
                # decision 格式：提取 data 欄位中的決策
                # 使用 sed 提取（處理轉義的引號）
                local decision_text
                decision_text=$(echo "$line" | sed -n 's/.*"data":"\([^}]*\)".*/\1/p')
                if [ -z "$decision_text" ]; then
                    # 嘗試從 JSON 物件中提取
                    decision_text=$(echo "$line" | sed -n 's/.*"decision":"\([^}]*\)".*/\1/p')
                fi
                # 還原轉義的引號
                decision_text=$(echo "$decision_text" | sed 's/\\"/"/g')
                if [ -n "$decision_text" ]; then
                    echo "$decision_text" >> "$temp_decisions"
                fi
                ;;
            task_complete)
                # 提取任務內容
                local task_name
                local task_result
                task_name=$(echo "$line" | grep -o '"task_name":"[^"]*"' | cut -d'"' -f4)
                task_result=$(echo "$line" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
                if [ -n "$task_name" ]; then
                    if [ -n "$task_result" ]; then
                        echo "$task_name ($task_result)" >> "$temp_tasks"
                    else
                        echo "$task_name" >> "$temp_tasks"
                    fi
                fi
                ;;
            error)
                # 提取錯誤訊息（data 可能是字串或物件）
                local error_msg
                error_msg=$(echo "$line" | grep -o '"data":"[^"]*"' | cut -d'"' -f4)
                if [ -z "$error_msg" ]; then
                    # 嘗試從 JSON 物件中提取 message
                    error_msg=$(echo "$line" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
                fi

                if [ -n "$error_msg" ]; then
                    # 提取時間戳
                    local timestamp
                    timestamp=$(echo "$line" | grep -o '"timestamp":"[^"]*"' | head -1 | cut -d'"' -f4)
                    if [ -n "$timestamp" ]; then
                        echo "[$timestamp] $error_msg" >> "$temp_errors"
                    else
                        echo "$error_msg" >> "$temp_errors"
                    fi
                fi
                ;;
        esac
    done < "$jsonl_file"

    # 輸出統計結果（簡單格式，供 Bash 解析）
    echo "event_count=$event_count"

    # 讀取並格式化決策陣列
    if [ -s "$temp_decisions" ]; then
        echo -n "decisions=["
        local first=true
        while IFS= read -r decision; do
            # 雙重轉義：因為 JSON 字串需要轉義，但我們已經有轉義的引號了
            local escaped_decision
            escaped_decision=$(echo "$decision" | sed 's/\\\"/\\\\\\"/g; s/"/\\"/g')
            if [ "$first" = true ]; then
                echo -n "\"$escaped_decision\""
                first=false
            else
                echo -n ",\"$escaped_decision\""
            fi
        done < "$temp_decisions"
        echo "]"
    else
        echo "decisions=[]"
    fi

    # 讀取並格式化任務陣列
    if [ -s "$temp_tasks" ]; then
        echo -n "tasks=["
        local first=true
        while IFS= read -r task; do
            local escaped_task
            escaped_task=$(echo "$task" | sed 's/"/\\"/g')
            if [ "$first" = true ]; then
                echo -n "\"$escaped_task\""
                first=false
            else
                echo -n ",\"$escaped_task\""
            fi
        done < "$temp_tasks"
        echo "]"
    else
        echo "tasks=[]"
    fi

    # 讀取並格式化錯誤陣列
    if [ -s "$temp_errors" ]; then
        echo -n "errors=["
        local first=true
        while IFS= read -r error; do
            local escaped_error
            escaped_error=$(echo "$error" | sed 's/"/\\"/g')
            if [ "$first" = true ]; then
                echo -n "\"$escaped_error\""
                first=false
            else
                echo -n ",\"$escaped_error\""
            fi
        done < "$temp_errors"
        echo "]"
    else
        echo "errors=[]"
    fi

    # 清理臨時檔案
    rm -f "$temp_decisions" "$temp_tasks" "$temp_errors" 2>/dev/null || true

    return $DAILY_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：Markdown 格式化
# ═══════════════════════════════════════════════════════════════

# 格式化為 Markdown
# 用法: format_daily_markdown <date> <event_count> <decisions_json> <tasks_json> <errors_json>
# 輸出: 完整的 Markdown 格式日報
format_daily_markdown() {
    local date="${1:-}"
    local event_count="${2:-0}"
    local decisions_json="${3:-[]}"
    local tasks_json="${4:-[]}"
    local errors_json="${5:-[]}"

    if [ -z "$date" ]; then
        echo "錯誤：format_daily_markdown 需要提供日期" >&2
        return $DAILY_ERROR
    fi

    # 計算各類型數量
    local decision_count=0
    local task_count=0
    local error_count=0

    # 簡單計數（計算逗號數量 + 1，如果不是空陣列）
    if [ "$decisions_json" != "[]" ]; then
        decision_count=$(echo "$decisions_json" | grep -o ',' | wc -l | tr -d ' ')
        decision_count=$((decision_count + 1))
    fi

    if [ "$tasks_json" != "[]" ]; then
        task_count=$(echo "$tasks_json" | grep -o ',' | wc -l | tr -d ' ')
        task_count=$((task_count + 1))
    fi

    if [ "$errors_json" != "[]" ]; then
        error_count=$(echo "$errors_json" | grep -o ',' | wc -l | tr -d ' ')
        error_count=$((error_count + 1))
    fi

    # 生成時間戳
    local generated_at
    generated_at=$(get_timestamp)

    # 生成 Frontmatter
    cat <<EOF
---
date: $date
generated: $generated_at
event_count: $event_count
---

# 日報 - $date

## 摘要

- 總事件數：$event_count
- 完成任務：$task_count
- 決策記錄：$decision_count
- 錯誤數：$error_count

EOF

    # 完成的任務
    echo "## 完成的任務"
    echo ""
    if [ "$tasks_json" != "[]" ]; then
        # 提取並格式化任務
        echo "$tasks_json" | sed 's/^\[//;s/\]$//' | sed 's/","/\n/g' | sed 's/^"//;s/"$//' | while IFS= read -r task; do
            # 判斷成功/失敗狀態
            if echo "$task" | grep -q "(success)"; then
                echo "- ✅ $(echo "$task" | sed 's/ (success)$//')"
            elif echo "$task" | grep -q "(failed)"; then
                echo "- ❌ $(echo "$task" | sed 's/ (failed)$//')"
            else
                echo "- $task"
            fi
        done
    else
        echo "（無完成的任務）"
    fi
    echo ""

    # 重要決策
    echo "## 重要決策"
    echo ""
    if [ "$decisions_json" != "[]" ]; then
        # 提取並格式化決策（還原轉義的引號）
        echo "$decisions_json" | sed 's/^\[//;s/\]$//' | sed 's/","/\n/g' | sed 's/^"//;s/"$//' | while IFS= read -r decision; do
            # 還原 JSON 轉義
            local unescaped_decision
            unescaped_decision=$(echo "$decision" | sed 's/\\"/"/g')
            echo "- $unescaped_decision"
        done
    else
        echo "（無決策記錄）"
    fi
    echo ""

    # 錯誤記錄
    if [ "$error_count" -gt 0 ]; then
        echo "## 錯誤記錄"
        echo ""
        # 提取並格式化錯誤
        echo "$errors_json" | sed 's/^\[//;s/\]$//' | sed 's/","/\n/g' | sed 's/^"//;s/"$//' | while IFS= read -r error; do
            echo "- $error"
        done
        echo ""
    fi

    return $DAILY_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：日報生成
# ═══════════════════════════════════════════════════════════════

# 檢查是否需要生成日報
# 用法: should_generate_summary <date>
# 返回: 0=需要生成，1=跳過
should_generate_summary() {
    local date="${1:-}"

    if [ -z "$date" ]; then
        echo "錯誤：should_generate_summary 需要提供日期" >&2
        return $DAILY_ERROR
    fi

    local jsonl_file="${DAILY_SESSION_DIR}/${date}.jsonl"
    local summary_file="${DAILY_OUTPUT_DIR}/${date}.md"

    # JSONL 不存在，跳過
    if [ ! -f "$jsonl_file" ]; then
        echo "跳過：JSONL 檔案不存在: $jsonl_file" >&2
        return 1
    fi

    # 日報不存在，需要生成
    if [ ! -f "$summary_file" ]; then
        return 0
    fi

    # 日報存在，檢查是否需要更新（比較修改時間）
    if [ "$jsonl_file" -nt "$summary_file" ]; then
        # JSONL 比日報新，需要重新生成
        return 0
    fi

    # 日報已是最新，跳過
    echo "跳過：日報已是最新: $summary_file" >&2
    return 1
}

# 生成指定日期的日報
# 用法: generate_daily_summary <date>
# 返回: 0=成功，1=失敗，2=跳過
generate_daily_summary() {
    local date="${1:-}"

    if [ -z "$date" ]; then
        echo "錯誤：generate_daily_summary 需要提供日期" >&2
        return $DAILY_ERROR
    fi

    # 檢查是否需要生成
    if ! should_generate_summary "$date"; then
        return $DAILY_SKIPPED
    fi

    local jsonl_file="${DAILY_SESSION_DIR}/${date}.jsonl"
    local summary_file="${DAILY_OUTPUT_DIR}/${date}.md"

    # 確保輸出目錄存在
    ensure_directory "$DAILY_OUTPUT_DIR" || {
        echo "錯誤：無法建立輸出目錄: $DAILY_OUTPUT_DIR" >&2
        return $DAILY_ERROR
    }

    # 步驟 1: 彙總事件
    local aggregation_result
    aggregation_result=$(aggregate_session_events "$jsonl_file")

    if [ $? -ne 0 ]; then
        echo "錯誤：無法彙總事件" >&2
        record_daily_failure
        return $DAILY_ERROR
    fi

    # 步驟 2: 解析彙總結果
    local event_count=0
    local decisions_json="[]"
    local tasks_json="[]"
    local errors_json="[]"

    while IFS='=' read -r key value; do
        case "$key" in
            event_count)
                event_count="$value"
                ;;
            decisions)
                decisions_json="$value"
                ;;
            tasks)
                tasks_json="$value"
                ;;
            errors)
                errors_json="$value"
                ;;
        esac
    done <<< "$aggregation_result"

    # 步驟 3: 格式化為 Markdown
    local markdown_content
    markdown_content=$(format_daily_markdown "$date" "$event_count" "$decisions_json" "$tasks_json" "$errors_json")

    if [ $? -ne 0 ]; then
        echo "錯誤：無法格式化 Markdown" >&2
        record_daily_failure
        return $DAILY_ERROR
    fi

    # 步驟 4: 寫入檔案
    echo "$markdown_content" > "$summary_file" 2>/dev/null || {
        echo "錯誤：無法寫入日報檔案: $summary_file" >&2
        record_daily_failure
        return $DAILY_ERROR
    }

    # 設定檔案權限為 600
    chmod 600 "$summary_file" 2>/dev/null || true

    echo "✅ 日報生成成功: $summary_file" >&2
    return $DAILY_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# Hook 整合介面
# ═══════════════════════════════════════════════════════════════

# SessionEnd Hook 入口函式
# 用法: handle_session_end_hook [json_input]
# 參數: json_input - Hook 傳入的 JSON 格式輸入（可選，從 stdin 讀取）
# 返回: 0=成功，1=失敗，2=跳過
handle_session_end_hook() {
    local json_input="${1:-}"

    # 如果沒有提供 JSON 輸入，從 stdin 讀取
    if [ -z "$json_input" ]; then
        json_input=$(cat)
    fi

    # 檢查 Kill Switch
    if is_daily_memory_disabled; then
        echo "⚠️  記憶系統已禁用，跳過日報生成" >&2
        return $DAILY_SKIPPED
    fi

    # 檢查熔斷器
    if is_daily_circuit_breaker_open; then
        echo "⚠️  熔斷器已開啟，跳過日報生成" >&2
        return $DAILY_SKIPPED
    fi

    # 生成當日日報（使用當前日期）
    local current_date
    current_date=$(date -u +%Y-%m-%d)

    # 容錯執行（即使失敗也返回成功，確保不阻擋 SessionEnd 流程）
    if generate_daily_summary "$current_date" 2>/dev/null; then
        return $DAILY_SUCCESS
    else
        echo "⚠️  日報生成失敗，但不阻擋 SessionEnd 流程" >&2
        return $DAILY_SUCCESS  # 返回成功以不阻擋 SessionEnd
    fi
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_daily_help() {
    cat <<'EOF'
Daily Summary Generator - 日常記錄生成

用法:
  # Hook 模式（由 SessionEnd Hook 自動觸發）
  echo '{"session_id":"abc123"}' | memory-daily-summary.sh hook

  # 手動生成模式
  memory-daily-summary.sh generate [YYYY-MM-DD]

  # 測試模式（彙總事件）
  memory-daily-summary.sh aggregate .claude/memory/sessions/2026-02-01.jsonl

  # 測試模式（格式化 Markdown）
  memory-daily-summary.sh format 2026-02-01 42 '["決策1"]' '["任務1"]' '[]'

指令:
  hook                  處理 SessionEnd Hook 輸入（從 stdin 讀取 JSON）
  generate [date]       手動生成日報（預設今天）
  aggregate <file>      測試彙總功能（JSONL → 統計）
  format <date> ...     測試格式化功能（統計 → Markdown）
  check [date]          檢查是否需要生成日報
  help                  顯示此說明

環境變數:
  CLAUDE_SESSION_ID     - 當前 Session ID（自動偵測）
  E2E_SESSION_ID        - E2E 測試 Session ID（測試環境）

輸入位置:
  .claude/memory/sessions/YYYY-MM-DD.jsonl

輸出位置:
  .claude/memory/daily/YYYY-MM-DD.md

Markdown 格式:
  ---
  date: 2026-02-01
  generated: 2026-02-01T23:59:59Z
  event_count: 42
  ---

  # 日報 - 2026-02-01

  ## 摘要
  - 總事件數：42
  - 完成任務：5
  - 決策記錄：3
  - 錯誤數：1

  ## 完成的任務
  - ✅ 實作記憶分類邏輯
  - ✅ 實作 MEMORY.md 更新邏輯
  ...

  ## 重要決策
  - 使用 TypeScript 作為主要語言
  - 採用 JSONL 格式儲存 Session 記錄
  ...

  ## 錯誤記錄
  - [12:30:00Z] 檔案寫入失敗：權限不足
  ...

安全機制:
  - Kill Switch 檢查（.disabled 檔案）
  - 熔斷器檢查（連續失敗自動停用）
  - 容錯執行（不阻擋 SessionEnd 流程）
  - 檔案權限：600（僅擁有者可讀寫）

智能更新:
  - 如果日報已存在且是最新的，跳過生成
  - 如果 JSONL 有更新，自動重新生成
  - 快速執行（< 1 秒）

返回碼:
  0 - 成功
  1 - 失敗
  2 - 跳過（Kill Switch、熔斷器、或已是最新）

範例:
  # 生成今天的日報
  bash hooks/scripts/memory-daily-summary.sh generate

  # 生成指定日期的日報
  bash hooks/scripts/memory-daily-summary.sh generate 2026-01-31

  # 檢查是否需要生成
  bash hooks/scripts/memory-daily-summary.sh check 2026-02-01

  # 測試彙總功能
  bash hooks/scripts/memory-daily-summary.sh aggregate \
    .claude/memory/sessions/2026-02-01.jsonl

  # 模擬 SessionEnd Hook
  echo '{"session_id":"test"}' | \
    bash hooks/scripts/memory-daily-summary.sh hook
EOF
}

# 命令行介面入口
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        hook)
            handle_session_end_hook
            exit $?
            ;;
        generate)
            shift
            target_date="${1:-$(date -u +%Y-%m-%d)}"
            generate_daily_summary "$target_date"
            exit $?
            ;;
        aggregate)
            shift
            if [ -z "${1:-}" ]; then
                echo "錯誤：必須提供 JSONL 檔案路徑" >&2
                echo "用法: $0 aggregate <jsonl_file>" >&2
                exit $DAILY_ERROR
            fi
            aggregate_session_events "$1"
            exit $?
            ;;
        format)
            shift
            if [ $# -lt 5 ]; then
                echo "錯誤：參數不足" >&2
                echo "用法: $0 format <date> <event_count> <decisions_json> <tasks_json> <errors_json>" >&2
                exit $DAILY_ERROR
            fi
            format_daily_markdown "$@"
            exit $?
            ;;
        check)
            shift
            target_date="${1:-$(date -u +%Y-%m-%d)}"
            if should_generate_summary "$target_date"; then
                echo "需要生成日報: $target_date"
                exit 0
            else
                echo "跳過生成（日報已是最新或 JSONL 不存在）"
                exit 1
            fi
            ;;
        help|--help|-h|*)
            show_daily_help
            exit 0
            ;;
    esac
fi
