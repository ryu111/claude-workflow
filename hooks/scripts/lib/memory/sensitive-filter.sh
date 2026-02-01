#!/usr/bin/env bash
# memory-sensitive-filter.sh - 敏感記憶過濾器
# 功能：過濾包含敏感標籤的記憶（基於 Agent 權限）
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-sensitive-filter.sh"
# 相容性：Bash 3.2+（macOS 預設版本）

set -uo pipefail

# 載入共用工具函式
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/../core/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 返回碼
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_INVALID_INPUT=2

# 敏感標籤列表（使用陣列）
readonly SENSITIVE_TAGS=(
    "sensitive"
    "secret"
    "private"
    "confidential"
)

# 預設具有敏感存取權限的 Agent（可透過配置檔覆蓋）
# 格式：逗號分隔的 agent 名稱（小寫）
readonly DEFAULT_SENSITIVE_ACCESS_AGENTS="main"

# 全域變數（載入配置後會覆蓋）
SENSITIVE_ACCESS_AGENTS=""

# ═══════════════════════════════════════════════════════════════
# 輔助函式
# ═══════════════════════════════════════════════════════════════

# 載入敏感存取權限配置
# 用法: load_sensitive_access_config [config_file]
# 返回: 0=成功載入或使用預設，1=載入失敗
load_sensitive_access_config() {
    local config_file="${1:-.claude/memory/security.yaml}"
    local example_file="templates/memory/security.yaml.example"

    # 使用預設值
    SENSITIVE_ACCESS_AGENTS="$DEFAULT_SENSITIVE_ACCESS_AGENTS"

    # 嘗試載入自訂配置
    if [ ! -f "$config_file" ]; then
        # 嘗試從範本載入
        if [ -f "$example_file" ]; then
            config_file="$example_file"
        else
            # 使用預設配置
            return $EXIT_SUCCESS
        fi
    fi

    # 簡單的 YAML 解析（僅解析 access_control.sensitive_access_agents）
    local in_access_control=false
    local agents=""

    while IFS= read -r line || [ -n "$line" ]; do
        # 跳過註解和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # 偵測 access_control 區塊
        if [[ "$line" =~ ^access_control: ]]; then
            in_access_control=true
            continue
        fi

        # 離開 access_control 區塊
        if [ "$in_access_control" = true ] && [[ "$line" =~ ^[a-zA-Z] ]] && [[ ! "$line" =~ ^access_control ]]; then
            in_access_control=false
        fi

        # 解析 sensitive_access_agents
        if [ "$in_access_control" = true ]; then
            if [[ "$line" =~ sensitive_access_agents:[[:space:]]*\"?([^\"]+)\"? ]]; then
                agents="${BASH_REMATCH[1]}"
                break
            fi
        fi
    done < "$config_file"

    # 如果成功載入，覆蓋預設值
    if [ -n "$agents" ]; then
        SENSITIVE_ACCESS_AGENTS="$agents"
    fi

    return $EXIT_SUCCESS
}

# 取得敏感標籤列表
# 用法: tags=$(get_sensitive_tags)
# 輸出: 逗號分隔的標籤列表
get_sensitive_tags() {
    local IFS=','
    echo "${SENSITIVE_TAGS[*]}"
}

# 判斷單一記憶是否為敏感記憶
# 用法: is_sensitive_memory '{"tags": "sensitive,project"}'
# 參數: memory - JSON 格式的單一記憶物件
# 返回: 0=敏感記憶，1=非敏感記憶
is_sensitive_memory() {
    local memory="${1:-}"

    if [ -z "$memory" ]; then
        return 1  # 空記憶視為非敏感
    fi

    # 提取 tags 欄位（簡單 JSON 解析）
    local tags=""

    # 使用 grep 提取 tags 值（處理可能的格式）
    # 支援格式："tags": "value" 或 "tags":"value"
    if echo "$memory" | grep -qE '"tags"[[:space:]]*:[[:space:]]*"'; then
        tags=$(echo "$memory" | grep -oE '"tags"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"tags"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
    fi

    # 如果沒有 tags，視為非敏感
    if [ -z "$tags" ]; then
        return 1
    fi

    # 檢查是否包含任何敏感標籤
    for sensitive_tag in "${SENSITIVE_TAGS[@]}"; do
        # 使用逗號包圍法避免子字串誤判
        # 例如：tags="not-sensitive" 不會被誤判為包含 "sensitive"
        if echo ",$tags," | grep -q ",$sensitive_tag,"; then
            return 0  # 偵測到敏感標籤
        fi
    done

    return 1  # 非敏感記憶
}

# 判斷 Agent 是否有敏感存取權限
# 用法: has_sensitive_access "main"
# 用法: has_sensitive_access "developer"
# 參數: agent - Agent 名稱（不區分大小寫）
# 返回: 0=有權限，1=無權限
has_sensitive_access() {
    local agent="${1:-}"

    if [ -z "$agent" ]; then
        return 1  # 未指定 agent，無權限
    fi

    # 確保配置已載入
    if [ -z "$SENSITIVE_ACCESS_AGENTS" ]; then
        load_sensitive_access_config
    fi

    # 轉換為小寫（不區分大小寫）
    local agent_lower
    agent_lower=$(echo "$agent" | tr '[:upper:]' '[:lower:]')

    # 檢查是否在授權列表中
    # 使用逗號包圍法確保精確匹配
    if echo ",$SENSITIVE_ACCESS_AGENTS," | grep -iq ",$agent_lower,"; then
        return 0  # 有權限
    fi

    return 1  # 無權限
}

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 過濾敏感記憶
# 用法: filter_sensitive_memories '{"results": [...]}' "developer"
# 用法: filter_sensitive_memories '{"results": [...]}' "main"
# 參數:
#   memories_json - JSON 格式的記憶列表（標準搜尋結果格式）
#   agent         - Agent 名稱（可選，預設無權限）
# 輸出: 過濾後的 JSON（移除敏感記憶）
# 返回: 0=成功，1=失敗
filter_sensitive_memories() {
    local memories_json="${1:-}"
    local agent="${2:-}"

    # 驗證輸入
    if [ -z "$memories_json" ]; then
        echo "錯誤：memories_json 不能為空" >&2
        return $EXIT_INVALID_INPUT
    fi

    # 檢查是否為有效的 JSON（簡單驗證）
    if ! echo "$memories_json" | grep -q '"results"[[:space:]]*:[[:space:]]*\['; then
        echo "錯誤：無效的 JSON 格式（缺少 results 陣列）" >&2
        return $EXIT_INVALID_INPUT
    fi

    # 檢查 Agent 權限
    local has_access=false
    if [ -n "$agent" ] && has_sensitive_access "$agent"; then
        has_access=true
    fi

    # 如果有權限，直接返回原始 JSON
    if [ "$has_access" = true ]; then
        echo "$memories_json"
        return $EXIT_SUCCESS
    fi

    # 過濾敏感記憶
    # 策略：逐行解析 JSON，移除敏感記憶物件

    local filtered_results=""
    local result_count=0
    local original_query=""
    local in_results=false
    local current_memory=""
    local brace_count=0

    # 提取原始查詢（用於輸出）
    if echo "$memories_json" | grep -qE '"query"[[:space:]]*:[[:space:]]*"'; then
        original_query=$(echo "$memories_json" | grep -oE '"query"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"query"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
    fi

    # 逐行解析 JSON
    while IFS= read -r line; do
        # 偵測 results 陣列開始
        if echo "$line" | grep -q '"results"[[:space:]]*:[[:space:]]*\['; then
            in_results=true
            continue
        fi

        # 偵測 results 陣列結束
        if [ "$in_results" = true ] && echo "$line" | grep -q '^[[:space:]]*\][[:space:]]*,\?[[:space:]]*$'; then
            in_results=false
            continue
        fi

        # 在 results 陣列內
        if [ "$in_results" = true ]; then
            # 累積當前記憶物件
            current_memory+="$line"

            # 計算大括號數量（簡單的平衡檢查）
            brace_count=$((brace_count + $(echo "$line" | grep -o '{' | wc -l)))
            brace_count=$((brace_count - $(echo "$line" | grep -o '}' | wc -l)))

            # 記憶物件完整時（大括號平衡）
            if [ "$brace_count" -eq 0 ] && [ -n "$current_memory" ]; then
                # 檢查是否為敏感記憶
                if ! is_sensitive_memory "$current_memory"; then
                    # 非敏感記憶，保留
                    if [ $result_count -gt 0 ]; then
                        filtered_results+=","
                    fi
                    filtered_results+="$current_memory"
                    ((result_count++))
                fi

                # 重置當前記憶
                current_memory=""
            fi
        fi
    done <<< "$memories_json"

    # 組裝過濾後的 JSON
    local escaped_query=$(echo "$original_query" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g')

    cat <<EOF
{
  "results": [
$filtered_results
  ],
  "count": $result_count,
  "query": "$escaped_query",
  "filtered": true,
  "reason": "敏感記憶已過濾（agent 無存取權限）"
}
EOF

    return $EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示已載入的權限配置
# 用法: show_sensitive_access_config
show_sensitive_access_config() {
    if [ -z "$SENSITIVE_ACCESS_AGENTS" ]; then
        echo "未載入配置，使用預設權限設定"
        load_sensitive_access_config
    fi

    echo "敏感記憶存取權限配置："
    echo ""
    echo "敏感標籤列表："
    for tag in "${SENSITIVE_TAGS[@]}"; do
        echo "  - $tag"
    done
    echo ""
    echo "具有敏感存取權限的 Agent："

    # 分割逗號分隔的 agent 列表
    IFS=',' read -ra agent_array <<< "$SENSITIVE_ACCESS_AGENTS"
    for agent in "${agent_array[@]}"; do
        agent=$(echo "$agent" | xargs)  # 去除空白
        echo "  - $agent"
    done

    echo ""
}

# 顯示使用說明
show_sensitive_filter_help() {
    cat <<'EOF'
敏感記憶過濾器 (Sensitive Memory Filter)

用法:
  source memory-sensitive-filter.sh

函式:
  load_sensitive_access_config [config_file]
    載入敏感存取權限配置（從 security.yaml）
    參數: config_file - 可選，配置檔路徑（預設 .claude/memory/security.yaml）
    返回: 0=成功，1=失敗

  get_sensitive_tags
    取得敏感標籤列表
    輸出: 逗號分隔的標籤列表

  is_sensitive_memory <memory_json>
    判斷單一記憶是否為敏感記憶
    參數: memory_json - JSON 格式的單一記憶物件
    返回: 0=敏感記憶，1=非敏感記憶

  has_sensitive_access <agent>
    判斷 Agent 是否有敏感存取權限
    參數: agent - Agent 名稱（不區分大小寫）
    返回: 0=有權限，1=無權限

  filter_sensitive_memories <memories_json> [agent]
    過濾敏感記憶（主要函式）
    參數:
      memories_json - JSON 格式的記憶列表（標準搜尋結果格式）
      agent         - Agent 名稱（可選，預設無權限）
    輸出: 過濾後的 JSON（移除敏感記憶）
    返回: 0=成功，1=失敗

  show_sensitive_access_config
    顯示已載入的權限配置

範例:
  # 載入配置
  load_sensitive_access_config ".claude/memory/security.yaml"

  # 檢查 Agent 權限
  if has_sensitive_access "main"; then
    echo "main agent 有權限存取敏感記憶"
  fi

  # 判斷單一記憶是否敏感
  memory='{"id":1,"tags":"sensitive,project"}'
  if is_sensitive_memory "$memory"; then
    echo "這是敏感記憶"
  fi

  # 過濾記憶列表
  search_result='{"results":[{"id":1,"tags":"sensitive"},{"id":2,"tags":"public"}]}'
  filtered=$(filter_sensitive_memories "$search_result" "developer")
  echo "$filtered"
  # 輸出: {"results":[{"id":2,"tags":"public"}],...}

  # Main agent 不過濾
  filtered=$(filter_sensitive_memories "$search_result" "main")
  echo "$filtered"
  # 輸出: 原始 JSON（包含所有記憶）

敏感標籤列表:
  - sensitive   # 基本敏感標籤
  - secret      # 機密標籤
  - private     # 私人標籤
  - confidential # 保密標籤

預設權限:
  - main agent 具有敏感存取權限
  - 其他 agent 無權限

配置檔:
  參考: templates/memory/security.yaml.example
  路徑: .claude/memory/security.yaml

配置格式 (YAML):
  access_control:
    sensitive_access_agents: "main,admin"

返回碼:
  0 - 成功
  1 - 一般錯誤
  2 - 無效的輸入參數
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
            load_sensitive_access_config "$@"
            exit $?
            ;;
        tags|get-tags)
            get_sensitive_tags
            exit 0
            ;;
        check-memory)
            shift
            if is_sensitive_memory "$@"; then
                echo "敏感記憶"
                exit 0
            else
                echo "非敏感記憶"
                exit 1
            fi
            ;;
        check-agent)
            shift
            if has_sensitive_access "$@"; then
                echo "有權限"
                exit 0
            else
                echo "無權限"
                exit 1
            fi
            ;;
        filter)
            shift
            filter_sensitive_memories "$@"
            exit $?
            ;;
        config|show)
            show_sensitive_access_config
            exit 0
            ;;
        help|--help|-h|*)
            show_sensitive_filter_help
            exit 0
            ;;
    esac
fi
