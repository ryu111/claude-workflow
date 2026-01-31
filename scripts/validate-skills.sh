#!/bin/bash
# validate-skills.sh - 驗證 plugin 中所有 skills 的結構、格式和引用
# 用法: ./validate-skills.sh [skills-path]

set -e

# 載入共用函式庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/validate-utils.sh"

# 計算路徑
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_PATH="${1:-$PLUGIN_DIR/skills}"

# 計數器
TOTAL_SKILLS=0
PASSED_SKILLS=0
FAILED_SKILLS=0
TOTAL_REFS=0
VALID_REFS=0
MISSING_REFS=0

# 暫存檔案用於收集結果
STRUCTURE_RESULTS=""
REFERENCE_RESULTS=""
SCRIPT_RESULTS=""
MISSING_FILES=""

print_header "🔍 Skills 驗證報告"
log_info "驗證路徑: $SKILLS_PATH"

# 檢查 skills 目錄是否存在
if ! check_dir_exists "$SKILLS_PATH"; then
    log_fail "Skills 目錄不存在: $SKILLS_PATH"
    exit 1
fi

# 遍歷所有 skill 目錄
for skill_dir in "$SKILLS_PATH"/*/; do
    [ -d "$skill_dir" ] || continue

    skill_name=$(basename "$skill_dir")
    TOTAL_SKILLS=$((TOTAL_SKILLS + 1))

    skill_md="$skill_dir/SKILL.md"
    has_skill_md="❌"
    has_frontmatter="❌"
    skill_status="❌"

    # 1. 檢查 SKILL.md 是否存在
    if check_file_exists "$skill_md"; then
        has_skill_md="✅"

        # 2. 檢查 YAML frontmatter
        if check_frontmatter "$skill_md"; then
            # 檢查必要欄位
            has_name=0
            has_desc=0
            has_user_inv=0
            has_model_inv=0

            check_frontmatter_field "$skill_md" "name" && has_name=1
            check_frontmatter_field "$skill_md" "description" && has_desc=1
            check_frontmatter_field "$skill_md" "user-invocable" && has_user_inv=1
            check_frontmatter_field "$skill_md" "disable-model-invocation" && has_model_inv=1

            if [ "$has_name" -eq 1 ] && [ "$has_desc" -eq 1 ] && [ "$has_user_inv" -eq 1 ] && [ "$has_model_inv" -eq 1 ]; then
                has_frontmatter="✅"
                skill_status="✅"
                PASSED_SKILLS=$((PASSED_SKILLS + 1))
            else
                has_frontmatter="⚠️"
                FAILED_SKILLS=$((FAILED_SKILLS + 1))
            fi
        else
            FAILED_SKILLS=$((FAILED_SKILLS + 1))
        fi
    else
        FAILED_SKILLS=$((FAILED_SKILLS + 1))
    fi

    STRUCTURE_RESULTS="$STRUCTURE_RESULTS| $skill_name | $has_skill_md | $has_frontmatter | $skill_status |\n"

    # 3. 檢查引用 (只在 SKILL.md 存在時)
    if check_file_exists "$skill_md"; then
        # 提取所有 markdown 連結引用
        refs=$(extract_markdown_links "$skill_md")

        ref_count=0
        valid_count=0
        missing_list=""

        for ref in $refs; do
            # 跳過外部連結
            is_external_link "$ref" && continue

            ref_count=$((ref_count + 1))
            TOTAL_REFS=$((TOTAL_REFS + 1))

            # 檢查檔案是否存在 (相對於 skill 目錄)
            if check_file_exists "$skill_dir/$ref"; then
                valid_count=$((valid_count + 1))
                VALID_REFS=$((VALID_REFS + 1))
            else
                MISSING_REFS=$((MISSING_REFS + 1))
                missing_list="$missing_list\n  - $ref"
            fi
        done

        missing_count=$((ref_count - valid_count))
        REFERENCE_RESULTS="$REFERENCE_RESULTS| $skill_name | $ref_count | $valid_count | $missing_count |\n"

        if [ -n "$missing_list" ]; then
            MISSING_FILES="$MISSING_FILES\n**$skill_name:**$missing_list"
        fi
    fi
done

# 4. 檢查腳本權限
script_files=$(find "$SKILLS_PATH" -name "*.sh" 2>/dev/null || true)
for script in $script_files; do
    rel_path="${script#$SKILLS_PATH/}"
    if check_file_executable "$script"; then
        SCRIPT_RESULTS="$SCRIPT_RESULTS| $rel_path | ✅ |\n"
    else
        SCRIPT_RESULTS="$SCRIPT_RESULTS| $rel_path | ❌ |\n"
    fi
done

# 輸出報告
print_section "結構驗證"
echo "| Skill | SKILL.md | Frontmatter | 狀態 |"
echo "|-------|:--------:|:-----------:|:----:|"
echo -e "$STRUCTURE_RESULTS"

print_section "引用驗證"
echo "| Skill | 引用數 | 有效 | 缺失 |"
echo "|-------|:------:|:----:|:----:|"
echo -e "$REFERENCE_RESULTS"

if [ -n "$MISSING_FILES" ]; then
    print_section "缺失檔案"
    echo -e "$MISSING_FILES"
fi

if [ -n "$SCRIPT_RESULTS" ]; then
    print_section "腳本權限"
    echo "| 腳本 | 權限 |"
    echo "|------|:----:|"
    echo -e "$SCRIPT_RESULTS"
fi

print_summary "$TOTAL_SKILLS" "$PASSED_SKILLS" "$FAILED_SKILLS" "Skills"
echo "- 引用總數：$TOTAL_REFS"
echo "- 有效引用：$VALID_REFS"
echo "- 缺失引用：$MISSING_REFS"

# 設定退出碼
print_final_status "$((FAILED_SKILLS + MISSING_REFS))"
exit $?
