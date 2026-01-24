#!/bin/bash
# plugin-status-display.sh - Plugin 載入狀態顯示
# 事件: SessionStart
# 功能: 顯示 claude-workflow plugin 載入資訊

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/claude-workflow}"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║            🔄 Claude Workflow Plugin 已載入                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 統計元件
AGENTS_COUNT=$(find "$PLUGIN_ROOT/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
SKILLS_COUNT=$(find "$PLUGIN_ROOT/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
HOOKS_COUNT=$(jq '.hooks | to_entries | map(.value | length) | add // 0' "$PLUGIN_ROOT/hooks/hooks.json" 2>/dev/null || echo 0)

echo "📦 已載入元件:"
echo "   • Agents: $AGENTS_COUNT"
echo "   • Skills: $SKILLS_COUNT"
echo "   • Hooks: $HOOKS_COUNT"
echo ""

# 顯示可用的 Agents
echo "🤖 可用 Agents:"
echo "   • ARCHITECT - 規劃系統架構"
echo "   • DESIGNER - UI/UX 設計"
echo "   • DEVELOPER - 程式碼實作"
echo "   • REVIEWER - 程式碼審查"
echo "   • TESTER - 測試驗證"
echo "   • DEBUGGER - 除錯排查"
echo ""

# 檢查是否有進行中的工作
if [ -d "./openspec/changes" ]; then
    ACTIVE=$(find ./openspec/changes -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    if [ "$ACTIVE" -gt 0 ]; then
        echo "📋 進行中的工作: $ACTIVE 個"
        for change_dir in ./openspec/changes/*/; do
            if [ -d "$change_dir" ]; then
                echo "   • $(basename "$change_dir")"
            fi
        done
        echo ""
        echo "💡 使用 '接手 [change-id]' 繼續工作"
        echo ""
    fi
fi

echo "🎯 快速開始:"
echo "   • 新功能: '規劃 [feature]'"
echo "   • 繼續: '接手 [change-id]'"
echo "   • 初始化專案: '~/.claude/plugins/claude-workflow/scripts/init.sh'"
echo ""

exit 0
