#!/usr/bin/env bash
# token-budget.sh - Token 預算控制函式庫
# 功能：提供 Token 計算、預算控制和截斷策略的共用函式
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/token-budget.sh"
# 相容性：Bash 3.2+（macOS 預設版本）

# 防止重複載入
[ -n "${TOKEN_BUDGET_SH_LOADED:-}" ] && return 0
readonly TOKEN_BUDGET_SH_LOADED=1

# 載入依賴庫（如果尚未載入）
MY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -z "${COMMON_SH_LOADED:-}" ] && source "${MY_LIB_DIR}/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# Token 預算常數（對應不同注入點）
readonly TOKEN_BUDGET_SESSION_START=200
readonly TOKEN_BUDGET_USER_PROMPT=300
readonly TOKEN_BUDGET_SUBAGENT_MIN=150
readonly TOKEN_BUDGET_SUBAGENT_MAX=200
readonly TOKEN_BUDGET_SUBAGENT=$(( (TOKEN_BUDGET_SUBAGENT_MIN + TOKEN_BUDGET_SUBAGENT_MAX) / 2 ))

# 單一記憶片段最大 Token 數（防止注入攻擊）
readonly TOKEN_MAX_SINGLE_MEMORY=500

# Token 估算策略常數
# 英文：約 4 字元 = 1 token
# 中文：約 1.5 字元 = 1 token
# 混合文本保守估計：3 字元 = 1 token
readonly TOKEN_ESTIMATE_CHARS_PER_TOKEN=3
readonly TOKEN_ESTIMATE_LINES_PER_TOKEN=10  # 平均每行約 10 tokens（舊版相容）

# 返回碼（使用 TOKEN_ 前綴避免衝突）
readonly TOKEN_EXIT_SUCCESS=0
readonly TOKEN_EXIT_ERROR=1
readonly TOKEN_EXIT_OVER_BUDGET=2
readonly TOKEN_EXIT_ATTACK_DETECTED=3

# 截斷提示訊息
readonly TOKEN_TRUNCATE_HINT="... (已截斷，完整內容見原始檔案)"

# ═══════════════════════════════════════════════════════════════
# 核心功能 - Token 計算
# ═══════════════════════════════════════════════════════════════

# 計算文本的 Token 數量（保守估算）
# 用法: token_count=$(count_tokens "$text")
# 參數: text - 要計算的文本
# 輸出: 估算的 Token 數量（整數）
# 返回: 0=成功，1=錯誤
count_tokens() {
    local text="${1:-}"

    if [ -z "$text" ]; then
        echo "0"
        return $TOKEN_EXIT_SUCCESS
    fi

    # 計算字元數
    local char_count
    char_count=$(printf "%s" "$text" | wc -c | tr -d ' ')

    # 估算 Token 數：字元數 / 3（保守估計）
    local token_count=$(( char_count / TOKEN_ESTIMATE_CHARS_PER_TOKEN ))

    # 至少返回 1（如果有內容）
    if [ "$token_count" -eq 0 ] && [ -n "$text" ]; then
        token_count=1
    fi

    echo "$token_count"
    return $TOKEN_EXIT_SUCCESS
}

# 計算文本的行數
# 用法: line_count=$(count_lines "$text")
# 參數: text - 要計算的文本
# 輸出: 行數（整數）
# 返回: 0=成功
count_lines() {
    local text="${1:-}"

    if [ -z "$text" ]; then
        echo "0"
        return $TOKEN_EXIT_SUCCESS
    fi

    local line_count
    line_count=$(printf "%s" "$text" | wc -l | tr -d ' ')

    echo "$line_count"
    return $TOKEN_EXIT_SUCCESS
}

# 使用行數估算 Token 數量（舊版相容）
# 用法: token_count=$(estimate_tokens_by_lines "$text")
# 參數: text - 要計算的文本
# 輸出: 估算的 Token 數量（整數）
# 返回: 0=成功
estimate_tokens_by_lines() {
    local text="${1:-}"

    if [ -z "$text" ]; then
        echo "0"
        return $TOKEN_EXIT_SUCCESS
    fi

    local line_count
    line_count=$(count_lines "$text")

    # 估算 Token 數：行數 × 10
    local token_count=$(( line_count * TOKEN_ESTIMATE_LINES_PER_TOKEN ))

    echo "$token_count"
    return $TOKEN_EXIT_SUCCESS
}

