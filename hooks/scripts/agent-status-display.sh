#!/bin/bash
# agent-status-display.sh - Agent 啟動視覺確認
# 事件: SubagentStart
# 功能: 當 Agent 啟動時顯示即時確認給用戶
# 2025 AI Guardrails: User Notification Pattern

# DEBUG
DEBUG_LOG="/tmp/claude-workflow-debug.log"
echo "[$(date)] agent-status-display.sh called (SubagentStart)" >> "$DEBUG_LOG"

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)
echo "[$(date)] SubagentStart INPUT: $INPUT" >> "$DEBUG_LOG"

# 解析 Agent 名稱（格式：claude-workflow:developer）
# 注意：SubagentStart 事件使用 .agent_type，不是 .agent_name
RAW_AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_type // empty' | tr '[:upper:]' '[:lower:]')
# 移除 plugin 前綴
AGENT_NAME=$(echo "$RAW_AGENT_NAME" | sed 's/.*://')

# 解析任務描述（優先使用 agent_description，fallback 到 description）
DESCRIPTION=$(echo "$INPUT" | jq -r '.agent_description // .description // empty')

echo "[$(date)] AGENT_NAME: $AGENT_NAME, DESCRIPTION: $DESCRIPTION" >> "$DEBUG_LOG"

# 如果沒有 agent 名稱，直接退出
if [ -z "$AGENT_NAME" ]; then
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
# 設定當前 Agent 狀態檔案（供 global-workflow-guard.sh 使用）
# ═══════════════════════════════════════════════════════════════

SESSION_ID="${CLAUDE_SESSION_ID:-default}"
AGENT_STATE_FILE="/tmp/claude-agent-state-${SESSION_ID}"

# 寫入當前 agent 名稱
echo "$AGENT_NAME" > "$AGENT_STATE_FILE"
echo "[$(date)] Set current agent to: $AGENT_NAME (file: $AGENT_STATE_FILE)" >> "$DEBUG_LOG"

# 根據 Agent 類型顯示不同的啟動訊息
# 注意：SubagentStart 的 stderr 會顯示給用戶
case "$AGENT_NAME" in
    developer)
        cat >&2 << 'EOF'

╔════════════════════════════════════════════════════╗
║                                                    ║
║       💻  D  E  V  E  L  O  P  E  R               ║
║                                                    ║
╚════════════════════════════════════════════════════╝
EOF
        if [ -n "$DESCRIPTION" ]; then
            echo "📋 任務: $DESCRIPTION" >&2
        fi
        echo "📚 Skills: drt-rules, development, ui-design, checkpoint" >&2
        echo "🧰 工具: Read, Glob, Grep, Write, Edit, Bash, Task" >&2
        echo "💡 完成後需要 REVIEWER 審查" >&2
        echo "" >&2
        ;;

    reviewer)
        cat >&2 << 'EOF'

╔════════════════════════════════════════════════════╗
║                                                    ║
║        🔍  R  E  V  I  E  W  E  R                 ║
║                                                    ║
╚════════════════════════════════════════════════════╝
EOF
        if [ -n "$DESCRIPTION" ]; then
            echo "📋 任務: $DESCRIPTION" >&2
        fi
        echo "📚 Skills: drt-rules, code-review" >&2
        echo "🧰 工具: Read, Glob, Grep (唯讀模式)" >&2
        echo "💡 完成後輸出 APPROVE / APPROVE+MINOR / REJECT" >&2
        echo "" >&2
        ;;

    tester)
        cat >&2 << 'EOF'

╔════════════════════════════════════════════════════╗
║                                                    ║
║          🧪  T  E  S  T  E  R                     ║
║                                                    ║
╚════════════════════════════════════════════════════╝
EOF
        if [ -n "$DESCRIPTION" ]; then
            echo "📋 任務: $DESCRIPTION" >&2
        fi
        echo "📚 Skills: drt-rules, test, error-handling" >&2
        echo "🧰 工具: Read, Glob, Grep, Bash" >&2
        echo "💡 完成後輸出 PASS / FAIL" >&2
        echo "" >&2
        ;;

    debugger)
        cat >&2 << 'EOF'

