#!/bin/bash
# test-ts-028.sh - development Skill 驗證
# 驗證: development skill 結構、frontmatter 和引用正確

echo "=== TS-028: development Skill 驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_DIR="$PROJECT_ROOT/skills/development"
SKILL_MD="$SKILL_DIR/SKILL.md"
AGENTS_DIR="$PROJECT_ROOT/agents"

# 驗證結果
PASS=true

# 1. 檢查 SKILL.md 存在
echo "1. 檢查 SKILL.md 存在..."
if [ -f "$SKILL_MD" ]; then
    echo "   ✅ skills/development/SKILL.md 存在"
else
    echo "   ❌ skills/development/SKILL.md 不存在"
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
REF_FILE="$SKILL_DIR/references/naming-conventions.md"
if [ -f "$REF_FILE" ]; then
    echo "   ✅ references/naming-conventions.md 存在"
else
    echo "   ❌ references/naming-conventions.md 不存在"
    PASS=false
fi

# 4. 檢查 Agent 引用
echo ""
echo "4. 檢查 Agent 引用..."
AGENTS_USING=0
for agent_file in "$AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    agent_name=$(basename "$agent_file" .md)
    if grep -q "skills/development" "$agent_file" 2>/dev/null; then
        echo "   ✅ $agent_name 引用此 skill"
        AGENTS_USING=$((AGENTS_USING + 1))
    fi
done

if [ "$AGENTS_USING" -eq 0 ]; then
    echo "   ⚠️  沒有 Agent 明確引用 development skill（可能通過其他方式自動載入）"
else
    echo "   共 $AGENTS_USING 個 Agent 引用"
fi

# 5. 檢查開發相關內容
echo ""
echo "5. 檢查開發相關內容..."
if [ -f "$SKILL_MD" ]; then
    has_naming=$(grep -c "命名規則" "$SKILL_MD" 2>/dev/null || echo 0)
    has_function=$(grep -c "函式設計" "$SKILL_MD" 2>/dev/null || echo 0)
    has_refactor=$(grep -c "重構" "$SKILL_MD" 2>/dev/null || echo 0)
    has_best=$(grep -c "最佳實踐" "$SKILL_MD" 2>/dev/null || echo 0)

    [ "$has_naming" -gt 0 ] && echo "   ✅ 包含命名規則內容" || { echo "   ❌ 缺少命名規則內容"; PASS=false; }
    [ "$has_function" -gt 0 ] && echo "   ✅ 包含函式設計內容" || { echo "   ❌ 缺少函式設計內容"; PASS=false; }
    [ "$has_refactor" -gt 0 ] && echo "   ✅ 包含重構內容" || { echo "   ❌ 缺少重構內容"; PASS=false; }
    [ "$has_best" -gt 0 ] && echo "   ✅ 包含最佳實踐內容" || { echo "   ❌ 缺少最佳實踐內容"; PASS=false; }
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-028 PASS: development skill 驗證通過"
    exit 0
else
    echo "❌ TS-028 FAIL"
    exit 1
fi
