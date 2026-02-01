#!/usr/bin/env bash
# memory-session-summary.sh - Session 摘要生成器
# 功能：在 SessionEnd Hook 觸發時彙總當前 Session 的關鍵事件
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

# 恢復 set 選項
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# 常數定義（使用 SESSION_SUMMARY_ 前綴避免與載入模組的常數衝突）
# ═══════════════════════════════════════════════════════════════

# 返回碼
SESSION_SUMMARY_SUCCESS=0
SESSION_SUMMARY_ERROR=1
SESSION_SUMMARY_SKIPPED=2

# 目錄路徑
SESSION_SUMMARY_LOG_DIR="${PWD}/.claude/memory/sessions"

# ═══════════════════════════════════════════════════════════════
# 內部輔助函式
# ═══════════════════════════════════════════════════════════════

# 檢查記憶系統是否禁用（通過 CLI）
# 用法: if is_summary_memory_disabled; then ...
is_summary_memory_disabled() {
    bash "${LIB_DIR}/core/kill-switch.sh" check >/dev/null 2>&1
    local status=$?
    [ $status -eq 1 ]  # 返回碼 1 表示完全禁用
}

# 檢查熔斷器是否開啟（通過 CLI）
# 用法: if is_summary_circuit_breaker_open; then ...
is_summary_circuit_breaker_open() {
    bash "${LIB_DIR}/core/circuit-breaker.sh" is-open >/dev/null 2>&1
}

# 記錄失敗到熔斷器（通過 CLI）
# 用法: record_summary_failure
record_summary_failure() {
    bash "${LIB_DIR}/core/circuit-breaker.sh" record-failure >/dev/null 2>&1
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：Session 摘要生成
# ═══════════════════════════════════════════════════════════════

# 取得當日 JSONL 檔案路徑
# 用法: log_file=$(get_session_jsonl_file)
get_session_jsonl_file() {
    local current_date
    current_date=$(date -u +%Y-%m-%d)
    printf '%s/%s.jsonl\n' "$SESSION_SUMMARY_LOG_DIR" "$current_date"
}

# 統計 D→R→T 流程執行次數
# 用法: drt_stats=$(count_drt_events <jsonl_file>)
# 輸出: JSON 格式 {"developer":3,"reviewer":2,"tester":2}
count_drt_events() {
    local jsonl_file="${1:-}"

    if [ ! -f "$jsonl_file" ]; then
        echo '{"developer":0,"reviewer":0,"tester":0}'
        return 0
    fi

    # 統計各 Agent 執行次數（從 type 為 task_start 或 task_complete 的事件中提取）
    local developer_count=0
    local reviewer_count=0
    local tester_count=0

    # 使用臨時檔案收集統計
    local temp_agents="${TMPDIR:-/tmp}/session_agents_$$.txt"
    > "$temp_agents"

    # 提取所有包含 "agent" 欄位的事件
    grep -o '"source_agent":"[^"]*"' "$jsonl_file" 2>/dev/null | cut -d'"' -f4 >> "$temp_agents" || true

    # 統計各 Agent 出現次數
    if [ -s "$temp_agents" ]; then
        developer_count=$(grep -c "developer" "$temp_agents" 2>/dev/null || echo 0)
        reviewer_count=$(grep -c "reviewer" "$temp_agents" 2>/dev/null || echo 0)
        tester_count=$(grep -c "tester" "$temp_agents" 2>/dev/null || echo 0)
    fi

    # 清理臨時檔案
    rm -f "$temp_agents" 2>/dev/null || true

    # 輸出 JSON
    printf '{"developer":%d,"reviewer":%d,"tester":%d}\n' "$developer_count" "$reviewer_count" "$tester_count"
}

# 統計完成的任務數
# 用法: task_count=$(count_completed_tasks <jsonl_file>)
count_completed_tasks() {
    local jsonl_file="${1:-}"

    if [ ! -f "$jsonl_file" ]; then
        echo 0
        return 0
    fi

    # 統計 task_complete 事件數量
    local count
    count=$(grep -c '"type":"task_complete"' "$jsonl_file" 2>/dev/null || true)

    # 如果 grep 失敗（沒有找到），count 為空字串
    if [ -z "$count" ] || [ "$count" = "0" ]; then
        echo 0
    else
        echo "$count"
    fi
}

# 提取重要決策
# 用法: decisions=$(extract_decisions <jsonl_file>)
# 輸出: JSON 陣列 ["決策1","決策2"]
extract_decisions() {
    local jsonl_file="${1:-}"

    if [ ! -f "$jsonl_file" ]; then
        echo '[]'
        return 0
    fi

    # 使用臨時檔案收集決策
    local temp_decisions="${TMPDIR:-/tmp}/session_decisions_$$.txt"
    > "$temp_decisions"

    # 提取 decision 和 precompact_flush 事件中的決策
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue

        # 提取事件類型
        local event_type
        event_type=$(echo "$line" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)

        case "$event_type" in
            precompact_flush)
                # 提取 decisions 陣列
                local decision_array
                decision_array=$(echo "$line" | grep -o '"decisions":\[[^]]*\]' | sed 's/"decisions"://')
                if [ -n "$decision_array" ] && [ "$decision_array" != "[]" ]; then
                    echo "$decision_array" | grep -o '"[^"]*"' | sed 's/^"//;s/"$//' | while read -r dec; do
                        [ -n "$dec" ] && echo "$dec" >> "$temp_decisions"
                    done
                fi
                ;;
            decision)
                # 提取 data 欄位中的決策
                local decision_text
                decision_text=$(echo "$line" | sed -n 's/.*"data":"\([^}]*\)".*/\1/p')
                if [ -z "$decision_text" ]; then
                    decision_text=$(echo "$line" | sed -n 's/.*"decision":"\([^}]*\)".*/\1/p')
                fi
                # 還原轉義的引號
                decision_text=$(echo "$decision_text" | sed 's/\\"/"/g')
                if [ -n "$decision_text" ]; then
                    echo "$decision_text" >> "$temp_decisions"
                fi
                ;;
        esac
    done < "$jsonl_file"

    # 組裝 JSON 陣列
    if [ -s "$temp_decisions" ]; then
        echo -n '['
        local first=true
        while IFS= read -r decision; do
            local escaped_decision
            escaped_decision=$(echo "$decision" | sed 's/\\\"/\\\\\\"/g; s/"/\\"/g')
            if [ "$first" = true ]; then
                echo -n "\"$escaped_decision\""
                first=false
            else
                echo -n ",\"$escaped_decision\""
            fi
        done < "$temp_decisions"
        echo ']'
    else
        echo '[]'
    fi

    # 清理臨時檔案
    rm -f "$temp_decisions" 2>/dev/null || true
}

