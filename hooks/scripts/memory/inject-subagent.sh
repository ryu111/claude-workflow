#!/bin/bash
# memory-inject-subagent.sh - SubagentStart Hook Agent 專屬記憶注入
# 功能：在 SubagentStart 時根據 Agent 類型注入專屬經驗記憶到 Context
# 邏輯：檢查熔斷器、快速開關、Phase C 後，安全注入 Agent 專屬經驗
# 觸發時機：SubagentStart Hook
# Token 預算：150-200 tokens（Agent 專屬經驗摘要）

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
source "${LIB_DIR}/memory/escape.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

readonly EXPERIENCES_DIR="${PWD}/.claude/memory/experiences"
readonly TOKEN_BUDGET_MIN=150
readonly TOKEN_BUDGET_MAX=200
readonly INJECT_EXIT_SUCCESS=0
readonly INJECT_EXIT_SKIPPED=1
readonly INJECT_EXIT_ERROR=2

# 除錯日誌
readonly DEBUG_LOG="/tmp/claude-workflow-debug.log"

# ═══════════════════════════════════════════════════════════════
# 輔助功能 - Agent 類型映射
# ═══════════════════════════════════════════════════════════════

# 取得 Agent 對應的經驗檔案名稱
# 用法: file=$(get_experience_file <agent_type>)
# 參數: agent_type - Agent 類型（小寫）
# 輸出: 對應的檔案名稱，如果不支援則輸出空字串
# 返回: 0=成功
get_experience_file() {
    local agent="${1:-}"

    case "$agent" in
        developer)
            echo "developer-tips.md"
            ;;
        reviewer)
            echo "reviewer-patterns.md"
            ;;
        tester)
            echo "tester-strategies.md"
            ;;
        debugger)
            echo "debugger-solutions.md"
            ;;
        architect)
            echo "architect-decisions.md"
            ;;
        designer)
            echo "designer-guidelines.md"
            ;;
        *)
            echo ""
            ;;
    esac

    return 0
}

# 列出所有支援的 Agent 類型
# 用法: list=$(list_supported_agents)
# 輸出: 空格分隔的 Agent 類型清單
list_supported_agents() {
    echo "developer reviewer tester debugger architect designer"
}

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 主流程：執行記憶注入
# 用法: main
# 返回: 0=成功，1=跳過（正常），2=錯誤（已處理）
main() {
    # 容錯包裝：任何錯誤都靜默失敗
    run_injection_with_safety || true

    # 確保返回成功（不阻擋 SubagentStart）
    return $INJECT_EXIT_SUCCESS
}

