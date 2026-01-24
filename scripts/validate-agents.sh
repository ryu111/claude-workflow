#!/bin/bash
# validate-agents.sh - 驗證 plugin 中所有 agents 的結構、frontmatter 和引用
# 用法: ./validate-agents.sh [agents-path]

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 取得腳本所在目錄，計算 agents 路徑
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
AGENTS_PATH="${1:-$PLUGIN_DIR/agents}"
SKILLS_PATH="$PLUGIN_DIR/skills"

# 計數器
TOTAL_AGENTS=0
PASSED_AGENTS=0
FAILED_AGENTS=0
TOTAL_SKILLS_REFS=0
VALID_SKILLS_REFS=0
MISSING_SKILLS_REFS=0

# 暫存結果
STRUCTURE_RESULTS=""
SKILLS_RESULTS=""
TOOLS_RESULTS=""
MISSING_SKILLS=""

echo "🤖 Agents 驗證報告"
echo "===================="
echo ""
echo "驗證路徑: $AGENTS_PATH"
echo ""

# 檢查 agents 目錄是否存在
if [ ! -d "$AGENTS_PATH" ]; then
    echo -e "${RED}錯誤: Agents 目錄不存在: $AGENTS_PATH${NC}"
    exit 1
fi

# 取得所有可用的 skills
AVAILABLE_SKILLS=""
if [ -d "$SKILLS_PATH" ]; then
    for skill_dir in "$SKILLS_PATH"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name=$(basename "$skill_dir")
        AVAILABLE_SKILLS="$AVAILABLE_SKILLS $skill_name"
    done
fi

# 遍歷所有 agent 檔案
for agent_file in "$AGENTS_PATH"/*.md; do
    [ -f "$agent_file" ] || continue

    agent_name=$(basename "$agent_file" .md)
    TOTAL_AGENTS=$((TOTAL_AGENTS + 1))

    has_frontmatter="❌"
    has_name="❌"
    has_description="❌"
    agent_status="❌"

    # 1. 檢查 frontmatter 存在
    if head -1 "$agent_file" | grep -q "^---$"; then
        has_frontmatter="✅"

        # 提取 frontmatter 區塊 (從第一個 --- 到第二個 ---)
        # macOS 相容：使用 awk 替代 head -n -1
        frontmatter=$(awk '/^---$/{if(++c==2)exit}c==1' "$agent_file")

        # 2. 檢查必要欄位
        if echo "$frontmatter" | grep -q "^name:"; then
            has_name="✅"
        fi

        if echo "$frontmatter" | grep -q "^description:"; then
            has_description="✅"
        fi

        # 判斷整體狀態
        if [ "$has_name" = "✅" ] && [ "$has_description" = "✅" ]; then
            agent_status="✅"
            PASSED_AGENTS=$((PASSED_AGENTS + 1))
        else
            FAILED_AGENTS=$((FAILED_AGENTS + 1))
        fi

        # 3. 檢查 skills 引用
        skills_line=$(echo "$frontmatter" | grep "^skills:" || true)
        if [ -n "$skills_line" ]; then
            # 提取 skills 清單 (格式: skills: skill1, skill2, skill3)
            # macOS 相容：使用 [[:space:]] 替代 \s
            skills_list=$(echo "$skills_line" | sed 's/^skills:[[:space:]]*//' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

            skill_count=0
            valid_skill_count=0
            missing_list=""

            for skill in $skills_list; do
                [ -z "$skill" ] && continue
                skill_count=$((skill_count + 1))
                TOTAL_SKILLS_REFS=$((TOTAL_SKILLS_REFS + 1))

                # 檢查 skill 是否存在
                if [ -d "$SKILLS_PATH/$skill" ]; then
                    valid_skill_count=$((valid_skill_count + 1))
                    VALID_SKILLS_REFS=$((VALID_SKILLS_REFS + 1))
                else
                    MISSING_SKILLS_REFS=$((MISSING_SKILLS_REFS + 1))
                    missing_list="$missing_list\n  - $skill"
                fi
            done

            missing_count=$((skill_count - valid_skill_count))
            SKILLS_RESULTS="$SKILLS_RESULTS| $agent_name | $skill_count | $valid_skill_count | $missing_count |\n"

            if [ -n "$missing_list" ]; then
                MISSING_SKILLS="$MISSING_SKILLS\n**$agent_name:**$missing_list"
            fi
        else
            SKILLS_RESULTS="$SKILLS_RESULTS| $agent_name | 0 | 0 | 0 |\n"
        fi

        # 4. 檢查 tools 配置
        tools_line=$(echo "$frontmatter" | grep -A 20 "^tools:" | grep -E "^\s+-" | head -10 || true)
        disallowed_line=$(echo "$frontmatter" | grep -A 20 "^disallowedTools:" | grep -E "^\s+-" | head -10 || true)

        tools_count=$(echo "$tools_line" | grep -c "^\s*-" 2>/dev/null || echo 0)
        disallowed_count=$(echo "$disallowed_line" | grep -c "^\s*-" 2>/dev/null || echo 0)

        TOOLS_RESULTS="$TOOLS_RESULTS| $agent_name | $tools_count | $disallowed_count |\n"

    else
        FAILED_AGENTS=$((FAILED_AGENTS + 1))
        SKILLS_RESULTS="$SKILLS_RESULTS| $agent_name | - | - | - |\n"
        TOOLS_RESULTS="$TOOLS_RESULTS| $agent_name | - | - |\n"
    fi

    STRUCTURE_RESULTS="$STRUCTURE_RESULTS| $agent_name | $has_frontmatter | $has_name | $has_description | $agent_status |\n"
done

# 輸出報告
echo "### 結構驗證"
echo "| Agent | Frontmatter | name | description | 狀態 |"
echo "|-------|:-----------:|:----:|:-----------:|:----:|"
echo -e "$STRUCTURE_RESULTS"

echo ""
echo "### Skills 引用驗證"
echo "| Agent | 引用數 | 有效 | 缺失 |"
echo "|-------|:------:|:----:|:----:|"
echo -e "$SKILLS_RESULTS"

if [ -n "$MISSING_SKILLS" ]; then
    echo ""
    echo "### 缺失的 Skills"
    echo -e "$MISSING_SKILLS"
fi

echo ""
echo "### Tools 配置"
echo "| Agent | 允許工具 | 禁止工具 |"
echo "|-------|:--------:|:--------:|"
echo -e "$TOOLS_RESULTS"

echo ""
echo "### 總結"
echo "- Agents 總數：$TOTAL_AGENTS"
echo "- 結構驗證通過：$PASSED_AGENTS"
echo "- 結構驗證失敗：$FAILED_AGENTS"
echo "- Skills 引用總數：$TOTAL_SKILLS_REFS"
echo "- 有效引用：$VALID_SKILLS_REFS"
echo "- 缺失引用：$MISSING_SKILLS_REFS"

# 設定退出碼
if [ "$FAILED_AGENTS" -gt 0 ] || [ "$MISSING_SKILLS_REFS" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠️ 發現問題，請檢查上方詳情${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ 所有驗證通過${NC}"
    exit 0
fi
