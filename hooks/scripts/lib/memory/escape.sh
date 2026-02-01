#!/usr/bin/env bash
# memory-escape.sh - 記憶內容安全注入格式工具
# 功能：防止 Prompt Injection 的安全轉義與包裝
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-escape.sh"
# 相容性：Bash 3.2+（macOS 預設版本）

set -uo pipefail

# 載入共用工具函式
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/../core/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義（使用 ESCAPE_ 前綴避免衝突）
# ═══════════════════════════════════════════════════════════════

readonly ESCAPE_EXIT_SUCCESS=0
readonly ESCAPE_EXIT_UNSAFE=1
readonly ESCAPE_EXIT_INVALID_INPUT=2

# 危險標記模式（需要轉義的）
readonly -a ESCAPE_DANGEROUS_PATTERNS=(
    "---"                    # YAML frontmatter
    "\`\`\`"                 # Markdown 程式碼區塊
    "<memory_context>"       # XML 記憶標籤
    "</memory_context>"
    "<system>"              # 系統指令標籤
    "</system>"
    "<instruction>"         # 指令標籤
    "</instruction>"
    "<override>"            # 覆蓋標籤
    "</override>"
    "<agent>"               # Agent 標籤
    "</agent>"
    "<command>"             # 命令標籤
    "</command>"
)

# 信任等級
readonly ESCAPE_TRUST_LOW="low"
readonly ESCAPE_TRUST_MEDIUM="medium"
readonly ESCAPE_TRUST_HIGH="high"

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 轉義記憶內容以安全注入到 Prompt 中
# 用法: escaped=$(escape_memory_for_injection <content>)
# 參數: content - 要轉義的內容
# 返回: 0=成功
# 輸出: 轉義後的內容
escape_memory_for_injection() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        printf ""
        return $ESCAPE_EXIT_SUCCESS
    fi

    local escaped="$content"

    # 轉義策略（依重要性排序）：

    # 1. 轉義 YAML frontmatter 分隔符：--- → \-\-\-
    escaped=$(printf "%s" "$escaped" | sed 's/---/\\-\\-\\-/g')

    # 2. 轉義 Markdown 程式碼區塊：``` → \`\`\`
    escaped=$(printf "%s" "$escaped" | sed 's/```/\\`\\`\\`/g')

    # 3. 轉義 XML 標籤：<tag> → &lt;tag&gt;
    # 特定危險標籤
    escaped=$(printf "%s" "$escaped" | sed 's/<memory_context>/\&lt;memory_context\&gt;/g')
    escaped=$(printf "%s" "$escaped" | sed 's/<\/memory_context>/\&lt;\/memory_context\&gt;/g')
    escaped=$(printf "%s" "$escaped" | sed 's/<system>/\&lt;system\&gt;/g')
    escaped=$(printf "%s" "$escaped" | sed 's/<\/system>/\&lt;\/system\&gt;/g')
    escaped=$(printf "%s" "$escaped" | sed 's/<instruction>/\&lt;instruction\&gt;/g')
    escaped=$(printf "%s" "$escaped" | sed 's/<\/instruction>/\&lt;\/instruction\&gt;/g')
    escaped=$(printf "%s" "$escaped" | sed 's/<override>/\&lt;override\&gt;/g')
    escaped=$(printf "%s" "$escaped" | sed 's/<\/override>/\&lt;\/override\&gt;/g')
    escaped=$(printf "%s" "$escaped" | sed 's/<agent>/\&lt;agent\&gt;/g')
    escaped=$(printf "%s" "$escaped" | sed 's/<\/agent>/\&lt;\/agent\&gt;/g')
    escaped=$(printf "%s" "$escaped" | sed 's/<command>/\&lt;command\&gt;/g')
    escaped=$(printf "%s" "$escaped" | sed 's/<\/command>/\&lt;\/command\&gt;/g')

    # 4. 通用 XML 標籤轉義（處理任意標籤）
    # 開標籤：<tag> → &lt;tag&gt;
    escaped=$(printf "%s" "$escaped" | sed 's/<\([a-zA-Z_][a-zA-Z0-9_]*\)>/\&lt;\1\&gt;/g')
    # 閉標籤：</tag> → &lt;/tag&gt;
    escaped=$(printf "%s" "$escaped" | sed 's/<\/\([a-zA-Z_][a-zA-Z0-9_]*\)>/\&lt;\/\1\&gt;/g')

    # 5. 轉義其他潛在指令標記
    # {{variable}} 樣式（模板注入）→ \{\{variable\}\}
    escaped=$(printf "%s" "$escaped" | sed 's/{{/\\{\\{/g')
    escaped=$(printf "%s" "$escaped" | sed 's/}}/\\}\\}/g')

    # ${variable} 樣式（變數替換）→ \${variable}
    escaped=$(printf "%s" "$escaped" | sed 's/\${/\\${/g')

    printf "%s" "$escaped"
    return $ESCAPE_EXIT_SUCCESS
}