╔════════════════════════════════════════════════════╗
║                                                    ║
║        🐛  D  E  B  U  G  G  E  R                 ║
║                                                    ║
╚════════════════════════════════════════════════════╝
EOF
        if [ -n "$DESCRIPTION" ]; then
            echo "📋 任務: $DESCRIPTION" >&2
        fi
        echo "📚 Skills: drt-rules, error-handling, debugging" >&2
        echo "🧰 工具: Read, Glob, Grep, Write, Task" >&2
        echo "💡 分析錯誤後返回 DEVELOPER 修復" >&2
        echo "" >&2
        ;;

    architect)
        cat >&2 << 'EOF'

╔════════════════════════════════════════════════════╗
║                                                    ║
║       🏗️  A  R  C  H  I  T  E  C  T               ║
║                                                    ║
╚════════════════════════════════════════════════════╝
EOF
        if [ -n "$DESCRIPTION" ]; then
            echo "📋 任務: $DESCRIPTION" >&2
        fi
        echo "📚 Skills: system-design, openspec, architecture-patterns" >&2
        echo "🧰 工具: Read, Glob, Grep, Write, Task" >&2
        echo "💡 輸出 OpenSpec 規格檔到 openspec/specs/" >&2
        echo "" >&2
        ;;

    designer)
        cat >&2 << 'EOF'

╔════════════════════════════════════════════════════╗
║                                                    ║
║        🎨  D  E  S  I  G  N  E  R                 ║
║                                                    ║
╚════════════════════════════════════════════════════╝
EOF
        if [ -n "$DESCRIPTION" ]; then
            echo "📋 任務: $DESCRIPTION" >&2
        fi
        echo "📚 Skills: ui-design, visual-design, design-systems" >&2
        echo "🧰 工具: Read, Glob, Grep, Write, Task" >&2
        echo "💡 輸出設計規格後交由 DEVELOPER 實作" >&2
        echo "" >&2
        ;;

    explorer|explore)
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════════╗" >&2
        echo "║                    🔭 EXPLORER 啟動                             ║" >&2
        echo "╚════════════════════════════════════════════════════════════════╝" >&2
        if [ -n "$DESCRIPTION" ]; then
            echo "📋 任務: $DESCRIPTION" >&2
        fi
        echo "" >&2
        ;;

    planner|plan)
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════════╗" >&2
        echo "║                    📋 PLANNER 啟動                              ║" >&2
        echo "╚════════════════════════════════════════════════════════════════╝" >&2
        if [ -n "$DESCRIPTION" ]; then
            echo "📋 任務: $DESCRIPTION" >&2
        fi
        echo "" >&2
        ;;

    main)
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════════╗" >&2
        echo "║                    🤖 MAIN 啟動                                 ║" >&2
        echo "╚════════════════════════════════════════════════════════════════╝" >&2
        if [ -n "$DESCRIPTION" ]; then
            echo "📋 任務: $DESCRIPTION" >&2
        fi
        echo "" >&2
        ;;

    general-purpose)
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════════╗" >&2
        echo "║                    🔧 GENERAL-PURPOSE 啟動                      ║" >&2
        echo "╚════════════════════════════════════════════════════════════════╝" >&2
        if [ -n "$DESCRIPTION" ]; then
            echo "📋 任務: $DESCRIPTION" >&2
        fi
        echo "" >&2
        ;;

    *)
        # 其他 agent 也顯示大框
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════════╗" >&2
        echo "║                    📋 $AGENT_NAME 啟動" >&2
        echo "╚════════════════════════════════════════════════════════════════╝" >&2
        if [ -n "$DESCRIPTION" ]; then
            echo "📋 任務: $DESCRIPTION" >&2
        fi
        echo "" >&2
        ;;
esac

# SubagentStart 不需要輸出 JSON decision
exit 0