# 安全執行注入流程
# 返回: 0=成功，1=跳過，2=錯誤
run_injection_with_safety() {
    # 步驟 1: 檢查熔斷器
    if is_circuit_breaker_open; then
        log_skip "熔斷器已開啟，跳過 Agent 專屬記憶注入"
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

    # 步驟 3: 檢查 Phase C（僅 Phase C 啟用 Agent 專屬注入）
    local current_phase
    current_phase=$(get_rollout_phase 2>/dev/null) || {
        log_skip "無法取得 Rollout Phase"
        return $INJECT_EXIT_SKIPPED
    }

    if ! is_feature_enabled "$FEATURE_INJECT_DYNAMIC" 2>/dev/null; then
        log_skip "Agent 專屬注入功能未啟用 (當前 Phase: $current_phase, 需要 Phase C)"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 4: 從 stdin 讀取 Hook 輸入（JSON 格式）
    local hook_input
    hook_input=$(cat) || {
        log_skip "無法讀取 Hook 輸入"
        return $INJECT_EXIT_SKIPPED
    }

    # 記錄輸入（除錯用）
    echo "[$(date)] memory-inject-subagent.sh INPUT: ${hook_input:0:200}..." >> "$DEBUG_LOG" 2>/dev/null || true

    # 驗證 JSON 格式
    if ! echo "$hook_input" | jq empty 2>/dev/null; then
        log_skip "Hook 輸入不是有效的 JSON"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 5: 解析 Agent 類型
    local agent_type
    agent_type=$(echo "$hook_input" | jq -r '.agent_type // .agent // empty' 2>/dev/null)

    if [ -z "$agent_type" ]; then
        log_skip "無法解析 Agent 類型"
        return $INJECT_EXIT_SKIPPED
    fi

    # 轉換為小寫（統一格式）
    agent_type=$(echo "$agent_type" | tr '[:upper:]' '[:lower:]')

    # 記錄解析結果（除錯用）
    echo "[$(date)] AGENT_TYPE: $agent_type" >> "$DEBUG_LOG" 2>/dev/null || true

    # 步驟 6: 取得對應的經驗檔案
    local experience_file
    experience_file=$(get_experience_file "$agent_type")

    if [ -z "$experience_file" ]; then
        log_skip "未知的 Agent 類型: $agent_type (支援: $(list_supported_agents))"
        return $INJECT_EXIT_SKIPPED
    fi

    local full_path="${EXPERIENCES_DIR}/${experience_file}"

    # 步驟 7: 檢查經驗檔案是否存在
    if [ ! -f "$full_path" ]; then
        log_skip "經驗檔案不存在: $full_path"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 8: 讀取經驗檔案內容
    local experience_content
    experience_content=$(cat "$full_path" 2>/dev/null) || {
        log_skip "無法讀取經驗檔案: $full_path"
        return $INJECT_EXIT_SKIPPED
    }

    if [ -z "$experience_content" ]; then
        log_skip "經驗檔案為空: $full_path"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 9: 提取關鍵內容（去除 YAML frontmatter）
    local extracted_content
    extracted_content=$(extract_markdown_content "$experience_content") || {
        log_skip "無法提取經驗內容"
        return $INJECT_EXIT_SKIPPED
    }

    if [ -z "$extracted_content" ]; then
        log_skip "提取後的經驗內容為空"
        return $INJECT_EXIT_SKIPPED
    fi

    # 步驟 10: 應用 Token 預算
    local budgeted_content
    budgeted_content=$(apply_token_budget "$extracted_content" "$agent_type") || {
        log_skip "無法應用 Token 預算"
        return $INJECT_EXIT_SKIPPED
    }

    # 步驟 11: 安全轉義
    local escaped_content
    escaped_content=$(escape_memory_for_injection "$budgeted_content") || {
        log_skip "安全轉義失敗"
        return $INJECT_EXIT_SKIPPED
    }

    # 步驟 12: 安全包裝
    local wrapped_content
    wrapped_content=$(wrap_memory_safely "$escaped_content" "agent-experience" "low") || {
        log_skip "安全包裝失敗"
        return $INJECT_EXIT_SKIPPED
    }

    # 步驟 13: 輸出到 stdout（Hook 注入）
    printf "%s\n" "$wrapped_content"

    return $INJECT_EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 提取 Markdown 內容（去除 YAML frontmatter）
# 用法: content=$(extract_markdown_content "$raw_content")
# 輸出: 去除 frontmatter 後的 Markdown 內容
# 返回: 0=成功，1=失敗
extract_markdown_content() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        return 1
    fi

    local output=""
    local in_frontmatter=false
    local frontmatter_ended=false

    while IFS= read -r line; do
        # 檢查 YAML frontmatter 分隔符（---）
        if [ "$line" = "---" ]; then
            if [ "$in_frontmatter" = false ] && [ "$frontmatter_ended" = false ]; then
                # 開始 frontmatter
                in_frontmatter=true
                continue
            elif [ "$in_frontmatter" = true ]; then
                # 結束 frontmatter
                in_frontmatter=false
                frontmatter_ended=true
                continue
            fi
        fi

        # 跳過 frontmatter 內容
        if [ "$in_frontmatter" = true ]; then
            continue
        fi

        # 提取 frontmatter 後的內容
        if [ "$frontmatter_ended" = true ]; then
            output+="$line"$'\n'
        fi
    done <<< "$content"

    # 如果沒有 frontmatter，返回原始內容
    if [ -z "$output" ]; then
        output="$content"
    fi

    # 清理多餘空行
    output=$(printf "%s" "$output" | sed '/^$/N;/^\n$/D')

    printf "%s" "$output"
    return 0
}

# 應用 Token 預算（簡單行數限制）
# 用法: content=$(apply_token_budget "$original_content" "$agent_type")
# 參數: content - 原始內容，agent_type - Agent 類型
# 輸出: 限制後的內容
# 返回: 0=成功
apply_token_budget() {
    local content="${1:-}"
    local agent_type="${2:-unknown}"

    if [ -z "$content" ]; then
        printf ""
        return 0
    fi

    # 簡單估算：平均 1 行 ≈ 10 tokens
    # Token 預算 150-200 → 約 15-20 行
    local max_lines=$(( (TOKEN_BUDGET_MIN + TOKEN_BUDGET_MAX) / 2 / 10 ))

    # 提取前 N 行
    local budgeted_content
    budgeted_content=$(printf "%s" "$content" | head -n "$max_lines")

    # 檢查是否有截斷
    local total_lines
    total_lines=$(printf "%s" "$content" | wc -l | tr -d ' ')

    if [ "$total_lines" -gt "$max_lines" ]; then
        # 有截斷，添加提示
        local experience_file
        experience_file=$(get_experience_file "$agent_type")
        if [ -z "$experience_file" ]; then
            experience_file="unknown.md"
        fi

        budgeted_content+=$'\n'
        budgeted_content+="..."$'\n'
        budgeted_content+="(完整經驗請見 .claude/memory/experiences/${experience_file})"$'\n'
    fi

    printf "%s" "$budgeted_content"
    return 0
}

