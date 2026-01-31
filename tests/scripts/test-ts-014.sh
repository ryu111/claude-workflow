#!/bin/bash
# test-ts-014.sh - Agent Skills 引用一致性驗證
# 驗證: 所有 Agent 引用的 skills 都存在，且沒有孤立 skill

echo "=== TS-014: Agent Skills 引用一致性驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AGENTS_DIR="$PROJECT_ROOT/agents"
SKILLS_DIR="$PROJECT_ROOT/skills"

# 驗證結果
PASS=true
REFERENCED_SKILLS=""  # 用字串存儲引用的 skills（空格分隔）

# 1. 收集所有 Agent 引用的 skills 並驗證存在
echo "1. 驗證 Agent 引用的 skills..."
for agent_file in "$AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    agent_name=$(basename "$agent_file" .md)

    # 提取 skills 欄位（YAML frontmatter 中）
    skills_line=$(grep "^skills:" "$agent_file" 2>/dev/null | head -1)
    if [ -z "$skills_line" ]; then
        echo "   ⚠️  $agent_name: 沒有定義 skills"
        continue
    fi

    # 解析 skills（逗號分隔）
    skills_value=$(echo "$skills_line" | sed 's/^skills: *//')
    IFS=',' read -ra skill_arr <<< "$skills_value"

    agent_valid=true
    skill_count=0
    for skill in "${skill_arr[@]}"; do
        skill=$(echo "$skill" | xargs)  # 移除空白
        [ -z "$skill" ] && continue

        skill_count=$((skill_count + 1))

        # 記錄引用的 skill（避免重複）
        if ! echo "$REFERENCED_SKILLS" | grep -qw "$skill"; then
            REFERENCED_SKILLS="$REFERENCED_SKILLS $skill"
        fi

        # 檢查 skill 目錄是否存在
        skill_dir="$SKILLS_DIR/$skill"
        if [ ! -d "$skill_dir" ]; then
            echo "   ❌ $agent_name 引用不存在的 skill: $skill"
            PASS=false
            agent_valid=false
        elif [ ! -f "$skill_dir/SKILL.md" ]; then
            echo "   ❌ $agent_name 引用的 skill '$skill' 缺少 SKILL.md"
            PASS=false
            agent_valid=false
        fi
    done

    if [ "$agent_valid" = true ]; then
        echo "   ✅ $agent_name: 所有引用有效 ($skill_count skills)"
    fi
done

# 2. 檢查孤立 skills（存在但未被任何 Agent 引用）
echo ""
echo "2. 檢查孤立 skills..."
orphan_count=0
for skill_dir in "$SKILLS_DIR"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")

    if ! echo "$REFERENCED_SKILLS" | grep -qw "$skill_name"; then
        echo "   ⚠️  孤立 skill: $skill_name（未被任何 Agent 引用）"
        orphan_count=$((orphan_count + 1))
    fi
done

if [ "$orphan_count" -eq 0 ]; then
    echo "   ✅ 沒有孤立 skills"
else
    echo "   共 $orphan_count 個孤立 skills（警告，不影響測試結果）"
fi

# 3. 統計
echo ""
echo "3. 統計摘要..."
total_agents=$(ls -1 "$AGENTS_DIR"/*.md 2>/dev/null | wc -l | xargs)
total_skills=$(ls -1d "$SKILLS_DIR"/*/ 2>/dev/null | wc -l | xargs)
referenced_count=$(echo "$REFERENCED_SKILLS" | wc -w | xargs)

echo "   Agents 總數: $total_agents"
echo "   Skills 總數: $total_skills"
echo "   被引用 Skills: $referenced_count"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-014 PASS: Agent Skills 引用一致性驗證通過"
    exit 0
else
    echo "❌ TS-014 FAIL"
    exit 1
fi