# 取得 Token 統計資訊
# 用法: stats=$(get_token_stats "$text")
# 參數: text - 要分析的文本
# 輸出: JSON 格式的統計資訊
# 返回: 0=成功，1=錯誤
get_token_stats() {
    local text="${1:-}"

    if [ -z "$text" ]; then
        echo '{"chars":0,"lines":0,"tokens":0,"method":"estimate"}'
        return $TOKEN_EXIT_SUCCESS
    fi

    local char_count
    char_count=$(printf "%s" "$text" | wc -c | tr -d ' ')

    local line_count
    line_count=$(count_lines "$text")

    local token_count
    token_count=$(count_tokens "$text")

    # 輸出 JSON 格式
    cat <<EOF
{"chars":$char_count,"lines":$line_count,"tokens":$token_count,"method":"estimate"}
EOF

    return $TOKEN_EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 - 預算控制
# ═══════════════════════════════════════════════════════════════

# 驗證單一記憶片段是否超過最大限制（防止注入攻擊）
# 用法: validate_memory_size "$content"
# 參數: content - 記憶內容
# 返回: 0=合法，TOKEN_EXIT_OVER_BUDGET=超出預算，TOKEN_EXIT_ATTACK_DETECTED=疑似攻擊
validate_memory_size() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        return $TOKEN_EXIT_SUCCESS
    fi

    local token_count
    token_count=$(count_tokens "$content")

    if [ "$token_count" -gt "$TOKEN_MAX_SINGLE_MEMORY" ]; then
        # 超過單一記憶最大限制，疑似注入攻擊
        return $TOKEN_EXIT_ATTACK_DETECTED
    fi

    return $TOKEN_EXIT_SUCCESS
}