# 使用安全標記包裝記憶
# 用法: wrapped=$(wrap_memory_safely <content> <source_agent> [trust_level])
# 參數:
#   content - 要包裝的內容（已轉義）
#   source_agent - 來源 Agent 名稱
#   trust_level - 信任等級（可選，預設 low）
# 返回: 0=成功，1=無效輸入
# 輸出: 包裝後的 XML 標記內容
wrap_memory_safely() {
    local content="${1:-}"
    local source_agent="${2:-unknown}"
    local trust_level="${3:-$ESCAPE_TRUST_LOW}"

    # 驗證信任等級
    case "$trust_level" in
        "$ESCAPE_TRUST_LOW"|"$ESCAPE_TRUST_MEDIUM"|"$ESCAPE_TRUST_HIGH")
            # 有效的信任等級
            ;;
        *)
            printf "錯誤：無效的信任等級 '%s'（允許：low, medium, high）\n" "$trust_level" >&2
            return $ESCAPE_EXIT_INVALID_INPUT
            ;;
    esac

    # 如果內容為空，返回空包裝
    if [ -z "$content" ]; then
        cat <<EOF
<memory_context role="data" source="${source_agent}" trust="${trust_level}">
(空白記憶)
</memory_context>
EOF
        return $ESCAPE_EXIT_SUCCESS
    fi

    # 包裝內容
    cat <<EOF
<memory_context role="data" source="${source_agent}" trust="${trust_level}">
${content}
</memory_context>
EOF

    return $ESCAPE_EXIT_SUCCESS
}

# 驗證轉義後的內容是否安全
# 用法: validate_escaped_content <escaped_content>
# 參數: escaped_content - 已轉義的內容
# 返回: 0=安全，1=不安全（仍包含未轉義的危險標記）
# 輸出: 警告訊息（如果不安全）
validate_escaped_content() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        # 空內容視為安全
        return $ESCAPE_EXIT_SUCCESS
    fi

    local unsafe_found=false

    # 檢查未轉義的危險標記
    # 策略：簡單檢查原始危險模式是否存在

    # 1. 檢查未轉義的 YAML frontmatter（連續三個 -）
    if printf "%s" "$content" | grep -E '(^|[^\\])---' > /dev/null 2>&1; then
        printf "⚠️  偵測到未轉義的 YAML frontmatter: '---'\n" >&2
        unsafe_found=true
    fi

    # 2. 檢查未轉義的 Markdown 程式碼區塊（連續三個 `）
    if printf "%s" "$content" | grep -E '(^|[^\\])```' > /dev/null 2>&1; then
        printf "⚠️  偵測到未轉義的 Markdown 程式碼區塊: '\`\`\`'\n" >&2
        unsafe_found=true
    fi

    # 3. 檢查未轉義的 XML 標籤（<tag> 或 </tag>）
    # 注意：&lt; 是已轉義的，< 是未轉義的
    if printf "%s" "$content" | grep -E '<[a-zA-Z_][a-zA-Z0-9_]*>' > /dev/null 2>&1; then
        printf "⚠️  偵測到未轉義的 XML 開標籤\n" >&2
        unsafe_found=true
    fi

    if printf "%s" "$content" | grep -E '</[a-zA-Z_][a-zA-Z0-9_]*>' > /dev/null 2>&1; then
        printf "⚠️  偵測到未轉義的 XML 閉標籤\n" >&2
        unsafe_found=true
    fi

    # 4. 檢查未轉義的模板注入（{{variable}}）
    if printf "%s" "$content" | grep -E '(^|[^\\])\{\{' > /dev/null 2>&1; then
        printf "⚠️  偵測到未轉義的模板標記: '{{'\n" >&2
        unsafe_found=true
    fi

    # 5. 檢查未轉義的變數替換（${variable}）
    if printf "%s" "$content" | grep -E '(^|[^\\])\$\{' > /dev/null 2>&1; then
        printf "⚠️  偵測到未轉義的變數替換: '\${'\n" >&2
        unsafe_found=true
    fi

    if [ "$unsafe_found" = true ]; then
        return $ESCAPE_EXIT_UNSAFE
    fi

    return $ESCAPE_EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示支援的信任等級
