#!/usr/bin/env bash
# memory-categorize.sh - 記憶分類邏輯工具
# 功能：根據記憶的內容和來源，決定應該儲存到哪個位置
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-categorize.sh"

set -euo pipefail

# 載入依賴
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/../core/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義（使用 CATEGORIZE_ 前綴避免衝突）
# ═══════════════════════════════════════════════════════════════

# 返回碼
readonly CATEGORIZE_SUCCESS=0
readonly CATEGORIZE_ERROR=1
readonly CATEGORIZE_INVALID_INPUT=2

# 記憶分類
readonly CATEGORY_LONG_TERM="long_term"
readonly CATEGORY_SESSION="session"
readonly CATEGORY_DAILY="daily"
readonly CATEGORY_EXPERIENCE="experience"

# 記憶目錄
readonly CATEGORIZE_MEMORY_DIR="${PWD}/.claude/memory"
readonly CATEGORIZE_LONG_TERM_FILE="${CATEGORIZE_MEMORY_DIR}/MEMORY.md"
readonly CATEGORIZE_SESSION_DIR="${CATEGORIZE_MEMORY_DIR}/sessions"
readonly CATEGORIZE_DAILY_DIR="${CATEGORIZE_MEMORY_DIR}/daily"
readonly CATEGORIZE_EXPERIENCE_DIR="${CATEGORIZE_MEMORY_DIR}/experiences"

# 來源類型（對應 memory-provenance.sh）
readonly CATEGORIZE_SOURCE_USER="user"
readonly CATEGORIZE_SOURCE_AGENT_IMPLICIT="agent_implicit"
readonly CATEGORIZE_SOURCE_SYSTEM="system"

# 偏好關鍵字（中文）
readonly CATEGORIZE_PREFER_KEYWORDS_ZH="偏好|喜歡|總是|永遠|禁止|不要|習慣|一直"

# 偏好關鍵字（英文）
readonly CATEGORIZE_PREFER_KEYWORDS_EN="prefer|like|always|never|don't|avoid|habit|usually"

# ═══════════════════════════════════════════════════════════════
# 核心功能：分類判斷
# ═══════════════════════════════════════════════════════════════

# 檢查內容是否包含偏好關鍵字
# 用法: contains_preference_keywords "content"
# 返回: 0=包含，1=不包含
contains_preference_keywords() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        return 1
    fi

    # 檢查中文關鍵字
    if echo "$content" | grep -qE "$CATEGORIZE_PREFER_KEYWORDS_ZH"; then
        return 0
    fi

    # 檢查英文關鍵字
    if echo "$content" | grep -qiE "$CATEGORIZE_PREFER_KEYWORDS_EN"; then
        return 0
    fi

    return 1
}

# 分類記憶
# 用法: categorize_memory content source_type [context]
# 參數:
#   content     - 記憶內容
#   source_type - 來源類型 (user|agent_implicit|system)
#   context     - 可選，額外上下文（如 agent_type）
# 輸出: 分類結果 (long_term|session|daily|experience)
categorize_memory() {
    local content="${1:-}"
    local source_type="${2:-}"
    local context="${3:-}"

    if [ -z "$content" ]; then
        echo "錯誤：categorize_memory 需要提供 content" >&2
        return $CATEGORIZE_INVALID_INPUT
    fi

    if [ -z "$source_type" ]; then
        echo "錯誤：categorize_memory 需要提供 source_type" >&2
        return $CATEGORIZE_INVALID_INPUT
    fi

    # 驗證 source_type
    case "$source_type" in
        "$CATEGORIZE_SOURCE_USER"|"$CATEGORIZE_SOURCE_AGENT_IMPLICIT"|"$CATEGORIZE_SOURCE_SYSTEM")
            # 合法
            ;;
        *)
            echo "錯誤：不合法的 source_type: $source_type" >&2
            echo "  合法值: $CATEGORIZE_SOURCE_USER, $CATEGORIZE_SOURCE_AGENT_IMPLICIT, $CATEGORIZE_SOURCE_SYSTEM" >&2
            return $CATEGORIZE_ERROR
            ;;
    esac

    # 規則 1: 用戶明確偏好 → long_term
    if [ "$source_type" = "$CATEGORIZE_SOURCE_USER" ]; then
        if contains_preference_keywords "$content"; then
            echo "$CATEGORY_LONG_TERM"
            return $CATEGORIZE_SUCCESS
        fi
    fi

    # 規則 2: Agent 經驗 → experience
    if [ "$source_type" = "$CATEGORIZE_SOURCE_AGENT_IMPLICIT" ]; then
        echo "$CATEGORY_EXPERIENCE"
        return $CATEGORIZE_SUCCESS
    fi

    # 規則 3: 系統生成（PreCompact） → session
    if [ "$source_type" = "$CATEGORIZE_SOURCE_SYSTEM" ]; then
        echo "$CATEGORY_SESSION"
        return $CATEGORIZE_SUCCESS
    fi

    # 規則 4: 預設 → session
    echo "$CATEGORY_SESSION"
    return $CATEGORIZE_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：路徑取得