# 檢查文本是否超過預算
# 用法: check_token_budget "$text" <max_tokens>
# 參數: text - 要檢查的文本，max_tokens - Token 預算
# 返回: 0=未超出，TOKEN_EXIT_OVER_BUDGET=超出預算
check_token_budget() {
    local text="${1:-}"
    local max_tokens="${2:-0}"

    if [ -z "$text" ]; then
        return $TOKEN_EXIT_SUCCESS
    fi

    if [ "$max_tokens" -le 0 ]; then
        # 無限預算
        return $TOKEN_EXIT_SUCCESS
    fi

    local token_count
    token_count=$(count_tokens "$text")

    if [ "$token_count" -gt "$max_tokens" ]; then
        return $TOKEN_EXIT_OVER_BUDGET
    fi

    return $TOKEN_EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 - 截斷策略
# ═══════════════════════════════════════════════════════════════

# 截斷文本到指定 Token 預算（按行截斷）
# 用法: truncated=$(truncate_to_budget "$text" <max_tokens>)
# 參數: text - 要截斷的文本，max_tokens - Token 預算
# 輸出: 截斷後的文本（如果需要，會添加截斷提示）
# 返回: 0=成功（未截斷或已截斷），1=錯誤
truncate_to_budget() {
    local text="${1:-}"
    local max_tokens="${2:-0}"

    if [ -z "$text" ]; then
        printf ""
        return $TOKEN_EXIT_SUCCESS
    fi

    if [ "$max_tokens" -le 0 ]; then
        # 無限預算，返回原文
        printf "%s" "$text"
        return $TOKEN_EXIT_SUCCESS
    fi

    # 先檢查是否超出預算
    if check_token_budget "$text" "$max_tokens"; then
        # 未超出，返回原文
        printf "%s" "$text"
        return $TOKEN_EXIT_SUCCESS
    fi

    # 超出預算，需要截斷
    # 策略 1：按行截斷（保持完整性）
    local max_lines=$(( max_tokens / TOKEN_ESTIMATE_LINES_PER_TOKEN ))
    local total_lines
    total_lines=$(count_lines "$text")

    if [ "$max_lines" -le 0 ]; then
        max_lines=1
    fi

    # 提取前 N 行
    local truncated
    truncated=$(printf "%s" "$text" | head -n "$max_lines")

    # 添加截斷提示（如果有截斷）
    if [ "$total_lines" -gt "$max_lines" ]; then
        truncated+=$'\n'
        truncated+="$TOKEN_TRUNCATE_HINT"
    fi

    printf "%s" "$truncated"
    return $TOKEN_EXIT_SUCCESS
}

# 截斷文本到指定 Token 預算（精確版，使用字元數）
# 用法: truncated=$(truncate_to_budget_precise "$text" <max_tokens>)
# 參數: text - 要截斷的文本，max_tokens - Token 預算
# 輸出: 截斷後的文本（如果需要，會添加截斷提示）
# 返回: 0=成功（未截斷或已截斷），1=錯誤
truncate_to_budget_precise() {
    local text="${1:-}"
    local max_tokens="${2:-0}"

    if [ -z "$text" ]; then
        printf ""
        return $TOKEN_EXIT_SUCCESS
    fi

    if [ "$max_tokens" -le 0 ]; then
        # 無限預算，返回原文
        printf "%s" "$text"
        return $TOKEN_EXIT_SUCCESS
    fi

    # 先檢查是否超出預算
    if check_token_budget "$text" "$max_tokens"; then
        # 未超出，返回原文
        printf "%s" "$text"
        return $TOKEN_EXIT_SUCCESS
    fi

    # 超出預算，需要截斷
    # 策略 2：按字元數截斷（更精確）
    local max_chars=$(( max_tokens * TOKEN_ESTIMATE_CHARS_PER_TOKEN ))
    local total_chars
    total_chars=$(printf "%s" "$text" | wc -c | tr -d ' ')

    # 提取前 N 個字元
    local truncated
    truncated=$(printf "%s" "$text" | head -c "$max_chars")

    # 添加截斷提示（如果有截斷）
    if [ "$total_chars" -gt "$max_chars" ]; then
        truncated+=$'\n'
        truncated+="$TOKEN_TRUNCATE_HINT"
    fi

    printf "%s" "$truncated"
    return $TOKEN_EXIT_SUCCESS
}

# 計算截斷比例
# 用法: ratio=$(get_truncate_ratio "$original_text" "$truncated_text")
# 參數: original_text - 原始文本，truncated_text - 截斷後的文本
# 輸出: 截斷比例（0-100 的整數，100 表示完全保留）
# 返回: 0=成功
get_truncate_ratio() {
    local original="${1:-}"
    local truncated="${2:-}"

    if [ -z "$original" ]; then
        echo "100"
        return $TOKEN_EXIT_SUCCESS
    fi

    local original_tokens
    original_tokens=$(count_tokens "$original")

    local truncated_tokens
    truncated_tokens=$(count_tokens "$truncated")

    if [ "$original_tokens" -eq 0 ]; then
        echo "100"
        return $TOKEN_EXIT_SUCCESS
    fi

    local ratio=$(( truncated_tokens * 100 / original_tokens ))

    echo "$ratio"
    return $TOKEN_EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 向後相容層（供現有腳本使用）
# ═══════════════════════════════════════════════════════════════

# 舊版相容函式：apply_token_budget（SessionStart）
# 用法: content=$(apply_token_budget "$original_content")
# 參數: content - 原始內容
# 輸出: 限制後的內容
# 返回: 0=成功
# 注意：此函式使用 SESSION_START 預算，並按行截斷
apply_token_budget_session_start() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        printf ""
        return $TOKEN_EXIT_SUCCESS
    fi

    # 簡單估算：平均 1 行 ≈ 10 tokens
    # Token 預算 200 → 約 20 行
    local max_lines=$(( TOKEN_BUDGET_SESSION_START / TOKEN_ESTIMATE_LINES_PER_TOKEN ))

    # 提取前 N 行
    local budgeted_content
    budgeted_content=$(printf "%s" "$content" | head -n "$max_lines")

    # 檢查是否有截斷
    local total_lines
    total_lines=$(count_lines "$content")

    if [ "$total_lines" -gt "$max_lines" ]; then
        # 有截斷，添加提示
        budgeted_content+=$'\n'
        budgeted_content+="..."$'\n'
        budgeted_content+="（完整記憶請見 .claude/memory/MEMORY.md）"$'\n'
    fi

    printf "%s" "$budgeted_content"
    return $TOKEN_EXIT_SUCCESS
}

# 舊版相容函式：apply_token_budget（UserPrompt）
# 用法: content=$(apply_token_budget "$original_content")
# 參數: content - 原始內容
# 輸出: 限制後的內容
# 返回: 0=成功
apply_token_budget_user_prompt() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        printf ""
        return $TOKEN_EXIT_SUCCESS
    fi

    # Token 預算 300 → 約 30 行
    local max_lines=$(( TOKEN_BUDGET_USER_PROMPT / TOKEN_ESTIMATE_LINES_PER_TOKEN ))

    local budgeted_content
    budgeted_content=$(printf "%s" "$content" | head -n "$max_lines")

    local total_lines
    total_lines=$(count_lines "$content")

    if [ "$total_lines" -gt "$max_lines" ]; then
        budgeted_content+=$'\n'
        budgeted_content+="..."$'\n'
        budgeted_content+="（完整記憶請見 .claude/memory/）"$'\n'
    fi

    printf "%s" "$budgeted_content"
    return $TOKEN_EXIT_SUCCESS
}

