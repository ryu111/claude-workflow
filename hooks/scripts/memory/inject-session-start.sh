#!/bin/bash
# memory-inject-session-start.sh - SessionStart Hook 記憶注入
# 功能：在 SessionStart 時自動注入相關記憶到 Context
# 邏輯：檢查熔斷器、快速開關、Phase 後，安全注入 MEMORY.md 關鍵區段
# 觸發時機：SessionStart Hook
# Token 預算：~200 tokens（關鍵區段摘要）

set -euo pipefail

# 載入依賴庫
MY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${MY_SCRIPT_DIR}/../lib"

# 載入共用函式庫（按依賴順序，避免重複）
# 注意：circuit-breaker.sh 和 safe-execute.sh 都會載入 common.sh
[ -z "${COMMON_SH_LOADED:-}" ] && source "${LIB_DIR}/core/common.sh" && COMMON_SH_LOADED=1

# circuit-breaker.sh 依賴 common.sh，會重新載入（已保護）
source "${LIB_DIR}/core/circuit-breaker.sh"

# kill-switch.sh 依賴 common.sh
source "${LIB_DIR}/core/kill-switch.sh"

# rollout-phase.sh 依賴 common.sh
source "${LIB_DIR}/core/rollout-phase.sh"

# memory-escape.sh 依賴 common.sh
source "${LIB_DIR}/memory/escape.sh"

# safe-execute.sh 依賴 common.sh 和 circuit-breaker.sh（已載入）
# 跳過避免重複載入問題
# source "${LIB_DIR}/core/safe-execute.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

readonly MEMORY_FILE="${PWD}/.claude/memory/MEMORY.md"
readonly TOKEN_BUDGET=200
readonly INJECT_EXIT_SUCCESS=0
readonly INJECT_EXIT_SKIPPED=1
readonly INJECT_EXIT_ERROR=2

# 關鍵區段（需要提取的區段標題）
readonly -a KEY_SECTIONS=(
    "## 專案偏好"
    "## 技術棧"
    "## 重要決策"
)

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 主流程：執行記憶注入
# 用法: main
# 返回: 0=成功，1=跳過（正常），2=錯誤（已處理）
main() {
    # 容錯包裝：任何錯誤都靜默失敗
    run_injection_with_safety || true

    # 確保返回成功（不阻擋 SessionStart）
    return $INJECT_EXIT_SUCCESS
}

# 安全執行注入流程
# 返回: 0=成功，1=跳過，2=錯誤
run_injection_with_safety() {
    # 步驟 1: 檢查熔斷器
    if is_circuit_breaker_open; then
        log_skip "熔斷器已開啟，跳過記憶注入"
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

    # 步驟 3: 檢查 Phase A+（Phase A 或更高）
    local current_phase
    current_phase=$(get_rollout_phase 2>/dev/null) || {
        log_skip "無法取得 Rollout Phase"
        return $INJECT_EXIT_SKIPPED
    }

    if ! is_feature_enabled "$FEATURE_INJECT_STATIC" 2>/dev/null; then
        log_skip "靜態注入功能未啟用（當前 Phase: $current_phase）"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 4: 檢查 MEMORY.md 是否存在
    if [ ! -f "$MEMORY_FILE" ]; then
        log_skip "MEMORY.md 不存在，跳過注入"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 5: 提取關鍵區段
    local extracted_content
    extracted_content=$(extract_key_sections) || {
        log_skip "無法提取關鍵區段"
        return $INJECT_EXIT_SKIPPED
    }

    # 檢查是否有內容
    if [ -z "$extracted_content" ]; then
        log_skip "MEMORY.md 無關鍵區段，跳過注入"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 6: 限制 Token 預算
    local budgeted_content
    budgeted_content=$(apply_token_budget "$extracted_content") || {
        log_skip "無法應用 Token 預算"
        return $INJECT_EXIT_SKIPPED
    }

    # 步驟 7: 安全轉義
    local escaped_content
    escaped_content=$(escape_memory_for_injection "$budgeted_content") || {
        log_skip "安全轉義失敗"
        return $INJECT_EXIT_SKIPPED
    }

    # 步驟 8: 安全包裝
    local wrapped_content
    wrapped_content=$(wrap_memory_safely "$escaped_content" "memory-system" "low") || {
        log_skip "安全包裝失敗"
        return $INJECT_EXIT_SKIPPED
    }

    # 步驟 9: 輸出到 stdout（Hook 注入）
    printf "%s\n" "$wrapped_content"

    return $INJECT_EXIT_SUCCESS
}

