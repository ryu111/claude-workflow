#!/bin/bash
# yaml-parser.sh - YAML Frontmatter 解析工具
# 功能：解析和操作 Markdown 檔案的 YAML frontmatter
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/yaml-parser.sh"

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

readonly FRONTMATTER_DELIMITER="---"

# 返回碼
readonly EXIT_SUCCESS=0
readonly EXIT_FILE_NOT_FOUND=1
readonly EXIT_NO_FRONTMATTER=2
readonly EXIT_FIELD_NOT_FOUND=3
readonly EXIT_ERROR=4

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 檢查檔案是否有 frontmatter
# 用法: has_frontmatter file_path
# 返回: 0=有，1=無
has_frontmatter() {
    local file_path="${1:-}"

    if [ -z "$file_path" ]; then
        echo "錯誤：has_frontmatter 需要提供檔案路徑" >&2
        return $EXIT_ERROR
    fi

    if [ ! -f "$file_path" ]; then
        return $EXIT_FILE_NOT_FOUND
    fi

    # 檢查檔案開頭是否為 ---
    local first_line
    first_line=$(head -n 1 "$file_path")

    if [ "$first_line" = "$FRONTMATTER_DELIMITER" ]; then
        # 檢查是否有第二個 ---
        if tail -n +2 "$file_path" | grep -q "^${FRONTMATTER_DELIMITER}$"; then
            return $EXIT_SUCCESS
        fi
    fi

    return $EXIT_NO_FRONTMATTER
}

# 取得 frontmatter 區塊（包含分隔線）
# 用法: get_frontmatter_block file_path
# 輸出: 完整的 frontmatter 區塊（包含 --- 分隔線）
get_frontmatter_block() {
    local file_path="${1:-}"

    if [ -z "$file_path" ]; then
        echo "錯誤：get_frontmatter_block 需要提供檔案路徑" >&2
        return $EXIT_ERROR
    fi

    if [ ! -f "$file_path" ]; then
        echo "錯誤：檔案不存在: $file_path" >&2
        return $EXIT_FILE_NOT_FOUND
    fi

    if ! has_frontmatter "$file_path"; then
        echo "錯誤：檔案無 frontmatter: $file_path" >&2
        return $EXIT_NO_FRONTMATTER
    fi

    # 提取從第一行到第二個 --- 之間的內容
    awk '
        BEGIN { in_frontmatter = 0; delimiter_count = 0 }
        /^---$/ {
            delimiter_count++
            print
            if (delimiter_count == 1) {
                in_frontmatter = 1
                next
            }
            if (delimiter_count == 2) {
                exit
            }
        }
        in_frontmatter { print }
    ' "$file_path"

    return $EXIT_SUCCESS
}

# 取得內容（不含 frontmatter）
# 用法: get_content_without_frontmatter file_path
# 輸出: frontmatter 之後的所有內容
get_content_without_frontmatter() {
    local file_path="${1:-}"

    if [ -z "$file_path" ]; then
        echo "錯誤：get_content_without_frontmatter 需要提供檔案路徑" >&2
        return $EXIT_ERROR
    fi

    if [ ! -f "$file_path" ]; then
        echo "錯誤：檔案不存在: $file_path" >&2
        return $EXIT_FILE_NOT_FOUND
    fi

    if ! has_frontmatter "$file_path"; then
        # 如果沒有 frontmatter，返回整個檔案
        cat "$file_path"
        return $EXIT_SUCCESS
    fi

    # 跳過 frontmatter，輸出後續內容
    awk '
        BEGIN { delimiter_count = 0; in_content = 0 }
        /^---$/ {
            delimiter_count++
            if (delimiter_count == 2) {
                in_content = 1
                next
            }
            next
        }
        in_content { print }
    ' "$file_path"

    return $EXIT_SUCCESS
}

