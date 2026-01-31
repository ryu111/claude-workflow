#!/bin/bash
# test-ts-035.sh - ralph-loop Skill 驗證
# 驗證: ralph-loop skill 結構、frontmatter 和特殊目錄結構

echo "=== TS-035: ralph-loop Skill 驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_DIR="$PROJECT_ROOT/skills/ralph-loop"
SKILL_MD="$SKILL_DIR/SKILL.md"
AGENTS_DIR="$PROJECT_ROOT/agents"

# 驗證結果
PASS=true

# 1. 檢查 SKILL.md 存在
echo "1. 檢查 SKILL.md 存在..."
if [ -f "$SKILL_MD" ]; then
    echo "   ✅ skills/ralph-loop/SKILL.md 存在"
else
    echo "   ❌ skills/ralph-loop/SKILL.md 不存在"
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

# 3. 檢查特殊目錄結構（ralph-loop 有 commands, hooks, scripts）
echo ""
echo "3. 檢查特殊目錄結構..."
REF_DIR="$SKILL_DIR/references"
CMD_DIR="$SKILL_DIR/commands"
HOOKS_DIR="$SKILL_DIR/hooks"
SCRIPTS_DIR="$SKILL_DIR/scripts"

if [ -d "$REF_DIR" ]; then
    echo "   ✅ references/ 目錄存在"
else
    echo "   ❌ references/ 目錄不存在"
    PASS=false
fi

if [ -d "$CMD_DIR" ]; then
    echo "   ✅ commands/ 目錄存在"
    # 檢查關鍵命令檔案
    if [ -f "$CMD_DIR/ralph-loop.md" ] && [ -f "$CMD_DIR/cancel-ralph.md" ]; then
        echo "   ✅ 核心命令檔案存在（ralph-loop.md, cancel-ralph.md）"
    else
        echo "   ⚠️  缺少部分核心命令檔案"
    fi
else
    echo "   ❌ commands/ 目錄不存在"
    PASS=false
fi

if [ -d "$HOOKS_DIR" ]; then
    echo "   ✅ hooks/ 目錄存在"
    if [ -f "$HOOKS_DIR/hooks.json" ]; then
        echo "   ✅ hooks/hooks.json 存在"
    else
        echo "   ⚠️  hooks/hooks.json 不存在"
    fi
else
    echo "   ❌ hooks/ 目錄不存在"
    PASS=false
fi

if [ -d "$SCRIPTS_DIR" ]; then
    echo "   ✅ scripts/ 目錄存在"
else
    echo "   ⚠️  scripts/ 目錄不存在"
fi

# 4. 檢查 Agent 引用
echo ""
echo "4. 檢查 Agent 引用..."
AGENTS_USING=0
for agent_file in "$AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    agent_name=$(basename "$agent_file" .md)
    if grep -q "ralph-loop" "$agent_file" 2>/dev/null; then
        echo "   ✅ $agent_name 引用此 skill"
        AGENTS_USING=$((AGENTS_USING + 1))
    fi
done

if [ "$AGENTS_USING" -eq 0 ]; then
    echo "   ⚠️  沒有 Agent 引用 ralph-loop skill（可能按需觸發）"
else
    echo "   共 $AGENTS_USING 個 Agent 引用"
fi

# 5. 檢查 Ralph Loop 特定內容
echo ""
echo "5. 檢查 Ralph Loop 特定內容..."
if [ -f "$SKILL_MD" ]; then
    has_max_iter=$(grep -c "max-iterations" "$SKILL_MD" 2>/dev/null || echo 0)
    has_stop_hook=$(grep -c "Stop hook" "$SKILL_MD" 2>/dev/null || echo 0)
    has_drt=$(grep -c "D→R→T\|DRT" "$SKILL_MD" 2>/dev/null || echo 0)
    has_promise=$(grep -c "promise.*TEXT.*promise" "$SKILL_MD" 2>/dev/null || echo 0)

    [ "$has_max_iter" -gt 0 ] && echo "   ✅ 包含 max-iterations 說明" || { echo "   ❌ 缺少 max-iterations 說明"; PASS=false; }
    [ "$has_stop_hook" -gt 0 ] && echo "   ✅ 包含 Stop hook 機制說明" || { echo "   ❌ 缺少 Stop hook 機制說明"; PASS=false; }
    [ "$has_drt" -gt 0 ] && echo "   ✅ 包含與 D→R→T 整合說明" || { echo "   ⚠️  缺少與 D→R→T 整合說明"; }
    [ "$has_promise" -gt 0 ] && echo "   ✅ 包含 promise 標籤退出條件" || { echo "   ⚠️  缺少 promise 標籤退出條件"; }
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-035 PASS: ralph-loop skill 驗證通過"
    exit 0
else
    echo "❌ TS-035 FAIL"
    exit 1
fi
