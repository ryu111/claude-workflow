#!/bin/bash
# validate-skills.sh - 驗證 plugin 中所有 skills 的結構、格式和引用
# 用法: ./validate-skills.sh [skills-path]

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 取得腳本所在目錄，計算 skills 路徑
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

echo "🔍 Skills 驗證報告"
echo "===================="
echo ""
echo "驗證路徑: $SKILLS_PATH"
echo ""

# 檢查 skills 目錄是否存在
if [ ! -d "$SKILLS_PATH" ]; then
    echo -e "${RED}錯誤: Skills 目錄不存在: $SKILLS_PATH${NC}"
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
    if [ -f "$skill_md" ]; then
        has_skill_md="✅"

        # 2. 檢查 YAML frontmatter
        if head -1 "$skill_md" | grep -q "^---$"; then
            # 檢查必要欄位
            has_name=$(grep -c "^name:" "$skill_md" 2>/dev/null || echo 0)
            has_desc=$(grep -c "^description:" "$skill_md" 2>/dev/null || echo 0)
            has_user_inv=$(grep -c "^user-invocable:" "$skill_md" 2>/dev/null || echo 0)
            has_model_inv=$(grep -c "^disable-model-invocation:" "$skill_md" 2>/dev/null || echo 0)

            if [ "$has_name" -gt 0 ] && [ "$has_desc" -gt 0 ] && [ "$has_user_inv" -gt 0 ] && [ "$has_model_inv" -gt 0 ]; then
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
    if [ -f "$skill_md" ]; then
        # 提取所有 markdown 連結引用
        refs=$(grep -oE '\]\([a-zA-Z0-9_/.~-]+\)' "$skill_md" 2>/dev/null | sed 's/](\(.*\))/\1/' || true)

        ref_count=0
        valid_count=0
        missing_list=""

        for ref in $refs; do
            # 跳過外部連結
            [[ "$ref" == http* ]] && continue
            [[ "$ref" == "#"* ]] && continue

            ref_count=$((ref_count + 1))
            TOTAL_REFS=$((TOTAL_REFS + 1))

            # 檢查檔案是否存在 (相對於 skill 目錄)
            if [ -f "$skill_dir/$ref" ]; then
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
    if [ -x "$script" ]; then
        SCRIPT_RESULTS="$SCRIPT_RESULTS| $rel_path | ✅ |\n"
    else
        SCRIPT_RESULTS="$SCRIPT_RESULTS| $rel_path | ❌ |\n"
    fi
done

# 輸出報告
echo "### 結構驗證"
echo "| Skill | SKILL.md | Frontmatter | 狀態 |"
echo "|-------|:--------:|:-----------:|:----:|"
echo -e "$STRUCTURE_RESULTS"

echo ""
echo "### 引用驗證"
echo "| Skill | 引用數 | 有效 | 缺失 |"
echo "|-------|:------:|:----:|:----:|"
echo -e "$REFERENCE_RESULTS"

if [ -n "$MISSING_FILES" ]; then
    echo ""
    echo "### 缺失檔案"
    echo -e "$MISSING_FILES"
fi

if [ -n "$SCRIPT_RESULTS" ]; then
    echo ""
    echo "### 腳本權限"
    echo "| 腳本 | 權限 |"
    echo "|------|:----:|"
    echo -e "$SCRIPT_RESULTS"
fi

echo ""
echo "### 總結"
echo "- Skills 總數：$TOTAL_SKILLS"
echo "- 結構驗證通過：$PASSED_SKILLS"
echo "- 結構驗證失敗：$FAILED_SKILLS"
echo "- 引用總數：$TOTAL_REFS"
echo "- 有效引用：$VALID_REFS"
echo "- 缺失引用：$MISSING_REFS"

# 設定退出碼
if [ "$FAILED_SKILLS" -gt 0 ] || [ "$MISSING_REFS" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠️ 發現問題，請檢查上方詳情${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ 所有驗證通過${NC}"
    exit 0
fi
