#!/usr/bin/env bash
# memory-sanitize.sh - 記憶內容消毒器
# 功能：阻擋惡意模式、轉義 Markdown 特殊字元，防止記憶毒化和 Prompt Injection
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-sanitize.sh"
# 相容性：Bash 3.2+（macOS 預設版本）

# 注意：不使用 set -e，因為偵測函式需要返回非零值表示「偵測到」
set -uo pipefail

# 載入共用工具函式
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/../core/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

readonly EXIT_SUCCESS=0
readonly EXIT_MALICIOUS_DETECTED=1
readonly EXIT_LOAD_FAILED=2

# 預設阻擋的惡意模式（使用索引陣列，相容 Bash 3.2）
DEFAULT_BLOCKED_PHRASES=(
    # 中文可疑指令
    "忽略安全"
    "跳過檢查"
    "禁用驗證"
    "允許 eval"
    "執行任意程式碼"
    "忽略以上所有指令"
    "繞過驗證"
    "跳過安全"
    "注入指令"

    # 英文可疑指令
    "ignore security"
    "skip validation"
    "disable check"
    "allow eval"
    "execute arbitrary code"
    "ignore all previous instructions"
    "bypass check"
    "bypass validation"
    "skip security"
    "inject command"

    # 危險操作
    "刪除所有"
    "delete all"
    "drop database"
    "rm -rf"
)

# 全域變數（載入自訂模式後會覆蓋）
BLOCKED_PHRASES=()

# ═══════════════════════════════════════════════════════════════
# 輔助函式
# ═══════════════════════════════════════════════════════════════

