#!/usr/bin/env bash
# memory-dedup.sh - 記憶語義去重工具
# 功能：識別重複的記憶條目並合併
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-dedup.sh"

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 返回碼
readonly DEDUP_SUCCESS=0
readonly DEDUP_NOT_DUPLICATE=1
readonly DEDUP_ERROR=2

# 相似度閾值（百分比）
readonly DEDUP_SIMILARITY_THRESHOLD=85

# ═══════════════════════════════════════════════════════════════
# 核心功能 1: 計算字串相似度
# ═══════════════════════════════════════════════════════════════

# 計算兩個字串的 Jaccard 相似度
# 用法: similarity=$(calculate_similarity "string1" "string2")
# 輸出: 相似度百分比（0-100）
# 返回: 0=成功，2=錯誤
calculate_similarity() {
    local str1="${1:-}"
    local str2="${2:-}"

    if [ -z "$str1" ] || [ -z "$str2" ]; then
        echo "錯誤：calculate_similarity 需要提供兩個字串" >&2
        return $DEDUP_ERROR
    fi

    # 如果完全相同，直接返回 100
    if [ "$str1" = "$str2" ]; then
        echo "100"
        return $DEDUP_SUCCESS
    fi

    # 正規化：轉小寫、移除多餘空白
    local norm1=$(echo "$str1" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    local norm2=$(echo "$str2" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # 如果正規化後相同，返回 100
    if [ "$norm1" = "$norm2" ]; then
        echo "100"
        return $DEDUP_SUCCESS
    fi

    # 計算行數差異比例（簡單方法）
    local lines1=$(echo "$norm1" | wc -l | tr -d '[:space:]')
    local lines2=$(echo "$norm2" | wc -l | tr -d '[:space:]')
    local total_lines=$((lines1 + lines2))

    if [ "$total_lines" -eq 0 ]; then
        echo "0"
        return $DEDUP_SUCCESS
    fi

    # 使用 diff 計算差異行數
    local diff_lines=$(diff <(echo "$norm1") <(echo "$norm2") 2>/dev/null | grep -c "^[<>]" || echo "0")

    # 計算相似度: (總行數 - 差異行數) / 總行數 * 100
    local similar_lines=$((total_lines - diff_lines))
    local similarity=$((similar_lines * 100 / total_lines))

    echo "$similarity"
    return $DEDUP_SUCCESS
}

# 使用詞袋模型計算 Jaccard 係數（更精確的方法）
# 用法: similarity=$(calculate_jaccard_similarity "string1" "string2")
# 輸出: 相似度百分比（0-100）
# 返回: 0=成功，2=錯誤
calculate_jaccard_similarity() {
    local str1="${1:-}"
    local str2="${2:-}"

    if [ -z "$str1" ] || [ -z "$str2" ]; then
        echo "錯誤：calculate_jaccard_similarity 需要提供兩個字串" >&2
        return $DEDUP_ERROR
    fi

    # 如果完全相同，直接返回 100
    if [ "$str1" = "$str2" ]; then
        echo "100"
        return $DEDUP_SUCCESS
    fi

    # 正規化並分詞（以空格和標點分隔）
    local words1=$(echo "$str1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u)
    local words2=$(echo "$str2" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u)

    # 計算交集大小（共同詞彙）
    local intersection=$(comm -12 <(echo "$words1") <(echo "$words2") | wc -l | tr -d '[:space:]')

    # 計算聯集大小（所有詞彙）
    local union=$(cat <(echo "$words1") <(echo "$words2") | sort -u | wc -l | tr -d '[:space:]')

    if [ "$union" -eq 0 ]; then
        echo "0"
        return $DEDUP_SUCCESS
    fi

    # Jaccard 係數 = 交集 / 聯集 * 100
    local similarity=$((intersection * 100 / union))

    echo "$similarity"
    return $DEDUP_SUCCESS
}

# 計算字符級別的相似度（適合中文）
# 用法: similarity=$(calculate_char_similarity "string1" "string2")
# 輸出: 相似度百分比（0-100）
# 返回: 0=成功，2=錯誤
# 說明: 使用最長公共子序列 (LCS) 比例作為相似度
calculate_char_similarity() {
    local str1="${1:-}"
    local str2="${2:-}"

    if [ -z "$str1" ] || [ -z "$str2" ]; then
        echo "錯誤：calculate_char_similarity 需要提供兩個字串" >&2
        return $DEDUP_ERROR
    fi

    # 如果完全相同，直接返回 100
    if [ "$str1" = "$str2" ]; then
        echo "100"
        return $DEDUP_SUCCESS
    fi

    # 正規化
    local norm1=$(echo "$str1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    local norm2=$(echo "$str2" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

    # 如果正規化後相同
    if [ "$norm1" = "$norm2" ]; then
        echo "100"
        return $DEDUP_SUCCESS
    fi

    # 計算字符長度
    local len1=${#norm1}
    local len2=${#norm2}
    local max_len=$len1
    [ "$len2" -gt "$max_len" ] && max_len=$len2

    if [ "$max_len" -eq 0 ]; then
        echo "0"
        return $DEDUP_SUCCESS
    fi

    # 簡化的編輯距離計算（使用 diff）
    # 將字符串每個字符放在單獨一行
    local chars1=$(echo "$norm1" | fold -w1)
    local chars2=$(echo "$norm2" | fold -w1)

    # 計算差異字符數（清理輸出，確保是數字）
    local diff_count
    diff_count=$(diff <(echo "$chars1") <(echo "$chars2") 2>/dev/null | grep "^[<>]" | wc -l | tr -d '[:space:]')
    # 確保是數字
    if ! [[ "$diff_count" =~ ^[0-9]+$ ]]; then
        diff_count=0
    fi

    # 計算相似度: (最大長度 - 差異數 / 2) / 最大長度 * 100
    # 除以 2 是因為 diff 會計算插入和刪除為兩次差異
    local edit_distance=$((diff_count / 2))
    local similarity=$(((max_len - edit_distance) * 100 / max_len))

    # 確保相似度在 0-100 之間
    [ "$similarity" -lt 0 ] && similarity=0
    [ "$similarity" -gt 100 ] && similarity=100

    echo "$similarity"
    return $DEDUP_SUCCESS
}

# 組合多種方法計算最終相似度
# 用法: similarity=$(calculate_combined_similarity "string1" "string2")
# 輸出: 相似度百分比（0-100）
# 返回: 0=成功，2=錯誤
# 說明: 綜合 Jaccard 和字符相似度，取較高值
calculate_combined_similarity() {
    local str1="${1:-}"
    local str2="${2:-}"

    if [ -z "$str1" ] || [ -z "$str2" ]; then
        echo "錯誤：calculate_combined_similarity 需要提供兩個字串" >&2
        return $DEDUP_ERROR
    fi

    # 計算兩種相似度
    local jaccard_sim
    local char_sim

    if ! jaccard_sim=$(calculate_jaccard_similarity "$str1" "$str2" 2>/dev/null); then
        jaccard_sim=0
    fi

    if ! char_sim=$(calculate_char_similarity "$str1" "$str2" 2>/dev/null); then
        char_sim=0
    fi

    # 取較高值（樂觀策略）
    local final_sim=$jaccard_sim
    [ "$char_sim" -gt "$final_sim" ] && final_sim=$char_sim

    echo "$final_sim"
    return $DEDUP_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 2: 判斷是否重複
# ═══════════════════════════════════════════════════════════════

# 判斷兩個內容是否重複
# 用法: is_duplicate "content1" "content2"
# 返回: 0=是重複，1=不是重複，2=錯誤
is_duplicate() {
    local content1="${1:-}"
    local content2="${2:-}"

    if [ -z "$content1" ] || [ -z "$content2" ]; then
        echo "錯誤：is_duplicate 需要提供兩個內容" >&2
        return $DEDUP_ERROR
    fi

    # 使用組合相似度計算
    local similarity
    if ! similarity=$(calculate_combined_similarity "$content1" "$content2" 2>/dev/null); then
        echo "錯誤：無法計算相似度" >&2
        return $DEDUP_ERROR
    fi

    # 如果相似度 >= 閾值，視為重複
    if [ "$similarity" -ge "$DEDUP_SIMILARITY_THRESHOLD" ]; then
        return $DEDUP_SUCCESS  # 0 = 是重複
    else
        return $DEDUP_NOT_DUPLICATE  # 1 = 不是重複
    fi
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 3: 合併記憶
# ═══════════════════════════════════════════════════════════════

# 合併兩個記憶條目（JSON 格式）
# 用法: merged=$(merge_memories "$old_memory_json" "$new_memory_json")
# 參數:
#   old_memory_json - 舊記憶的 JSON 字串（包含 content, updated, access_count, tags）
#   new_memory_json - 新記憶的 JSON 字串
# 輸出: 合併後的記憶 JSON 字串
# 合併策略:
#   - 保留較新的 updated 時間戳
#   - 累加 access_count
#   - 合併 tags（去重）
#   - 保留較長的 content（假設更完整）
# 返回: 0=成功，2=錯誤
merge_memories() {
    local old_memory="${1:-}"
    local new_memory="${2:-}"

    if [ -z "$old_memory" ] || [ -z "$new_memory" ]; then
        echo "錯誤：merge_memories 需要提供兩個記憶條目" >&2
        return $DEDUP_ERROR
    fi

    # 檢查是否安裝 jq
    if ! command -v jq >/dev/null 2>&1; then
        echo "錯誤：需要安裝 jq 工具" >&2
        echo "提示：brew install jq 或 apt-get install jq" >&2
        return $DEDUP_ERROR
    fi

    # 解析 JSON 欄位
    local old_content=$(echo "$old_memory" | jq -r '.content // ""')
    local new_content=$(echo "$new_memory" | jq -r '.content // ""')
    local old_updated=$(echo "$old_memory" | jq -r '.updated // ""')
    local new_updated=$(echo "$new_memory" | jq -r '.updated // ""')
    local old_count=$(echo "$old_memory" | jq -r '.access_count // 0')
    local new_count=$(echo "$new_memory" | jq -r '.access_count // 0')
    local old_tags=$(echo "$old_memory" | jq -r '.tags // ""')
    local new_tags=$(echo "$new_memory" | jq -r '.tags // ""')

    # 選擇較長的內容（假設更完整）
    local merged_content="$new_content"
    if [ "${#old_content}" -gt "${#new_content}" ]; then
        merged_content="$old_content"
    fi

    # 選擇較新的時間戳
    local merged_updated="$new_updated"
    if [[ "$old_updated" > "$new_updated" ]]; then
        merged_updated="$old_updated"
    fi

    # 累加 access_count
    local merged_count=$((old_count + new_count))

    # 合併 tags（去重）
    local merged_tags=""
    if [ -n "$old_tags" ] && [ -n "$new_tags" ]; then
        merged_tags=$(echo -e "${old_tags}\n${new_tags}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort -u | tr '\n' ',' | sed 's/,$//')
    elif [ -n "$old_tags" ]; then
        merged_tags="$old_tags"
    elif [ -n "$new_tags" ]; then
        merged_tags="$new_tags"
    fi

    # 建立合併後的 JSON
    local merged_json=$(jq -n \
        --arg content "$merged_content" \
        --arg updated "$merged_updated" \
        --argjson count "$merged_count" \
        --arg tags "$merged_tags" \
        '{
            content: $content,
            updated: $updated,
            access_count: $count,
            tags: $tags
        }')

    echo "$merged_json"
    return $DEDUP_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 4: 找出重複記憶
# ═══════════════════════════════════════════════════════════════

# 在記憶列表中找出重複項
# 用法: duplicates=$(find_duplicates "memory1_json" "memory2_json" ...)
# 參數: 多個記憶的 JSON 字串（透過 stdin 輸入，每行一個 JSON）
# 輸出: 重複記憶對的索引（格式：index1,index2），每行一對
# 返回: 0=成功，2=錯誤
find_duplicates() {
    # 從 stdin 讀取記憶列表
    local memories=()
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            memories+=("$line")
        fi
    done

    if [ "${#memories[@]}" -lt 2 ]; then
        # 少於 2 個記憶，無需比較
        return $DEDUP_SUCCESS
    fi

    # 雙重迴圈比較所有記憶對
    local total="${#memories[@]}"
    local i j

    for ((i=0; i<total; i++)); do
        for ((j=i+1; j<total; j++)); do
            # 提取內容
            local content1
            local content2

            if command -v jq >/dev/null 2>&1; then
                content1=$(echo "${memories[$i]}" | jq -r '.content // ""')
                content2=$(echo "${memories[$j]}" | jq -r '.content // ""')
            else
                # Fallback: 簡單提取（假設格式規範）
                content1=$(echo "${memories[$i]}" | grep -o '"content":"[^"]*"' | cut -d'"' -f4)
                content2=$(echo "${memories[$j]}" | grep -o '"content":"[^"]*"' | cut -d'"' -f4)
            fi

            # 檢查是否重複
            if is_duplicate "$content1" "$content2" 2>/dev/null; then
                echo "$i,$j"
            fi
        done
    done

    return $DEDUP_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_dedup_help() {
    cat <<'EOF'
記憶語義去重工具 (Memory Deduplication)

用法:
  source memory-dedup.sh

主要函式:
  is_duplicate <content1> <content2>
    判斷兩個內容是否重複
    返回: 0=是重複，1=不是重複，2=錯誤

  calculate_similarity <str1> <str2>
    計算兩個字串的相似度（簡單方法）
    輸出: 相似度百分比（0-100）

  calculate_jaccard_similarity <str1> <str2>
    計算兩個字串的 Jaccard 相似度（詞彙級別）
    輸出: 相似度百分比（0-100）

  calculate_char_similarity <str1> <str2>
    計算兩個字串的字符相似度（適合中文）
    輸出: 相似度百分比（0-100）

  calculate_combined_similarity <str1> <str2>
    計算綜合相似度（組合多種方法）
    輸出: 相似度百分比（0-100）

  merge_memories <old_memory_json> <new_memory_json>
    合併兩個記憶條目
    輸出: 合併後的記憶 JSON 字串

  find_duplicates
    從 stdin 讀取記憶列表，找出重複項
    輸入: 每行一個記憶 JSON
    輸出: 重複記憶對的索引（index1,index2）

相似度閾值:
  ${DEDUP_SIMILARITY_THRESHOLD}% - 高於此值視為重複

合併策略:
  - updated: 保留較新的時間戳
  - access_count: 累加
  - tags: 合併並去重
  - content: 保留較長的（假設更完整）

範例:
  # 判斷是否重複
  if is_duplicate "content1" "content2"; then
      echo "是重複"
  else
      echo "不是重複"
  fi

  # 計算相似度
  similarity=$(calculate_jaccard_similarity "text1" "text2")
  echo "相似度: ${similarity}%"

  # 合併記憶
  old_mem='{"content":"old","updated":"2024-01-01T10:00:00Z","access_count":5,"tags":"tag1"}'
  new_mem='{"content":"new","updated":"2024-01-02T10:00:00Z","access_count":3,"tags":"tag2"}'
  merged=$(merge_memories "$old_mem" "$new_mem")
  echo "$merged"

  # 找出重複項
  cat memories.jsonl | find_duplicates

返回碼:
  0 - 成功（或是重複）
  1 - 不是重複
  2 - 錯誤

依賴:
  - jq (用於 JSON 處理) - merge_memories 和 find_duplicates 需要
  - diff, comm, sort, tr, wc - 用於相似度計算
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        help|--help|-h|"")
            show_dedup_help
            exit 0
            ;;
        is-duplicate)
            shift
            if [ $# -lt 2 ]; then
                echo "錯誤：需要提供兩個內容參數" >&2
                exit 2
            fi
            if is_duplicate "$1" "$2"; then
                echo "是重複 (相似度 >= ${DEDUP_SIMILARITY_THRESHOLD}%)"
                exit 0
            else
                echo "不是重複"
                exit 1
            fi
            ;;
        similarity)
            shift
            if [ $# -lt 2 ]; then
                echo "錯誤：需要提供兩個字串參數" >&2
                exit 2
            fi
            result=$(calculate_similarity "$1" "$2")
            echo "$result"
            exit 0
            ;;
        jaccard)
            shift
            if [ $# -lt 2 ]; then
                echo "錯誤：需要提供兩個字串參數" >&2
                exit 2
            fi
            result=$(calculate_jaccard_similarity "$1" "$2")
            echo "$result"
            exit 0
            ;;
        char-sim)
            shift
            if [ $# -lt 2 ]; then
                echo "錯誤：需要提供兩個字串參數" >&2
                exit 2
            fi
            result=$(calculate_char_similarity "$1" "$2")
            echo "$result"
            exit 0
            ;;
        combined)
            shift
            if [ $# -lt 2 ]; then
                echo "錯誤：需要提供兩個字串參數" >&2
                exit 2
            fi
            result=$(calculate_combined_similarity "$1" "$2")
            echo "$result"
            exit 0
            ;;
        merge)
            shift
            if [ $# -lt 2 ]; then
                echo "錯誤：需要提供兩個記憶 JSON 參數" >&2
                exit 2
            fi
            merged=$(merge_memories "$1" "$2")
            echo "$merged"
            exit $?
            ;;
        find-duplicates)
            find_duplicates
            exit $?
            ;;
        test)
            # 執行簡單測試
            echo "═══════════════════════════════════════"
            echo "記憶去重工具測試"
            echo "═══════════════════════════════════════"
            echo ""

            # 測試 1: 完全相同
            echo "測試 1: 完全相同的字串"
            text1="這是一個測試"
            text2="這是一個測試"
            sim=$(calculate_jaccard_similarity "$text1" "$text2")
            echo "相似度: ${sim}%"
            if is_duplicate "$text1" "$text2"; then
                echo "結果: ✅ 是重複"
            else
                echo "結果: ❌ 不是重複"
            fi
            echo ""

            # 測試 2: 高度相似
            echo "測試 2: 高度相似的字串"
            text1="使用 TypeScript 進行開發"
            text2="使用 TypeScript 來進行開發"
            sim=$(calculate_jaccard_similarity "$text1" "$text2")
            echo "相似度: ${sim}%"
            if is_duplicate "$text1" "$text2"; then
                echo "結果: ✅ 是重複 (>= ${DEDUP_SIMILARITY_THRESHOLD}%)"
            else
                echo "結果: ⬜ 不是重複 (< ${DEDUP_SIMILARITY_THRESHOLD}%)"
            fi
            echo ""

            # 測試 3: 不相似
            echo "測試 3: 不相似的字串"
            text1="使用 TypeScript"
            text2="安裝 Python 套件"
            sim=$(calculate_jaccard_similarity "$text1" "$text2")
            echo "相似度: ${sim}%"
            if is_duplicate "$text1" "$text2"; then
                echo "結果: ❌ 是重複"
            else
                echo "結果: ✅ 不是重複"
            fi
            echo ""

            # 測試 4: 合併記憶（如果有 jq）
            if command -v jq >/dev/null 2>&1; then
                echo "測試 4: 合併記憶"
                old_mem='{"content":"舊內容","updated":"2024-01-01T10:00:00Z","access_count":5,"tags":"tag1,tag2"}'
                new_mem='{"content":"較長的新內容","updated":"2024-01-02T10:00:00Z","access_count":3,"tags":"tag2,tag3"}'
                merged=$(merge_memories "$old_mem" "$new_mem")
                echo "舊記憶: $old_mem"
                echo "新記憶: $new_mem"
                echo "合併後: $merged"
            else
                echo "測試 4: 跳過（需要 jq）"
            fi

            echo ""
            echo "═══════════════════════════════════════"
            echo "測試完成"
            echo "═══════════════════════════════════════"
            exit 0
            ;;
        *)
            echo "錯誤：未知命令: $1" >&2
            show_dedup_help
            exit 2
            ;;
    esac
fi
