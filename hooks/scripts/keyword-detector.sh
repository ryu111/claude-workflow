#!/bin/bash
# keyword-detector.sh - 用戶輸入關鍵字檢測
# 事件: UserPromptSubmit
# 功能: 檢測用戶輸入中的關鍵字，並注入相應的提示內容
# 作用: 提供上下文敏感的 AI 輔助

# ═══════════════════════════════════════════════════════════════
# 框架設定
# ═══════════════════════════════════════════════════════════════

# DEBUG: 記錄 hook 被呼叫
DEBUG_LOG="/tmp/claude-workflow-debug.log"
echo "[$(date)] keyword-detector.sh called" >> "$DEBUG_LOG"

# ═══════════════════════════════════════════════════════════════
# JSON 輸入處理
# ═══════════════════════════════════════════════════════════════

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)
echo "[$(date)] INPUT: $INPUT" >> "$DEBUG_LOG"

# 驗證 JSON 格式（先測試是否為有效 JSON）
if ! echo "$INPUT" | jq empty 2>/dev/null; then
    echo "[$(date)] ERROR: Invalid JSON input" >> "$DEBUG_LOG"
    echo "❌ 錯誤：無效的 JSON 輸入格式" >&2
    exit 1
fi

# 解析 userPrompt 欄位
USER_PROMPT=$(echo "$INPUT" | jq -r '.userPrompt // empty' 2>/dev/null)

# 記錄解析結果
echo "[$(date)] USER_PROMPT extracted: ${USER_PROMPT:0:100}..." >> "$DEBUG_LOG"

# ═══════════════════════════════════════════════════════════════
# 基本錯誤處理
# ═══════════════════════════════════════════════════════════════

# 檢查 userPrompt 是否為空
if [ -z "$USER_PROMPT" ]; then
    echo "[$(date)] WARNING: userPrompt is empty" >> "$DEBUG_LOG"
    # 空輸入時返回空的 additionalContext
    cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": ""
  }
}
EOF
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
# 關鍵字映射表定義
# ═══════════════════════════════════════════════════════════════

# 關鍵字映射：優先級|類型|關鍵字列表
# 優先級數字越小越高
# 注意：不使用 'plan' 關鍵字（與 Claude Code Plan Mode 衝突）
# 注意：多字詞請保持空格（如 "修 bug"），匹配函數會處理
readonly KEYWORD_MAPPINGS=(
  "1|ARCHITECT|規劃 架構 系統設計"
  "2|DESIGNER|設計 UI UX 界面 介面"
  "3|RESUME|接手 resume"
  "4|LOOP|loop 持續 繼續"
  "5|DEVELOPER|實作 開發 寫程式碼 implement"
  "6|REVIEWER|審查 review 檢查程式碼"
  "7|TESTER|測試 test 驗證"
  "8|DEBUGGER|debug 除錯 修 bug"
)

# ═══════════════════════════════════════════════════════════════
# 關鍵字匹配函數
# ═══════════════════════════════════════════════════════════════

# 全字匹配函數（支援中英文，忽略大小寫）
# 參數：
#   $1 - 用戶輸入的完整 prompt
#   $2 - 要匹配的關鍵字
# 返回：0 = 匹配成功，1 = 未匹配
#
# 匹配策略：
#   - 英文：使用 word boundary，避免「test」匹配「testing」
#   - 中文：直接子字串匹配（中文詞語間無分隔符）
match_keyword() {
    local prompt="$1"
    local keyword="$2"

    # 轉換為小寫進行比對
    local prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
    local keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')

    # 檢查關鍵字是否包含英文字母
    if echo "$keyword" | grep -q '[a-zA-Z]'; then
        # 英文關鍵字：使用 -w 全字匹配
        echo "$prompt_lower" | grep -qw "$keyword_lower"
    else
        # 中文關鍵字：直接匹配子字串
        # 使用 grep -F（固定字串）避免特殊字元問題
        echo "$prompt_lower" | grep -qF "$keyword_lower"
    fi
}

# 檢測關鍵字並返回最高優先級的匹配
# 參數：$1 - 用戶輸入的 prompt
# 輸出：匹配的類型（如 ARCHITECT）或空字串
detect_keywords() {
    local prompt="$1"
    local best_match=""
    local best_priority=999

    # 遍歷所有關鍵字映射
    for mapping in "${KEYWORD_MAPPINGS[@]}"; do
        # 解析映射：priority|type|keywords
        local priority=$(echo "$mapping" | cut -d'|' -f1)
        local type=$(echo "$mapping" | cut -d'|' -f2)
        local keywords=$(echo "$mapping" | cut -d'|' -f3)

        # 檢查該類型的所有關鍵字
        for keyword in $keywords; do
            if match_keyword "$prompt" "$keyword"; then
                echo "[$(date)] Matched keyword: '$keyword' -> $type (priority: $priority)" >> "$DEBUG_LOG"

                # 如果優先級更高（數字更小），更新最佳匹配
                if [ "$priority" -lt "$best_priority" ]; then
                    best_match="$type"
                    best_priority="$priority"
                fi
            fi
        done
    done

    # 返回最佳匹配
    echo "$best_match"
}