# ═══════════════════════════════════════════════════════════════

# 取得目標路徑
# 用法: get_target_path category [context]
# 參數:
#   category - 分類 (long_term|session|daily|experience)
#   context  - 可選，額外上下文（如 agent_type）
# 輸出: 完整檔案路徑
get_target_path() {
    local category="${1:-}"
    local context="${2:-}"

    if [ -z "$category" ]; then
        echo "錯誤：get_target_path 需要提供 category" >&2
        return $CATEGORIZE_INVALID_INPUT
    fi

    # 驗證 category
    case "$category" in
        "$CATEGORY_LONG_TERM"|"$CATEGORY_SESSION"|"$CATEGORY_DAILY"|"$CATEGORY_EXPERIENCE")
            # 合法
            ;;
        *)
            echo "錯誤：不合法的 category: $category" >&2
            echo "  合法值: $CATEGORY_LONG_TERM, $CATEGORY_SESSION, $CATEGORY_DAILY, $CATEGORY_EXPERIENCE" >&2
            return $CATEGORIZE_ERROR
            ;;
    esac

    case "$category" in
        "$CATEGORY_LONG_TERM")
            echo "$CATEGORIZE_LONG_TERM_FILE"
            ;;
        "$CATEGORY_SESSION")
            local date_str=$(date -u +%Y-%m-%d)
            echo "${CATEGORIZE_SESSION_DIR}/${date_str}.jsonl"
            ;;
        "$CATEGORY_DAILY")
            local date_str=$(date -u +%Y-%m-%d)
            echo "${CATEGORIZE_DAILY_DIR}/${date_str}.md"
            ;;
        "$CATEGORY_EXPERIENCE")
            local agent="${context:-unknown}"
            echo "${CATEGORIZE_EXPERIENCE_DIR}/${agent}-patterns.md"
            ;;
    esac

    return $CATEGORIZE_SUCCESS
}

