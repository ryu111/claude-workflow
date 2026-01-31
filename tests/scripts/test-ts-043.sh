#!/bin/bash
# test-ts-043.sh - 完整工作流整合測試
# 驗證: 整個 claude-workflow plugin 的組件完整性

echo "=== TS-043: 完整工作流整合測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=true

# 檢查 jq 依賴
if ! command -v jq &> /dev/null; then
    echo "⚠️  警告: jq 未安裝，部分 JSON 驗證將被跳過"
    echo "   建議安裝: brew install jq (macOS) 或 apt-get install jq (Linux)"
    echo ""
    JQ_AVAILABLE=false
else
    JQ_AVAILABLE=true
fi

# 1. 驗證腳本完整性
echo "1️⃣  驗證腳本完整性..."
echo ""

EXPECTED_VALIDATE_SCRIPTS=(
    "validate-skills.sh"
    "validate-agents.sh"
    "validate-hooks.sh"
    "validate-commands.sh"
    "validate-plugin.sh"
)

for script in "${EXPECTED_VALIDATE_SCRIPTS[@]}"; do
    SCRIPT_PATH="$PROJECT_ROOT/scripts/$script"
    if [ ! -f "$SCRIPT_PATH" ]; then
        echo "❌ 缺少驗證腳本: scripts/$script"
        PASS=false
    else
        echo "✓ scripts/$script 存在"

        # 檢查執行權限
        if [ ! -x "$SCRIPT_PATH" ]; then
            echo "  ⚠️  無執行權限"
            PASS=false
        fi
    fi
done

echo ""

# 2. Hook 腳本完整性
echo "2️⃣  Hook 腳本完整性..."
echo ""

EXPECTED_HOOK_SCRIPTS=(
    "plugin-status-display.sh"
    "agent-status-display.sh"
    "workflow-gate.sh"
    "keyword-detector.sh"
    "subagent-validator.sh"
    "session-state-init.sh"
    "session-state-cleanup.sh"
    "global-workflow-guard.sh"
    "auto-format.sh"
    "drt-completion-checker.sh"
    "openspec-complete-detector.sh"
    "session-cleanup-report.sh"
    "violation-collector.sh"
)

HOOK_COUNT=0
for script in "${EXPECTED_HOOK_SCRIPTS[@]}"; do
    SCRIPT_PATH="$PROJECT_ROOT/hooks/scripts/$script"
    if [ ! -f "$SCRIPT_PATH" ]; then
        echo "❌ 缺少 Hook 腳本: hooks/scripts/$script"
        PASS=false
    else
        echo "✓ hooks/scripts/$script 存在"
        ((HOOK_COUNT++))

        # 檢查執行權限
        if [ ! -x "$SCRIPT_PATH" ]; then
            echo "  ⚠️  無執行權限"
            PASS=false
        fi
    fi
done

echo ""
echo "✓ Hook 腳本數量: $HOOK_COUNT/${#EXPECTED_HOOK_SCRIPTS[@]}"

