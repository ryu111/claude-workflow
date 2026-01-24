#!/bin/bash
# dev-reload.sh - 開發時快速重載 Plugin
# 用法: bash scripts/dev-reload.sh
# 功能: 清除快取並創建符號連結到本地目錄

set -e

PLUGIN_NAME="claude-workflow"
PLUGIN_ID="claude-workflow"
VERSION="0.1.0"
CACHE_DIR="$HOME/.claude/plugins/cache/$PLUGIN_NAME"
LOCAL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "🔄 Claude Workflow Plugin 開發重載"
echo ""

# 清除快取
if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo "✅ 已清除快取: $CACHE_DIR"
else
    echo "ℹ️  快取不存在"
fi

# 創建符號連結到本地目錄
echo ""
echo "🔗 創建符號連結..."
mkdir -p "$CACHE_DIR/$PLUGIN_ID"
ln -sf "$LOCAL_DIR" "$CACHE_DIR/$PLUGIN_ID/$VERSION"
echo "✅ 已連結: $CACHE_DIR/$PLUGIN_ID/$VERSION → $LOCAL_DIR"

echo ""
echo "📋 下一步："
echo "   重啟 Claude Code Session 讓 hooks 生效"
echo "   Cmd+Shift+P → Claude Code: Restart Session"
echo ""
echo "💡 開發優勢："
echo "   - 本地修改會立即反映在快取中"
echo "   - 無需重新安裝 Plugin"
echo "   - 只需重啟 Session 即可測試新功能"
