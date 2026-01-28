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

# ═══════════════════════════════════════════════════════════════
# 自動執行模式檢查
# ═══════════════════════════════════════════════════════════════

AUTO_EXEC_FILE="${STATE_DIR}/.auto-execute-pending"

# ═══════════════════════════════════════════════════════════════
# Bug Fix 2: 檢查退出關鍵字（從 user_prompt 中偵測）
# ═══════════════════════════════════════════════════════════════
# 檢查是否有用戶輸入（user_prompt）包含退出關鍵字
USER_PROMPT=$(echo "$INPUT" | jq -r '.user_prompt // empty' 2>/dev/null)
if [ -n "$USER_PROMPT" ]; then
    # 退出關鍵字清單
    if echo "$USER_PROMPT" | grep -qiE '(解鎖|unlock|取消自動執行|退出.*workflow|debug|診斷)'; then
        echo "[$(date)] Auto-execute exit keyword detected: clearing state" >> "$DEBUG_LOG"
        rm -f "$AUTO_EXEC_FILE" 2>/dev/null
        echo "" >&2
        echo "✅ 已退出自動執行模式" >&2
        echo "" >&2
        exit 0
    fi
fi

if [ -f "$AUTO_EXEC_FILE" ]; then
    # 讀取自動執行狀態
    AUTO_EXEC_CHANGE_ID=$(jq -r '.change_id // empty' "$AUTO_EXEC_FILE" 2>/dev/null)

    if [ -n "$AUTO_EXEC_CHANGE_ID" ]; then
        echo "[$(date)] Auto-execute mode active: $AUTO_EXEC_CHANGE_ID" >> "$DEBUG_LOG"

        # 解析工具名稱（提前解析以供檢查）
        TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

        # 檢查是否為允許的操作
        case "$TOOL_NAME" in
            Read|Glob|Grep|Task|WebFetch|WebSearch)
                # 允許這些工具（唯讀和查詢操作）
                echo "[$(date)] Auto-execute: allowing $TOOL_NAME" >> "$DEBUG_LOG"
                ;;
            Bash)
                # 只允許 mv 命令（移動 specs → changes）
                COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
                if echo "$COMMAND" | grep -qE "^mv.*openspec/specs.*openspec/changes"; then
                    echo "[$(date)] Auto-execute: allowing mv command" >> "$DEBUG_LOG"
                    # 移動完成後，清除自動執行狀態
                    # 注意：這是 PreToolUse Hook，我們假設 mv 會成功
                    # 如果失敗，用戶重新執行時會再次嘗試
                    rm -f "$AUTO_EXEC_FILE"
                    echo "[$(date)] Auto-execute: cleared pending state after mv" >> "$DEBUG_LOG"
                    exit 0  # 允許 mv 命令執行
                else
                    # Bug Fix 3: 檢查是否為診斷用的唯讀命令（擴展版）
                    # Bash 診斷命令白名單：基本、文件檢查、git 唯讀
                    if echo "$COMMAND" | grep -qE '^(ls|find|cat|head|tail|echo|pwd|wc|grep|diff|file|stat|which|type|env|date|whoami|hostname)(\s|$)'; then
                        echo "[$(date)] Auto-execute: allowing diagnostic read-only command" >> "$DEBUG_LOG"
                        exit 0
                    fi

                    # git 唯讀命令白名單（排除危險操作）
                    if echo "$COMMAND" | grep -qE '^git\s+(status|log|diff|branch|show|remote|config)'; then
                        # 確保不包含危險子命令
                        if ! echo "$COMMAND" | grep -qE '(push|commit|reset|checkout|merge|rebase|cherry-pick|revert|stash|clean)'; then
                            echo "[$(date)] Auto-execute: allowing git read-only command" >> "$DEBUG_LOG"
                            exit 0
                        fi
                    fi

                    # 阻擋其他 Bash 命令
                    echo "" >&2
                    echo "╔════════════════════════════════════════════════════════════════╗" >&2
                    echo "║             🚫 自動執行模式 - 僅允許特定操作                    ║" >&2
                    echo "╚════════════════════════════════════════════════════════════════╝" >&2
                    echo "" >&2
                    echo "📋 當前狀態：規劃已完成，等待自動執行" >&2
                    echo "🔄 允許的操作：" >&2
                    echo "   1. mv openspec/specs/$AUTO_EXEC_CHANGE_ID openspec/changes/" >&2
                    echo "   2. Task(developer) 啟動第一個任務" >&2
                    echo "   3. 診斷命令（唯讀）：" >&2
                    echo "      - 基本：ls, find, cat, head, tail, echo, pwd" >&2
                    echo "      - 檢查：wc, grep, diff, file, stat, which, type" >&2
                    echo "      - 系統：env, date, whoami, hostname" >&2
                    echo "      - git：status, log, diff, branch, show, remote, config" >&2
                    echo "" >&2
                    echo "💡 退出自動執行模式：說「解鎖」、「unlock」、「debug」或「診斷」" >&2
                    echo "" >&2
                    cat << EOF
{
  "decision": "block",
  "reason": "自動執行模式中，僅允許移動規格和啟動 DEVELOPER。請先執行：mv openspec/specs/$AUTO_EXEC_CHANGE_ID openspec/changes/"
}
EOF
                    exit 0
                fi
                ;;
            Write)
                # Bug Fix 3: 允許寫入到 /tmp/ 或用戶桌面（診斷報告）
                FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
                if [ -n "$FILE_PATH" ]; then
                    if echo "$FILE_PATH" | grep -qE '^(/tmp/|/private/tmp/|'$HOME'/Desktop/)'; then
                        echo "[$(date)] Auto-execute: allowing Write to diagnostic location: $FILE_PATH" >> "$DEBUG_LOG"
                        exit 0
                    fi
                fi
                # 繼續阻擋邏輯
                ;;
            *)
                # 阻擋其他工具
                echo "" >&2
                echo "╔════════════════════════════════════════════════════════════════╗" >&2
                echo "║             🚫 自動執行模式 - 請先完成規格移動                  ║" >&2
                echo "╚════════════════════════════════════════════════════════════════╝" >&2
                echo "" >&2
                echo "💡 退出自動執行模式：說「解鎖」、「unlock」、「debug」或「診斷」" >&2
                echo "" >&2
                cat << EOF
{
  "decision": "block",
  "reason": "自動執行模式中。請先：1) mv specs → changes，2) Task(developer) 啟動任務"
}
EOF
                exit 0
                ;;
        esac
    fi
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

    # 先移除安全的重定向模式，再檢查危險運算符
    # 安全的重定向：2>/dev/null, 2>&1, >/dev/null, 1>/dev/null
    COMMAND_SANITIZED=$(echo "$COMMAND" | sed -E 's/[0-9]*>(&[0-9]+|\/dev\/null)//g')
    echo "[$(date)] Sanitized command: $COMMAND_SANITIZED" >> "$DEBUG_LOG"

    # 檢查是否包含寫入運算符（即使命令本身在白名單中）
    DANGEROUS_OPERATORS=">|>>|\\|.*tee|\\\`|\\$\\("
    if echo "$COMMAND_SANITIZED" | grep -qE "$DANGEROUS_OPERATORS"; then
        echo "[$(date)] Bash command blocked (contains dangerous operators)" >> "$DEBUG_LOG"
        # 繼續執行阻擋邏輯（不 exit 0）
    else
        # ═══════════════════════════════════════════════════════════════
        # 唯讀命令白名單（擴展版）
        # ═══════════════════════════════════════════════════════════════

        # 白名單：唯讀命令前綴（包含所有 git 命令、測試與格式化檢查）
        # 擴展：新增 git 唯讀命令（status, log, diff, branch, show, remote, config）
        READONLY_PATTERNS="^(git (status|log|diff|branch|show|remote|config)|ls|pwd|cat|head|tail|wc|grep|rg|ag|find|which|file|stat|du|df|date|uname|whoami|hostname|env|printenv|type|node --version|npm --version|npm list|npm ls|python --version|pip --version|pip list|pip show|go version|cargo --version|rustc --version|jq|yq|npm (test|run test|run lint|run check)|npx |yarn (test|lint)|pytest|python -m pytest|go test|cargo test|make test|prettier --check|eslint --print-config|black --check|ruff check)"

        if echo "$COMMAND" | grep -qE "$READONLY_PATTERNS"; then
            # 對於 git 命令，額外檢查是否包含危險子命令
            if echo "$COMMAND" | grep -qE '^git '; then
                if echo "$COMMAND" | grep -qE '(push|commit|reset|checkout|merge|rebase|cherry-pick|revert|stash|clean)'; then
                    echo "[$(date)] Bash command blocked (git with dangerous subcommand)" >> "$DEBUG_LOG"
                    # 繼續執行阻擋邏輯（不 exit）
                else
                    echo "[$(date)] Bash command allowed (git read-only)" >> "$DEBUG_LOG"
                    exit 0
                fi
            else
                echo "[$(date)] Bash command allowed (read-only)" >> "$DEBUG_LOG"
                exit 0
            fi
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 黑名單檢查（刪去法：只有這些需要 D→R→T）
# ═══════════════════════════════════════════════════════════════