# 提取關鍵區段
# 用法: content=$(extract_key_sections)
# 輸出: 提取的 Markdown 內容
# 返回: 0=成功，1=失敗
extract_key_sections() {
    local output=""
    local current_section=""
    local in_section=false

    while IFS= read -r line; do
        # 檢查是否為區段標題
        if [[ "$line" =~ ^##\  ]]; then
            # 檢查是否為關鍵區段
            local is_key_section=false
            for section in "${KEY_SECTIONS[@]}"; do
                if [ "$line" = "$section" ]; then
                    is_key_section=true
                    current_section="$section"
                    break
                fi
            done

            if [ "$is_key_section" = true ]; then
                # 開始新的關鍵區段
                in_section=true
                output+="$line"$'\n'
            else
                # 遇到其他區段，停止提取當前區段
                in_section=false
            fi
        elif [ "$in_section" = true ]; then
            # 在關鍵區段內，提取內容（直到下一個 ## 或檔案結尾）
            if [[ "$line" =~ ^##\  ]]; then
                # 遇到下一個區段，停止
                in_section=false
            else
                # 提取內容（跳過空行過多、註解過多）
                if [ -n "$line" ] || [ -n "$output" ]; then
                    output+="$line"$'\n'
                fi
            fi
        fi
    done < "$MEMORY_FILE"

    # 清理多餘空行
    output=$(printf "%s" "$output" | sed '/^$/N;/^\n$/D')

    printf "%s" "$output"
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
    # Token 預算 200 → 約 20 行
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
        budgeted_content+="（完整記憶請見 .claude/memory/MEMORY.md）"$'\n'
    fi

    printf "%s" "$budgeted_content"
    return 0
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 記錄跳過訊息（靜默，僅用於除錯）
# 用法: log_skip "原因"
log_skip() {
    local reason="${1:-unknown}"
    # 靜默模式：不輸出（避免干擾 Hook 輸出）
    # 如需除錯，取消註解：
    # echo "⏭️  跳過記憶注入: $reason" >&2
    return 0
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_help() {
    cat <<'EOF'
用法: memory-inject-session-start.sh [command]

指令:
  run                執行記憶注入（預設，用於 Hook）
  test               測試模式（顯示除錯訊息）
  extract            僅提取關鍵區段（測試用）
  help               顯示此說明

功能:
  - 在 SessionStart Hook 觸發時自動注入 MEMORY.md 關鍵區段
  - 檢查熔斷器、快速開關、Rollout Phase
  - 安全轉義並包裝記憶內容
  - Token 預算限制（~200 tokens）
  - 任何錯誤都靜默失敗，不阻擋 SessionStart

關鍵區段:
  - ## 專案偏好
  - ## 技術棧
  - ## 重要決策

安全機制:
  1. 熔斷器檢查（連續失敗保護）
  2. 快速開關檢查（.disabled, .inject-disabled）
  3. Phase 檢查（需 Phase A+）
  4. 安全轉義（防止 Prompt Injection）
  5. 容錯包裝（safe_execute）

輸出格式:
  <memory_context role="data" source="memory-system" trust="low">
  ## 專案偏好
  ...
  ## 技術棧
  ...
  ## 重要決策
  ...
  </memory_context>

返回碼:
  0 - 成功或正常跳過（不阻擋 Hook）

Hook 配置:
  {
    "event": "SessionStart",
    "hooks": [
      {
        "script": "memory-inject-session-start.sh",
        "timeout": 5000
      }
    ]
  }

範例:
  # Hook 執行（自動）
  bash hooks/scripts/memory-inject-session-start.sh run

  # 測試模式（顯示除錯訊息）
  bash hooks/scripts/memory-inject-session-start.sh test

  # 僅提取關鍵區段
  bash hooks/scripts/memory-inject-session-start.sh extract
EOF
}

# 測試模式（啟用除錯訊息）
run_test_mode() {
    # 覆蓋 log_skip 函式以顯示訊息
    log_skip() {
        echo "⏭️  跳過記憶注入: $1" >&2
    }

    # 執行主流程
    main
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
            run_test_mode
            exit $?
            ;;
        extract)
            extract_key_sections
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
