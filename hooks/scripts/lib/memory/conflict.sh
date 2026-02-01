#!/usr/bin/env bash
# memory-conflict.sh - 記憶矛盾偵測工具
# 功能：偵測記憶之間的矛盾（如「偏好 X」vs「不要 X」）
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-conflict.sh"

set -euo pipefail

# 載入依賴
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/../core/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義（使用 CONFLICT_ 前綴避免衝突）
# ═══════════════════════════════════════════════════════════════

# 返回碼
readonly CONFLICT_FOUND=0
readonly CONFLICT_NOT_FOUND=1
readonly CONFLICT_ERROR=2

# 衝突類型
readonly CONFLICT_TYPE_PREFERENCE="PREFERENCE_CONFLICT"
readonly CONFLICT_TYPE_ACTION="ACTION_CONFLICT"
readonly CONFLICT_TYPE_VALUE="VALUE_CONFLICT"
readonly CONFLICT_TYPE_STATE="STATE_CONFLICT"

# 矛盾模式定義（中文）
# 格式：正面關鍵字|對應的負面關鍵字
readonly CONFLICT_PATTERNS_ZH=(
    "偏好|不要"
    "喜歡|討厭"
    "總是|永不"
    "永遠|絕不"
    "使用|禁止"
    "啟用|禁用"
    "開啟|關閉"
    "允許|拒絕"
    "接受|排除"
    "包含|排除"
)

# 矛盾模式定義（英文）
readonly CONFLICT_PATTERNS_EN=(
    "prefer|avoid"
    "like|dislike"
    "always|never"
    "use|forbid"
    "enable|disable"
    "allow|deny"
    "include|exclude"
    "accept|reject"
    "on|off"
    "yes|no"
)

# 行為關鍵字（中文）
readonly ACTION_KEYWORDS_ZH="使用|執行|啟用|開啟|呼叫|運行"

# 行為關鍵字（英文）
readonly ACTION_KEYWORDS_EN="use|execute|enable|call|run|invoke"

# ═══════════════════════════════════════════════════════════════
# 輔助功能：提取關鍵概念
# ═══════════════════════════════════════════════════════════════

# 提取記憶中的關鍵概念（名詞、工具名稱等）
# 用法: extract_concept "content"
# 返回: 關鍵概念（空格分隔）
extract_concept() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        return 1
    fi

    # 簡單的啟發式規則：
    # 1. 提取引號內的內容（如「TypeScript」、"React"）
    # 2. 提取大寫字母開頭的單詞（如 TypeScript, React）
    # 3. 提取常見技術名詞模式
    # 4. 排除常見關鍵字（Always, Never 等）

    local concepts=""

    # 提取引號內容（中文）
    local zh_quoted
    zh_quoted=$(echo "$content" | grep -oE '「[^」]+」' | sed 's/[「」]//g' || true)
    if [ -n "$zh_quoted" ]; then
        concepts="$zh_quoted"
    fi

    # 提取引號內容（英文）
    local en_quoted
    en_quoted=$(echo "$content" | grep -oE '"[^"]+"' | sed 's/"//g' || true)
    if [ -n "$en_quoted" ]; then
        concepts="$concepts $en_quoted"
    fi

    # 提取大寫字母開頭的單詞（長度 > 2，排除常見關鍵字）
    local capitalized
    capitalized=$(echo "$content" | grep -oE '\b[A-Z][A-Za-z0-9]{2,}\b' | grep -vE '^(Never|Always|Prefer|Avoid|Like|Dislike|Enable|Disable|Allow|Deny|Include|Exclude|Accept|Reject)$' || true)
    if [ -n "$capitalized" ]; then
        concepts="$concepts $capitalized"
    fi

    # 去重並輸出
    echo "$concepts" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 1：偵測矛盾
# ═══════════════════════════════════════════════════════════════