if [ $HOOK_COUNT -ne ${#EXPECTED_HOOK_SCRIPTS[@]} ]; then
    PASS=false
fi

echo ""

# 3. Agent 定義完整性（6 個）
echo "3️⃣  Agent 定義完整性..."
echo ""

EXPECTED_AGENTS=(
    "architect"
    "designer"
    "developer"
    "reviewer"
    "tester"
    "debugger"
)

AGENT_COUNT=0
for agent in "${EXPECTED_AGENTS[@]}"; do
    AGENT_PATH="$PROJECT_ROOT/agents/$agent.md"
    if [ ! -f "$AGENT_PATH" ]; then
        echo "❌ 缺少 Agent: agents/$agent.md"
        PASS=false
    else
        ((AGENT_COUNT++))

        # 檢查 frontmatter
        if ! head -20 "$AGENT_PATH" | grep -q "^name: $agent$"; then
            echo "  ⚠️  agents/$agent.md frontmatter 缺少或錯誤: name"
            PASS=false
        fi
    fi
done

echo "✓ Agent 數量: $AGENT_COUNT/${#EXPECTED_AGENTS[@]}"

if [ $AGENT_COUNT -ne ${#EXPECTED_AGENTS[@]} ]; then
    PASS=false
fi

echo ""

# 4. Skill 定義完整性（13 個）
echo "4️⃣  Skill 定義完整性..."
echo ""

EXPECTED_SKILLS=(
    "drt-rules"
    "openspec"
    "orchestration"
    "ralph-loop"
    "development"
    "code-review"
    "test"
    "debugging"
    "ui-design"
    "reuse-first"
    "checkpoint"
    "error-handling"
    "browser-automation"
)

SKILL_COUNT=0
for skill in "${EXPECTED_SKILLS[@]}"; do
    SKILL_PATH="$PROJECT_ROOT/skills/$skill/SKILL.md"
    if [ ! -f "$SKILL_PATH" ]; then
        echo "❌ 缺少 Skill: skills/$skill/SKILL.md"
        PASS=false
    else
        ((SKILL_COUNT++))

        # 檢查 frontmatter
        if ! head -20 "$SKILL_PATH" | grep -q "^name: $skill$"; then
            echo "  ⚠️  skills/$skill/SKILL.md frontmatter 缺少或錯誤: name"
            PASS=false
        fi
    fi
done

echo "✓ Skill 數量: $SKILL_COUNT/${#EXPECTED_SKILLS[@]}"

if [ $SKILL_COUNT -ne ${#EXPECTED_SKILLS[@]} ]; then
    PASS=false
fi

echo ""

# 5. Command 定義完整性（8 個）
echo "5️⃣  Command 定義完整性..."
echo ""

EXPECTED_COMMANDS=(
    "plan"
    "resume"
    "loop"
    "init"
    "validate-skills"
    "validate-agents"
    "validate-hooks"
    "validate-plugin"
)

COMMAND_COUNT=0
for cmd in "${EXPECTED_COMMANDS[@]}"; do
    CMD_PATH="$PROJECT_ROOT/commands/$cmd.md"
    if [ ! -f "$CMD_PATH" ]; then
        echo "❌ 缺少 Command: commands/$cmd.md"
        PASS=false
    else
        ((COMMAND_COUNT++))

        # 檢查 frontmatter
        if ! head -20 "$CMD_PATH" | grep -q "^name: $cmd$"; then
            echo "  ⚠️  commands/$cmd.md frontmatter 缺少或錯誤: name"
            PASS=false
        fi

        # resume 指令透過關鍵字觸發，不需要 user-invocable: true
        if [ "$cmd" != "resume" ]; then
            if ! head -20 "$CMD_PATH" | grep -q "^user-invocable: true$"; then
                echo "  ⚠️  commands/$cmd.md frontmatter 缺少: user-invocable: true"
                PASS=false
            fi
        fi
    fi
done

echo "✓ Command 數量: $COMMAND_COUNT/${#EXPECTED_COMMANDS[@]}"

if [ $COMMAND_COUNT -ne ${#EXPECTED_COMMANDS[@]} ]; then
    PASS=false
fi

echo ""

# 6. Plugin 配置有效性
echo "6️⃣  Plugin 配置有效性..."
echo ""

PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"

if [ ! -f "$PLUGIN_JSON" ]; then
    echo "❌ 缺少 plugin.json"
    PASS=false
else
    echo "✓ .claude-plugin/plugin.json 存在"

    # 檢查 JSON 格式（需要 jq）
    if [ "$JQ_AVAILABLE" = true ]; then
        if ! jq empty "$PLUGIN_JSON" 2>/dev/null; then
            echo "  ❌ plugin.json 格式錯誤（非有效 JSON）"
            PASS=false
        else
            echo "  ✓ JSON 格式有效"

            # 檢查必要欄位
            if ! jq -e '.name' "$PLUGIN_JSON" >/dev/null 2>&1; then
                echo "  ❌ 缺少欄位: name"
                PASS=false
            else
                PLUGIN_NAME=$(jq -r '.name' "$PLUGIN_JSON")
                echo "  ✓ name: $PLUGIN_NAME"
            fi

            if ! jq -e '.version' "$PLUGIN_JSON" >/dev/null 2>&1; then
                echo "  ❌ 缺少欄位: version"
                PASS=false
            else
                PLUGIN_VERSION=$(jq -r '.version' "$PLUGIN_JSON")
                echo "  ✓ version: $PLUGIN_VERSION"
            fi

            if ! jq -e '.description' "$PLUGIN_JSON" >/dev/null 2>&1; then
                echo "  ❌ 缺少欄位: description"
                PASS=false
            else
                echo "  ✓ description 欄位存在"
            fi
        fi
    else
        echo "  ⚠️  跳過 JSON 驗證（jq 未安裝）"
    fi
fi

echo ""

# 7. 執行所有驗證腳本
echo "7️⃣  執行所有驗證腳本..."
echo ""

VALIDATE_ERRORS=0

for script in "${EXPECTED_VALIDATE_SCRIPTS[@]}"; do
    SCRIPT_PATH="$PROJECT_ROOT/scripts/$script"
    if [ -x "$SCRIPT_PATH" ]; then
        echo "→ 執行 scripts/$script..."
        if bash "$SCRIPT_PATH" >/dev/null 2>&1; then
            echo "  ✓ $script 驗證通過"
        else
            echo "  ❌ $script 驗證失敗"
            ((VALIDATE_ERRORS++))
            PASS=false
        fi
    fi
done

if [ $VALIDATE_ERRORS -eq 0 ]; then
    echo ""
    echo "✓ 所有驗證腳本執行通過"
else
    echo ""
    echo "❌ $VALIDATE_ERRORS 個驗證腳本執行失敗"
fi

echo ""

# 8. D→R→T 流程組件連貫性檢查
echo "8️⃣  D→R→T 流程組件連貫性..."
echo ""

# 檢查核心 Skill 是否被 Agent 引用
CORE_SKILL_REFS=0

if grep -q "drt-rules" "$PROJECT_ROOT/agents/developer.md"; then
    echo "✓ developer agent 引用 drt-rules skill"
    ((CORE_SKILL_REFS++))
fi

if grep -q "code-review" "$PROJECT_ROOT/agents/reviewer.md"; then
    echo "✓ reviewer agent 引用 code-review skill"
    ((CORE_SKILL_REFS++))
fi

if grep -q "test" "$PROJECT_ROOT/agents/tester.md"; then
    echo "✓ tester agent 引用 test skill"
    ((CORE_SKILL_REFS++))
fi

if [ $CORE_SKILL_REFS -lt 3 ]; then
    echo "⚠️  部分核心 Skill 未被正確引用"
    PASS=false
fi

echo ""

# 結果摘要
echo "========================================="
echo "               測試摘要"
echo "========================================="
echo ""
echo "組件統計:"
echo "  - 驗證腳本: ${#EXPECTED_VALIDATE_SCRIPTS[@]} 個"
echo "  - Hook 腳本: $HOOK_COUNT 個"
echo "  - Agent 定義: $AGENT_COUNT 個"
echo "  - Skill 定義: $SKILL_COUNT 個"
echo "  - Command 定義: $COMMAND_COUNT 個"
echo ""

if [ "$PASS" = true ]; then
    echo "✅ TS-043 PASS: 完整工作流整合測試通過"
    echo ""
    echo "🎉 Plugin 組件完整性驗證成功！"
    exit 0
else
    echo "❌ TS-043 FAIL: 發現問題，請檢查上述錯誤訊息"
    echo ""
    echo "💡 建議執行個別驗證腳本進行詳細檢查："
    echo "   bash scripts/validate-skills.sh"
    echo "   bash scripts/validate-agents.sh"
    echo "   bash scripts/validate-hooks.sh"
    exit 1
fi