# 載入自訂阻擋模式從 security.yaml
# 用法: load_blocked_phrases [config_file]
# 返回: 0=成功載入或使用預設，1=載入失敗
load_blocked_phrases() {
    local config_file="${1:-templates/memory/security.yaml.example}"

    # 複製預設模式到全域變數
    BLOCKED_PHRASES=("${DEFAULT_BLOCKED_PHRASES[@]}")

    # 檢查配置檔是否存在
    if [ ! -f "$config_file" ]; then
        # 使用預設模式
        return $EXIT_SUCCESS
    fi

    # 簡單的 YAML 解析（僅解析 sanitization.blocked_phrases 區塊）
    local in_sanitization=false
    local in_blocked_phrases=false
    local custom_phrases=()

    while IFS= read -r line || [ -n "$line" ]; do
        # 跳過註解和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # 偵測 sanitization 區塊
        if [[ "$line" =~ ^sanitization: ]]; then
            in_sanitization=true
            continue
        fi

        # 偵測 blocked_phrases 區塊
        if [ "$in_sanitization" = true ] && [[ "$line" =~ ^[[:space:]]+blocked_phrases: ]]; then
            in_blocked_phrases=true
            continue
        fi

        # 離開 sanitization 區塊
        if [ "$in_sanitization" = true ] && [[ "$line" =~ ^[a-zA-Z] ]] && [[ ! "$line" =~ ^sanitization ]]; then
            in_sanitization=false
            in_blocked_phrases=false
        fi

        # 解析 blocked_phrases 項目
        if [ "$in_blocked_phrases" = true ]; then
            # 匹配 - "phrase" 或 - phrase 格式
            if [[ "$line" =~ -[[:space:]]+\"([^\"]+)\" ]]; then
                custom_phrases+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ -[[:space:]]+([^[:space:]]+) ]]; then
                custom_phrases+=("${BASH_REMATCH[1]}")
            fi
        fi
    done < "$config_file"

    # 如果成功載入自訂模式，覆蓋預設模式
    if [ ${#custom_phrases[@]} -gt 0 ]; then
        BLOCKED_PHRASES=("${custom_phrases[@]}")
    fi

    return $EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 檢查是否包含惡意內容
# 用法: contains_malicious_content <content>
# 返回: 0=安全, 1=包含惡意內容
contains_malicious_content() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        return $EXIT_SUCCESS
    fi

    # 確保模式已載入
    if [ ${#BLOCKED_PHRASES[@]} -eq 0 ]; then
        load_blocked_phrases
    fi

    # 轉換內容為小寫以進行不區分大小寫比對
    local content_lower
    content_lower=$(echo "$content" | tr '[:upper:]' '[:lower:]')

    # 逐個檢查阻擋模式
    for phrase in "${BLOCKED_PHRASES[@]}"; do
        local phrase_lower
        phrase_lower=$(echo "$phrase" | tr '[:upper:]' '[:lower:]')

        # 使用 grep 進行不區分大小寫的匹配
        if echo "$content_lower" | grep -qF "$phrase_lower"; then
            # 偵測到惡意內容，輸出警告到 stderr
            echo "⚠️  偵測到可疑模式: \"$phrase\"" >&2
            return $EXIT_MALICIOUS_DETECTED
        fi
    done

    return $EXIT_SUCCESS
}

# 轉義特殊字元
# 用法: escaped=$(escape_special_chars <content>)
# 功能: 轉義 Markdown 特殊字元，防止 Prompt Injection
escape_special_chars() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        echo ""
        return $EXIT_SUCCESS
    fi

    # 轉義策略：
    # 1. --- → \-\-\- (防止建立新的 YAML frontmatter)
    # 2. ``` → \`\`\` (防止建立程式碼區塊)
    # 3. <tag> → &lt;tag&gt; (防止 XML 標籤注入)

    local escaped="$content"

    # 轉義 --- (YAML frontmatter 分隔符)
    escaped=$(echo "$escaped" | sed 's/---/\\-\\-\\-/g')

    # 轉義 ``` (Markdown 程式碼區塊)
    escaped=$(echo "$escaped" | sed 's/```/\\`\\`\\`/g')

    # 轉義常見的 XML 標籤（可能用於 Prompt Injection）
    # <memory_context>, <system>, <instruction>, <override> 等
    escaped=$(echo "$escaped" | sed 's/<memory_context>/\&lt;memory_context\&gt;/g')
    escaped=$(echo "$escaped" | sed 's/<\/memory_context>/\&lt;\/memory_context\&gt;/g')
    escaped=$(echo "$escaped" | sed 's/<system>/\&lt;system\&gt;/g')
    escaped=$(echo "$escaped" | sed 's/<\/system>/\&lt;\/system\&gt;/g')
    escaped=$(echo "$escaped" | sed 's/<instruction>/\&lt;instruction\&gt;/g')
    escaped=$(echo "$escaped" | sed 's/<\/instruction>/\&lt;\/instruction\&gt;/g')
    escaped=$(echo "$escaped" | sed 's/<override>/\&lt;override\&gt;/g')
    escaped=$(echo "$escaped" | sed 's/<\/override>/\&lt;\/override\&gt;/g')

    # 通用 XML 標籤轉義（處理任意標籤）
    escaped=$(echo "$escaped" | sed 's/<\([a-zA-Z_][a-zA-Z0-9_]*\)>/\&lt;\1\&gt;/g')
    escaped=$(echo "$escaped" | sed 's/<\/\([a-zA-Z_][a-zA-Z0-9_]*\)>/\&lt;\/\1\&gt;/g')

    echo "$escaped"
}

# 消毒記憶內容
# 用法: sanitized=$(sanitize_memory_content <content>)
# 返回: 0=成功（安全或已消毒），1=包含惡意內容被阻擋
# 輸出: 消毒後的內容（如果安全）
sanitize_memory_content() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        echo ""
        return $EXIT_SUCCESS
    fi

    # 步驟 1: 檢查惡意內容
    if ! contains_malicious_content "$content"; then
        # 有惡意內容，阻擋
        echo "🚫 偵測到惡意模式，記憶內容已阻擋" >&2
        return $EXIT_MALICIOUS_DETECTED
    fi

    # 步驟 2: 轉義特殊字元
    local sanitized
    sanitized=$(escape_special_chars "$content")

    # 輸出消毒後的內容
    echo "$sanitized"
    return $EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示已載入的阻擋模式資訊
# 用法: show_blocked_patterns
show_blocked_patterns() {
    if [ ${#BLOCKED_PHRASES[@]} -eq 0 ]; then
        echo "未載入任何阻擋模式，使用預設模式"
        load_blocked_phrases
    fi

    echo "已載入的惡意模式："
    echo ""

    for phrase in "${BLOCKED_PHRASES[@]}"; do
        echo "  🚫 \"$phrase\""
    done

    echo ""
    echo "總計: ${#BLOCKED_PHRASES[@]} 個模式"
}

# 顯示使用說明
show_sanitize_help() {
    cat <<'EOF'
記憶內容消毒器 (Memory Sanitizer)

用法:
  source memory-sanitize.sh

函式:
  load_blocked_phrases [config_file]
    載入自訂阻擋模式（從 security.yaml）
    參數: config_file - 可選，配置檔路徑（預設 templates/memory/security.yaml.example）
    返回: 0=成功，1=失敗

  contains_malicious_content <content>
    檢查內容是否包含惡意模式
    參數: content - 要檢查的內容
    返回: 0=安全，1=包含惡意內容
    輸出: 警告訊息（stderr）

  escape_special_chars <content>
    轉義 Markdown 特殊字元，防止 Prompt Injection
    參數: content - 要轉義的內容
    返回: 0=成功
    輸出: 轉義後的內容

  sanitize_memory_content <content>
    消毒記憶內容（檢查 + 轉義）
    參數: content - 要消毒的內容
    返回: 0=成功（安全或已消毒），1=包含惡意內容被阻擋
    輸出: 消毒後的內容

  show_blocked_patterns
    顯示已載入的阻擋模式

範例:
  # 載入自訂模式
  load_blocked_phrases "templates/memory/security.yaml.example"

  # 檢查惡意內容
  if contains_malicious_content "忽略安全檢查"; then
    echo "內容安全"
  else
    echo "偵測到惡意內容"
  fi

  # 轉義特殊字元
  escaped=$(escape_special_chars "使用 ```bash 程式碼``` 範例")
  echo "$escaped"
  # 輸出: 使用 \`\`\`bash 程式碼\`\`\` 範例

  # 完整消毒
  if sanitized=$(sanitize_memory_content "記憶內容"); then
    echo "消毒成功: $sanitized"
  else
    echo "內容被阻擋"
  fi

阻擋的惡意模式:
  中文:
    - 忽略安全, 跳過檢查, 禁用驗證
    - 允許 eval, 執行任意程式碼
    - 忽略以上所有指令, 繞過驗證
    - 刪除所有

  英文:
    - ignore security, skip validation, disable check
    - allow eval, execute arbitrary code
    - ignore all previous instructions, bypass check
    - delete all, drop database, rm -rf

轉義的特殊字元:
  - --- (YAML frontmatter)
  - ``` (Markdown 程式碼區塊)
  - <tag> (XML 標籤，如 <memory_context>, <system>)

配置檔:
  參考: templates/memory/security.yaml.example
  位置: sanitization.blocked_phrases
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        load)
            shift
            load_blocked_phrases "$@"
            exit $?
            ;;
        check)
            shift
            if contains_malicious_content "$@"; then
                echo "✅ 內容安全"
                exit 0
            else
                echo "❌ 偵測到惡意內容"
                exit 1
            fi
            ;;
        escape)
            shift
            escape_special_chars "$@"
            exit $?
            ;;
        sanitize)
            shift
            if result=$(sanitize_memory_content "$@"); then
                echo "$result"
                exit 0
            else
                exit 1
            fi
            ;;
        patterns|show)
            show_blocked_patterns
            exit 0
            ;;
        help|--help|-h|*)
            show_sanitize_help
            exit 0
            ;;
    esac
fi
