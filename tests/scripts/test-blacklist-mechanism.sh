#!/bin/bash
# 測試黑名單機制

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD_SCRIPT="$PROJECT_ROOT/hooks/scripts/global-workflow-guard.sh"

# 測試函式
source "$GUARD_SCRIPT" 2>/dev/null || true

# 顏色輸出
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 測試計數器
TESTS_PASSED=0
TESTS_FAILED=0

# 測試輔助函式
test_case() {
    local description="$1"
    local file_path="$2"
    local expected="$3"  # "ALLOW" or "BLOCK"

    echo -n "Testing: $description ... "

    if needs_drt "$file_path"; then
        result="BLOCK"
    else
        result="ALLOW"
    fi

    if [ "$result" = "$expected" ]; then
        echo -e "${GREEN}✓ PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL (expected: $expected, got: $result)${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          黑名單機制測試                                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試案例：應該 ALLOW 的檔案
# ═══════════════════════════════════════════════════════════════

echo "## 測試 1: 應該允許的檔案（非程式碼、非核心目錄）"
echo ""

test_case "Markdown 文件" "CLAUDE.md" "ALLOW"
test_case "Command 文件" "commands/resume.md" "ALLOW"
test_case "Skill 文件" "skills/drt-rules/SKILL.md" "ALLOW"
test_case "README" "README.md" "ALLOW"
test_case "JSON 配置" ".claude/config.json" "ALLOW"
test_case "YAML 配置" "config.yaml" "ALLOW"
test_case "文字檔案" "notes.txt" "ALLOW"
test_case "TOML 配置" "pyproject.toml" "ALLOW"
test_case "環境變數範例" ".env.example" "ALLOW"

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試案例：應該 BLOCK 的檔案（程式碼檔案）
# ═══════════════════════════════════════════════════════════════

echo "## 測試 2: 應該阻擋的檔案（程式碼檔案）"
echo ""

test_case "TypeScript 檔案" "src/utils.ts" "BLOCK"
test_case "JavaScript 檔案" "src/app.js" "BLOCK"
test_case "Python 檔案" "scripts/deploy.py" "BLOCK"
test_case "Shell 腳本" "build.sh" "BLOCK"
test_case "Go 檔案" "main.go" "BLOCK"
test_case "Java 檔案" "Main.java" "BLOCK"
test_case "Rust 檔案" "main.rs" "BLOCK"
test_case "C++ 檔案" "main.cpp" "BLOCK"

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試案例：應該 BLOCK 的檔案（核心目錄）
# ═══════════════════════════════════════════════════════════════

echo "## 測試 3: 應該阻擋的檔案（核心目錄）"
echo ""

test_case "Hook 腳本" "hooks/scripts/global-workflow-guard.sh" "BLOCK"
test_case "Hook 配置" "hooks/hooks.json" "BLOCK"
test_case "Agent 定義" "agents/developer.md" "BLOCK"
test_case "Agent JSON" "agents/developer.json" "BLOCK"
test_case "Plugin 配置" ".claude-plugin/plugin.json" "BLOCK"

echo ""

# ═══════════════════════════════════════════════════════════════
# 邊界測試
# ═══════════════════════════════════════════════════════════════

echo "## 測試 4: 邊界情況"
echo ""

test_case "Hook 文檔（核心目錄）" "hooks/README.md" "BLOCK"
test_case "Skills 目錄中的 sh 檔案" "skills/examples/example.sh" "BLOCK"
test_case "Tests 目錄中的 py 檔案" "tests/test_app.py" "BLOCK"
test_case "Docs 目錄中的 md 檔案" "docs/guide.md" "ALLOW"

echo ""

# ═══════════════════════════════════════════════════════════════
# 測試結果
# ═══════════════════════════════════════════════════════════════

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          測試結果                                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "通過: $TESTS_PASSED"
echo "失敗: $TESTS_FAILED"
echo "總計: $((TESTS_PASSED + TESTS_FAILED))"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 所有測試通過！${NC}"
    exit 0
else
    echo -e "${RED}✗ 有 $TESTS_FAILED 個測試失敗${NC}"
    exit 1
fi
