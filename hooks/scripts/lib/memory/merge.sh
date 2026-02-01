#!/bin/bash
# memory-merge.sh - 記憶更新合併工具
# 功能：實作新舊記憶的合併邏輯
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-merge.sh"

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 返回碼（使用 MERGE_ 前綴避免衝突）
readonly MERGE_SUCCESS=0
readonly MERGE_ERROR=1
readonly MERGE_INVALID_INPUT=2

# 來源優先級
readonly SOURCE_PRIORITY_USER=3
readonly SOURCE_PRIORITY_AGENT=2
readonly SOURCE_PRIORITY_SYSTEM=1

# ═══════════════════════════════════════════════════════════════
# 輔助功能：取得當前時間戳
# ═══════════════════════════════════════════════════════════════

# 取得 ISO 8601 時間戳
# 用法: timestamp=$(get_merge_timestamp)
# 輸出: 2024-01-01T10:30:00Z
get_merge_timestamp() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能：JSON 解析和操作
# ═══════════════════════════════════════════════════════════════

# 從 JSON 字串提取欄位值
# 用法: value=$(json_get_field "json_string" "field_name")
# 參數:
#   json_string - JSON 字串
#   field_name  - 欄位名稱
# 輸出: 欄位值（去除引號）
json_get_field() {
    local json_string="${1:-}"
    local field_name="${2:-}"

    if [ -z "$json_string" ] || [ -z "$field_name" ]; then
        echo "錯誤：json_get_field 需要提供 json_string 和 field_name" >&2
        return $MERGE_ERROR
    fi

    # 使用簡單的 grep + sed 提取（避免依賴 jq）
    local value

    # 先嘗試提取字串類型（有引號，支援可選空格）
    value=$(echo "$json_string" | grep -oE "\"${field_name}\":[[:space:]]*\"[^\"]*\"" 2>/dev/null | sed -E 's/[^:]+:[[:space:]]*"([^"]*)"/\1/' 2>/dev/null || true)

    # 如果沒找到，嘗試提取數字類型（無引號）
    if [ -z "$value" ]; then
        value=$(echo "$json_string" | grep -oE "\"${field_name}\":[[:space:]]*[0-9]+" 2>/dev/null | sed -E 's/[^:]+:[[:space:]]*([0-9]+)/\1/' 2>/dev/null || true)
    fi

    echo "$value"
    return 0
}