# 統計 Git 變更（複用 session-cleanup-report 邏輯）
# 用法: git_stats=$(get_git_changes)
# 輸出: JSON 格式 {"staged":2,"modified":3}
get_git_changes() {
    local staged=0
    local modified=0

    if [ -d ".git" ]; then
        modified=$(git diff --shortstat 2>/dev/null | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo 0)
        staged=$(git diff --cached --shortstat 2>/dev/null | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo 0)
    fi

    printf '{"staged":%d,"modified":%d}\n' "$staged" "$modified"
}

# 生成 Session 摘要並記錄到 JSONL
# 用法: generate_session_summary
# 返回: 0=成功，1=失敗
generate_session_summary() {
    # 步驟 1: 取得 JSONL 檔案路徑
    local jsonl_file
    jsonl_file=$(get_session_jsonl_file)

    if [ ! -f "$jsonl_file" ]; then
        echo "⚠️  JSONL 檔案不存在，跳過摘要生成: $jsonl_file" >&2
        return $SESSION_SUMMARY_SKIPPED
    fi

    # 步驟 2: 統計各項數據
    local tasks_completed
    local drt_stats
    local decisions
    local git_changes

    tasks_completed=$(count_completed_tasks "$jsonl_file")
    drt_stats=$(count_drt_events "$jsonl_file")
    decisions=$(extract_decisions "$jsonl_file")
    git_changes=$(get_git_changes)

    # 步驟 3: 組裝摘要 JSON（單行格式，避免換行導致 JSONL 格式錯誤）
    local summary_data
    summary_data=$(printf '{"tasks_completed":%d,"drt_stats":%s,"decisions":%s,"git_changes":%s}' \
        "$tasks_completed" \
        "$drt_stats" \
        "$decisions" \
        "$git_changes")

    # 步驟 4: 記錄到 JSONL（使用 session-log.sh 的函式）
    if ! log_session_event "session_summary" "$summary_data" 2>/dev/null; then
        echo "⚠️  無法記錄 Session 摘要到 JSONL" >&2
        record_summary_failure
        return $SESSION_SUMMARY_ERROR
    fi

    echo "✅ Session 摘要已生成" >&2
    return $SESSION_SUMMARY_SUCCESS
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
    if is_summary_memory_disabled; then
        echo "⚠️  記憶系統已禁用，跳過 Session 摘要生成" >&2
        return $SESSION_SUMMARY_SKIPPED
    fi

    # 檢查熔斷器
    if is_summary_circuit_breaker_open; then
        echo "⚠️  熔斷器已開啟，跳過 Session 摘要生成" >&2
        return $SESSION_SUMMARY_SKIPPED
    fi

    # 容錯執行（即使失敗也返回成功，確保不阻擋 SessionEnd 流程）
    if generate_session_summary 2>/dev/null; then
        return $SESSION_SUMMARY_SUCCESS
    else
        echo "⚠️  Session 摘要生成失敗，但不阻擋 SessionEnd 流程" >&2
        return $SESSION_SUMMARY_SUCCESS  # 返回成功以不阻擋 SessionEnd
    fi
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_summary_help() {
    cat <<'EOF'
Session 摘要生成器 (Session Summary Generator)

用法:
  # Hook 模式（由 SessionEnd Hook 自動觸發）
  echo '{"session_id":"abc123"}' | memory-session-summary.sh hook

  # 手動生成模式
  memory-session-summary.sh generate

  # 測試模式（統計任務）
  memory-session-summary.sh test-tasks

  # 測試模式（統計 D→R→T）
  memory-session-summary.sh test-drt

  # 測試模式（提取決策）
  memory-session-summary.sh test-decisions

  # 測試模式（Git 變更）
  memory-session-summary.sh test-git

指令:
  hook                  處理 SessionEnd Hook 輸入（從 stdin 讀取 JSON）
  generate              手動生成 Session 摘要
  test-tasks            測試任務統計功能
  test-drt              測試 D→R→T 統計功能
  test-decisions        測試決策提取功能
  test-git              測試 Git 變更統計功能
  help                  顯示此說明

環境變數:
  CLAUDE_SESSION_ID     - 當前 Session ID（自動偵測）
  E2E_SESSION_ID        - E2E 測試 Session ID（測試環境）

輸入位置:
  .claude/memory/sessions/YYYY-MM-DD.jsonl

輸出格式:
  記錄到 JSONL，事件類型為 session_summary
  {
    "type": "session_summary",
    "data": {
      "tasks_completed": 5,
      "drt_stats": {
        "developer": 3,
        "reviewer": 2,
        "tester": 2
      },
      "decisions": ["決策1", "決策2"],
      "git_changes": {
        "staged": 2,
        "modified": 3
      }
    }
  }

安全機制:
  - Kill Switch 檢查（.disabled 檔案）
  - 熔斷器檢查（連續失敗自動停用）
  - 容錯執行（不阻擋 SessionEnd 流程）

返回碼:
  0 - 成功
  1 - 失敗
  2 - 跳過（Kill Switch、熔斷器、或 JSONL 不存在）

範例:
  # 手動生成 Session 摘要
  bash hooks/scripts/memory-session-summary.sh generate

  # 測試任務統計
  bash hooks/scripts/memory-session-summary.sh test-tasks

  # 模擬 SessionEnd Hook
  echo '{"session_id":"test"}' | \
    bash hooks/scripts/memory-session-summary.sh hook
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
            generate_session_summary
            exit $?
            ;;
        test-tasks)
            jsonl_file=$(get_session_jsonl_file)
            count_completed_tasks "$jsonl_file"
            exit $?
            ;;
        test-drt)
            jsonl_file=$(get_session_jsonl_file)
            count_drt_events "$jsonl_file"
            exit $?
            ;;
        test-decisions)
            jsonl_file=$(get_session_jsonl_file)
            extract_decisions "$jsonl_file"
            exit $?
            ;;
        test-git)
            get_git_changes
            exit $?
            ;;
        help|--help|-h|*)
            show_summary_help
            exit 0
            ;;
    esac
fi