# 舊版相容函式：apply_token_budget（Subagent）
# 用法: content=$(apply_token_budget "$original_content" "$agent_type")
# 參數: content - 原始內容，agent_type - Agent 類型（用於截斷提示）
# 輸出: 限制後的內容
# 返回: 0=成功
apply_token_budget_subagent() {
    local content="${1:-}"
    local agent_type="${2:-unknown}"

    if [ -z "$content" ]; then
        printf ""
        return $TOKEN_EXIT_SUCCESS
    fi

    # Token 預算 150-200 → 約 15-20 行
    local max_lines=$(( TOKEN_BUDGET_SUBAGENT / TOKEN_ESTIMATE_LINES_PER_TOKEN ))

    local budgeted_content
    budgeted_content=$(printf "%s" "$content" | head -n "$max_lines")

    local total_lines
    total_lines=$(count_lines "$content")

    if [ "$total_lines" -gt "$max_lines" ]; then
        # 構造經驗檔案名稱提示（簡化版，不載入 get_experience_file）
        local hint_file="${agent_type}-tips.md"
        case "$agent_type" in
            developer) hint_file="developer-tips.md" ;;
            reviewer) hint_file="reviewer-patterns.md" ;;
            tester) hint_file="tester-strategies.md" ;;
            debugger) hint_file="debugger-solutions.md" ;;
            architect) hint_file="architect-decisions.md" ;;
            designer) hint_file="designer-guidelines.md" ;;
        esac

        budgeted_content+=$'\n'
        budgeted_content+="..."$'\n'
        budgeted_content+="(完整經驗請見 .claude/memory/experiences/${hint_file})"$'\n'
    fi

    printf "%s" "$budgeted_content"
    return $TOKEN_EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_help() {
    cat <<'EOF'
用法: token-budget.sh <command> [arguments]

指令:

  count <text>                  計算文本的 Token 數量
  stats <text>                  取得文本的 Token 統計資訊（JSON 格式）
  validate <text>               驗證單一記憶是否超過 500 tokens
  truncate <text> <max_tokens>  截斷文本到指定預算
  ratio <original> <truncated>  計算截斷比例

  help                          顯示此說明

功能:

  - Token 計算：使用保守估算（3 字元 = 1 token）
  - 預算控制：驗證內容是否超過預算
  - 截斷策略：優先按行截斷，保持完整性
  - 單一記憶最大 500 tokens（防止注入攻擊）

常數定義:

  TOKEN_BUDGET_SESSION_START=200      # SessionStart Hook 預算
  TOKEN_BUDGET_USER_PROMPT=300        # UserPromptSubmit Hook 預算
  TOKEN_BUDGET_SUBAGENT=175           # SubagentStart Hook 預算
  TOKEN_MAX_SINGLE_MEMORY=500         # 單一記憶最大 Token 數

核心函式:

  count_tokens <text>                 計算 Token 數量
  get_token_stats <text>              取得統計資訊（JSON）
  validate_memory_size <content>      驗證記憶大小
  check_token_budget <text> <max>     檢查是否超出預算
  truncate_to_budget <text> <max>     截斷到預算（按行）
  truncate_to_budget_precise <text> <max>  截斷到預算（按字元）
  get_truncate_ratio <orig> <trunc>   計算截斷比例

舊版相容函式（供現有腳本遷移使用）:

  apply_token_budget_session_start <content>       # SessionStart
  apply_token_budget_user_prompt <content>         # UserPrompt
  apply_token_budget_subagent <content> <agent>    # Subagent

返回碼:

  TOKEN_EXIT_SUCCESS=0          成功
  TOKEN_EXIT_ERROR=1            錯誤
  TOKEN_EXIT_OVER_BUDGET=2      超出預算
  TOKEN_EXIT_ATTACK_DETECTED=3  疑似注入攻擊（超過 500 tokens）

範例:

  # 作為函式庫使用（在其他腳本中）
  source "hooks/scripts/lib/token-budget.sh"
  token_count=$(count_tokens "Hello, world!")
  truncated=$(truncate_to_budget "$long_text" 200)

  # 作為 CLI 執行（測試）
  bash hooks/scripts/lib/token-budget.sh count "Hello, world!"
  bash hooks/scripts/lib/token-budget.sh stats "$(cat file.txt)"
  bash hooks/scripts/lib/token-budget.sh validate "$(cat memory.md)"
  bash hooks/scripts/lib/token-budget.sh truncate "$(cat long.txt)" 200

測試案例:

  # 測試 1: 計算 Token 數量
  echo "測試文本" | xargs bash hooks/scripts/lib/token-budget.sh count

  # 測試 2: 驗證記憶大小（應該成功）
  echo "正常大小的記憶片段" | xargs bash hooks/scripts/lib/token-budget.sh validate

  # 測試 3: 截斷長文本
  cat long-file.txt | xargs bash hooks/scripts/lib/token-budget.sh truncate 200

注意:

  - Token 估算為保守估計，實際可能略有不同
  - 中英文混合文本按 3 字元/token 計算
  - 截斷策略優先按行，保持 Markdown 格式完整性
  - 單一記憶超過 500 tokens 視為疑似注入攻擊
EOF
}