# 從 JSON 字串提取陣列欄位
# 用法: array_values=$(json_get_array "json_string" "array_field")
# 輸出: 每行一個值（去除引號）
json_get_array() {
    local json_string="${1:-}"
    local field_name="${2:-}"

    if [ -z "$json_string" ] || [ -z "$field_name" ]; then
        echo "錯誤：json_get_array 需要提供 json_string 和 field_name" >&2
        return $MERGE_ERROR
    fi

    # 提取陣列內容（簡化版，假設陣列為 ["item1", "item2"] 格式）
    local array_content
    array_content=$(echo "$json_string" | grep -o "\"${field_name}\"[[:space:]]*:[[:space:]]*\[[^]]*\]" | sed -E 's/.*\[(.*)\]/\1/' || echo "")

    if [ -z "$array_content" ]; then
        return 0
    fi

    # 分割並輸出每個元素
    echo "$array_content" | sed 's/,/\n/g' | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//'
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 1: 合併標籤
# ═══════════════════════════════════════════════════════════════

# 合併兩組標籤（去重）
# 用法: merged_tags=$(merge_tags "tag1,tag2" "tag2,tag3")
# 參數:
#   tags1 - 第一組標籤（逗號分隔或 JSON 陣列）
#   tags2 - 第二組標籤（逗號分隔或 JSON 陣列）
# 輸出: 合併後的標籤（逗號分隔）
# 返回: 0=成功，1=失敗
merge_tags() {
    local tags1="${1:-}"
    local tags2="${2:-}"

    # 如果都為空，返回空字串
    if [ -z "$tags1" ] && [ -z "$tags2" ]; then
        echo ""
        return $MERGE_SUCCESS
    fi

    # 處理 JSON 陣列格式（如果有）
    # 簡化處理：將 ["tag1", "tag2"] 轉換為 tag1,tag2
    tags1=$(echo "$tags1" | sed 's/^\[//; s/\]$//; s/"//g; s/[[:space:]]//g')
    tags2=$(echo "$tags2" | sed 's/^\[//; s/\]$//; s/"//g; s/[[:space:]]//g')

    # 合併並去重
    local all_tags
    if [ -n "$tags1" ] && [ -n "$tags2" ]; then
        all_tags="${tags1},${tags2}"
    elif [ -n "$tags1" ]; then
        all_tags="$tags1"
    else
        all_tags="$tags2"
    fi

    # 去重（使用 tr + sort + uniq）
    local unique_tags
    unique_tags=$(echo "$all_tags" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')

    echo "$unique_tags"
    return $MERGE_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 2: 更新時間戳
# ═══════════════════════════════════════════════════════════════

# 更新記憶的時間戳
# 用法: updated_memory=$(update_timestamp "memory_json")
# 參數:
#   memory_json - 記憶的 JSON 字串
# 輸出: 更新後的 JSON 字串
# 返回: 0=成功，1=失敗
update_timestamp() {
    local memory_json="${1:-}"

    if [ -z "$memory_json" ]; then
        echo "錯誤：update_timestamp 需要提供 memory_json" >&2
        return $MERGE_INVALID_INPUT
    fi

    local timestamp
    timestamp=$(get_merge_timestamp)

    # 替換 updated 欄位
    local updated_json
    updated_json=$(echo "$memory_json" | sed -E "s/\"updated\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"updated\": \"$timestamp\"/")

    # 如果沒有 updated 欄位，則新增（插入到第二個欄位位置）
    if ! echo "$updated_json" | grep -q "\"updated\""; then
        updated_json=$(echo "$updated_json" | sed -E "s/(\{[^}]*)(\"[^\"]+\"[[:space:]]*:[^,}]+)/\1\2, \"updated\": \"$timestamp\"/")
    fi

    echo "$updated_json"
    return $MERGE_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 3: 累加存取次數
# ═══════════════════════════════════════════════════════════════

# 累加記憶的存取次數
# 用法: updated_memory=$(increment_access_count "memory_json" count)
# 參數:
#   memory_json - 記憶的 JSON 字串
#   count       - 要累加的次數（預設 1）
# 輸出: 更新後的 JSON 字串
# 返回: 0=成功，1=失敗
increment_access_count() {
    local memory_json="${1:-}"
    local count="${2:-1}"

    if [ -z "$memory_json" ]; then
        echo "錯誤：increment_access_count 需要提供 memory_json" >&2
        return $MERGE_INVALID_INPUT
    fi

    # 提取當前 access_count
    local current_count
    current_count=$(json_get_field "$memory_json" "access_count" || echo "0")

    # 計算新的 access_count
    local new_count=$((current_count + count))

    # 替換 access_count 欄位
    local updated_json
    updated_json=$(echo "$memory_json" | sed -E "s/\"access_count\"[[:space:]]*:[[:space:]]*[0-9]+/\"access_count\": $new_count/")

    # 如果沒有 access_count 欄位，則新增
    if ! echo "$updated_json" | grep -q "\"access_count\""; then
        updated_json=$(echo "$updated_json" | sed -E "s/(\{[^}]*)(\"[^\"]+\"[[:space:]]*:[^,}]+)/\1\2, \"access_count\": $new_count/")
    fi

    echo "$updated_json"
    return $MERGE_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 4: 判斷來源優先級
# ═══════════════════════════════════════════════════════════════

# 取得來源類型的優先級
# 用法: priority=$(get_source_priority "source_type")
# 參數:
#   source_type - 來源類型（user | agent | system）
# 輸出: 優先級數字（3=user, 2=agent, 1=system）
get_source_priority() {
    local source_type="${1:-system}"

    case "$source_type" in
        user)
            echo "$SOURCE_PRIORITY_USER"
            ;;
        agent)
            echo "$SOURCE_PRIORITY_AGENT"
            ;;
        system|*)
            echo "$SOURCE_PRIORITY_SYSTEM"
            ;;
    esac
}

# 比較兩個來源的優先級，返回較高優先級的來源類型
# 用法: higher_source=$(get_higher_priority_source "source1" "source2")
# 參數:
#   source1 - 第一個來源類型
#   source2 - 第二個來源類型
# 輸出: 較高優先級的來源類型
get_higher_priority_source() {
    local source1="${1:-system}"
    local source2="${2:-system}"

    local priority1
    local priority2
    priority1=$(get_source_priority "$source1")
    priority2=$(get_source_priority "$source2")

    if [ "$priority1" -ge "$priority2" ]; then
        echo "$source1"
    else
        echo "$source2"
    fi
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 5: 合併兩個記憶
# ═══════════════════════════════════════════════════════════════

# 合併兩個記憶（JSON 格式）
# 用法: merged=$(merge_memory "old_json" "new_json")
# 參數:
#   old_json - 舊記憶的 JSON 字串
#   new_json - 新記憶的 JSON 字串
# 合併規則:
#   - content: 使用新記憶的內容
#   - tags: 合併兩者（去重）
#   - access_count: 累加
#   - created: 保留舊記憶的
#   - updated: 使用當前時間
#   - source_type: 保留較高優先級（user > agent > system）
# 輸出: 合併後的 JSON 字串
# 返回: 0=成功，1=失敗
merge_memory() {
    local old_json="${1:-}"
    local new_json="${2:-}"

    if [ -z "$old_json" ] || [ -z "$new_json" ]; then
        echo "錯誤：merge_memory 需要提供 old_json 和 new_json" >&2
        return $MERGE_INVALID_INPUT
    fi

    # 提取舊記憶的欄位
    local old_created
    local old_tags
    local old_access_count
    local old_source_type

    old_created=$(json_get_field "$old_json" "created")
    [ -z "$old_created" ] && old_created=$(get_merge_timestamp)

    old_tags=$(json_get_field "$old_json" "tags")
    [ -z "$old_tags" ] && old_tags=""

    old_access_count=$(json_get_field "$old_json" "access_count")
    [ -z "$old_access_count" ] && old_access_count=0

    old_source_type=$(json_get_field "$old_json" "source_type")
    [ -z "$old_source_type" ] && old_source_type="system"

    # 提取新記憶的欄位
    local new_content
    local new_tags
    local new_access_count
    local new_source_type

    new_content=$(json_get_field "$new_json" "content")
    [ -z "$new_content" ] && new_content=""

    new_tags=$(json_get_field "$new_json" "tags")
    [ -z "$new_tags" ] && new_tags=""

    new_access_count=$(json_get_field "$new_json" "access_count")
    [ -z "$new_access_count" ] && new_access_count=1

    new_source_type=$(json_get_field "$new_json" "source_type")
    [ -z "$new_source_type" ] && new_source_type="system"

    # 合併邏輯
    local merged_tags
    local merged_access_count
    local merged_source_type
    local merged_updated

    merged_tags=$(merge_tags "$old_tags" "$new_tags")
    merged_access_count=$((old_access_count + new_access_count))
    merged_source_type=$(get_higher_priority_source "$old_source_type" "$new_source_type")
    merged_updated=$(get_merge_timestamp)

    # 建立合併後的 JSON
    # 注意：這裡使用簡化的 JSON 建立方式（假設 content 不包含引號）
    # 在生產環境中應該使用 jq 或更健壯的 JSON 處理
    local merged_json
    merged_json=$(cat <<EOF
{
  "content": "$new_content",
  "tags": "$merged_tags",
  "access_count": $merged_access_count,
  "created": "$old_created",
  "updated": "$merged_updated",
  "source_type": "$merged_source_type"
}
EOF
)

    # 移除多餘的換行和空白（壓縮為單行）
    merged_json=$(echo "$merged_json" | tr -d '\n' | sed 's/[[:space:]]\+/ /g')

    echo "$merged_json"
    return $MERGE_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能：顯示幫助
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_merge_help() {
    cat <<'EOF'
記憶更新合併工具 (Memory Merge)

用法:
  source memory-merge.sh

核心函式:
  merge_memory <old_json> <new_json>
    合併兩個記憶
    參數:
      old_json - 舊記憶的 JSON 字串
      new_json - 新記憶的 JSON 字串
    合併規則:
      - content: 使用新記憶的內容
      - tags: 合併兩者（去重）
      - access_count: 累加
      - created: 保留舊記憶的
      - updated: 使用當前時間
      - source_type: 保留較高優先級（user > agent > system）
    輸出: 合併後的 JSON 字串
    返回: 0=成功，1=失敗

輔助函式:
  merge_tags <tags1> <tags2>
    合併兩組標籤（去重）
    參數:
      tags1 - 第一組標籤（逗號分隔）
      tags2 - 第二組標籤（逗號分隔）
    輸出: 合併後的標籤（逗號分隔）

  update_timestamp <memory_json>
    更新記憶的時間戳
    參數:
      memory_json - 記憶的 JSON 字串
    輸出: 更新後的 JSON 字串

  increment_access_count <memory_json> [count]
    累加記憶的存取次數
    參數:
      memory_json - 記憶的 JSON 字串
      count       - 要累加的次數（預設 1）
    輸出: 更新後的 JSON 字串

  get_source_priority <source_type>
    取得來源類型的優先級
    參數:
      source_type - 來源類型（user | agent | system）
    輸出: 優先級數字（3=user, 2=agent, 1=system）

  get_higher_priority_source <source1> <source2>
    比較兩個來源的優先級
    參數:
      source1 - 第一個來源類型
      source2 - 第二個來源類型
    輸出: 較高優先級的來源類型

範例:
  # 合併兩個記憶
  old='{"content":"舊內容","tags":"tag1","access_count":5,"created":"2024-01-01T00:00:00Z","source_type":"system"}'
  new='{"content":"新內容","tags":"tag2","access_count":1,"source_type":"user"}'
  merged=$(merge_memory "$old" "$new")
  echo "$merged"
  # 輸出: {"content":"新內容","tags":"tag1,tag2","access_count":6,"created":"2024-01-01T00:00:00Z","updated":"2024-01-02T00:00:00Z","source_type":"user"}

  # 合併標籤
  tags=$(merge_tags "tag1,tag2" "tag2,tag3")
  echo "$tags"
  # 輸出: tag1,tag2,tag3

  # 更新時間戳
  updated=$(update_timestamp "$old")

  # 累加存取次數
  updated=$(increment_access_count "$old" 3)

來源優先級:
  user   > agent > system
    3        2       1

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
        merge)
            shift
            merge_memory "$@"
            exit $?
            ;;
        merge-tags)
            shift
            merge_tags "$@"
            exit $?
            ;;
        update-timestamp)
            shift
            update_timestamp "$@"
            exit $?
            ;;
        increment-count)
            shift
            increment_access_count "$@"
            exit $?
            ;;
        get-priority)
            shift
            get_source_priority "$@"
            exit $?
            ;;
        higher-priority)
            shift
            get_higher_priority_source "$@"
            exit $?
            ;;
        test)
            # 測試用例
            echo "=== 測試記憶合併工具 ===" >&2
            echo "" >&2

            # 測試 1: 合併標籤
            echo "測試 1: 合併標籤" >&2
            tags_result=$(merge_tags "tag1,tag2" "tag2,tag3")
            echo "  結果: $tags_result" >&2
            echo "  預期: tag1,tag2,tag3" >&2
            echo "" >&2

            # 測試 2: 來源優先級
            echo "測試 2: 來源優先級" >&2
            higher=$(get_higher_priority_source "user" "system")
            echo "  結果: $higher" >&2
            echo "  預期: user" >&2
            echo "" >&2

            # 測試 3: 完整合併
            echo "測試 3: 完整記憶合併" >&2
            old_mem='{"content":"舊內容","tags":"tag1","access_count":5,"created":"2024-01-01T00:00:00Z","source_type":"system"}'
            new_mem='{"content":"新內容","tags":"tag2","access_count":1,"source_type":"user"}'
            merged=$(merge_memory "$old_mem" "$new_mem")
            echo "  結果: $merged" >&2
            echo "" >&2

            echo "✅ 測試完成" >&2
            exit 0
            ;;
        help|--help|-h|*)
            show_merge_help
            exit 0
            ;;
    esac
fi
