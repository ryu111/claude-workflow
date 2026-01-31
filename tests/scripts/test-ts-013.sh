#!/bin/bash
# test-ts-013.sh - browser-automation Skill 驗證
# 驗證: browser-automation skill 結構、frontmatter 和引用正確

echo "=== TS-013: browser-automation Skill 驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_DIR="$PROJECT_ROOT/skills/browser-automation"
SKILL_MD="$SKILL_DIR/SKILL.md"
AGENTS_DIR="$PROJECT_ROOT/agents"

# 驗證結果
PASS=true

# 1. 檢查 SKILL.md 存在
echo "1. 檢查 SKILL.md 存在..."
if [ -f "$SKILL_MD" ]; then
    echo "   ✅ skills/browser-automation/SKILL.md 存在"
else
    echo "   ❌ skills/browser-automation/SKILL.md 不存在"
    PASS=false
fi

# 2. 檢查 YAML frontmatter 必要欄位
echo ""
echo "2. 檢查 YAML frontmatter..."
if [ -f "$SKILL_MD" ]; then
    # 檢查是否以 --- 開頭
    if head -1 "$SKILL_MD" | grep -q "^---$"; then
        # 檢查必要欄位
        has_name=$(grep -c "^name:" "$SKILL_MD" 2>/dev/null || echo 0)
        has_desc=$(grep -c "^description:" "$SKILL_MD" 2>/dev/null || echo 0)
        has_user_inv=$(grep -c "^user-invocable:" "$SKILL_MD" 2>/dev/null || echo 0)
        has_model_inv=$(grep -c "^disable-model-invocation:" "$SKILL_MD" 2>/dev/null || echo 0)

        [ "$has_name" -gt 0 ] && echo "   ✅ name 欄位存在" || { echo "   ❌ 缺少 name 欄位"; PASS=false; }
        [ "$has_desc" -gt 0 ] && echo "   ✅ description 欄位存在" || { echo "   ❌ 缺少 description 欄位"; PASS=false; }
        [ "$has_user_inv" -gt 0 ] && echo "   ✅ user-invocable 欄位存在" || { echo "   ❌ 缺少 user-invocable 欄位"; PASS=false; }
        [ "$has_model_inv" -gt 0 ] && echo "   ✅ disable-model-invocation 欄位存在" || { echo "   ❌ 缺少 disable-model-invocation 欄位"; PASS=false; }
    else
        echo "   ❌ YAML frontmatter 格式錯誤（缺少 ---）"
        PASS=false
    fi
fi

# 3. 檢查 references/testing-patterns.md 存在
echo ""
echo "3. 檢查參考文件..."
REF_FILE="$SKILL_DIR/references/testing-patterns.md"
if [ -f "$REF_FILE" ]; then
    echo "   ✅ references/testing-patterns.md 存在"
else
    echo "   ❌ references/testing-patterns.md 不存在"
    PASS=false
fi

# 4. 檢查 Agent 引用
echo ""
echo "4. 檢查 Agent 引用..."
AGENTS_USING=0
for agent_file in "$AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    agent_name=$(basename "$agent_file" .md)
    if grep -q "browser-automation" "$agent_file" 2>/dev/null; then
        echo "   ✅ $agent_name 引用此 skill"
        AGENTS_USING=$((AGENTS_USING + 1))
    fi
done

if [ "$AGENTS_USING" -eq 0 ]; then
    echo "   ❌ 沒有 Agent 引用 browser-automation skill"
    PASS=false
else
    echo "   共 $AGENTS_USING 個 Agent 引用"
fi

# 5. 檢查工具對照內容
echo ""
echo "5. 檢查工具對照內容..."
if [ -f "$SKILL_MD" ]; then
    has_chrome=$(grep -c "claude-in-chrome" "$SKILL_MD" 2>/dev/null || echo 0)
    has_agent=$(grep -c "agent-browser" "$SKILL_MD" 2>/dev/null || echo 0)
    has_table=$(grep -c "|.*claude-in-chrome.*|.*agent-browser.*|" "$SKILL_MD" 2>/dev/null || echo 0)

    [ "$has_chrome" -gt 0 ] && echo "   ✅ 包含 claude-in-chrome 內容" || { echo "   ❌ 缺少 claude-in-chrome 內容"; PASS=false; }
    [ "$has_agent" -gt 0 ] && echo "   ✅ 包含 agent-browser 內容" || { echo "   ❌ 缺少 agent-browser 內容"; PASS=false; }
    [ "$has_table" -gt 0 ] && echo "   ✅ 包含工具對照表" || echo "   ⚠️  未發現格式化對照表（可能使用其他格式）"
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-013 PASS: browser-automation skill 驗證通過"
    exit 0
else
    echo "❌ TS-013 FAIL"
    exit 1
fi