# ═══════════════════════════════════════════════════════════════
# 範本讀取與變數替換
# ═══════════════════════════════════════════════════════════════

# 載入範本內容
# 參數：$1 - agent 類型（小寫，如 architect, developer）
# 輸出：範本內容或空字串
# 優先級：用戶自訂範本 > 預設範本 > 空字串
load_template() {
    local agent="$1"
    local template_content=""

    # 驗證 CLAUDE_PLUGIN_ROOT 環境變數
    if [ -z "$CLAUDE_PLUGIN_ROOT" ]; then
        echo "[$(date)] ERROR: CLAUDE_PLUGIN_ROOT not set" >> "$DEBUG_LOG"
        echo ""
        return 1
    fi

    # 用戶自訂範本路徑（使用 CLAUDE_PROJECT_ROOT 或 fallback 到 PWD）
    local project_root="${CLAUDE_PROJECT_ROOT:-$PWD}"
    local user_template="${project_root}/.claude/templates/${agent}.md"

    # 預設範本路徑（使用 CLAUDE_PLUGIN_ROOT 環境變數）
    local default_template="${CLAUDE_PLUGIN_ROOT}/hooks/templates/${agent}.md"

    # 優先讀取用戶自訂範本
    if [ -f "$user_template" ]; then
        # 檢查檔案權限
        if [ ! -r "$user_template" ]; then
            echo "[$(date)] WARNING: User template exists but is not readable: $user_template" >> "$DEBUG_LOG"
        else
            template_content=$(cat "$user_template" 2>/dev/null)
            echo "[$(date)] Loaded user template: $user_template" >> "$DEBUG_LOG"
        fi
    fi

    # 如果用戶範本不存在或無法讀取，使用預設範本
    if [ -z "$template_content" ] && [ -f "$default_template" ]; then
        # 檢查檔案權限
        if [ ! -r "$default_template" ]; then
            echo "[$(date)] WARNING: Default template exists but is not readable: $default_template" >> "$DEBUG_LOG"
        else
            template_content=$(cat "$default_template" 2>/dev/null)
            echo "[$(date)] Loaded default template: $default_template" >> "$DEBUG_LOG"
        fi
    fi

    # 範本不存在或無法讀取時記錄警告
    if [ -z "$template_content" ]; then
        echo "[$(date)] WARNING: No accessible template found for agent '$agent'" >> "$DEBUG_LOG"
    fi

    # 輸出範本內容
    echo "$template_content"
}

# 替換範本中的變數
# 參數：
#   $1 - 範本內容
#   $2 - 用戶 prompt
# 輸出：替換後的內容
#
# 安全性：使用 Bash 內建字串替換，100% 安全
# 支援：所有特殊字元（&, /, \, ", ', 換行符等）
# 優點：無外部依賴，跨平台相容
substitute_variables() {
    local template="$1"
    local user_prompt="$2"

    # 使用 Bash 內建的字串替換 ${var//pattern/replacement}
    # 這是最安全的方法，不需要任何轉義
    local result="${template//\{\{PROMPT\}\}/$user_prompt}"

    echo "[$(date)] Variables substituted in template (using Bash builtin)" >> "$DEBUG_LOG"
    echo "$result"
}

# ═══════════════════════════════════════════════════════════════
# 關鍵字檢測執行
# ═══════════════════════════════════════════════════════════════

DETECTED_KEYWORDS=$(detect_keywords "$USER_PROMPT")
ADDITIONAL_CONTEXT=""

# 記錄檢測結果
echo "[$(date)] Detected keywords: $DETECTED_KEYWORDS" >> "$DEBUG_LOG"

# 如果檢測到關鍵字，載入並處理範本
if [ -n "$DETECTED_KEYWORDS" ]; then
    # 將類型轉換為小寫（範本檔案名稱使用小寫）
    AGENT_TYPE=$(echo "$DETECTED_KEYWORDS" | tr '[:upper:]' '[:lower:]')

    # 載入範本
    TEMPLATE=$(load_template "$AGENT_TYPE")

    # 如果範本存在，進行變數替換
    if [ -n "$TEMPLATE" ]; then
        ADDITIONAL_CONTEXT=$(substitute_variables "$TEMPLATE" "$USER_PROMPT")
        echo "[$(date)] Template processed for agent: $AGENT_TYPE" >> "$DEBUG_LOG"
    else
        echo "[$(date)] No template content for agent: $AGENT_TYPE" >> "$DEBUG_LOG"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 輸出 JSON 格式
# ═══════════════════════════════════════════════════════════════

# 構建 JSON 輸出
# 使用 jq 確保 JSON 格式正確
jq -n \
  --arg event "UserPromptSubmit" \
  --arg context "$ADDITIONAL_CONTEXT" \
  '{
    hookSpecificOutput: {
      hookEventName: $event,
      additionalContext: $context
    }
  }'

echo "[$(date)] keyword-detector.sh completed successfully" >> "$DEBUG_LOG"
exit 0
