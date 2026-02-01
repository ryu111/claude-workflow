#!/bin/bash
# memory-update.sh - MEMORY.md 更新邏輯工具函式庫
# 功能：提供 MEMORY.md 檔案的區段更新、追加內容、版本管理
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-update.sh"

# 注意：不使用 set -e，因為我們需要優雅處理錯誤
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# 載入依賴模組
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 複製 common.sh 的函式（避免載入衝突）
get_timestamp() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

ensure_directory() {
    local dir_path="${1:-}"
    if [ -z "$dir_path" ]; then
        echo "錯誤：ensure_directory 需要提供目錄路徑" >&2
        return 1
    fi
    if [ ! -d "$dir_path" ]; then
        mkdir -p "$dir_path" || {
            echo "錯誤：無法建立目錄: $dir_path" >&2
            return 1
        }
    fi
    return 0
}

ensure_memory_dir() {
    local memory_dir="${PWD}/.claude/memory"
    ensure_directory "$memory_dir"
}

# 複製 atomic-write.sh 的核心功能
atomic_write() {
    local enable_backup=false
    local file_path=""
    local content=""

    # 簡化的選項解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--backup)
                enable_backup=true
                shift
                ;;
            -p|--permission)
                shift 2  # 忽略權限設定
                ;;
            *)
                if [ -z "$file_path" ]; then
                    file_path="$1"
                elif [ -z "$content" ]; then
                    content="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$file_path" ]; then
        echo "錯誤：atomic_write 需要提供檔案路徑" >&2
        return 1
    fi

    # 確保父目錄存在
    local parent_dir="$(dirname "$file_path")"
    ensure_directory "$parent_dir" || return 1

    # 備份（如果啟用）
    if [ "$enable_backup" = true ] && [ -f "$file_path" ]; then
        cp "$file_path" "${file_path}.backup.$(date +%s)" 2>/dev/null || true
    fi

    # 原子性寫入
    local temp_file="${file_path}.tmp.$$"
    echo "$content" > "$temp_file" || return 1
    chmod 600 "$temp_file" 2>/dev/null || true
    mv "$temp_file" "$file_path" || return 1

    return 0
}

# 複製 yaml-parser.sh 的核心功能
has_frontmatter() {
    local file_path="${1:-}"
    if [ ! -f "$file_path" ]; then
        return 1
    fi
    local first_line="$(head -n 1 "$file_path")"
    if [ "$first_line" = "---" ]; then
        if tail -n +2 "$file_path" | grep -q "^---$"; then
            return 0
        fi
    fi
    return 1
}