# CLI 入口
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        count)
            shift
            count_tokens "$*"
            ;;
        stats)
            shift
            get_token_stats "$*"
            ;;
        validate)
            shift
            validate_memory_size "$*"
            exit_code=$?
            case $exit_code in
                $TOKEN_EXIT_SUCCESS)
                    echo "✅ 合法（未超過 ${TOKEN_MAX_SINGLE_MEMORY} tokens）"
                    ;;
                $TOKEN_EXIT_ATTACK_DETECTED)
                    echo "⚠️  疑似注入攻擊（超過 ${TOKEN_MAX_SINGLE_MEMORY} tokens）"
                    ;;
            esac
            exit $exit_code
            ;;
        truncate)
            shift
            max_tokens="${1:-0}"
            if [ "$max_tokens" -le 0 ]; then
                echo "錯誤：需要提供有效的 Token 預算" >&2
                echo "用法: token-budget.sh truncate <max_tokens> < file.txt" >&2
                exit $TOKEN_EXIT_ERROR
            fi
            # 從 stdin 讀取文本
            text=$(cat)
            if [ -z "$text" ]; then
                echo "錯誤：未提供文本輸入" >&2
                exit $TOKEN_EXIT_ERROR
            fi
            truncate_to_budget "$text" "$max_tokens"
            ;;
        ratio)
            shift
            # 從 stdin 讀取兩個文本（用分隔符分開）
            if [ $# -eq 0 ]; then
                echo "錯誤：需要提供原始文本和截斷後的文本" >&2
                echo "用法: token-budget.sh ratio <original> <truncated>" >&2
                exit $TOKEN_EXIT_ERROR
            fi
            original="${1:-}"
            truncated="${2:-}"
            ratio=$(get_truncate_ratio "$original" "$truncated")
            echo "${ratio}%"
            ;;
        help|--help|-h)
            show_help
            exit $TOKEN_EXIT_SUCCESS
            ;;
        *)
            echo "錯誤：無效的指令 '${1}'" >&2
            echo "" >&2
            show_help
            exit $TOKEN_EXIT_ERROR
            ;;
    esac
fi
