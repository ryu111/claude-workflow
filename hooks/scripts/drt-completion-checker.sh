#!/bin/bash
# drt-completion-checker.sh - D→R→T 完成檢查
# 事件: Stop
# 功能: 在 session 結束前檢查是否有未完成的 D→R→T 流程

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)

# 檢查是否有進行中的 OpenSpec
if [ -d "./openspec/changes" ]; then
    # Bug Fix 1: 使用雙引號包裹路徑並正確處理空格
    ACTIVE_CHANGES=$(find "./openspec/changes" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | xargs -0 echo)

    if [ -n "$ACTIVE_CHANGES" ]; then
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║                   📋 進行中的工作                               ║"
        echo "╚════════════════════════════════════════════════════════════════╝"

        # Bug Fix 1: 使用 find -print0 和 while read 處理空格
        find "./openspec/changes" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | while IFS= read -r -d '' change_dir; do
            change_id=$(basename "$change_dir")
            tasks_file="$change_dir/tasks.md"

            if [ -f "$tasks_file" ]; then
                total=$(grep -c "^\- \[" "$tasks_file" 2>/dev/null || echo 0)
                completed=$(grep -c "^\- \[x\]" "$tasks_file" 2>/dev/null || echo 0)

                echo ""
                echo "📁 $change_id"
                echo "   進度: $completed/$total 任務完成"

                # 找出下一個待處理的任務
                next_task=$(grep "^\- \[ \]" "$tasks_file" | head -1 | sed 's/- \[ \] //')
                if [ -n "$next_task" ]; then
                    echo "   下一個: $next_task"
                fi
            fi
        done

        echo ""
        echo "💡 使用 '接手 [change-id]' 繼續工作"
    fi
fi

exit 0
