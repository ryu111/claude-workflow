#!/bin/bash
# global-workflow-guard.sh - 全局工作流守衛
# 事件: PreToolUse (Write|Edit|Bash|NotebookEdit)
# 功能: 阻擋 Main Agent 直接使用檔案修改工具，強制透過 DEVELOPER agent
# 2025 AI Guardrails: Tool-Level Enforcement Pattern

# ═══════════════════════════════════════════════════════════════
# 配置
# ═══════════════════════════════════════════════════════════════

DEBUG_LOG="/tmp/claude-workflow-debug.log"

# 讀取 stdin 的 JSON 輸入（必須先讀取才能解析 session_id）
INPUT=$(cat)

# 從 JSON 輸入讀取 session_id（與 agent-status-display.sh 一致）
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "null" ]; then
    # Fallback to environment variable
    SESSION_ID="${CLAUDE_SESSION_ID:-default}"
fi
AGENT_STATE_FILE="/tmp/claude-agent-state-${SESSION_ID}"

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
STATE_DIR="${PWD}/.drt-state"
mkdir -p "$STATE_DIR" 2>/dev/null
BYPASS_FILE="${STATE_DIR}/.drt-bypass"
if [ -f "$BYPASS_FILE" ]; then
    echo "[$(date)] BYPASS: config file" >> "$DEBUG_LOG"
    exit 0
fi

# 自動執行模式已移除（v0.5.15）
# D→R→T 阻擋已經足夠控制流程

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
# Bash 命令檢查（簡化版 v0.6）
# 核心原則：只阻擋「檔案寫入」操作，其他全部允許
# ═══════════════════════════════════════════════════════════════

