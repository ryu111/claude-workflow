#!/bin/bash
# memory-inject-user-prompt.sh - UserPromptSubmit Hook 動態記憶注入
# 功能：根據用戶輸入動態搜尋並注入相關記憶到 Context
# 邏輯：檢查熔斷器、快速開關、Phase 後，搜尋並安全注入相關記憶
# 觸發時機：UserPromptSubmit Hook
# Token 預算：~300 tokens（動態搜尋 3-5 條記憶）

set -euo pipefail

# 載入依賴庫
MY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${MY_SCRIPT_DIR}/../lib"

# 載入共用函式庫（按依賴順序，避免重複）
[ -z "${COMMON_SH_LOADED:-}" ] && source "${LIB_DIR}/core/common.sh" && COMMON_SH_LOADED=1

# 載入各依賴函式庫
source "${LIB_DIR}/core/circuit-breaker.sh"
source "${LIB_DIR}/core/kill-switch.sh"
source "${LIB_DIR}/core/rollout-phase.sh"
source "${LIB_DIR}/memory/search.sh"
source "${LIB_DIR}/memory/escape.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

readonly TOKEN_BUDGET=300
readonly MAX_MEMORIES=5
readonly MIN_MEMORIES=3
readonly INJECT_EXIT_SUCCESS=0
readonly INJECT_EXIT_SKIPPED=1
readonly INJECT_EXIT_ERROR=2

# 除錯日誌
readonly DEBUG_LOG="/tmp/claude-workflow-debug.log"

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 主流程：執行記憶注入
# 用法: main
# 返回: 0=成功，1=跳過（正常），2=錯誤（已處理）
main() {
    # 容錯包裝：任何錯誤都靜默失敗
    run_injection_with_safety || true

    # 確保返回成功（不阻擋 UserPromptSubmit）
    return $INJECT_EXIT_SUCCESS
}

# 安全執行注入流程
# 返回: 0=成功，1=跳過，2=錯誤
run_injection_with_safety() {
    # 步驟 1: 檢查熔斷器
    if is_circuit_breaker_open; then
        log_skip "熔斷器已開啟，跳過動態記憶注入"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 2: 檢查快速開關
    local kill_switch_status
    check_kill_switches
    kill_switch_status=$?

    case $kill_switch_status in
        $EXIT_DISABLED)
            log_skip "記憶系統已完全禁用"
            return $INJECT_EXIT_SKIPPED
            ;;
        $EXIT_INJECT_DISABLED)
            log_skip "記憶注入已禁用"
            return $INJECT_EXIT_SKIPPED
            ;;
        $EXIT_READONLY)
            # 只讀模式允許注入（注入是讀取操作）
            ;;
        $EXIT_NORMAL)
            # 正常，繼續
            ;;
        *)
            log_skip "快速開關檢查異常"
            return $INJECT_EXIT_SKIPPED
            ;;
    esac

    # 步驟 3: 檢查 Phase C（僅 Phase C 啟用動態注入）
    local current_phase
    current_phase=$(get_rollout_phase 2>/dev/null) || {
        log_skip "無法取得 Rollout Phase"
        return $INJECT_EXIT_SKIPPED
    }

    if ! is_feature_enabled "$FEATURE_INJECT_DYNAMIC" 2>/dev/null; then
        log_skip "動態注入功能未啟用（當前 Phase: $current_phase，需要 Phase C）"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 4: 檢查索引是否可用（動態注入依賴索引搜尋）
    if ! check_search_phase_enabled 2>/dev/null; then
        log_skip "記憶搜尋功能未啟用（需要 Phase B+）"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 5: 從 stdin 讀取 Hook 輸入（JSON 格式）
    local hook_input
    hook_input=$(cat) || {
        log_skip "無法讀取 Hook 輸入"
        return $INJECT_EXIT_SKIPPED
    }

    # 記錄輸入（除錯用）
    echo "[$(date)] memory-inject-user-prompt.sh INPUT: ${hook_input:0:200}..." >> "$DEBUG_LOG" 2>/dev/null || true

    # 驗證 JSON 格式
    if ! echo "$hook_input" | jq empty 2>/dev/null; then
        log_skip "Hook 輸入不是有效的 JSON"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 6: 解析用戶輸入
    local user_prompt
    user_prompt=$(echo "$hook_input" | jq -r '.prompt // empty' 2>/dev/null)

    if [ -z "$user_prompt" ]; then
        log_skip "用戶輸入為空"
        return $INJECT_EXIT_SKIPPED
    fi

    # 記錄解析結果（除錯用）
    echo "[$(date)] USER_PROMPT: ${user_prompt:0:100}..." >> "$DEBUG_LOG" 2>/dev/null || true

    # 步驟 7: 提取關鍵字（簡單分詞）
    local keywords
    keywords=$(extract_keywords "$user_prompt") || {
        log_skip "無法提取關鍵字"
        return $INJECT_EXIT_SKIPPED
    }

    if [ -z "$keywords" ]; then
        log_skip "未找到有效關鍵字"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 8: 搜尋相關記憶
    local search_results
    search_results=$(search_memory "$keywords" "$MAX_MEMORIES" "" 2>/dev/null) || {
        log_skip "記憶搜尋失敗"
        return $INJECT_EXIT_SKIPPED
    }

    # 步驟 9: 檢查搜尋結果數量
    local result_count
    result_count=$(echo "$search_results" | jq -r '.count // 0' 2>/dev/null)

    if [ "$result_count" -eq 0 ]; then
        log_skip "未找到相關記憶"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 10: 選擇最相關的記憶（3-5 條）
    local selected_count
    if [ "$result_count" -lt "$MIN_MEMORIES" ]; then
        selected_count=$result_count
    else
        selected_count=$MIN_MEMORIES
    fi

    # 步驟 11: 格式化為 Markdown
    local formatted_content
    formatted_content=$(format_memories_to_markdown "$search_results" "$selected_count") || {
        log_skip "無法格式化記憶"
        return $INJECT_EXIT_SKIPPED
    }

    if [ -z "$formatted_content" ]; then
        log_skip "格式化後的記憶為空"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 12: 應用 Token 預算
    local budgeted_content
    budgeted_content=$(apply_token_budget "$formatted_content") || {
        log_skip "無法應用 Token 預算"
        return $INJECT_EXIT_SKIPPED
    }

    # 步驟 13: 安全轉義
    local escaped_content
    escaped_content=$(escape_memory_for_injection "$budgeted_content") || {
        log_skip "安全轉義失敗"
        return $INJECT_EXIT_SKIPPED
    }

    # 步驟 14: 安全包裝
    local wrapped_content
    wrapped_content=$(wrap_memory_safely "$escaped_content" "dynamic-recall" "low") || {
        log_skip "安全包裝失敗"
        return $INJECT_EXIT_SKIPPED
    }

    # 步驟 15: 輸出為 Hook 輸出格式
    output_hook_result "$wrapped_content"

    return $INJECT_EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 提取關鍵字（簡單分詞）
