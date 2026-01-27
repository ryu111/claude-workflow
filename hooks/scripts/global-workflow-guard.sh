#!/bin/bash
# global-workflow-guard.sh - 全局工作流守衛
# 事件: PreToolUse (Write|Edit|Bash|NotebookEdit)
# 功能: 阻擋 Main Agent 直接使用檔案修改工具，強制透過 DEVELOPER agent
# 2025 AI Guardrails: Tool-Level Enforcement Pattern

# ═══════════════════════════════════════════════════════════════
# 配置
# ═══════════════════════════════════════════════════════════════

DEBUG_LOG="/tmp/claude-workflow-debug.log"

# 修正 1: Session ID 隔離
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
AGENT_STATE_FILE="/tmp/claude-agent-state-${SESSION_ID}"

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)
echo "[$(date)] global-workflow-guard.sh called (session: $SESSION_ID)" >> "$DEBUG_LOG"
echo "[$(date)] INPUT: $INPUT" >> "$DEBUG_LOG"

# ═══════════════════════════════════════════════════════════════
# Bypass 檢查
# ═══════════════════════════════════════════════════════════════

# 方式 1: 環境變數
if [ "$CLAUDE_WORKFLOW_BYPASS" = "true" ] || [ "$CLAUDE_WORKFLOW_BYPASS" = "1" ]; then
    echo "[$(date)] BYPASS: environment variable" >> "$DEBUG_LOG"
    exit 0
fi

# 方式 2: 配置文件
STATE_DIR="${PWD}/.claude"
BYPASS_FILE="${STATE_DIR}/.drt-bypass"
if [ -f "$BYPASS_FILE" ]; then
    echo "[$(date)] BYPASS: config file" >> "$DEBUG_LOG"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
# 解析工具名稱
# ═══════════════════════════════════════════════════════════════

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
echo "[$(date)] TOOL_NAME: $TOOL_NAME" >> "$DEBUG_LOG"

# 如果無法解析工具名稱，允許通過
if [ -z "$TOOL_NAME" ]; then
    echo "[$(date)] No tool name, allowing" >> "$DEBUG_LOG"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
# 檢查是否在 Subagent 中執行
# ═══════════════════════════════════════════════════════════════

IS_SUBAGENT=false
CURRENT_AGENT="main"

# 修正 3: 競態條件處理 - 等待狀態檔案建立（最多 500ms）
if [ ! -f "$AGENT_STATE_FILE" ]; then
    for i in $(seq 1 5); do
        sleep 0.1
        [ -f "$AGENT_STATE_FILE" ] && break
    done
fi

# 方法 1: 檢查狀態檔案（由 SubagentStart hook 設定）
if [ -f "$AGENT_STATE_FILE" ]; then
    CURRENT_AGENT=$(cat "$AGENT_STATE_FILE" 2>/dev/null || echo "main")
    if [ "$CURRENT_AGENT" != "main" ] && [ -n "$CURRENT_AGENT" ]; then
        IS_SUBAGENT=true
    fi
fi

echo "[$(date)] IS_SUBAGENT: $IS_SUBAGENT (agent: $CURRENT_AGENT)" >> "$DEBUG_LOG"

# ═══════════════════════════════════════════════════════════════
# 修正 2: Bash 命令白名單處理
# ═══════════════════════════════════════════════════════════════