# 程式碼副檔名（需要 D→R→T）
CODE_EXTENSIONS="ts|js|jsx|tsx|py|sh|go|java|c|cpp|h|hpp|cs|sql|rs|rb|swift|kt|scala|php|lua|pl|r"

# 核心目錄（需要 D→R→T）
CORE_DIRECTORIES=(
    "hooks/"            # 整個 hooks 目錄（包含 hooks.json 配置檔案）
    "agents/"
    ".claude-plugin/"
)

# 檢查是否為程式碼檔案
is_code_file() {
    local file_path="$1"
    local ext="${file_path##*.}"
    echo "$ext" | grep -qiE "^($CODE_EXTENSIONS)$"
}

# 檢查是否在核心目錄
is_core_directory() {
    local file_path="$1"
    for dir in "${CORE_DIRECTORIES[@]}"; do
        if [[ "$file_path" == *"$dir"* ]]; then
            return 0
        fi
    done
    return 1
}

# 判斷是否需要 D→R→T
needs_drt() {
    local file_path="$1"

    # 程式碼檔案 → 需要 D→R→T
    if is_code_file "$file_path"; then
        echo "[$(date)] Blacklist check: code file detected ($file_path)" >> "$DEBUG_LOG"
        return 0
    fi

    # 核心目錄 → 需要 D→R→T
    if is_core_directory "$file_path"; then
        echo "[$(date)] Blacklist check: core directory detected ($file_path)" >> "$DEBUG_LOG"
        return 0
    fi

    # 其他 → Main Agent 可以直接做
    echo "[$(date)] Blacklist check: allowed (non-code, non-core: $file_path)" >> "$DEBUG_LOG"
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
        # 黑名單檢查：只有程式碼和核心目錄需要 D→R→T
        if ! needs_drt "$FILE_PATH"; then
            echo "[$(date)] ✅ Blacklist: Main Agent allowed to modify $FILE_PATH (non-code, non-core)" >> "$DEBUG_LOG"
            exit 0  # 允許 Main Agent 直接修改
        else
            # 需要 D→R→T，繼續執行阻擋邏輯
            if is_code_file "$FILE_PATH"; then
                BLOCK_REASON="code file (*.${FILE_PATH##*.})"
            elif is_core_directory "$FILE_PATH"; then
                BLOCK_REASON="core directory"
            else
                BLOCK_REASON="unknown"
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
echo "📝 黑名單規則：" >&2
echo "   ✅ 允許修改：文檔(.md)、配置(.json, .yaml)、非核心目錄" >&2
echo "   🚫 需要 D→R→T：程式碼檔案、hooks/、agents/、.claude-plugin/" >&2
echo "" >&2

# 輸出 JSON 阻擋決策到 stdout（供 Claude Code 解析）
cat << EOF
{
  "decision": "block",
  "reason": "Main Agent 禁止直接使用 '$TOOL_NAME'：$DETAILED_REASON。必須透過 Task 工具委派給 DEVELOPER agent。這是 D→R→T 工作流的強制要求。"
}
EOF

exit 0
