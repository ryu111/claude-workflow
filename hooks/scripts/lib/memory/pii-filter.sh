#!/usr/bin/env bash
# memory-pii-filter.sh - 敏感資料過濾器
# 功能：偵測和阻擋敏感資料（PII, API Keys, Tokens）
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-pii-filter.sh"
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
readonly EXIT_PII_DETECTED=1
readonly EXIT_LOAD_FAILED=2

# 動作類型
readonly ACTION_BLOCK="block"
readonly ACTION_WARN="warn"

# 預設模式（使用索引陣列，相容 Bash 3.2）
# 格式：name:::regex:::action（使用 ::: 作為分隔符，避免與 regex 衝突）
DEFAULT_PATTERNS=(
    "api_key:::(api[_-]?key|apikey)[[:space:]]*[=:][[:space:]]*[\"']?[a-zA-Z0-9_-]{20,}[\"']?:::$ACTION_BLOCK"
    "password:::(password|passwd|pwd)[[:space:]]*[=:][[:space:]]*[\"'][^\"']+[\"']:::$ACTION_BLOCK"
    "connection_string:::(mongodb|mysql|postgres|redis)://[^[:space:]]+:::$ACTION_BLOCK"
    "bearer_token:::Bearer[[:space:]]+[a-zA-Z0-9_-]+\\.[a-zA-Z0-9_-]+\\.[a-zA-Z0-9_-]+:::$ACTION_BLOCK"
    "openai_key:::sk-[A-Za-z0-9]{32,}:::$ACTION_BLOCK"
    "github_token:::ghp_[A-Za-z0-9]{36}:::$ACTION_BLOCK"
    "ssn:::[0-9]{3}-[0-9]{2}-[0-9]{4}:::$ACTION_BLOCK"
)

# 全域變數（載入自訂模式後會覆蓋）
PATTERNS=()

# ═══════════════════════════════════════════════════════════════
# 輔助函式
# ═══════════════════════════════════════════════════════════════

# 解析單一 pattern 字串
# 用法: parse_pattern_entry "name:::regex:::action"
# 輸出: 三個變數（透過分割）: pattern_name, pattern_regex, pattern_action
parse_pattern_entry() {
    local entry="${1:-}"
    # 使用 awk 分割（更可靠）
    pattern_name=$(echo "$entry" | awk -F':::' '{print $1}')
    pattern_regex=$(echo "$entry" | awk -F':::' '{print $2}')
    pattern_action=$(echo "$entry" | awk -F':::' '{print $3}')
}