# 用法: keywords=$(extract_keywords "$user_prompt")
# 輸出: 關鍵字字串（空格分隔）
# 返回: 0=成功，1=失敗
extract_keywords() {
    local prompt="${1:-}"

    if [ -z "$prompt" ]; then
        return 1
    fi

    # 簡單分詞策略：
    # 1. 移除標點符號（保留中文字元）
    # 2. 分割為單詞
    # 3. 過濾停用詞
    # 4. 取前 3-5 個關鍵詞

    # 停用詞清單（常見無意義詞）
    local -a stop_words=("the" "a" "an" "and" "or" "but" "in" "on" "at" "to" "for" "of" "with" "by" "is" "are" "was" "were" "我" "你" "他" "的" "了" "嗎" "呢")

    # 移除標點符號，保留空格和中文字元
    local cleaned=$(echo "$prompt" | sed 's/[[:punct:]]/ /g')

    # 分割為單詞（空格分隔）
    local -a words=()
    while IFS=' ' read -ra word_array; do
        for word in "${word_array[@]}"; do
            # 過濾空白和長度 < 2 的詞
            if [ -n "$word" ] && [ "${#word}" -ge 2 ]; then
                # 檢查是否為停用詞
                local is_stop_word=false
                for stop in "${stop_words[@]}"; do
                    if [ "$word" = "$stop" ]; then
                        is_stop_word=true
                        break
                    fi
                done

                # 非停用詞則加入
                if [ "$is_stop_word" = false ]; then
                    words+=("$word")
                fi
            fi
        done
    done <<< "$cleaned"

    # 取前 5 個關鍵詞
    local selected_words=("${words[@]:0:5}")

    # 組合為 FTS5 查詢字串（使用 OR 連接）
    local query=""
    for word in "${selected_words[@]}"; do
        if [ -n "$query" ]; then
            query="$query OR $word"
        else
            query="$word"
        fi
    done

    echo "$query"
    return 0
}

# 格式化記憶為 Markdown
# 用法: content=$(format_memories_to_markdown "$search_results" <count>)
# 參數: search_results - JSON 格式的搜尋結果，count - 選擇數量
# 輸出: Markdown 格式的記憶
# 返回: 0=成功，1=失敗
format_memories_to_markdown() {
    local results="${1:-}"
    local count="${2:-3}"

    if [ -z "$results" ]; then
        return 1
    fi

    local output="## 相關記憶"$'\n\n'

    # 使用 jq 提取前 N 條記憶
    local index=0
    while [ $index -lt "$count" ]; do
        local memory
        memory=$(echo "$results" | jq -r ".results[$index] // empty" 2>/dev/null)

        if [ -z "$memory" ] || [ "$memory" = "null" ]; then
            break
        fi

        local source_file=$(echo "$memory" | jq -r '.source_file // "未知來源"')
        local section=$(echo "$memory" | jq -r '.section // ""')
        local content=$(echo "$memory" | jq -r '.content // ""')

        # 格式化：### 來自 <source> - <section>
        if [ -n "$section" ]; then
            output+="### 來自 $source_file - $section"$'\n'
        else
            output+="### 來自 $source_file"$'\n'
        fi

        output+="$content"$'\n\n'

        ((index++))
    done

    # 移除末尾多餘空行
    output=$(echo "$output" | sed '/^$/N;/^\n$/D')

    echo "$output"
    return 0
}

