#!/bin/bash
# dev-reload.sh - 開發時快速重載 Plugin
# 用法: bash scripts/dev-reload.sh

set -e

PLUGIN_NAME="claude-workflow"
CACHE_DIR="$HOME/.claude/plugins/cache/$PLUGIN_NAME"

echo "🔄 Claude Workflow Plugin 開發重載"
echo ""

# 清除快取
if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo "✅ 已清除快取: $CACHE_DIR"
else
    echo "ℹ️  快取不存在，跳過清除"
fi

echo ""
echo "📋 下一步："
echo "   1. 重啟 Claude Code Session"
echo "   2. Cmd+Shift+P → Claude Code: Restart Session"
echo ""
echo "💡 或者重新安裝 Plugin："
echo "   Cmd+Shift+P → Claude Code: Manage Plugins"
echo "   加入: /Users/sbu/projects/claude-workflow"
