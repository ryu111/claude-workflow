#!/bin/bash
# test-ts-030.sh - test Skill 驗證
# 驗證: test skill 結構、frontmatter 和引用正確

echo "=== TS-030: test Skill 驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_DIR="$PROJECT_ROOT/skills/test"
SKILL_MD="$SKILL_DIR/SKILL.md"
AGENTS_DIR="$PROJECT_ROOT/agents"

# 驗證結果
PASS=true

# 1. 檢查 SKILL.md 存在
echo "1. 檢查 SKILL.md 存在..."
if [ -f "$SKILL_MD" ]; then
    echo "   ✅ skills/test/SKILL.md 存在"
else
    echo "   ❌ skills/test/SKILL.md 不存在"
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
REF_FILE="$SKILL_DIR/references/coverage-thresholds.md"
if [ -f "$REF_FILE" ]; then
    echo "   ✅ references/coverage-thresholds.md 存在"
else
    echo "   ❌ references/coverage-thresholds.md 不存在"
    PASS=false
fi

# 4. 檢查 Agent 引用
echo ""
echo "4. 檢查 Agent 引用..."
AGENTS_USING=0
for agent_file in "$AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    agent_name=$(basename "$agent_file" .md)
    if grep -q "skills/test" "$agent_file" 2>/dev/null; then
        echo "   ✅ $agent_name 引用此 skill"
        AGENTS_USING=$((AGENTS_USING + 1))
    fi
done

if [ "$AGENTS_USING" -eq 0 ]; then
    echo "   ⚠️  沒有 Agent 明確引用 test skill（可能通過其他方式自動載入）"
else
    echo "   共 $AGENTS_USING 個 Agent 引用"
fi

# 5. 檢查測試相關內容
echo ""
echo "5. 檢查測試相關內容..."
if [ -f "$SKILL_MD" ]; then
    has_pyramid=$(grep -c "測試金字塔" "$SKILL_MD" 2>/dev/null || echo 0)
    has_frameworks=$(grep -c "pytest\|jest\|vitest" "$SKILL_MD" 2>/dev/null || echo 0)
    has_aaa=$(grep -c "Arrange.*Act.*Assert" "$SKILL_MD" 2>/dev/null || echo 0)
    has_coverage=$(grep -c "覆蓋率\|coverage" "$SKILL_MD" 2>/dev/null || echo 0)

    [ "$has_pyramid" -gt 0 ] && echo "   ✅ 包含測試金字塔內容" || { echo "   ❌ 缺少測試金字塔內容"; PASS=false; }
    [ "$has_frameworks" -gt 0 ] && echo "   ✅ 包含測試框架內容" || { echo "   ❌ 缺少測試框架內容"; PASS=false; }
    [ "$has_aaa" -gt 0 ] && echo "   ✅ 包含 AAA 模式內容" || { echo "   ❌ 缺少 AAA 模式內容"; PASS=false; }
    [ "$has_coverage" -gt 0 ] && echo "   ✅ 包含覆蓋率內容" || { echo "   ❌ 缺少覆蓋率內容"; PASS=false; }
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-030 PASS: test skill 驗證通過"
    exit 0
else
    echo "❌ TS-030 FAIL"
    exit 1
fi