# 應用 Token 預算（簡單行數限制）
# 用法: content=$(apply_token_budget "$original_content")
# 參數: content - 原始內容
# 輸出: 限制後的內容
# 返回: 0=成功
apply_token_budget() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        printf ""
        return 0
    fi

    # 簡單估算：平均 1 行 ≈ 10 tokens
    # Token 預算 300 → 約 30 行
    local max_lines=$((TOKEN_BUDGET / 10))

    # 提取前 N 行
    local budgeted_content
    budgeted_content=$(printf "%s" "$content" | head -n "$max_lines")

    # 檢查是否有截斷
    local total_lines
    total_lines=$(printf "%s" "$content" | wc -l | tr -d ' ')

    if [ "$total_lines" -gt "$max_lines" ]; then
        # 有截斷，添加提示
        budgeted_content+=$'\n'
        budgeted_content+="..."$'\n'
        budgeted_content+="（完整記憶請見 .claude/memory/）"$'\n'
    fi

    printf "%s" "$budgeted_content"
    return 0
}

# 輸出 Hook 結果（JSON 格式）
# 用法: output_hook_result "$wrapped_content"
# 參數: content - 包裝後的內容
output_hook_result() {
    local content="${1:-}"

    # 轉義 JSON 特殊字元
    local escaped_content=$(echo "$content" | jq -Rs '.')

    # 輸出 Hook 結果格式
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $escaped_content
  }
}
EOF
}

# 記錄跳過訊息（靜默，僅用於除錯）
# 用法: log_skip "原因"
log_skip() {
    local reason="${1:-unknown}"
    # 靜默模式：不輸出（避免干擾 Hook 輸出）
    # 如需除錯，記錄到 DEBUG_LOG
    echo "[$(date)] memory-inject-user-prompt.sh SKIP: $reason" >> "$DEBUG_LOG" 2>/dev/null || true
    return 0
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_help() {
    cat <<'EOF'
用法: memory-inject-user-prompt.sh [command]

指令:
  run                執行動態記憶注入（預設，用於 Hook）
  test <prompt>      測試模式（模擬用戶輸入）
  help               顯示此說明

功能:
  - 在 UserPromptSubmit Hook 觸發時根據用戶輸入動態搜尋記憶
  - 檢查熔斷器、快速開關、Rollout Phase
  - 使用 FTS5 搜尋與用戶輸入相關的記憶
  - 過濾 sensitive 標籤記憶
  - 安全轉義並包裝記憶內容
  - Token 預算限制（~300 tokens）
  - 任何錯誤都靜默失敗，不阻擋 UserPromptSubmit

安全機制:
  1. 熔斷器檢查（連續失敗保護）
  2. 快速開關檢查（.disabled, .inject-disabled）
  3. Phase 檢查（需 Phase C）
  4. 過濾敏感記憶（sensitive 標籤）
  5. 安全轉義（防止 Prompt Injection）
  6. 容錯包裝（safe_execute）

輸出格式:
  {
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": "<memory_context>...</memory_context>"
    }
  }

返回碼:
  0 - 成功或正常跳過（不阻擋 Hook）

Hook 配置:
  {
    "event": "UserPromptSubmit",
    "hooks": [
      {
        "script": "memory-inject-user-prompt.sh",
        "timeout": 5000
      }
    ]
  }

範例:
  # Hook 執行（自動）
  echo '{"prompt": "如何使用 TypeScript"}' | bash hooks/scripts/memory-inject-user-prompt.sh run

  # 測試模式
  bash hooks/scripts/memory-inject-user-prompt.sh test "如何使用 TypeScript"
EOF
}

# 測試模式（模擬用戶輸入）
run_test_mode() {
    local test_prompt="${1:-測試輸入}"

    # 構造測試輸入 JSON
    local test_input=$(cat <<EOF
{
  "prompt": "$test_prompt"
}
EOF
)

    # 覆蓋 log_skip 函式以顯示訊息
    log_skip() {
        echo "⏭️  跳過動態記憶注入: $1" >&2
    }

    # 通過 stdin 傳遞測試輸入
    echo "$test_input" | main
    local exit_code=$?

    echo "" >&2
    echo "測試完成，退出碼: $exit_code" >&2
    return $exit_code
}

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-run}" in
        run)
            main
            exit $?
            ;;
        test)
            run_test_mode "${2:-測試輸入}"
            exit $?
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "錯誤：無效的指令 '${1}'" >&2
            echo "" >&2
            show_help
            exit 1
            ;;
    esac
else
    # 被 source 或 Hook 呼叫，執行主流程
    main
fi