# 對於 Bash 工具，檢查命令是否為唯讀操作
if [ "$TOOL_NAME" = "Bash" ] && [ "$IS_SUBAGENT" = false ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    echo "[$(date)] Bash command: $COMMAND" >> "$DEBUG_LOG"

    # ═══════════════════════════════════════════════════════════════
    # Plugin 腳本白名單（允許 Plugin 內部腳本執行）
    # ═══════════════════════════════════════════════════════════════

    # 允許來自 Plugin 目錄的腳本（Command 的 allowed-tools 授權）
    PLUGIN_SCRIPT_PATTERNS=(
        # ralph-wiggum plugin
        "\\.claude/plugins/.*/ralph-wiggum.*/setup-ralph-loop\\.sh"
        # claude-workflow plugin
        "claude-workflow.*/scripts/init\\.sh"
        "claude-workflow.*/scripts/validate-.*\\.sh"
    )

    is_plugin_script() {
        local cmd="$1"
        for pattern in "${PLUGIN_SCRIPT_PATTERNS[@]}"; do
            if echo "$cmd" | grep -qE "$pattern"; then
                return 0
            fi
        done
        return 1
    }

    # 檢查是否為 Plugin 腳本
    if is_plugin_script "$COMMAND"; then
        echo "[$(date)] Plugin script allowed: $COMMAND" >> "$DEBUG_LOG"
        exit 0
    fi

    # ═══════════════════════════════════════════════════════════════
    # 危險操作符檢查
    # ═══════════════════════════════════════════════════════════════

    # 檢查是否包含寫入運算符（即使命令本身在白名單中）
    DANGEROUS_OPERATORS=">|>>|\\|.*tee|\\\`|\\$\\("
    if echo "$COMMAND" | grep -qE "$DANGEROUS_OPERATORS"; then
        echo "[$(date)] Bash command blocked (contains dangerous operators)" >> "$DEBUG_LOG"
        # 繼續執行阻擋邏輯（不 exit 0）
    else
        # ═══════════════════════════════════════════════════════════════
        # 唯讀命令白名單（擴展版）
        # ═══════════════════════════════════════════════════════════════

        # 白名單：唯讀命令前綴（包含更多 git 命令、測試與格式化檢查）
        READONLY_PATTERNS="^(git (status|log|diff|branch|show|remote|rev-parse|ls-files|blame|tag|config --get|rev-list|describe|shortlog)|ls|pwd|cat|head|tail|wc|grep|rg|ag|find|which|file|stat|du|df|date|uname|whoami|hostname|env|printenv|node --version|npm --version|npm list|npm ls|python --version|pip --version|pip list|pip show|go version|cargo --version|rustc --version|jq|yq|npm (test|run test|run lint|run check)|npx |yarn (test|lint)|pytest|python -m pytest|go test|cargo test|make test|prettier --check|eslint --print-config|black --check|ruff check)"

        if echo "$COMMAND" | grep -qE "$READONLY_PATTERNS"; then
            echo "[$(date)] Bash command allowed (read-only)" >> "$DEBUG_LOG"
            exit 0
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 工具白名單（Main Agent 允許使用的工具）
# ═══════════════════════════════════════════════════════════════

# Main Agent 允許的唯讀/協調工具
MAIN_ALLOWED_TOOLS=(
    "Read"
    "Glob"
    "Grep"
    "Task"
    "WebFetch"
    "WebSearch"
    "AskUserQuestion"
    "EnterPlanMode"
    "ExitPlanMode"
    "TaskCreate"
    "TaskUpdate"
    "TaskGet"
    "TaskList"
    "Skill"
    "ListMcpResourcesTool"
    "ReadMcpResourceTool"
    # Memory MCP tools
    "mcp__memory-service__store_memory"
    "mcp__memory-service__retrieve_memory"
    "mcp__memory-service__recall_memory"
    "mcp__memory-service__search_by_tag"
    # Browser tools (strictly read-only operations)
    "mcp__claude-in-chrome__tabs_context_mcp"
    "mcp__claude-in-chrome__read_page"
    "mcp__claude-in-chrome__find"
    "mcp__claude-in-chrome__get_page_text"
)

# 檢查工具是否在白名單中
is_tool_allowed() {
    local tool="$1"
    for allowed in "${MAIN_ALLOWED_TOOLS[@]}"; do
        if [ "$tool" = "$allowed" ]; then
            return 0
        fi
    done
    return 1
}

# ═══════════════════════════════════════════════════════════════
# 決策邏輯
# ═══════════════════════════════════════════════════════════════

# 如果是 Subagent，允許所有工具
if [ "$IS_SUBAGENT" = true ]; then
    echo "[$(date)] Subagent '$CURRENT_AGENT' allowed to use '$TOOL_NAME'" >> "$DEBUG_LOG"
    exit 0
fi

# 如果是 Main Agent 且工具在白名單中，允許
if is_tool_allowed "$TOOL_NAME"; then
    echo "[$(date)] Main Agent allowed tool: $TOOL_NAME" >> "$DEBUG_LOG"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
# 阻擋 Main Agent 使用禁止的工具
# ═══════════════════════════════════════════════════════════════

echo "[$(date)] BLOCKED: Main Agent attempting to use '$TOOL_NAME'" >> "$DEBUG_LOG"

# 輸出阻擋訊息到 stderr（顯示給用戶）
echo "" >&2
echo "╔════════════════════════════════════════════════════════════════╗" >&2
echo "║             🚫 D→R→T 工作流違規                                ║" >&2
echo "╚════════════════════════════════════════════════════════════════╝" >&2
echo "" >&2
echo "❌ Main Agent 禁止直接使用 '$TOOL_NAME' 工具" >&2
echo "" >&2
echo "📋 正確做法：" >&2
echo "   使用 Task 工具委派給 DEVELOPER agent：" >&2
echo "" >&2
echo "   Task(" >&2
echo "     subagent_type='claude-workflow:developer'," >&2
echo "     prompt='你的任務描述'" >&2
echo "   )" >&2
echo "" >&2
echo "💡 為什麼？" >&2
echo "   D→R→T 工作流確保所有程式碼變更經過：" >&2
echo "   DEVELOPER → REVIEWER → TESTER" >&2
echo "" >&2

# 輸出 JSON 阻擋決策到 stdout（供 Claude Code 解析）
cat << EOF
{
  "decision": "block",
  "reason": "Main Agent 禁止直接使用 '$TOOL_NAME'，必須透過 Task 工具委派給 DEVELOPER agent。這是 D→R→T 工作流的強制要求。"
}
EOF

exit 0
