#!/bin/bash
# session-cleanup-report.sh - Session 結束清理與報告
# 事件: SessionEnd
# 功能: 優雅清理進程 + 生成 Session Report

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    📊 Session Report                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 1. 檢查進行中的工作
if [ -d "./openspec/changes" ]; then
    ACTIVE_CHANGES=$(find ./openspec/changes -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')

    if [ "$ACTIVE_CHANGES" -gt 0 ]; then
        echo "📋 進行中的工作: $ACTIVE_CHANGES 個"

        for change_dir in ./openspec/changes/*/; do
            if [ -d "$change_dir" ]; then
                change_id=$(basename "$change_dir")
                tasks_file="$change_dir/tasks.md"

                if [ -f "$tasks_file" ]; then
                    total=$(grep -c "^\- \[" "$tasks_file" 2>/dev/null || echo 0)
                    completed=$(grep -c "^\- \[x\]" "$tasks_file" 2>/dev/null || echo 0)

                    if [ "$total" -gt 0 ]; then
                        percent=$((completed * 100 / total))
                        echo "   • $change_id: $completed/$total ($percent%)"
                    fi
                fi
            fi
        done
        echo ""
    fi
fi

# 2. Git 變更統計
if [ -d ".git" ]; then
    MODIFIED=$(git diff --shortstat 2>/dev/null | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo 0)
    STAGED=$(git diff --cached --shortstat 2>/dev/null | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo 0)

    if [ "$MODIFIED" != "0" ] || [ "$STAGED" != "0" ]; then
        echo "📝 Git 變更:"
        [ "$STAGED" != "0" ] && echo "   • 已暫存: $STAGED 個檔案"
        [ "$MODIFIED" != "0" ] && echo "   • 未暫存: $MODIFIED 個檔案"
        echo ""
    fi
fi

# 3. 優雅清理背景進程
# 注意：這裡使用非強制清理，只標記需要清理的進程
# Claude Code 會自動處理其管理的進程

# 檢查是否有需要提醒的進程
if command -v pgrep &> /dev/null; then
    # 檢查常見的開發服務
    DEV_SERVERS=$(pgrep -f "npm run dev|yarn dev|node.*server|python.*flask|python.*django" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$DEV_SERVERS" -gt 0 ]; then
        echo "⚠️  偵測到 $DEV_SERVERS 個開發服務可能仍在執行"
        echo "   使用 '/tasks' 查看背景任務"
        echo ""
    fi
fi

# 4. 結束訊息
echo "✅ Session 結束"
echo ""
echo "💡 下次繼續: 使用 '接手 [change-id]' 恢復工作"

exit 0