# 偵測兩個記憶是否矛盾
# 用法: detect_conflict "memory1" "memory2"
# 返回:
#   0 - 發現矛盾
#   1 - 無矛盾
#   2 - 錯誤
detect_conflict() {
    local memory1="${1:-}"
    local memory2="${2:-}"

    if [ -z "$memory1" ] || [ -z "$memory2" ]; then
        echo "錯誤：detect_conflict 需要提供兩個記憶內容" >&2
        return $CONFLICT_ERROR
    fi

    # 提取關鍵概念
    local concepts1
    local concepts2
    concepts1=$(extract_concept "$memory1")
    concepts2=$(extract_concept "$memory2")

    # 尋找共同概念
    local common_concepts=""
    for concept in $concepts1; do
        if echo "$concepts2" | grep -qw "$concept"; then
            common_concepts="$common_concepts $concept"
        fi
    done

    # 注意：即使沒有明確的共同概念，仍可能存在矛盾
    # （例如「總是用 const」vs「永不用 let」）
    # 因此我們不在此處直接返回，而是繼續檢查矛盾模式

    # 檢查中文矛盾模式
    for pattern in "${CONFLICT_PATTERNS_ZH[@]}"; do
        local positive=$(echo "$pattern" | cut -d'|' -f1)
        local negative=$(echo "$pattern" | cut -d'|' -f2)

        # 檢查 memory1 是否包含正面關鍵字，memory2 是否包含負面關鍵字
        if echo "$memory1" | grep -qE "$positive" && echo "$memory2" | grep -qE "$negative"; then
            if [ -n "$common_concepts" ]; then
                # 有共同概念時，嚴格匹配：確認關鍵字與概念在同一句
                for concept in $common_concepts; do
                    if echo "$memory1" | grep -E "$positive.*$concept|$concept.*$positive" > /dev/null 2>&1 && \
                       echo "$memory2" | grep -E "$negative.*$concept|$concept.*$negative" > /dev/null 2>&1; then
                        return $CONFLICT_FOUND
                    fi
                done
            else
                # 無共同概念但包含矛盾關鍵字，可能是潛在矛盾
                return $CONFLICT_FOUND
            fi
        fi

        # 反向檢查
        if echo "$memory1" | grep -qE "$negative" && echo "$memory2" | grep -qE "$positive"; then
            if [ -n "$common_concepts" ]; then
                for concept in $common_concepts; do
                    if echo "$memory1" | grep -E "$negative.*$concept|$concept.*$negative" > /dev/null 2>&1 && \
                       echo "$memory2" | grep -E "$positive.*$concept|$concept.*$positive" > /dev/null 2>&1; then
                        return $CONFLICT_FOUND
                    fi
                done
            else
                return $CONFLICT_FOUND
            fi
        fi
    done

    # 檢查英文矛盾模式
    for pattern in "${CONFLICT_PATTERNS_EN[@]}"; do
        local positive=$(echo "$pattern" | cut -d'|' -f1)
        local negative=$(echo "$pattern" | cut -d'|' -f2)

        if echo "$memory1" | grep -qiE "\b$positive\b" && echo "$memory2" | grep -qiE "\b$negative\b"; then
            if [ -n "$common_concepts" ]; then
                # 有共同概念時，嚴格匹配
                for concept in $common_concepts; do
                    if echo "$memory1" | grep -iE "\b$positive\b.*\b$concept\b|\b$concept\b.*\b$positive\b" > /dev/null 2>&1 && \
                       echo "$memory2" | grep -iE "\b$negative\b.*\b$concept\b|\b$concept\b.*\b$negative\b" > /dev/null 2>&1; then
                        return $CONFLICT_FOUND
                    fi
                done
            else
                # 無共同概念但包含矛盾關鍵字
                return $CONFLICT_FOUND
            fi
        fi

        # 反向檢查
        if echo "$memory1" | grep -qiE "\b$negative\b" && echo "$memory2" | grep -qiE "\b$positive\b"; then
            if [ -n "$common_concepts" ]; then
                for concept in $common_concepts; do
                    if echo "$memory1" | grep -iE "\b$negative\b.*\b$concept\b|\b$concept\b.*\b$negative\b" > /dev/null 2>&1 && \
                       echo "$memory2" | grep -iE "\b$positive\b.*\b$concept\b|\b$concept\b.*\b$positive\b" > /dev/null 2>&1; then
                        return $CONFLICT_FOUND
                    fi
                done
            else
                return $CONFLICT_FOUND
            fi
        fi
    done

    return $CONFLICT_NOT_FOUND
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 2：判斷衝突類型
# ═══════════════════════════════════════════════════════════════

# 判斷矛盾的類型
# 用法: get_conflict_type "memory1" "memory2"
# 輸出: PREFERENCE_CONFLICT | ACTION_CONFLICT | VALUE_CONFLICT | STATE_CONFLICT
# 返回:
#   0 - 成功識別類型
#   1 - 無法識別類型
get_conflict_type() {
    local memory1="${1:-}"
    local memory2="${2:-}"

    if [ -z "$memory1" ] || [ -z "$memory2" ]; then
        echo "錯誤：get_conflict_type 需要提供兩個記憶內容" >&2
        return 1
    fi

    # 先確認是否真的有矛盾
    if ! detect_conflict "$memory1" "$memory2" 2>/dev/null; then
        return 1
    fi

    local combined="$memory1 $memory2"

    # 規則 1: 偏好衝突（包含「偏好」、「喜歡」等關鍵字）
    if echo "$combined" | grep -qE "偏好|喜歡|討厭|prefer|like|dislike"; then
        echo "$CONFLICT_TYPE_PREFERENCE"
        return 0
    fi

    # 規則 2: 行為衝突（包含「使用」、「執行」等動詞）
    if echo "$combined" | grep -qE "$ACTION_KEYWORDS_ZH"; then
        echo "$CONFLICT_TYPE_ACTION"
        return 0
    fi

    if echo "$combined" | grep -qiE "\b($ACTION_KEYWORDS_EN)\b"; then
        echo "$CONFLICT_TYPE_ACTION"
        return 0
    fi

    # 規則 3: 狀態衝突（包含「啟用/禁用」、「開啟/關閉」）
    if echo "$combined" | grep -qE "啟用|禁用|開啟|關閉|enable|disable|on|off"; then
        echo "$CONFLICT_TYPE_STATE"
        return 0
    fi

    # 規則 4: 預設為值衝突
    echo "$CONFLICT_TYPE_VALUE"
    return 0
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 3：找出所有矛盾
# ═══════════════════════════════════════════════════════════════

# 找出記憶列表中的所有矛盾對
# 用法: find_conflicts memory_file
# 參數:
#   memory_file - 記憶檔案路徑（每行一條記憶）
# 輸出: JSON 格式的矛盾報告
# 返回:
#   0 - 有矛盾
#   1 - 無矛盾
#   2 - 錯誤
find_conflicts() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ]; then
        echo "錯誤：find_conflicts 需要提供記憶檔案路徑" >&2
        return $CONFLICT_ERROR
    fi

    if [ ! -f "$memory_file" ]; then
        echo "錯誤：檔案不存在: $memory_file" >&2
        return $CONFLICT_ERROR
    fi

    # 讀取所有記憶到陣列（相容方式）
    local memories=()
    while IFS= read -r line; do
        memories+=("$line")
    done < "$memory_file"

    local conflict_count=0
    local conflicts_json="["

    # 兩兩比對
    for ((i=0; i<${#memories[@]}; i++)); do
        for ((j=i+1; j<${#memories[@]}; j++)); do
            local mem1="${memories[$i]}"
            local mem2="${memories[$j]}"

            # 跳過空行
            if [ -z "$mem1" ] || [ -z "$mem2" ]; then
                continue
            fi

            # 偵測矛盾
            if detect_conflict "$mem1" "$mem2" 2>/dev/null; then
                local conflict_type
                conflict_type=$(get_conflict_type "$mem1" "$mem2" 2>/dev/null || echo "UNKNOWN")

                # 構建 JSON 條目
                if [ $conflict_count -gt 0 ]; then
                    conflicts_json="$conflicts_json,"
                fi

                conflicts_json="$conflicts_json
  {
    \"index1\": $((i + 1)),
    \"index2\": $((j + 1)),
    \"memory1\": $(echo "$mem1" | jq -Rs .),
    \"memory2\": $(echo "$mem2" | jq -Rs .),
    \"conflict_type\": \"$conflict_type\"
  }"

                ((conflict_count++))
            fi
        done
    done

    conflicts_json="$conflicts_json
]"

    # 輸出結果
    if [ $conflict_count -gt 0 ]; then
        cat <<EOF
{
  "total_memories": ${#memories[@]},
  "conflict_count": $conflict_count,
  "conflicts": $conflicts_json
}
EOF
        return $CONFLICT_FOUND
    else
        cat <<EOF
{
  "total_memories": ${#memories[@]},
  "conflict_count": 0,
  "conflicts": []
}
EOF
        return $CONFLICT_NOT_FOUND
    fi
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 4：生成衝突報告
# ═══════════════════════════════════════════════════════════════

# 生成人類可讀的衝突報告
# 用法: generate_conflict_report memory_file
# 參數:
#   memory_file - 記憶檔案路徑
# 輸出: Markdown 格式的報告
generate_conflict_report() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ]; then
        echo "錯誤：generate_conflict_report 需要提供記憶檔案路徑" >&2
        return $CONFLICT_ERROR
    fi

    # 取得 JSON 結果
    local json_result
    json_result=$(find_conflicts "$memory_file")
    local status=$?

    # 解析 JSON
    local conflict_count
    conflict_count=$(echo "$json_result" | jq -r '.conflict_count')

    if [ "$conflict_count" = "0" ]; then
        cat <<EOF
# 記憶矛盾檢測報告

**狀態**: ✅ 無矛盾
**檢測時間**: $(date -u +%Y-%m-%dT%H:%M:%SZ)

所有記憶內容一致，未發現矛盾。
EOF
        return $status
    fi

    # 生成報告標題
    cat <<EOF
# 記憶矛盾檢測報告

**狀態**: ⚠️ 發現 $conflict_count 處矛盾
**檢測時間**: $(date -u +%Y-%m-%dT%H:%M:%SZ)

---

## 矛盾列表

EOF

    # 遍歷每個矛盾
    echo "$json_result" | jq -r '.conflicts[] | @json' | while IFS= read -r conflict; do
        local index1=$(echo "$conflict" | jq -r '.index1')
        local index2=$(echo "$conflict" | jq -r '.index2')
        local memory1=$(echo "$conflict" | jq -r '.memory1')
        local memory2=$(echo "$conflict" | jq -r '.memory2')
        local conflict_type=$(echo "$conflict" | jq -r '.conflict_type')

        # 轉換衝突類型為中文
        local type_zh
        case "$conflict_type" in
            "$CONFLICT_TYPE_PREFERENCE")
                type_zh="偏好衝突"
                ;;
            "$CONFLICT_TYPE_ACTION")
                type_zh="行為衝突"
                ;;
            "$CONFLICT_TYPE_VALUE")
                type_zh="值衝突"
                ;;
            "$CONFLICT_TYPE_STATE")
                type_zh="狀態衝突"
                ;;
            *)
                type_zh="未知衝突"
                ;;
        esac

        cat <<EOF
### 矛盾 #$index1 vs #$index2

**類型**: $type_zh ($conflict_type)

**記憶 A (行 $index1)**:
> $memory1

**記憶 B (行 $index2)**:
> $memory2

**建議**:
- 請確認哪個記憶是正確的
- 刪除或修改其中一個記憶
- 或標記為例外情況

---

EOF
    done

    cat <<EOF
## 處理建議

1. **手動審查**: 逐一檢查上述矛盾
2. **選擇保留**: 確定哪個記憶應該保留
3. **更新記憶**: 刪除或修改衝突的記憶
4. **重新檢測**: 修改後重新執行檢測

**注意**: 某些看似矛盾的記憶可能是不同情境下的有效偏好。
EOF

    return $status
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示矛盾模式說明
show_conflict_patterns() {
    cat <<'EOF'
記憶矛盾偵測模式
═══════════════════════════════════════

## 中文矛盾模式

| 正面關鍵字 | 負面關鍵字 | 範例 |
|-----------|-----------|------|
| 偏好      | 不要      | 偏好 TypeScript vs 不要 TypeScript |
| 喜歡      | 討厭      | 喜歡 React vs 討厭 React |
| 總是      | 永不      | 總是使用 const vs 永不使用 const |
| 永遠      | 絕不      | 永遠啟用 lint vs 絕不啟用 lint |
| 使用      | 禁止      | 使用 eval vs 禁止 eval |
| 啟用      | 禁用      | 啟用快取 vs 禁用快取 |
| 開啟      | 關閉      | 開啟日誌 vs 關閉日誌 |
| 允許      | 拒絕      | 允許訪問 vs 拒絕訪問 |

## 英文矛盾模式

| Positive  | Negative | Example |
|-----------|----------|---------|
| prefer    | avoid    | prefer TypeScript vs avoid TypeScript |
| like      | dislike  | like React vs dislike React |
| always    | never    | always use const vs never use const |
| use       | forbid   | use eval vs forbid eval |
| enable    | disable  | enable cache vs disable cache |
| allow     | deny     | allow access vs deny access |

## 衝突類型

1. **PREFERENCE_CONFLICT** - 偏好衝突
   包含關鍵字：偏好、喜歡、討厭、prefer、like、dislike

2. **ACTION_CONFLICT** - 行為衝突
   包含關鍵字：使用、執行、啟用、use、execute、enable

3. **VALUE_CONFLICT** - 值衝突
   其他語義矛盾

4. **STATE_CONFLICT** - 狀態衝突
   包含關鍵字：啟用/禁用、開啟/關閉、enable/disable、on/off

## 偵測邏輯

1. 提取關鍵概念（引號內容、大寫單詞）
2. 檢查兩個記憶是否有共同概念
3. 檢查是否同時包含正反關鍵字
4. 確認關鍵字與概念的位置關係

EOF
}

# 顯示使用說明
show_conflict_help() {
    cat <<'EOF'
記憶矛盾偵測工具 (Memory Conflict Detection)

用法:
  source memory-conflict.sh

函式:
  detect_conflict <memory1> <memory2>
    偵測兩個記憶是否矛盾
    參數:
      memory1 - 第一條記憶內容
      memory2 - 第二條記憶內容
    返回:
      0 - 發現矛盾
      1 - 無矛盾
      2 - 錯誤

  get_conflict_type <memory1> <memory2>
    判斷矛盾的類型
    參數:
      memory1 - 第一條記憶內容
      memory2 - 第二條記憶內容
    輸出: PREFERENCE_CONFLICT | ACTION_CONFLICT | VALUE_CONFLICT | STATE_CONFLICT
    返回:
      0 - 成功識別類型
      1 - 無法識別類型

  find_conflicts <memory_file>
    找出記憶檔案中的所有矛盾對
    參數:
      memory_file - 記憶檔案路徑（每行一條記憶）
    輸出: JSON 格式的矛盾報告
    返回:
      0 - 有矛盾
      1 - 無矛盾
      2 - 錯誤

  generate_conflict_report <memory_file>
    生成人類可讀的衝突報告
    參數:
      memory_file - 記憶檔案路徑
    輸出: Markdown 格式的報告

  show_conflict_patterns
    顯示所有矛盾模式說明

範例:
  # 偵測兩個記憶是否矛盾
  if detect_conflict "我偏好 TypeScript" "不要使用 TypeScript"; then
    echo "發現矛盾"
  fi

  # 判斷矛盾類型
  type=$(get_conflict_type "我喜歡 React" "我討厭 React")
  echo "矛盾類型: $type"

  # 找出檔案中的所有矛盾
  find_conflicts memories.txt

  # 生成報告
  generate_conflict_report memories.txt > conflict-report.md

  # 顯示矛盾模式
  show_conflict_patterns

CLI 模式:
  bash memory-conflict.sh detect "memory1" "memory2"
  bash memory-conflict.sh type "memory1" "memory2"
  bash memory-conflict.sh find memories.txt
  bash memory-conflict.sh report memories.txt
  bash memory-conflict.sh patterns
  bash memory-conflict.sh help

衝突類型:
  - PREFERENCE_CONFLICT: 偏好衝突（偏好/不要、喜歡/討厭）
  - ACTION_CONFLICT: 行為衝突（使用/禁止、執行/避免）
  - VALUE_CONFLICT: 值衝突（其他語義矛盾）
  - STATE_CONFLICT: 狀態衝突（啟用/禁用、開啟/關閉）

注意事項:
  - 偵測基於關鍵字和啟發式規則
  - 可能產生誤報（需人工確認）
  - 不同情境下的相反偏好可能是合理的
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        detect)
            shift
            if [ $# -lt 2 ]; then
                echo "錯誤：需要提供兩個記憶內容" >&2
                exit 2
            fi
            if detect_conflict "$1" "$2"; then
                echo "✅ 發現矛盾"
                exit 0
            else
                echo "❌ 無矛盾"
                exit 1
            fi
            ;;
        type)
            shift
            if [ $# -lt 2 ]; then
                echo "錯誤：需要提供兩個記憶內容" >&2
                exit 2
            fi
            get_conflict_type "$1" "$2"
            exit $?
            ;;
        find)
            shift
            if [ $# -lt 1 ]; then
                echo "錯誤：需要提供記憶檔案路徑" >&2
                exit 2
            fi
            find_conflicts "$1"
            exit $?
            ;;
        report)
            shift
            if [ $# -lt 1 ]; then
                echo "錯誤：需要提供記憶檔案路徑" >&2
                exit 2
            fi
            generate_conflict_report "$1"
            exit $?
            ;;
        patterns)
            show_conflict_patterns
            exit 0
            ;;
        help|--help|-h|*)
            show_conflict_help
            exit 0
            ;;
    esac
fi