# 載入自訂模式從 security.yaml
# 用法: load_custom_patterns [config_file]
# 返回: 0=成功載入或使用預設，1=載入失敗
load_custom_patterns() {
    local config_file="${1:-.claude/memory/security.yaml}"
    local example_file="templates/memory/security.yaml.example"

    # 複製預設模式到全域變數
    PATTERNS=("${DEFAULT_PATTERNS[@]}")

    # 嘗試載入自訂配置
    if [ ! -f "$config_file" ]; then
        # 嘗試從範本載入
        if [ -f "$example_file" ]; then
            config_file="$example_file"
        else
            # 使用預設模式
            return $EXIT_SUCCESS
        fi
    fi

    # 簡單的 YAML 解析（僅解析 pii_filter.patterns 區塊）
    local in_pii_filter=false
    local in_patterns=false
    local current_name=""
    local current_regex=""
    local current_action=""
    local custom_patterns=()

    while IFS= read -r line || [ -n "$line" ]; do
        # 跳過註解和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # 偵測 pii_filter 區塊
        if [[ "$line" =~ ^pii_filter: ]]; then
            in_pii_filter=true
            continue
        fi

        # 偵測 patterns 區塊
        if [ "$in_pii_filter" = true ] && [[ "$line" =~ ^[[:space:]]+patterns: ]]; then
            in_patterns=true
            continue
        fi

        # 離開 pii_filter 區塊
        if [ "$in_pii_filter" = true ] && [[ "$line" =~ ^[a-zA-Z] ]] && [[ ! "$line" =~ ^pii_filter ]]; then
            in_pii_filter=false
            in_patterns=false
        fi

        # 解析 pattern 項目
        if [ "$in_patterns" = true ]; then
            if [[ "$line" =~ -[[:space:]]+name:[[:space:]]*\"?([^\"]+)\"? ]]; then
                # 儲存前一個 pattern（如果有）
                if [ -n "$current_name" ] && [ -n "$current_regex" ]; then
                    custom_patterns+=("$current_name:::$current_regex:::${current_action:-$ACTION_BLOCK}")
                fi

                # 開始新的 pattern
                current_name="${BASH_REMATCH[1]}"
                current_regex=""
                current_action=""
            elif [[ "$line" =~ regex:[[:space:]]*\"(.+)\" ]]; then
                current_regex="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ action:[[:space:]]*\"?([^\"]+)\"? ]]; then
                current_action="${BASH_REMATCH[1]}"
            fi
        fi
    done < "$config_file"

    # 儲存最後一個 pattern
    if [ -n "$current_name" ] && [ -n "$current_regex" ]; then
        custom_patterns+=("$current_name:::$current_regex:::${current_action:-$ACTION_BLOCK}")
    fi

    # 如果成功載入自訂模式，覆蓋預設模式
    if [ ${#custom_patterns[@]} -gt 0 ]; then
        PATTERNS=("${custom_patterns[@]}")
    fi

    return $EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 偵測敏感資料
# 用法: detect_sensitive_data content
# 返回: 0=無敏感資料, 1=偵測到敏感資料
# 輸出: JSON 格式的偵測結果
detect_sensitive_data() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        echo '{"detected":false,"findings":[]}'
        return $EXIT_SUCCESS
    fi

    # 確保模式已載入
    if [ ${#PATTERNS[@]} -eq 0 ]; then
        load_custom_patterns
    fi

    local detected=false
    local findings=()

    # 逐個模式檢查
    for pattern_entry in "${PATTERNS[@]}"; do
        # 解析 pattern entry（使用 awk）
        local pattern_name pattern_regex pattern_action
        pattern_name=$(echo "$pattern_entry" | awk -F':::' '{print $1}')
        pattern_regex=$(echo "$pattern_entry" | awk -F':::' '{print $2}')
        pattern_action=$(echo "$pattern_entry" | awk -F':::' '{print $3}')

        # 使用 grep 偵測（忽略大小寫，顯示匹配部分）
        if echo "$content" | grep -qiE "$pattern_regex"; then
            detected=true

            # 擷取匹配的內容（用於報告，但需脫敏）
            local match
            match=$(echo "$content" | grep -ioE "$pattern_regex" | head -1 || echo "")

            # 脫敏處理（只顯示前後各 3 個字元）
            local masked_match
            if [ -z "$match" ]; then
                masked_match="***"
            elif [ ${#match} -le 6 ]; then
                masked_match="***"
            else
                local prefix="${match:0:3}"
                local suffix="${match: -3}"
                masked_match="${prefix}***${suffix}"
            fi

            # 建立 finding JSON（手動拼接，避免依賴 jq）
            local finding="{\"type\":\"$pattern_name\",\"action\":\"$pattern_action\",\"match\":\"$masked_match\"}"
            findings+=("$finding")
        fi
    done

    # 組裝 JSON 輸出
    if [ "$detected" = true ]; then
        local findings_json
        findings_json=$(IFS=,; echo "${findings[*]}")
        echo "{\"detected\":true,\"findings\":[$findings_json]}"
        return $EXIT_PII_DETECTED
    else
        echo '{"detected":false,"findings":[]}'
        return $EXIT_SUCCESS
    fi
}

# 檢查並阻擋敏感資料
# 用法: check_and_block_pii content
# 返回: 0=通過（無敏感資料或僅警告），1=阻擋（偵測到需阻擋的敏感資料）
# 輸出: 偵測結果訊息（stderr）
check_and_block_pii() {
    local content="${1:-}"

    # 執行偵測
    local result
    result=$(detect_sensitive_data "$content")
    local detect_exit_code=$?

    if [ $detect_exit_code -eq $EXIT_SUCCESS ]; then
        # 無敏感資料
        return $EXIT_SUCCESS
    fi

    # 解析結果（簡化版，使用 grep）
    local has_block_action=false

    # 檢查是否有 block 動作
    if echo "$result" | grep -q "\"action\":\"$ACTION_BLOCK\""; then
        has_block_action=true
    fi

    # 輸出警告訊息
    echo "⚠️  偵測到敏感資料：" >&2

    # 提取並顯示 findings（簡化版）
    echo "$result" | grep -oE '"type":"[^"]+","action":"[^"]+"' | while IFS= read -r finding; do
        local type
        local action
        type=$(echo "$finding" | grep -oE '"type":"[^"]+' | cut -d'"' -f4)
        action=$(echo "$finding" | grep -oE '"action":"[^"]+' | cut -d'"' -f4)

        if [ "$action" = "$ACTION_BLOCK" ]; then
            echo "  ❌ [$type] - 已阻擋" >&2
        else
            echo "  ⚠️  [$type] - 警告" >&2
        fi
    done

    # 決定是否阻擋
    if [ "$has_block_action" = true ]; then
        echo "" >&2
        echo "🚫 偵測到需阻擋的敏感資料，操作已中止" >&2
        return $EXIT_PII_DETECTED
    else
        echo "" >&2
        echo "✅ 僅警告，允許繼續操作" >&2
        return $EXIT_SUCCESS
    fi
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示已載入的模式資訊
# 用法: show_loaded_patterns
show_loaded_patterns() {
    if [ ${#PATTERNS[@]} -eq 0 ]; then
        echo "未載入任何模式，使用預設模式"
        load_custom_patterns
    fi

    echo "已載入的敏感資料模式："
    echo ""

    for pattern_entry in "${PATTERNS[@]}"; do
        # 解析 pattern entry（使用 awk）
        local pattern_name pattern_regex pattern_action
        pattern_name=$(echo "$pattern_entry" | awk -F':::' '{print $1}')
        pattern_regex=$(echo "$pattern_entry" | awk -F':::' '{print $2}')
        pattern_action=$(echo "$pattern_entry" | awk -F':::' '{print $3}')

        local action_icon
        if [ "$pattern_action" = "$ACTION_BLOCK" ]; then
            action_icon="🚫"
        else
            action_icon="⚠️ "
        fi

        echo "  $action_icon [$pattern_name] - $pattern_action"
    done

    echo ""
    echo "總計: ${#PATTERNS[@]} 個模式"
}

# 顯示使用說明
show_pii_filter_help() {
    cat <<'EOF'
敏感資料過濾器 (PII Filter)

用法:
  source memory-pii-filter.sh

函式:
  load_custom_patterns [config_file]
    載入自訂敏感資料模式（從 security.yaml）
    參數: config_file - 可選，配置檔路徑（預設 .claude/memory/security.yaml）
    返回: 0=成功，1=失敗

  detect_sensitive_data <content>
    偵測內容中的敏感資料
    參數: content - 要檢查的內容
    返回: 0=無敏感資料，1=偵測到敏感資料
    輸出: JSON 格式的偵測結果

  check_and_block_pii <content>
    檢查並阻擋敏感資料（根據 action 設定）
    參數: content - 要檢查的內容
    返回: 0=通過，1=阻擋
    輸出: 警告訊息（stderr）

  show_loaded_patterns
    顯示已載入的敏感資料模式

範例:
  # 載入自訂模式
  load_custom_patterns ".claude/memory/security.yaml"

  # 偵測敏感資料
  result=$(detect_sensitive_data "api_key=sk-abc123...")
  echo "$result"
  # 輸出: {"detected":true,"findings":[{"type":"openai_key","action":"block","match":"sk-***..."}]}

  # 檢查並阻擋
  if ! check_and_block_pii "password=secret123"; then
    echo "操作被阻擋"
  fi

支援的敏感資料類型:
  - API Key (api_key=xxx, apikey:xxx)
  - 密碼 (password=, passwd=, pwd=)
  - 連線字串 (mongodb://, mysql://, postgres://, redis://)
  - Bearer Token / JWT
  - OpenAI API Key (sk-...)
  - GitHub Token (ghp_...)
  - SSN (xxx-xx-xxxx)
  - 長 Token (32+ 字元，警告模式)

動作類型:
  - block: 阻擋操作
  - warn: 僅警告，允許繼續

配置檔:
  參考: templates/memory/security.yaml.example
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
            load_custom_patterns "$@"
            exit $?
            ;;
        detect)
            shift
            detect_sensitive_data "$@"
            exit $?
            ;;
        check)
            shift
            check_and_block_pii "$@"
            exit $?
            ;;
        patterns|show)
            show_loaded_patterns
            exit 0
            ;;
        help|--help|-h|*)
            show_pii_filter_help
            exit 0
            ;;
    esac
fi
