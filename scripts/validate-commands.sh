#!/bin/bash
# validate-commands.sh - 驗證 plugin 中所有 commands 的結構、frontmatter 和引用
# 用法: ./validate-commands.sh [commands-path]

set -e

# 載入共用函式庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/validate-utils.sh"

# 計算路徑
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
COMMANDS_PATH="${1:-$PLUGIN_DIR/commands}"

# 計數器
TOTAL_COMMANDS=0
PASSED_COMMANDS=0
FAILED_COMMANDS=0
TOTAL_REFS=0
VALID_REFS=0
MISSING_REFS=0

# 暫存結果
STRUCTURE_RESULTS=""
REFERENCE_RESULTS=""
MISSING_FILES=""
NAMING_ISSUES=""

print_header "📜 Commands 驗證報告"
log_info "驗證路徑: $COMMANDS_PATH"

# 檢查 commands 目錄是否存在
if ! check_dir_exists "$COMMANDS_PATH"; then
    log_fail "Commands 目錄不存在: $COMMANDS_PATH"
    exit 1
fi

# 遍歷所有 command 檔案
for command_file in "$COMMANDS_PATH"/*.md; do
    [ -f "$command_file" ] || continue

    command_filename=$(basename "$command_file" .md)
    TOTAL_COMMANDS=$((TOTAL_COMMANDS + 1))

    has_frontmatter="❌"
    has_name="❌"
    has_description="❌"
    naming_consistent="❌"
    command_status="❌"
    name_in_frontmatter=""

    # 1. 檢查 frontmatter 存在
    if check_frontmatter "$command_file"; then
        has_frontmatter="✅"

        # 提取 frontmatter 區塊
        frontmatter=$(extract_frontmatter "$command_file")

        # 2. 檢查必要欄位: name
        if echo "$frontmatter" | grep -q "^name:"; then
            has_name="✅"
            name_in_frontmatter=$(echo "$frontmatter" | grep "^name:" | sed 's/^name:[[:space:]]*//' | sed 's/[[:space:]]*$//')
        fi

        # 3. 檢查必要欄位: description
        if echo "$frontmatter" | grep -q "^description:"; then
            has_description="✅"
        fi

        # 4. 檢查命名一致性（檔名 vs frontmatter name）
        if [ -n "$name_in_frontmatter" ]; then
            if [ "$command_filename" = "$name_in_frontmatter" ]; then
                naming_consistent="✅"
            else
                naming_consistent="⚠️"
                NAMING_ISSUES="$NAMING_ISSUES\n  - $command_filename.md: 檔名與 name 欄位不一致 (name: $name_in_frontmatter)"
            fi
        fi

        # 5. 檢查選用欄位（僅記錄，不影響 pass/fail）
        has_argument_hint="❌"
        has_user_invocable="❌"
        has_allowed_tools="❌"

        if echo "$frontmatter" | grep -q "^argument-hint:"; then
            has_argument_hint="✅"
        fi

        if echo "$frontmatter" | grep -q "^user-invocable:"; then
            has_user_invocable="✅"
        fi

        if echo "$frontmatter" | grep -q "^allowed-tools:"; then
            has_allowed_tools="✅"
        fi

        # 判斷整體狀態（必要欄位 + 命名一致性）
        if [ "$has_name" = "✅" ] && [ "$has_description" = "✅" ] && [ "$naming_consistent" = "✅" ]; then
            command_status="✅"
            PASSED_COMMANDS=$((PASSED_COMMANDS + 1))
        else
            FAILED_COMMANDS=$((FAILED_COMMANDS + 1))
        fi

    else
        FAILED_COMMANDS=$((FAILED_COMMANDS + 1))
    fi

    STRUCTURE_RESULTS="$STRUCTURE_RESULTS| $command_filename | $has_frontmatter | $has_name | $has_description | $naming_consistent | $command_status |\n"

    # 6. 檢查引用 (只在檔案有效時)
    if check_file_exists "$command_file"; then
        # 提取所有 markdown 連結引用
        refs=$(extract_markdown_links "$command_file")

        ref_count=0
        valid_count=0
        missing_list=""

        for ref in $refs; do
            # 跳過外部連結
            is_external_link "$ref" && continue

            ref_count=$((ref_count + 1))
            TOTAL_REFS=$((TOTAL_REFS + 1))

            # 檢查檔案是否存在 (相對於 commands 目錄)
            ref_path="$COMMANDS_PATH/$ref"
            if check_file_exists "$ref_path"; then
                valid_count=$((valid_count + 1))
                VALID_REFS=$((VALID_REFS + 1))
            else
                MISSING_REFS=$((MISSING_REFS + 1))
                missing_list="$missing_list\n  - $ref"
            fi
        done

        missing_count=$((ref_count - valid_count))
        REFERENCE_RESULTS="$REFERENCE_RESULTS| $command_filename | $ref_count | $valid_count | $missing_count |\n"

        if [ -n "$missing_list" ]; then
            MISSING_FILES="$MISSING_FILES\n**$command_filename:**$missing_list"
        fi
    fi
done

# 輸出報告
print_section "結構驗證"
echo "| Command | Frontmatter | name | description | 命名一致 | 狀態 |"
echo "|---------|:-----------:|:----:|:-----------:|:--------:|:----:|"
echo -e "$STRUCTURE_RESULTS"

if [ -n "$NAMING_ISSUES" ]; then
    print_section "命名不一致問題"
    echo -e "$NAMING_ISSUES"
fi

print_section "引用驗證"
echo "| Command | 引用數 | 有效 | 缺失 |"
echo "|---------|:------:|:----:|:----:|"
echo -e "$REFERENCE_RESULTS"

if [ -n "$MISSING_FILES" ]; then
    print_section "缺失檔案"
    echo -e "$MISSING_FILES"
fi

print_summary "$TOTAL_COMMANDS" "$PASSED_COMMANDS" "$FAILED_COMMANDS" "Commands"
echo "- 引用總數：$TOTAL_REFS"
echo "- 有效引用：$VALID_REFS"
echo "- 缺失引用：$MISSING_REFS"

# 設定退出碼
print_final_status "$((FAILED_COMMANDS + MISSING_REFS))"
exit $?
