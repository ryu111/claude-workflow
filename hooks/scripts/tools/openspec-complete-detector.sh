#!/bin/bash
# openspec-complete-detector.sh - OpenSpec 完成偵測
# 事件: PreCompact
# 功能: 在 context compact 前檢查是否有已完成的 OpenSpec 需要歸檔

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)

# 檢查是否有完成的 OpenSpec
if [ -d "./openspec/changes" ]; then
    # Bug Fix 1: 使用雙引號包裹路徑並正確處理空格
    find "./openspec/changes" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | while IFS= read -r -d '' change_dir; do
        if [ -d "$change_dir" ]; then
            change_id=$(basename "$change_dir")
            tasks_file="$change_dir/tasks.md"

            if [ -f "$tasks_file" ]; then
                # 計算未完成的任務
                incomplete=$(grep -c "^\- \[ \]" "$tasks_file" 2>/dev/null | head -1 | tr -d '\n\r ' || echo "0")

                if [ "$incomplete" -eq 0 ]; then
                    total=$(grep -c "^\- \[" "$tasks_file" 2>/dev/null | head -1 | tr -d '\n\r ' || echo "0")

                    if [ "$total" -gt 0 ]; then
                        echo "╔════════════════════════════════════════════════════════════════╗"
                        echo "║                   🎉 工作完成                                   ║"
                        echo "╚════════════════════════════════════════════════════════════════╝"
                        echo ""
                        echo "📋 $change_id 的所有任務已完成！"
                        echo ""
                        echo "💡 建議執行歸檔："
                        echo "   mv \"./openspec/changes/$change_id\" \"./openspec/archive/\""
                        echo "   git add . && git commit -m 'chore: archive $change_id'"
                    fi
                fi
            fi
        fi
    done
fi

exit 0