# 記錄跳過訊息（靜默，僅用於除錯）
# 用法: log_skip "原因"
log_skip() {
    local reason="${1:-unknown}"
    # 靜默模式：不輸出（避免干擾 Hook 輸出）
    # 如需除錯，記錄到 DEBUG_LOG
    echo "[$(date)] memory-inject-subagent.sh SKIP: $reason" >> "$DEBUG_LOG" 2>/dev/null || true
    return 0
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_help() {
    cat <<'EOF'
用法: memory-inject-subagent.sh [command]

指令:
  run                執行 Agent 專屬記憶注入（預設，用於 Hook）
  test <agent_type>  測試模式（模擬指定 Agent 啟動）
  list               列出支援的 Agent 類型與對應經驗檔案
  help               顯示此說明

功能:
  - 在 SubagentStart Hook 觸發時根據 Agent 類型注入專屬經驗
  - 檢查熔斷器、快速開關、Rollout Phase（需 Phase C）
  - 讀取對應的經驗檔案並應用 Token 預算
  - 安全轉義並包裝記憶內容
  - Token 預算限制（150-200 tokens）
  - 任何錯誤都靜默失敗，不阻擋 SubagentStart

支援的 Agent 類型:
  - developer  → experiences/developer-tips.md
  - reviewer   → experiences/reviewer-patterns.md
  - tester     → experiences/tester-strategies.md
  - debugger   → experiences/debugger-solutions.md
  - architect  → experiences/architect-decisions.md
  - designer   → experiences/designer-guidelines.md

安全機制:
  1. 熔斷器檢查（連續失敗保護）
  2. 快速開關檢查（.disabled, .inject-disabled）
  3. Phase 檢查（需 Phase C）
  4. 安全轉義（防止 Prompt Injection）
  5. 容錯包裝（safe_execute）
  6. ACL 檢查（未來實作）

輸出格式:
  <memory_context role="data" source="agent-experience" trust="low">
  ## REVIEWER 經驗

  ### 常見問題模式
  - 缺少錯誤處理...

  ### 審查清單
  - 檢查 SQL 注入...
  </memory_context>

返回碼:
  0 - 成功或正常跳過（不阻擋 Hook）

Hook 配置:
  {
    "event": "SubagentStart",
    "hooks": [
      {
        "script": "memory-inject-subagent.sh",
        "timeout": 5000
      }
    ]
  }

範例:
  # Hook 執行（自動）
  echo '{"agent_type": "reviewer"}' | bash hooks/scripts/memory-inject-subagent.sh run

  # 測試模式（模擬 REVIEWER 啟動）
  bash hooks/scripts/memory-inject-subagent.sh test reviewer

  # 列出支援的 Agent 類型
  bash hooks/scripts/memory-inject-subagent.sh list
EOF
}

# 測試模式（模擬 Agent 啟動）
run_test_mode() {
    local test_agent="${1:-developer}"

    # 構造測試輸入 JSON
    local test_input=$(cat <<EOF
{
  "agent_type": "$test_agent"
}
EOF
)

    # 覆蓋 log_skip 函式以顯示訊息
    log_skip() {
        echo "⏭️  跳過 Agent 專屬記憶注入: $1" >&2
    }

    # 通過 stdin 傳遞測試輸入
    echo "$test_input" | main
    local exit_code=$?

    echo "" >&2
    echo "測試完成，退出碼: $exit_code" >&2
    return $exit_code
}

# 列出支援的 Agent 類型
list_agents() {
    echo "📋 支援的 Agent 類型與對應經驗檔案"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local agents
    agents=$(list_supported_agents)

    for agent in $agents; do
        local exp_file
        exp_file=$(get_experience_file "$agent")
        local full_path="${EXPERIENCES_DIR}/${exp_file}"

        if [ -f "$full_path" ]; then
            printf "  ✅ %s → %s\n" "$agent" "$exp_file"
        else
            printf "  ⬜ %s → %s (檔案不存在)\n" "$agent" "$exp_file"
        fi
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📁 經驗檔案目錄: $EXPERIENCES_DIR"
}

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-run}" in
        run)
            main
            exit $?
            ;;
        test)
            run_test_mode "${2:-developer}"
            exit $?
            ;;
        list)
            list_agents
            exit 0
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