if [ "$TOOL_NAME" = "Bash" ] && [ "$IS_SUBAGENT" = false ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    echo "[$(date)] Bash command: $COMMAND" >> "$DEBUG_LOG"

    # 移除安全的重定向（不會寫入檔案）：
    # - 2>/dev/null, >/dev/null, 1>/dev/null（丟棄輸出）
    # - 2>&1, 1>&2（合併輸出流）
    COMMAND_SANITIZED=$(echo "$COMMAND" | sed -E 's/[0-9]*>(&[0-9]+|\/dev\/null)//g')
    echo "[$(date)] Sanitized command: $COMMAND_SANITIZED" >> "$DEBUG_LOG"

    # ═══════════════════════════════════════════════════════════════
    # 檔案寫入檢測（唯一的阻擋條件）
    # ═══════════════════════════════════════════════════════════════
    #
    # 阻擋的操作：
    #   > file     覆寫寫入（但不是 >&2 這類流重定向）
    #   >> file    追加寫入
    #   tee file   寫入檔案（但允許 tee /dev/null）
    #
    # 允許的操作：
    #   |          管道（git log | head）
    #   $()        命令替換
    #   ``         反引號命令替換
    #   所有讀取命令（cat, grep, find, git, npm, etc.）
    #
    # ═══════════════════════════════════════════════════════════════

    FILE_WRITE_PATTERN='(^|[;&[:space:]])(>>?)[[:space:]]*[^&[:space:]]|[[:space:]]tee[[:space:]]'

    if echo "$COMMAND_SANITIZED" | grep -qE "$FILE_WRITE_PATTERN"; then
        echo "[$(date)] Bash command blocked (file write detected)" >> "$DEBUG_LOG"
        # 繼續執行阻擋邏輯
    else
        echo "[$(date)] Bash command allowed (no file write)" >> "$DEBUG_LOG"
        exit 0
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 黑名單檢查（簡化版：只阻擋程式碼檔案和保護目錄）
# ═══════════════════════════════════════════════════════════════

# 程式碼檔案副檔名正則（需要 D→R→T）
CODE_FILE_PATTERN='\.(ts|tsx|js|jsx|py|sh|go|java|c|cpp|h|hpp|cs|sql|rs|rb|swift|kt|scala|php|lua|pl|r)$'

# 保護目錄正則（需要 D→R→T）
PROTECTED_DIRS='(^|/)hooks/|(^|/)agents/|(^|/)\.claude-plugin/'

# 簡化判斷：是否需要 D→R→T
needs_drt() {
    local file_path="$1"

    # 檢查是否為保護目錄
    if [[ "$file_path" =~ $PROTECTED_DIRS ]]; then
        echo "[$(date)] Blacklist: protected directory ($file_path)" >> "$DEBUG_LOG"
        return 0
    fi

    # 檢查是否為程式碼檔案
    if [[ "$file_path" =~ $CODE_FILE_PATTERN ]]; then
        echo "[$(date)] Blacklist: code file ($file_path)" >> "$DEBUG_LOG"
        return 0
    fi

    # 其他檔案允許 Main Agent 直接操作
    echo "[$(date)] Blacklist: allowed (non-code, non-protected: $file_path)" >> "$DEBUG_LOG"
    return 1
}

# ═══════════════════════════════════════════════════════════════
# 工具白名單（Main Agent 允許使用的唯讀工具）
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
# Write/Edit 工具的黑名單檢查
# ═══════════════════════════════════════════════════════════════

# 對於 Write/Edit 工具，進行黑名單檢查
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    echo "[$(date)] DEBUG: FILE_PATH=$FILE_PATH" >> "$DEBUG_LOG"

    # 容錯處理：如果無法解析 FILE_PATH
    if [ -z "$FILE_PATH" ]; then
        echo "[$(date)] WARNING: Failed to parse file_path for $TOOL_NAME, using conservative blocking" >> "$DEBUG_LOG"
        BLOCK_REASON="failed to parse file_path (conservative blocking)"
        # 繼續執行阻擋邏輯（不 exit）
    else
        # 黑名單檢查：只有程式碼和保護目錄需要 D→R→T
        if ! needs_drt "$FILE_PATH"; then
            echo "[$(date)] ✅ Blacklist: Main Agent allowed to modify $FILE_PATH (non-code, non-protected)" >> "$DEBUG_LOG"
            exit 0  # 允許 Main Agent 直接修改
        else
            # 需要 D→R→T，繼續執行阻擋邏輯
            if [[ "$FILE_PATH" =~ $PROTECTED_DIRS ]]; then
                BLOCK_REASON="保護目錄 (hooks/agents/.claude-plugin/)"
            elif [[ "$FILE_PATH" =~ $CODE_FILE_PATTERN ]]; then
                BLOCK_REASON="程式碼檔案 (*.${FILE_PATH##*.})"
            else
                BLOCK_REASON="受保護資源"
            fi
            echo "[$(date)] 🚫 Blacklist: blocked - $BLOCK_REASON: $FILE_PATH" >> "$DEBUG_LOG"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 阻擋 Main Agent 使用禁止的工具
# ═══════════════════════════════════════════════════════════════

echo "[$(date)] BLOCKED: Main Agent attempting to use '$TOOL_NAME'" >> "$DEBUG_LOG"

# 判斷阻擋原因的詳細資訊
DETAILED_REASON=""
if [ -n "${FILE_PATH:-}" ] && [ -n "${BLOCK_REASON:-}" ]; then
    DETAILED_REASON="檔案 '$FILE_PATH' 是 $BLOCK_REASON"
else
    DETAILED_REASON="工具 '$TOOL_NAME' 需要透過 DEVELOPER agent"
fi

# 輸出阻擋訊息到 stderr（顯示給用戶）
echo "" >&2
echo "╔════════════════════════════════════════════════════════════════╗" >&2
echo "║             🚫 D→R→T 工作流違規                                ║" >&2
echo "╚════════════════════════════════════════════════════════════════╝" >&2
echo "" >&2
echo "❌ Main Agent 禁止直接修改：$DETAILED_REASON" >&2
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
echo "📝 規則說明：" >&2
echo "   🚫 需要 D→R→T 流程的資源：" >&2
echo "      • 程式碼檔案（.ts/.js/.py/.sh 等）" >&2
echo "      • 保護目錄（hooks/, agents/, .claude-plugin/）" >&2
echo "" >&2
echo "   ✅ Main Agent 可直接修改：" >&2
echo "      • 文檔（.md, .txt）" >&2
echo "      • 配置（.json, .yaml, .toml）在非保護目錄" >&2
echo "      • 其他非程式碼檔案" >&2
echo "" >&2

# 輸出 JSON 阻擋決策到 stdout（供 Claude Code 解析）
cat << EOF
{
  "decision": "block",
  "reason": "Main Agent 禁止直接使用 '$TOOL_NAME'：$DETAILED_REASON。必須透過 Task 工具委派給 DEVELOPER agent。這是 D→R→T 工作流的強制要求。"
}
EOF

exit 0