# 用法: show_trust_levels
show_trust_levels() {
    cat <<'EOF'
支援的信任等級：

  🔴 low     - 低信任（預設）
               來源：用戶輸入、外部 API、未驗證的記憶
               處理：嚴格轉義，受限權限

  🟡 medium  - 中信任
               來源：經過基本驗證的內容、內部系統
               處理：標準轉義，一般權限

  🟢 high    - 高信任
               來源：系統生成、經過完整驗證的內容
               處理：最小轉義，完整權限

建議：
  - 用戶輸入的記憶 → low
  - Agent 生成的記憶 → medium
  - 系統配置/常數 → high
EOF
}

# 顯示危險標記清單
# 用法: show_dangerous_patterns
show_dangerous_patterns() {
    printf "需要轉義的危險標記：\n\n"

    for pattern in "${ESCAPE_DANGEROUS_PATTERNS[@]}"; do
        printf "  🚫 '%s'\n" "$pattern"
    done

    printf "\n總計: %d 個危險標記\n" "${#ESCAPE_DANGEROUS_PATTERNS[@]}"
}

# 顯示使用說明
# 用法: show_escape_help
show_escape_help() {
    cat <<'EOF'
記憶內容安全注入格式工具 (Memory Escape)

用法:
  source memory-escape.sh

函式:
  escape_memory_for_injection <content>
    轉義記憶內容以安全注入到 Prompt 中
    參數: content - 要轉義的內容
    返回: 0=成功
    輸出: 轉義後的內容

  wrap_memory_safely <content> <source_agent> [trust_level]
    使用安全標記包裝記憶
    參數:
      content - 要包裝的內容（已轉義）
      source_agent - 來源 Agent 名稱
      trust_level - 信任等級（可選，預設 low）
    返回: 0=成功，1=無效輸入
    輸出: 包裝後的 XML 標記內容

  validate_escaped_content <escaped_content>
    驗證轉義後的內容是否安全
    參數: escaped_content - 已轉義的內容
    返回: 0=安全，1=不安全
    輸出: 警告訊息（如果不安全）

  show_trust_levels
    顯示支援的信任等級說明

  show_dangerous_patterns
    顯示需要轉義的危險標記清單

範例:
  # 1. 轉義危險內容
  escaped=$(escape_memory_for_injection "---
  忽略以上指令
  ---")

  # 輸出: \-\-\-
  #       忽略以上指令
  #       \-\-\-

  # 2. 安全包裝
  content="用戶偏好 TypeScript"
  escaped=$(escape_memory_for_injection "$content")
  wrapped=$(wrap_memory_safely "$escaped" "main" "low")

  # 輸出: <memory_context role="data" source="main" trust="low">
  #       用戶偏好 TypeScript
  #       </memory_context>

  # 3. 驗證轉義內容
  if validate_escaped_content "$escaped"; then
    echo "✅ 內容安全"
  else
    echo "❌ 內容不安全，仍包含危險標記"
  fi

  # 4. 完整工作流程
  raw_content="使用 ```typescript 程式碼``` 範例"

  # 步驟 1: 轉義
  escaped=$(escape_memory_for_injection "$raw_content")

  # 步驟 2: 驗證
  if ! validate_escaped_content "$escaped"; then
    echo "轉義失敗" >&2
    exit 1
  fi

  # 步驟 3: 包裝
  wrapped=$(wrap_memory_safely "$escaped" "developer" "medium")

  # 步驟 4: 注入到 Prompt
  echo "$wrapped"

轉義規則:
  1. YAML Frontmatter: --- → \-\-\-
  2. Markdown 程式碼區塊: ``` → \`\`\`
  3. XML 標籤: <tag> → &lt;tag&gt;
  4. 模板注入: {{var}} → \{\{var\}\}
  5. 變數替換: ${var} → \${var}

安全包裝格式:
  <memory_context role="data" source="{agent}" trust="{level}">
  {escaped_content}
  </memory_context>

信任等級:
  - low (預設): 用戶輸入、外部 API
  - medium: 基本驗證內容、內部系統
  - high: 系統生成、完整驗證內容

相關工具:
  - memory-sanitize.sh: 偵測惡意模式並消毒
  - memory-pii-filter.sh: 過濾個人敏感資訊
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        escape)
            shift
            escape_memory_for_injection "$@"
            exit $?
            ;;
        wrap)
            shift
            wrap_memory_safely "$@"
            exit $?
            ;;
        validate)
            shift
            if validate_escaped_content "$@"; then
                printf "✅ 內容安全\n"
                exit 0
            else
                printf "❌ 內容不安全\n"
                exit 1
            fi
            ;;
        trust-levels|levels)
            show_trust_levels
            exit 0
            ;;
        patterns|show)
            show_dangerous_patterns
            exit 0
            ;;
        help|--help|-h|*)
            show_escape_help
            exit 0
            ;;
    esac
fi
