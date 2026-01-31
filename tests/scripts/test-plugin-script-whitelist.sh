#!/bin/bash
# test-plugin-script-whitelist.sh - 測試 Plugin 腳本白名單功能

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_SCRIPT="${SCRIPT_DIR}/../../hooks/scripts/global-workflow-guard.sh"

# 顏色輸出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 測試計數器
TESTS_PASSED=0
TESTS_FAILED=0

# 測試輔助函數
test_command() {
    local description="$1"
    local command="$2"
    local should_pass="$3"  # "pass" or "block"

    # 模擬 Main Agent 執行 Bash 命令
    export CLAUDE_SESSION_ID="test-$$"
    AGENT_STATE_FILE="/tmp/claude-agent-state-${CLAUDE_SESSION_ID}"
    echo "main" > "$AGENT_STATE_FILE"

    # 構造輸入 JSON
    INPUT_JSON=$(cat <<EOF
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "$command"
  }
}
EOF
)

    # 執行守衛腳本
    RESULT=$(echo "$INPUT_JSON" | bash "$GUARD_SCRIPT" 2>/dev/null || true)
    DECISION=$(echo "$RESULT" | jq -r '.decision // "allow"' 2>/dev/null || echo "allow")

    # 判斷測試結果
    if [ "$should_pass" = "pass" ] && [ "$DECISION" != "block" ]; then
        echo -e "${GREEN}✓${NC} PASS: $description"
        ((TESTS_PASSED++))
    elif [ "$should_pass" = "block" ] && [ "$DECISION" = "block" ]; then
        echo -e "${GREEN}✓${NC} BLOCK: $description"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} FAIL: $description (expected: $should_pass, got: $DECISION)"
        ((TESTS_FAILED++))
    fi

    # 清理
    rm -f "$AGENT_STATE_FILE"
}

echo "════════════════════════════════════════════════════════════"
echo "測試 Plugin 腳本白名單功能"
echo "════════════════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════
# Plugin 腳本白名單測試
# ═══════════════════════════════════════════════════════════════

echo "🔹 Plugin 腳本白名單測試"
echo ""

test_command \
    "ralph-wiggum setup-ralph-loop.sh" \
    "bash ~/.claude/plugins/cache/ralph-wiggum/ralph-wiggum/1.0.0/setup-ralph-loop.sh --arg1 value1" \
    "pass"

test_command \
    "claude-workflow init.sh" \
    "bash /path/to/claude-workflow/scripts/init.sh" \
    "pass"

test_command \
    "claude-workflow validate-agents.sh" \
    "bash ~/projects/claude-workflow/scripts/validate-agents.sh" \
    "pass"

test_command \
    "claude-workflow validate-skills.sh" \
    "bash ./claude-workflow/scripts/validate-skills.sh" \
    "pass"

echo ""

# ═══════════════════════════════════════════════════════════════
# 擴展的 Git 命令白名單測試
# ═══════════════════════════════════════════════════════════════

echo "🔹 擴展的 Git 命令白名單測試"
echo ""

test_command \
    "git rev-list" \
    "git rev-list HEAD~5..HEAD" \
    "pass"

test_command \
    "git describe" \
    "git describe --tags --abbrev=0" \
    "pass"

test_command \
    "git shortlog" \
    "git shortlog -s -n" \
    "pass"

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試與格式化命令白名單測試
# ═══════════════════════════════════════════════════════════════

echo "🔹 測試與格式化命令白名單測試"
echo ""

test_command \
    "npm run lint" \
    "npm run lint" \
    "pass"

test_command \
    "npm run check" \
    "npm run check" \
    "pass"

test_command \
    "prettier --check" \
    "prettier --check src/" \
    "pass"

test_command \
    "black --check" \
    "black --check ." \
    "pass"

test_command \
    "ruff check" \
    "ruff check src/" \
    "pass"

test_command \
    "go test" \
    "go test ./..." \
    "pass"

test_command \
    "cargo test" \
    "cargo test --all" \
    "pass"

echo ""

# ═══════════════════════════════════════════════════════════════
# 環境資訊命令白名單測試
# ═══════════════════════════════════════════════════════════════

echo "🔹 環境資訊命令白名單測試"
echo ""

test_command \
    "env" \
    "env" \
    "pass"

test_command \
    "printenv" \
    "printenv PATH" \
    "pass"

test_command \
    "go version" \
    "go version" \
    "pass"

test_command \
    "cargo --version" \
    "cargo --version" \
    "pass"

test_command \
    "rustc --version" \
    "rustc --version" \
    "pass"

echo ""

# ═══════════════════════════════════════════════════════════════
# 搜尋工具命令白名單測試
# ═══════════════════════════════════════════════════════════════

echo "🔹 搜尋工具命令白名單測試"
echo ""

test_command \
    "rg (ripgrep)" \
    "rg 'pattern' src/" \
    "pass"

test_command \
    "ag (the silver searcher)" \
    "ag 'pattern' src/" \
    "pass"

test_command \
    "yq" \
    "yq eval '.version' config.yaml" \
    "pass"

echo ""

# ═══════════════════════════════════════════════════════════════
# 危險命令阻擋測試
# ═══════════════════════════════════════════════════════════════

echo "🔹 危險命令阻擋測試"
echo ""

test_command \
    "rm 命令（應阻擋）" \
    "rm -rf /tmp/test" \
    "block"

test_command \
    "重定向輸出（應阻擋）" \
    "echo 'test' > file.txt" \
    "block"

test_command \
    "管道加 tee（應阻擋）" \
    "cat file | tee output.txt" \
    "block"

test_command \
    "Command substitution（應阻擋）" \
    "echo \$(whoami)" \
    "block"

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試摘要
# ═══════════════════════════════════════════════════════════════

echo "════════════════════════════════════════════════════════════"
echo "測試摘要"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "總測試數: $((TESTS_PASSED + TESTS_FAILED))"
echo -e "${GREEN}通過: ${TESTS_PASSED}${NC}"
echo -e "${RED}失敗: ${TESTS_FAILED}${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 所有測試通過！${NC}"
    exit 0
else
    echo -e "${RED}✗ 有測試失敗${NC}"
    exit 1
fi
