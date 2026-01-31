#!/bin/bash
# test-ts-029.sh - code-review Skill 驗證
# 驗證: code-review skill 結構、frontmatter 和引用正確

echo "=== TS-029: code-review Skill 驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_DIR="$PROJECT_ROOT/skills/code-review"
SKILL_MD="$SKILL_DIR/SKILL.md"
AGENTS_DIR="$PROJECT_ROOT/agents"

# 驗證結果
PASS=true

# 1. 檢查 SKILL.md 存在
echo "1. 檢查 SKILL.md 存在..."
if [ -f "$SKILL_MD" ]; then
    echo "   ✅ skills/code-review/SKILL.md 存在"
else
    echo "   ❌ skills/code-review/SKILL.md 不存在"
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

# 3. 檢查 references/ 目錄
echo ""
echo "3. 檢查參考文件..."
REF_FILE="$SKILL_DIR/references/security-checklist.md"
if [ -f "$REF_FILE" ]; then
    echo "   ✅ references/security-checklist.md 存在"
else
    echo "   ❌ references/security-checklist.md 不存在"
    PASS=false
fi

# 4. 檢查 Agent 引用
echo ""
echo "4. 檢查 Agent 引用..."
AGENTS_USING=0
for agent_file in "$AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    agent_name=$(basename "$agent_file" .md)
    if grep -q "skills/code-review" "$agent_file" 2>/dev/null; then
        echo "   ✅ $agent_name 引用此 skill"
        AGENTS_USING=$((AGENTS_USING + 1))
    fi
done

if [ "$AGENTS_USING" -eq 0 ]; then
    echo "   ⚠️  沒有 Agent 明確引用 code-review skill（可能通過其他方式自動載入）"
else
    echo "   共 $AGENTS_USING 個 Agent 引用"
fi

# 5. 檢查審查相關內容
echo ""
echo "5. 檢查審查相關內容..."
if [ -f "$SKILL_MD" ]; then
    has_priority=$(grep -c "審查優先順序" "$SKILL_MD" 2>/dev/null || echo 0)
    has_checklist=$(grep -c "審查清單" "$SKILL_MD" 2>/dev/null || echo 0)
    has_severity=$(grep -c "嚴重程度" "$SKILL_MD" 2>/dev/null || echo 0)
    has_decision=$(grep -c "決策矩陣\|APPROVE\|REJECT" "$SKILL_MD" 2>/dev/null || echo 0)

    [ "$has_priority" -gt 0 ] && echo "   ✅ 包含審查優先順序內容" || { echo "   ❌ 缺少審查優先順序內容"; PASS=false; }
    [ "$has_checklist" -gt 0 ] && echo "   ✅ 包含審查清單內容" || { echo "   ❌ 缺少審查清單內容"; PASS=false; }
    [ "$has_severity" -gt 0 ] && echo "   ✅ 包含嚴重程度內容" || { echo "   ❌ 缺少嚴重程度內容"; PASS=false; }
    [ "$has_decision" -gt 0 ] && echo "   ✅ 包含決策矩陣內容" || { echo "   ❌ 缺少決策矩陣內容"; PASS=false; }
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-029 PASS: code-review skill 驗證通過"
    exit 0
else
    echo "❌ TS-029 FAIL"
    exit 1
fi
