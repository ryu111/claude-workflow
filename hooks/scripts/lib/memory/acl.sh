#!/bin/bash
# memory-acl.sh - Agent 存取控制 (ACL) 檢查
# 功能：檢查 Agent 是否有權限存取特定記憶檔案
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-acl.sh"

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 依賴檢查與載入
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入 YAML 解析工具
if [ -f "$SCRIPT_DIR/yaml-parser.sh" ]; then
    # shellcheck source=./yaml-parser.sh
    source "$SCRIPT_DIR/../core/yaml-parser.sh"
else
    echo "錯誤：找不到 yaml-parser.sh" >&2
    exit 1
fi

# 載入共用工具
if [ -f "$SCRIPT_DIR/common.sh" ]; then
    # shellcheck source=./common.sh
    source "$SCRIPT_DIR/../core/common.sh"
else
    echo "錯誤：找不到 common.sh" >&2
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

readonly ACL_EXIT_ALLOWED=0
readonly ACL_EXIT_DENIED=1
readonly ACL_EXIT_FILE_ERROR=2

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 取得允許的 Agent 列表
# 用法: get_allowed_agents memory_file
# 輸出: Agent 列表（每行一個），若無設定則輸出空字串
# 返回: 0=成功，1=檔案錯誤
get_allowed_agents() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ]; then
        echo "錯誤：get_allowed_agents 需要提供檔案路徑" >&2
        return 1
    fi

    if [ ! -f "$memory_file" ]; then
        echo "錯誤：檔案不存在: $memory_file" >&2
        return 1
    fi

    # 檢查是否有 frontmatter
    if ! has_frontmatter "$memory_file" 2>/dev/null; then
        # 無 frontmatter = 無限制，返回空字串
        return 0
    fi

    # 提取 frontmatter 區塊
    local frontmatter
    frontmatter=$(get_frontmatter_block "$memory_file" 2>/dev/null) || return 0

    # 解析 access.allowed_agents 陣列
    # 使用 awk 處理 YAML 陣列格式
    local allowed_agents
    allowed_agents=$(echo "$frontmatter" | awk '
        BEGIN { in_allowed = 0 }
        /^access:/ { in_access = 1; next }
        in_access && /^[[:space:]]+allowed_agents:/ { in_allowed = 1; next }
        in_allowed && /^[[:space:]]*-[[:space:]]*/ {
            # 提取 "- agent_name" 格式的值
            gsub(/^[[:space:]]*-[[:space:]]*/, "")
            gsub(/["\047]/, "")  # 移除引號
            print
            next
        }
        in_allowed && /^[[:space:]]+[a-z_]+:/ { in_allowed = 0 }
        in_allowed && /^[a-z_]+:/ { in_allowed = 0 }
    ')

    echo "$allowed_agents"
    return 0
}

# 取得禁止的 Agent 列表
# 用法: get_forbidden_agents memory_file
# 輸出: Agent 列表（每行一個），若無設定則輸出空字串
# 返回: 0=成功，1=檔案錯誤
get_forbidden_agents() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ]; then
        echo "錯誤：get_forbidden_agents 需要提供檔案路徑" >&2
        return 1
    fi

    if [ ! -f "$memory_file" ]; then
        echo "錯誤：檔案不存在: $memory_file" >&2
        return 1
    fi

    # 檢查是否有 frontmatter
    if ! has_frontmatter "$memory_file" 2>/dev/null; then
        # 無 frontmatter = 無限制，返回空字串
        return 0
    fi

    # 提取 frontmatter 區塊
    local frontmatter
    frontmatter=$(get_frontmatter_block "$memory_file" 2>/dev/null) || return 0

    # 解析 access.forbidden_agents 陣列
    local forbidden_agents
    forbidden_agents=$(echo "$frontmatter" | awk '
        BEGIN { in_forbidden = 0 }
        /^access:/ { in_access = 1; next }
        in_access && /^[[:space:]]+forbidden_agents:/ { in_forbidden = 1; next }
        in_forbidden && /^[[:space:]]*-[[:space:]]*/ {
            # 提取 "- agent_name" 格式的值
            gsub(/^[[:space:]]*-[[:space:]]*/, "")
            gsub(/["\047]/, "")  # 移除引號
            print
            next
        }
        in_forbidden && /^[[:space:]]+[a-z_]+:/ { in_forbidden = 0 }
        in_forbidden && /^[a-z_]+:/ { in_forbidden = 0 }
    ')

    echo "$forbidden_agents"
    return 0
}

# 判斷 Agent 是否被允許存取
# 用法: is_agent_allowed agent allowed_list forbidden_list
# 參數:
#   agent - Agent 名稱（小寫）
#   allowed_list - 允許的 Agent 列表（換行分隔）
#   forbidden_list - 禁止的 Agent 列表（換行分隔）
# 返回: 0=允許，1=拒絕
is_agent_allowed() {
    local agent="${1:-}"
    local allowed_list="${2:-}"
    local forbidden_list="${3:-}"

    if [ -z "$agent" ]; then
        echo "錯誤：is_agent_allowed 需要提供 Agent 名稱" >&2
        return 1
    fi

    # 標準化 Agent 名稱（轉小寫）
    agent=$(echo "$agent" | tr '[:upper:]' '[:lower:]')

    # 規則 1: 如果在 forbidden_agents 中 → 拒絕
    if [ -n "$forbidden_list" ]; then
        if echo "$forbidden_list" | grep -q "^${agent}$"; then
            return 1
        fi
    fi

    # 規則 2: 如果 allowed_agents 不為空且不包含此 agent → 拒絕
    if [ -n "$allowed_list" ]; then
        if ! echo "$allowed_list" | grep -q "^${agent}$"; then
            return 1
        fi
    fi

    # 規則 3: 否則 → 允許
    return 0
}

# 檢查 Agent 是否有權限存取記憶檔案（主要函式）
# 用法: check_memory_access agent memory_file
# 參數:
#   agent - Agent 名稱（如 developer, reviewer, tester）
#   memory_file - 記憶檔案路徑
# 返回:
#   0 - 允許存取
#   1 - 拒絕存取
#   2 - 檔案錯誤（不存在或無法讀取）
check_memory_access() {
    local agent="${1:-}"
    local memory_file="${2:-}"

    if [ -z "$agent" ] || [ -z "$memory_file" ]; then
        echo "錯誤：check_memory_access 需要提供 Agent 名稱和檔案路徑" >&2
        return $ACL_EXIT_FILE_ERROR
    fi

    if [ ! -f "$memory_file" ]; then
        echo "錯誤：記憶檔案不存在: $memory_file" >&2
        return $ACL_EXIT_FILE_ERROR
    fi

    # 標準化 Agent 名稱（轉小寫）
    agent=$(echo "$agent" | tr '[:upper:]' '[:lower:]')

    # 取得 ACL 列表
    local allowed_agents forbidden_agents

    allowed_agents=$(get_allowed_agents "$memory_file" 2>/dev/null) || {
        echo "錯誤：無法解析 allowed_agents" >&2
        return $ACL_EXIT_FILE_ERROR
    }

    forbidden_agents=$(get_forbidden_agents "$memory_file" 2>/dev/null) || {
        echo "錯誤：無法解析 forbidden_agents" >&2
        return $ACL_EXIT_FILE_ERROR
    }

    # 執行存取檢查
    if is_agent_allowed "$agent" "$allowed_agents" "$forbidden_agents"; then
        return $ACL_EXIT_ALLOWED
    else
        echo "❌ Agent '$agent' 無權存取此記憶檔案: $memory_file" >&2
        return $ACL_EXIT_DENIED
    fi
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_acl_help() {
    cat <<'EOF'
Agent 存取控制 (ACL) 檢查工具

用法:
  source memory-acl.sh

函式:
  check_memory_access <agent> <memory_file>
    檢查 Agent 是否有權限存取記憶檔案
    參數:
      agent       - Agent 名稱（如 developer, reviewer, tester）
      memory_file - 記憶檔案路徑
    返回:
      0 - 允許存取
      1 - 拒絕存取
      2 - 檔案錯誤

  get_allowed_agents <memory_file>
    取得記憶檔案的 allowed_agents 列表

  get_forbidden_agents <memory_file>
    取得記憶檔案的 forbidden_agents 列表

  is_agent_allowed <agent> <allowed_list> <forbidden_list>
    判斷 Agent 是否被允許（內部使用）

存取控制邏輯:
  1. 如果 agent 在 forbidden_agents 中 → 拒絕
  2. 如果 allowed_agents 不為空且 agent 不在其中 → 拒絕
  3. 否則 → 允許

Frontmatter 格式:
  ---
  access:
    allowed_agents:
      - reviewer
      - tester
    forbidden_agents:
      - developer
  ---

範例:
  # 檢查 DEVELOPER 是否可存取
  if check_memory_access "developer" ".claude/memory/MEMORY.md"; then
    echo "允許"
  else
    echo "拒絕"
  fi

  # 列出允許的 Agent
  get_allowed_agents ".claude/memory/MEMORY.md"

  # 列出禁止的 Agent
  get_forbidden_agents ".claude/memory/MEMORY.md"

返回碼:
  0 - 允許存取
  1 - 拒絕存取
  2 - 檔案錯誤
EOF
}

# ═══════════════════════════════════════════════════════════════
# CLI 介面（用於測試）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        check)
            shift
            if [ $# -lt 2 ]; then
                echo "用法: $0 check <agent> <memory_file>" >&2
                exit 1
            fi
            check_memory_access "$1" "$2"
            exit_code=$?
            if [ $exit_code -eq $ACL_EXIT_ALLOWED ]; then
                echo "✅ 允許存取"
            elif [ $exit_code -eq $ACL_EXIT_DENIED ]; then
                echo "❌ 拒絕存取"
            else
                echo "⚠️ 檔案錯誤"
            fi
            exit $exit_code
            ;;
        allowed)
            shift
            if [ $# -lt 1 ]; then
                echo "用法: $0 allowed <memory_file>" >&2
                exit 1
            fi
            echo "允許的 Agent 列表:"
            get_allowed_agents "$1"
            exit $?
            ;;
        forbidden)
            shift
            if [ $# -lt 1 ]; then
                echo "用法: $0 forbidden <memory_file>" >&2
                exit 1
            fi
            echo "禁止的 Agent 列表:"
            get_forbidden_agents "$1"
            exit $?
            ;;
        test)
            # 簡單的自我測試
            shift
            echo "=== 執行自我測試 ==="
            echo ""

            # 建立測試檔案
            TEST_FILE="/tmp/test-memory-acl-$$.md"
            cat > "$TEST_FILE" <<'TEST_EOF'
---
access:
  allowed_agents:
    - reviewer
    - tester
  forbidden_agents:
    - developer
---

# 測試記憶檔案

此檔案用於測試 ACL 功能。
TEST_EOF

            echo "測試檔案: $TEST_FILE"
            echo ""

            # 測試 1: 允許的 Agent
            echo "測試 1: REVIEWER（應允許）"
            if check_memory_access "reviewer" "$TEST_FILE" 2>/dev/null; then
                echo "✅ 通過"
            else
                echo "❌ 失敗"
            fi
            echo ""

            # 測試 2: 禁止的 Agent
            echo "測試 2: DEVELOPER（應拒絕）"
            if ! check_memory_access "developer" "$TEST_FILE" 2>/dev/null; then
                echo "✅ 通過"
            else
                echo "❌ 失敗"
            fi
            echo ""

            # 測試 3: 不在列表中的 Agent
            echo "測試 3: ARCHITECT（不在 allowed_agents，應拒絕）"
            if ! check_memory_access "architect" "$TEST_FILE" 2>/dev/null; then
                echo "✅ 通過"
            else
                echo "❌ 失敗"
            fi
            echo ""

            # 測試 4: 取得列表
            echo "測試 4: 取得 allowed_agents 列表"
            allowed=$(get_allowed_agents "$TEST_FILE")
            if echo "$allowed" | grep -q "reviewer" && echo "$allowed" | grep -q "tester"; then
                echo "✅ 通過（找到 reviewer 和 tester）"
            else
                echo "❌ 失敗"
            fi
            echo ""

            # 測試 5: 取得禁止列表
            echo "測試 5: 取得 forbidden_agents 列表"
            forbidden=$(get_forbidden_agents "$TEST_FILE")
            if echo "$forbidden" | grep -q "developer"; then
                echo "✅ 通過（找到 developer）"
            else
                echo "❌ 失敗"
            fi
            echo ""

            # 清理測試檔案
            rm -f "$TEST_FILE"

            echo "=== 測試完成 ==="
            exit 0
            ;;
        help|--help|-h|*)
            show_acl_help
            exit 0
            ;;
    esac
fi