parse_frontmatter() {
    local file_path="${1:-}"
    local field="${2:-}"

    if [ ! -f "$file_path" ] || ! has_frontmatter "$file_path"; then
        return 1
    fi

    if [ -z "$field" ]; then
        return 0
    fi

    # 提取欄位值
    local value
    value=$(awk -v field="$field" '
        BEGIN { in_fm = 0; delimiter_count = 0 }
        /^---$/ {
            delimiter_count++
            if (delimiter_count == 1) { in_fm = 1; next }
            if (delimiter_count == 2) { exit }
        }
        in_fm && $0 ~ "^" field ":" {
            sub(/^[^:]+:[[:space:]]*/, "")
            gsub(/^["'\'']|["'\'']$/, "")
            print
            exit
        }
    ' "$file_path")

    if [ -z "$value" ]; then
        return 1
    fi

    echo "$value"
    return 0
}

update_frontmatter() {
    local file_path="${1:-}"
    local field="${2:-}"
    local value="${3:-}"

    if [ -z "$file_path" ] || [ -z "$field" ]; then
        return 1
    fi

    if [ ! -f "$file_path" ] || ! has_frontmatter "$file_path"; then
        return 1
    fi

    local temp_file="${file_path}.tmp.$$"

    awk -v field="$field" -v new_value="$value" '
        BEGIN { in_fm = 0; delimiter_count = 0; found = 0 }
        /^---$/ {
            delimiter_count++
            print
            if (delimiter_count == 1) { in_fm = 1; next }
            if (delimiter_count == 2) { in_fm = 0; next }
        }
        in_fm && $0 ~ "^" field ":" {
            match($0, /^[[:space:]]*/)
            indent = substr($0, RSTART, RLENGTH)
            print indent field ": " new_value
            found = 1
            next
        }
        { print }
    ' "$file_path" > "$temp_file"

    if [ ! -s "$temp_file" ]; then
        rm -f "$temp_file"
        return 1
    fi

    mv "$temp_file" "$file_path"
    return 0
}

# ═══════════════════════════════════════════════════════════════
# 常數定義（使用 UPDATE_ 前綴避免衝突）
# ═══════════════════════════════════════════════════════════════

# 返回碼
UPDATE_SUCCESS=0
UPDATE_FAILED=1
UPDATE_SECTION_NOT_FOUND=2
UPDATE_FILE_NOT_FOUND=3

# 更新模式
readonly UPDATE_MODE_APPEND="append"
readonly UPDATE_MODE_REPLACE="replace"
readonly UPDATE_MODE_MERGE="merge"

# 區段標記
readonly UPDATE_SECTION_MARKER="##"

# ═══════════════════════════════════════════════════════════════
# 核心功能 1: 尋找區段
# ═══════════════════════════════════════════════════════════════

# 在 MEMORY.md 中找到指定區段的起始和結束行號
# 用法: find_section file_path section_name
# 輸出: start_line:end_line (例如: "5:10")
# 返回:
#   0 - 成功找到
#   2 - 區段不存在
#   3 - 檔案不存在
find_section() {
    local file_path="${1:-}"
    local section_name="${2:-}"

    if [ -z "$file_path" ] || [ -z "$section_name" ]; then
        echo "錯誤：find_section 需要提供檔案路徑和區段名稱" >&2
        return $UPDATE_FAILED
    fi

    if [ ! -f "$file_path" ]; then
        echo "錯誤：檔案不存在: $file_path" >&2
        return $UPDATE_FILE_NOT_FOUND
    fi

    # 使用 awk 找到區段的起始和結束行號
    local result
    result=$(awk -v section="$section_name" '
        BEGIN {
            start_line = 0
            end_line = 0
            found = 0
        }
        # 匹配區段標題（支援中文）
        /^## / {
            # 提取區段名稱（去除 ## 和前後空白）
            current_section = $0
            sub(/^##[[:space:]]*/, "", current_section)

            if (current_section == section && !found) {
                start_line = NR
                found = 1
                next
            }

            # 如果已經找到目標區段，遇到下一個 ## 表示區段結束
            if (found && start_line > 0) {
                end_line = NR - 1
                exit
            }
        }
        END {
            # 如果找到了區段但沒有遇到下一個 ##，則結束行為檔案末尾
            if (found && end_line == 0) {
                end_line = NR
            }

            if (start_line > 0) {
                print start_line ":" end_line
            }
        }
    ' "$file_path")

    if [ -z "$result" ]; then
        echo "錯誤：區段不存在: $section_name" >&2
        return $UPDATE_SECTION_NOT_FOUND
    fi

    echo "$result"
    return $UPDATE_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 2: 追加內容到區段
# ═══════════════════════════════════════════════════════════════

# 在指定區段末尾追加內容
# 用法: append_to_section file_path section_name content [source]
# 參數:
#   file_path    - MEMORY.md 檔案路徑
#   section_name - 區段名稱（如「專案偏好」）
#   content      - 要追加的內容
#   source       - 可選，來源標記（如「REVIEWER」）
# 返回:
#   0 - 成功
#   1 - 失敗
append_to_section() {
    local file_path="${1:-}"
    local section_name="${2:-}"
    local content="${3:-}"
    local source="${4:-}"

    if [ -z "$file_path" ] || [ -z "$section_name" ] || [ -z "$content" ]; then
        echo "錯誤：append_to_section 需要提供檔案路徑、區段名稱和內容" >&2
        return $UPDATE_FAILED
    fi

    # 如果檔案不存在，建立新檔案
    if [ ! -f "$file_path" ]; then
        local timestamp
        timestamp=$(get_timestamp)

        # 建立帶有 frontmatter 的新檔案
        local initial_content="---
created: ${timestamp}
updated: ${timestamp}
version: 1
tags: [preferences, project]
---

## ${section_name}

${content}"

        if [ -n "$source" ]; then
            initial_content="${initial_content}

<!-- 來源: ${source} | 時間: ${timestamp} -->"
        fi

        atomic_write -b -p 600 "$file_path" "$initial_content"
        return $?
    fi

    # 嘗試找到區段
    local section_range
    if section_range=$(find_section "$file_path" "$section_name" 2>/dev/null); then
        # 區段存在，追加內容到區段末尾
        local end_line
        end_line=$(echo "$section_range" | cut -d':' -f2)

        # 建立臨時檔案
        local temp_file="${file_path}.tmp.$$"

        # 在指定行後插入內容
        awk -v end_line="$end_line" -v new_content="$content" -v source="$source" -v timestamp="$(get_timestamp)" '
            NR == end_line {
                print
                print ""
                print new_content
                if (source != "") {
                    print ""
                    print "<!-- 來源: " source " | 時間: " timestamp " -->"
                }
                next
            }
            { print }
        ' "$file_path" > "$temp_file"

        # 使用原子性寫入替換檔案
        if [ -s "$temp_file" ]; then
            cat "$temp_file" | atomic_write -b "$file_path" "$(cat "$temp_file")"
            rm -f "$temp_file"
        else
            rm -f "$temp_file"
            return $UPDATE_FAILED
        fi
    else
        # 區段不存在，在檔案末尾建立新區段
        local timestamp
        timestamp=$(get_timestamp)

        local new_section="

## ${section_name}

${content}"

        if [ -n "$source" ]; then
            new_section="${new_section}

<!-- 來源: ${source} | 時間: ${timestamp} -->"
        fi

        # 讀取現有內容
        local existing_content
        existing_content=$(cat "$file_path")

        # 追加新區段
        atomic_write -b "$file_path" "${existing_content}${new_section}"
    fi

    # 更新 frontmatter
    update_frontmatter_version "$file_path"

    return $UPDATE_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 3: 替換區段內容
# ═══════════════════════════════════════════════════════════════

# 替換整個區段的內容
# 用法: replace_section file_path section_name content
# 參數:
#   file_path    - MEMORY.md 檔案路徑
#   section_name - 區段名稱
#   content      - 新的內容
# 返回:
#   0 - 成功
#   1 - 失敗
#   2 - 區段不存在
replace_section() {
    local file_path="${1:-}"
    local section_name="${2:-}"
    local content="${3:-}"

    if [ -z "$file_path" ] || [ -z "$section_name" ]; then
        echo "錯誤：replace_section 需要提供檔案路徑和區段名稱" >&2
        return $UPDATE_FAILED
    fi

    if [ ! -f "$file_path" ]; then
        echo "錯誤：檔案不存在: $file_path" >&2
        return $UPDATE_FILE_NOT_FOUND
    fi

    # 找到區段
    local section_range
    if ! section_range=$(find_section "$file_path" "$section_name" 2>/dev/null); then
        echo "錯誤：區段不存在: $section_name" >&2
        return $UPDATE_SECTION_NOT_FOUND
    fi

    local start_line end_line
    start_line=$(echo "$section_range" | cut -d':' -f1)
    end_line=$(echo "$section_range" | cut -d':' -f2)

    # 建立臨時檔案
    local temp_file="${file_path}.tmp.$$"

    # 替換區段內容（保留區段標題）
    awk -v start="$start_line" -v end="$end_line" -v new_content="$content" '
        NR == start {
            print
            print ""
            print new_content
            skip = 1
            next
        }
        NR > end {
            skip = 0
        }
        !skip { print }
    ' "$file_path" > "$temp_file"

    # 使用原子性寫入替換檔案
    if [ -s "$temp_file" ]; then
        cat "$temp_file" | atomic_write -b "$file_path" "$(cat "$temp_file")"
        rm -f "$temp_file"
    else
        rm -f "$temp_file"
        return $UPDATE_FAILED
    fi

    # 更新 frontmatter
    update_frontmatter_version "$file_path"

    return $UPDATE_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 4: 智慧合併內容
# ═══════════════════════════════════════════════════════════════

# 智慧合併新內容與現有內容
# 用法: merge_with_existing file_path section_name new_content
# 參數:
#   file_path    - MEMORY.md 檔案路徑
#   section_name - 區段名稱
#   new_content  - 新的內容
# 說明:
#   檢查重複（使用簡單的字串比對）
#   保留現有內容，追加非重複的新內容
# 返回:
#   0 - 成功
#   1 - 失敗
merge_with_existing() {
    local file_path="${1:-}"
    local section_name="${2:-}"
    local new_content="${3:-}"

    if [ -z "$file_path" ] || [ -z "$section_name" ] || [ -z "$new_content" ]; then
        echo "錯誤：merge_with_existing 需要提供檔案路徑、區段名稱和新內容" >&2
        return $UPDATE_FAILED
    fi

    if [ ! -f "$file_path" ]; then
        # 檔案不存在，直接追加（會建立新檔案）
        append_to_section "$file_path" "$section_name" "$new_content"
        return $?
    fi

    # 找到區段
    local section_range
    if ! section_range=$(find_section "$file_path" "$section_name" 2>/dev/null); then
        # 區段不存在，直接追加（會建立新區段）
        append_to_section "$file_path" "$section_name" "$new_content"
        return $?
    fi

    # 提取現有區段內容
    local start_line end_line
    start_line=$(echo "$section_range" | cut -d':' -f1)
    end_line=$(echo "$section_range" | cut -d':' -f2)

    local existing_content
    existing_content=$(sed -n "$((start_line + 1)),${end_line}p" "$file_path")

    # 簡單的重複檢查：如果新內容已經存在於現有內容中，則跳過
    if echo "$existing_content" | grep -Fq "$new_content"; then
        echo "資訊：內容已存在，跳過合併" >&2
        return $UPDATE_SUCCESS
    fi

    # 追加新內容
    append_to_section "$file_path" "$section_name" "$new_content"
    return $?
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 5: 更新 frontmatter 版本
# ═══════════════════════════════════════════════════════════════

# 更新 MEMORY.md 的 frontmatter
# 用法: update_frontmatter_version file_path
# 說明:
#   更新 updated 時間戳
#   增加 version 計數
# 返回:
#   0 - 成功
#   1 - 失敗
update_frontmatter_version() {
    local file_path="${1:-}"

    if [ -z "$file_path" ]; then
        echo "錯誤：update_frontmatter_version 需要提供檔案路徑" >&2
        return $UPDATE_FAILED
    fi

    if [ ! -f "$file_path" ]; then
        echo "錯誤：檔案不存在: $file_path" >&2
        return $UPDATE_FILE_NOT_FOUND
    fi

    # 檢查是否有 frontmatter
    if ! has_frontmatter "$file_path" 2>/dev/null; then
        echo "警告：檔案無 frontmatter，跳過版本更新" >&2
        return $UPDATE_SUCCESS
    fi

    # 更新 updated 時間戳
    local timestamp
    timestamp=$(get_timestamp)

    if ! update_frontmatter "$file_path" "updated" "$timestamp" 2>/dev/null; then
        echo "警告：無法更新 updated 時間戳" >&2
    fi

    # 更新 version（讀取當前版本，+1）
    local current_version
    if current_version=$(parse_frontmatter "$file_path" "version" 2>/dev/null); then
        local new_version=$((current_version + 1))

        if ! update_frontmatter "$file_path" "version" "$new_version" 2>/dev/null; then
            echo "警告：無法更新版本號" >&2
        fi
    else
        # 如果沒有 version 欄位，設定為 1
        # 注意：update_frontmatter 無法新增欄位，這裡只是記錄警告
        echo "警告：frontmatter 中無 version 欄位" >&2
    fi

    return $UPDATE_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 6: 統一更新介面
# ═══════════════════════════════════════════════════════════════

# 更新 MEMORY.md 的指定區段
# 用法: update_memory section_name content mode [source]
# 參數:
#   section_name - 區段名稱（如「專案偏好」、「技術棧」、「REVIEWER 經驗」）
#   content      - 要更新的內容
#   mode         - 更新模式（append | replace | merge）
#   source       - 可選，來源標記（如「REVIEWER」）
# 說明:
#   自動尋找專案根目錄的 .claude/memory/MEMORY.md
# 返回:
#   0 - 成功
#   1 - 失敗
update_memory() {
    local section_name="${1:-}"
    local content="${2:-}"
    local mode="${3:-$UPDATE_MODE_APPEND}"
    local source="${4:-}"

    if [ -z "$section_name" ] || [ -z "$content" ]; then
        echo "錯誤：update_memory 需要提供區段名稱和內容" >&2
        return $UPDATE_FAILED
    fi

    # 驗證模式
    case "$mode" in
        "$UPDATE_MODE_APPEND"|"$UPDATE_MODE_REPLACE"|"$UPDATE_MODE_MERGE")
            # 合法模式
            ;;
        *)
            echo "錯誤：不支援的更新模式: $mode" >&2
            echo "支援的模式: append, replace, merge" >&2
            return $UPDATE_FAILED
            ;;
    esac

    # 確定 MEMORY.md 檔案路徑
    local memory_file="${PWD}/.claude/memory/MEMORY.md"

    # 確保目錄存在
    if ! ensure_memory_dir; then
        return $UPDATE_FAILED
    fi

    # 根據模式執行對應操作
    case "$mode" in
        "$UPDATE_MODE_APPEND")
            append_to_section "$memory_file" "$section_name" "$content" "$source"
            ;;
        "$UPDATE_MODE_REPLACE")
            replace_section "$memory_file" "$section_name" "$content"
            ;;
        "$UPDATE_MODE_MERGE")
            merge_with_existing "$memory_file" "$section_name" "$content"
            ;;
    esac

    return $?
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_memory_update_help() {
    cat <<'EOF'
MEMORY.md 更新工具

用法:
  source memory-update.sh

主要函式:
  update_memory <section> <content> <mode> [source]
    更新 MEMORY.md 的指定區段
    參數:
      section - 區段名稱（如「專案偏好」）
      content - 要更新的內容
      mode    - 更新模式（append | replace | merge）
      source  - 可選，來源標記（如「REVIEWER」）

輔助函式:
  find_section <file> <section>
    找到區段的起始和結束行號

  append_to_section <file> <section> <content> [source]
    在區段末尾追加內容

  replace_section <file> <section> <content>
    替換整個區段的內容

  merge_with_existing <file> <section> <content>
    智慧合併新內容與現有內容

  update_frontmatter_version <file>
    更新 frontmatter 的時間戳和版本

範例:
  # 追加內容
  update_memory "專案偏好" "使用 TypeScript" "append" "DEVELOPER"

  # 替換區段
  update_memory "技術棧" "Frontend: React\nBackend: Node.js" "replace"

  # 智慧合併
  update_memory "REVIEWER 經驗" "注意錯誤處理" "merge" "REVIEWER"

返回碼:
  0 - 成功
  1 - 失敗
  2 - 區段不存在
  3 - 檔案不存在
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        help|--help|-h|"")
            show_memory_update_help
            exit 0
            ;;
        find)
            shift
            find_section "$@"
            exit $?
            ;;
        append)
            shift
            append_to_section "$@"
            exit $?
            ;;
        replace)
            shift
            replace_section "$@"
            exit $?
            ;;
        merge)
            shift
            merge_with_existing "$@"
            exit $?
            ;;
        update-version)
            shift
            update_frontmatter_version "$@"
            exit $?
            ;;
        update)
            shift
            update_memory "$@"
            exit $?
            ;;
        *)
            echo "錯誤：未知命令: $1" >&2
            show_memory_update_help
            exit 1
            ;;
    esac
fi