# 解析 frontmatter 欄位
# 用法: parse_frontmatter file_path [field]
# 參數:
#   file_path - Markdown 檔案路徑
#   field     - 可選，指定欄位名稱。若不指定則輸出全部 frontmatter（不含分隔線）
# 輸出: 欄位值（去除引號）或完整 frontmatter
# 返回:
#   0 - 成功
#   1 - 檔案不存在
#   2 - 無 frontmatter
#   3 - 欄位不存在
parse_frontmatter() {
    local file_path="${1:-}"
    local field="${2:-}"

    if [ -z "$file_path" ]; then
        echo "錯誤：parse_frontmatter 需要提供檔案路徑" >&2
        return $EXIT_ERROR
    fi

    if [ ! -f "$file_path" ]; then
        echo "錯誤：檔案不存在: $file_path" >&2
        return $EXIT_FILE_NOT_FOUND
    fi

    if ! has_frontmatter "$file_path"; then
        echo "錯誤：檔案無 frontmatter: $file_path" >&2
        return $EXIT_NO_FRONTMATTER
    fi

    # 如果沒有指定欄位，返回完整 frontmatter（不含分隔線）
    if [ -z "$field" ]; then
        awk '
            BEGIN { in_frontmatter = 0; delimiter_count = 0 }
            /^---$/ {
                delimiter_count++
                if (delimiter_count == 1) {
                    in_frontmatter = 1
                    next
                }
                if (delimiter_count == 2) {
                    exit
                }
            }
            in_frontmatter { print }
        ' "$file_path"
        return $EXIT_SUCCESS
    fi

    # 提取指定欄位的值
    local frontmatter_block
    frontmatter_block=$(get_frontmatter_block "$file_path" 2>/dev/null) || return $?

    local value
    # 暫時關閉 pipefail，因為 grep 找不到時會返回 1
    set +o pipefail
    value=$(printf '%s\n' "$frontmatter_block" | grep "^${field}:" | head -1 | sed -E 's/^[^:]+:[[:space:]]*//') || true
    set -o pipefail

    if [ -z "$value" ]; then
        echo "錯誤：欄位不存在: $field" >&2
        return $EXIT_FIELD_NOT_FOUND
    fi

    # 去除引號（單引號或雙引號）
    value=$(printf '%s\n' "$value" | sed -E 's/^["'\''](.*)["'\'']$/\1/')

    printf '%s\n' "$value"
    return $EXIT_SUCCESS
}

# 更新 frontmatter 欄位
# 用法: update_frontmatter file_path field value
# 參數:
#   file_path - Markdown 檔案路徑
#   field     - 欄位名稱
#   value     - 新的值
# 返回:
#   0 - 成功
#   1 - 檔案不存在
#   2 - 無 frontmatter
#   4 - 更新失敗
update_frontmatter() {
    local file_path="${1:-}"
    local field="${2:-}"
    local value="${3:-}"

    if [ -z "$file_path" ] || [ -z "$field" ]; then
        echo "錯誤：update_frontmatter 需要提供檔案路徑和欄位名稱" >&2
        return $EXIT_ERROR
    fi

    if [ ! -f "$file_path" ]; then
        echo "錯誤：檔案不存在: $file_path" >&2
        return $EXIT_FILE_NOT_FOUND
    fi

    if ! has_frontmatter "$file_path"; then
        echo "錯誤：檔案無 frontmatter: $file_path" >&2
        return $EXIT_NO_FRONTMATTER
    fi

    # 建立臨時檔案
    local temp_file="${file_path}.tmp.$$"

    # 使用 awk 更新欄位
    awk -v field="$field" -v new_value="$value" '
        BEGIN {
            in_frontmatter = 0
            delimiter_count = 0
            field_found = 0
        }
        /^---$/ {
            delimiter_count++
            print
            if (delimiter_count == 1) {
                in_frontmatter = 1
                next
            }
            if (delimiter_count == 2) {
                in_frontmatter = 0
                next
            }
        }
        in_frontmatter {
            if ($0 ~ "^" field ":") {
                # 保留原始縮排和格式
                match($0, /^[[:space:]]*/)
                indent = substr($0, RSTART, RLENGTH)
                print indent field ": " new_value
                field_found = 1
                next
            }
        }
        { print }
        END {
            if (!field_found && in_frontmatter) {
                # 如果欄位不存在，在 frontmatter 結束前新增
                # 這裡不處理，因為需要在正確位置插入
                exit 3
            }
        }
    ' "$file_path" > "$temp_file"

    local awk_exit_code=$?

    # 檢查是否成功
    if [ $awk_exit_code -eq 3 ]; then
        echo "錯誤：欄位不存在，無法更新: $field" >&2
        rm -f "$temp_file"
        return $EXIT_FIELD_NOT_FOUND
    fi

    if [ ! -s "$temp_file" ]; then
        echo "錯誤：更新失敗" >&2
        rm -f "$temp_file"
        return $EXIT_ERROR
    fi

    # 替換原始檔案
    mv "$temp_file" "$file_path"

    return $EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_yaml_parser_help() {
    cat <<'EOF'
YAML Frontmatter 解析工具

用法:
  source yaml-parser.sh

函式:
  has_frontmatter <file_path>
    檢查檔案是否有 frontmatter
    返回: 0=有，1=無

  get_frontmatter_block <file_path>
    取得完整 frontmatter 區塊（包含分隔線）

  get_content_without_frontmatter <file_path>
    取得 frontmatter 之後的內容

  parse_frontmatter <file_path> [field]
    解析 frontmatter 欄位
    參數:
      file_path - Markdown 檔案路徑
      field     - 可選，欄位名稱
    返回: 欄位值或完整 frontmatter

  update_frontmatter <file_path> <field> <value>
    更新 frontmatter 欄位
    參數:
      file_path - Markdown 檔案路徑
      field     - 欄位名稱
      value     - 新的值

範例:
  # 檢查是否有 frontmatter
  if has_frontmatter "file.md"; then
    echo "有 frontmatter"
  fi

  # 取得特定欄位
  version=$(parse_frontmatter "file.md" "version")

  # 更新欄位
  update_frontmatter "file.md" "updated" "2024-01-01"

  # 取得完整 frontmatter
  parse_frontmatter "file.md"

  # 取得內容（不含 frontmatter）
  get_content_without_frontmatter "file.md"

返回碼:
  0 - 成功
  1 - 檔案不存在
  2 - 無 frontmatter
  3 - 欄位不存在
  4 - 一般錯誤
EOF
}

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        has)
            shift
            has_frontmatter "$@"
            exit $?
            ;;
        get-block)
            shift
            get_frontmatter_block "$@"
            exit $?
            ;;
        get-content)
            shift
            get_content_without_frontmatter "$@"
            exit $?
            ;;
        parse)
            shift
            parse_frontmatter "$@"
            exit $?
            ;;
        update)
            shift
            update_frontmatter "$@"
            exit $?
            ;;
        help|--help|-h|*)
            show_yaml_parser_help
            exit 0
            ;;
    esac
fi