# 綜合功能：分類並取得路徑
# 用法: categorize_and_get_path content source_type [context]
# 參數:
#   content     - 記憶內容
#   source_type - 來源類型
#   context     - 可選，額外上下文（如 agent_type）
# 輸出: JSON 格式 {"category":"...", "target_path":"..."}
categorize_and_get_path() {
    local content="${1:-}"
    local source_type="${2:-}"
    local context="${3:-}"

    # 步驟 1: 分類
    local category
    category=$(categorize_memory "$content" "$source_type" "$context")
    local status=$?

    if [ $status -ne $CATEGORIZE_SUCCESS ]; then
        return $status
    fi

    # 步驟 2: 取得路徑
    local target_path
    target_path=$(get_target_path "$category" "$context")
    status=$?

    if [ $status -ne $CATEGORIZE_SUCCESS ]; then
        return $status
    fi

    # 步驟 3: 組裝 JSON
    cat <<EOF
{
  "category": "$category",
  "target_path": "$target_path"
}
EOF

    return $CATEGORIZE_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示分類規則說明
show_categorization_rules() {
    cat <<'EOF'
記憶分類規則
═══════════════════════════════════════

規則 1: 用戶明確偏好 → long_term
  條件: source_type = user AND 包含偏好關鍵字
  目標: .claude/memory/MEMORY.md
  關鍵字（中文）: 偏好、喜歡、總是、永遠、禁止、不要、習慣、一直
  關鍵字（英文）: prefer, like, always, never, don't, avoid, habit, usually

規則 2: Agent 經驗 → experience
  條件: source_type = agent_implicit
  目標: .claude/memory/experiences/{agent}-patterns.md
  說明: Agent 自動推論的經驗模式

規則 3: 系統生成 → session
  條件: source_type = system
  目標: .claude/memory/sessions/YYYY-MM-DD.jsonl
  說明: PreCompact 等系統自動生成的記憶

規則 4: 預設 → session
  條件: 其他所有情況
  目標: .claude/memory/sessions/YYYY-MM-DD.jsonl
  說明: 預設儲存到當日 Session 記錄

分類優先級:
  1. 用戶偏好（最重要）
  2. Agent 經驗
  3. 系統生成
  4. 預設（Session）

目標路徑:
  - long_term   : .claude/memory/MEMORY.md
  - session     : .claude/memory/sessions/YYYY-MM-DD.jsonl
  - daily       : .claude/memory/daily/YYYY-MM-DD.md
  - experience  : .claude/memory/experiences/{agent}-patterns.md
EOF
}

# 顯示使用說明
show_categorize_help() {
    cat <<'EOF'
記憶分類邏輯工具 (Memory Categorization)

用法:
  source memory-categorize.sh

函式:
  contains_preference_keywords <content>
    檢查內容是否包含偏好關鍵字
    參數: content - 要檢查的內容
    返回: 0=包含，1=不包含

  categorize_memory <content> <source_type> [context]
    根據內容和來源決定分類
    參數:
      content     - 記憶內容
      source_type - 來源類型 (user|agent_implicit|system)
      context     - 可選，額外上下文（如 agent_type）
    輸出: 分類結果 (long_term|session|daily|experience)

  get_target_path <category> [context]
    根據分類取得目標路徑
    參數:
      category - 分類 (long_term|session|daily|experience)
      context  - 可選，額外上下文（如 agent_type）
    輸出: 完整檔案路徑

  categorize_and_get_path <content> <source_type> [context]
    綜合功能：分類並取得路徑
    參數:
      content     - 記憶內容
      source_type - 來源類型
      context     - 可選，額外上下文
    輸出: JSON 格式 {"category":"...", "target_path":"..."}

  show_categorization_rules
    顯示分類規則說明

範例:
  # 檢查是否包含偏好關鍵字
  if contains_preference_keywords "我偏好使用 TypeScript"; then
    echo "包含偏好關鍵字"
  fi

  # 分類記憶
  category=$(categorize_memory "我總是使用 const" "user")
  echo "分類: $category"

  # 取得目標路徑
  target_path=$(get_target_path "long_term")
  echo "目標路徑: $target_path"

  # 綜合功能
  result=$(categorize_and_get_path "我喜歡 TypeScript" "user")
  echo "$result"

  # Agent 經驗分類
  result=$(categorize_and_get_path "審查拒絕原因: 缺少錯誤處理" "agent_implicit" "reviewer")
  echo "$result"

  # 顯示分類規則
  show_categorization_rules

來源類型:
  - user           : 用戶明確提供的記憶
  - agent_implicit : Agent 推論得出的記憶
  - system         : 系統自動生成的記憶

分類結果:
  - long_term   : 長期記憶（用戶偏好、技術棧、專案規範）
  - session     : Session 記錄（決策、任務進度）
  - daily       : 每日摘要（工作日誌）
  - experience  : Agent 經驗（審查模式、測試策略）

分類規則:
  1. 用戶偏好（含關鍵字）→ long_term
  2. Agent 經驗          → experience
  3. 系統生成            → session
  4. 預設                → session
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        check-keywords)
            shift
            if contains_preference_keywords "$@"; then
                echo "✅ 包含偏好關鍵字"
                exit 0
            else
                echo "❌ 不包含偏好關鍵字"
                exit 1
            fi
            ;;
        categorize)
            shift
            categorize_memory "$@"
            exit $?
            ;;
        get-path)
            shift
            get_target_path "$@"
            exit $?
            ;;
        categorize-and-path)
            shift
            categorize_and_get_path "$@"
            exit $?
            ;;
        rules)
            show_categorization_rules
            exit 0
            ;;
        help|--help|-h|*)
            show_categorize_help
            exit 0
            ;;
    esac
fi
