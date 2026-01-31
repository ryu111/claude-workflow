#!/bin/bash
# test-ts-033.sh - error-handling Skill 驗證
# 驗證: error-handling skill 結構、frontmatter 和引用正確

echo "=== TS-033: error-handling Skill 驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_DIR="$PROJECT_ROOT/skills/error-handling"
SKILL_MD="$SKILL_DIR/SKILL.md"
AGENTS_DIR="$PROJECT_ROOT/agents"

# 驗證結果
PASS=true

# 1. 檢查 SKILL.md 存在
echo "1. 檢查 SKILL.md 存在..."
if [ -f "$SKILL_MD" ]; then
    echo "   ✅ skills/error-handling/SKILL.md 存在"
else
    echo "   ❌ skills/error-handling/SKILL.md 不存在"
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

# 3. 檢查參考文件
echo ""
echo "3. 檢查參考文件..."
REF_DIR="$SKILL_DIR/references"
TMPL_DIR="$SKILL_DIR/templates"

if [ -d "$REF_DIR" ]; then
    echo "   ✅ references/ 目錄存在"
    if [ -f "$REF_DIR/error-codes.md" ]; then
        echo "   ✅ references/error-codes.md 存在"
    else
        echo "   ⚠️  references/error-codes.md 不存在"
    fi
else
    echo "   ❌ references/ 目錄不存在"
    PASS=false
fi

if [ -d "$TMPL_DIR" ]; then
    echo "   ✅ templates/ 目錄存在"
    if [ -f "$TMPL_DIR/error-report.md" ]; then
        echo "   ✅ templates/error-report.md 存在"
    else
        echo "   ⚠️  templates/error-report.md 不存在"
    fi
else
    echo "   ❌ templates/ 目錄不存在"
    PASS=false
fi

# 4. 檢查 Agent 引用
echo ""
echo "4. 檢查 Agent 引用..."
AGENTS_USING=0
for agent_file in "$AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    agent_name=$(basename "$agent_file" .md)
    if grep -q "error-handling" "$agent_file" 2>/dev/null; then
        echo "   ✅ $agent_name 引用此 skill"
        AGENTS_USING=$((AGENTS_USING + 1))
    fi
done

if [ "$AGENTS_USING" -eq 0 ]; then
    echo "   ⚠️  沒有 Agent 引用 error-handling skill（可能按需觸發）"
else
    echo "   共 $AGENTS_USING 個 Agent 引用"
fi

# 5. 檢查錯誤處理特定內容
echo ""
echo "5. 檢查錯誤處理特定內容..."
if [ -f "$SKILL_MD" ]; then
    has_retry=$(grep -c "重試\|retry" "$SKILL_MD" 2>/dev/null || echo 0)
    has_classification=$(grep -c "錯誤分類\|可重試\|可修復\|致命" "$SKILL_MD" 2>/dev/null || echo 0)
    has_recovery=$(grep -c "自動修復\|恢復策略" "$SKILL_MD" 2>/dev/null || echo 0)
    has_exponential=$(grep -c "指數退避" "$SKILL_MD" 2>/dev/null || echo 0)

    [ "$has_retry" -gt 0 ] && echo "   ✅ 包含重試策略內容" || { echo "   ❌ 缺少重試策略內容"; PASS=false; }
    [ "$has_classification" -gt 0 ] && echo "   ✅ 包含錯誤分類內容" || { echo "   ❌ 缺少錯誤分類內容"; PASS=false; }
    [ "$has_recovery" -gt 0 ] && echo "   ✅ 包含自動修復策略" || { echo "   ❌ 缺少自動修復策略"; PASS=false; }
    [ "$has_exponential" -gt 0 ] && echo "   ✅ 包含指數退避策略" || { echo "   ⚠️  缺少指數退避策略"; }
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-033 PASS: error-handling skill 驗證通過"
    exit 0
else
    echo "❌ TS-033 FAIL"
    exit 1
fi
