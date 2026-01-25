#!/bin/bash
# plugin-status-display.sh - Plugin 載入時提供 AI Context
# 事件: SessionStart
# 功能: 注入 D→R→T 工作流規則作為 AI context
# 新增: 清理休眠的 Claude 進程及其 MCP server

# ═══════════════════════════════════════════════════════════════
# MCP 進程清理（防止記憶體洩漏）
# ═══════════════════════════════════════════════════════════════

cleanup_stale_processes() {
    local cleaned=0
    local current_pid=$$

    # 找出 Sleep 狀態的 claude --resume 進程（排除當前進程的父進程鏈）
    # 這些是舊的、應該已結束但還在運行的進程
    local stale_pids=$(ps aux 2>/dev/null | grep -E "claude.*--resume" | grep " S " | awk '{print $2}')

    if [ -n "$stale_pids" ]; then
        for pid in $stale_pids; do
            # 安全檢查：不要終止自己的父進程
            local is_ancestor=false
            local check_pid=$current_pid
            while [ "$check_pid" -gt 1 ]; do
                if [ "$check_pid" = "$pid" ]; then
                    is_ancestor=true
                    break
                fi
                check_pid=$(ps -p $check_pid -o ppid= 2>/dev/null | tr -d ' ')
            done

            if [ "$is_ancestor" = false ]; then
                # 先終止該 claude 進程的子進程（包括 memory server）
                pkill -P "$pid" 2>/dev/null
                # 再終止 claude 進程本身
                kill "$pid" 2>/dev/null
                if [ $? -eq 0 ]; then
                    cleaned=$((cleaned + 1))
                fi
            fi
        done
    fi

    # 清理孤兒 memory server（父進程已不存在）
    local orphan_mem_pids=$(ps aux 2>/dev/null | grep "[m]emory server" | awk '{print $2}')
    if [ -n "$orphan_mem_pids" ]; then
        for mem_pid in $orphan_mem_pids; do
            local parent_pid=$(ps -p "$mem_pid" -o ppid= 2>/dev/null | tr -d ' ')
            # 檢查父進程是否是 claude
            if ! ps -p "$parent_pid" -o command= 2>/dev/null | grep -q "claude"; then
                kill "$mem_pid" 2>/dev/null
                if [ $? -eq 0 ]; then
                    cleaned=$((cleaned + 1))
                fi
            fi
        done
    fi

    if [ $cleaned -gt 0 ]; then
        echo "🧹 已清理 $cleaned 個休眠進程" >&2
    fi
}

# 執行清理（輸出到 stderr，不影響 JSON 輸出）
cleanup_stale_processes

# ═══════════════════════════════════════════════════════════════
# LLM Service 自動啟動
# ═══════════════════════════════════════════════════════════════

# 優先使用 CLAUDE_PLUGIN_ROOT，否則回退到 BASH_SOURCE
if [ -n "$CLAUDE_PLUGIN_ROOT" ]; then
    LLM_MANAGER="$CLAUDE_PLUGIN_ROOT/hooks/scripts/llm-service-manager.sh"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LLM_MANAGER="$SCRIPT_DIR/llm-service-manager.sh"
fi

if [ -x "$LLM_MANAGER" ]; then
    # 執行 LLM Service 管理（輸出到 stderr）
    "$LLM_MANAGER" status >&2
else
    echo "⚠️ LLM Service Manager 未找到: $LLM_MANAGER" >&2
fi

# ═══════════════════════════════════════════════════════════════
# 輸出 JSON 格式的 AI context
# ═══════════════════════════════════════════════════════════════

cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "## Claude Workflow Plugin 已啟用\n\n### D→R→T 流程強制執行中\n\n所有程式碼變更必須遵循：\n1. **DEVELOPER** 實作程式碼\n2. **REVIEWER** 審查（APPROVE/REJECT）\n3. **TESTER** 測試（PASS/FAIL）\n\n### 風險等級判定\n- 🟢 LOW（文檔、設定）→ D→T\n- 🟡 MEDIUM（一般功能）→ D→R→T\n- 🔴 HIGH（安全、API）→ D→R(opus)→T\n\n### 禁止事項\n- 跳過 REVIEWER 直接進入 TESTER\n- 硬編碼魔術字串（使用 enum/常數）\n- REVIEWER/TESTER 不得修改程式碼\n\n### 可用指令\n- `/plan [feature]` - 規劃新功能\n- `/resume [change-id]` - 接手現有工作"
  }
}
EOF

exit 0
