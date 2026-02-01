#!/bin/bash
# test-ts-067-memory-acl.sh - Agent 存取控制 (ACL) 函式庫測試
# 驗證: hooks/scripts/lib/memory-acl.sh 核心功能

echo "=== TS-067: Agent 存取控制 (ACL) 函式庫測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_UNDER_TEST="$PROJECT_ROOT/hooks/scripts/lib/memory-acl.sh"

# 建立臨時測試檔案
TEST_DIR=$(mktemp -d)
TEST_MEMORY_FILE="$TEST_DIR/test-memory.md"

# 清理函式
cleanup() {
    rm -rf "$TEST_DIR"
}

trap cleanup EXIT

# ============================================================
# 測試 0: 腳本存在性與語法正確性
# ============================================================

echo "【測試 0】腳本存在性與語法正確性"

if [ ! -f "$SCRIPT_UNDER_TEST" ]; then
    echo "❌ memory-acl.sh 不存在，路徑: $SCRIPT_UNDER_TEST"
    exit 1
fi

echo "✓ memory-acl.sh 已找到"

# 語法檢查
if bash -n "$SCRIPT_UNDER_TEST" 2>&1; then
    echo "✓ 語法檢查通過"
else
    echo "✗ 語法錯誤"
    exit 1
fi

echo ""

# ============================================================
# 測試 1: 載入函式庫
# ============================================================

echo "【測試 1】載入函式庫"

# 切換到專案根目錄（讓腳本能找到依賴）
cd "$PROJECT_ROOT" || exit 1

# Source 函式庫
if source "$SCRIPT_UNDER_TEST" 2>&1; then
    echo "✓ 函式庫載入成功"
else
    echo "✗ 函式庫載入失敗"
    exit 1
fi

echo ""

# ============================================================
# 測試 2: 常數定義
# ============================================================

echo "【測試 2】常數定義檢查"

TEST2_PASS=true

# 檢查 ACL 返回碼常數
for const_name in \
    ACL_EXIT_ALLOWED \
    ACL_EXIT_DENIED \
    ACL_EXIT_FILE_ERROR
do
    const_value="${!const_name}"
    if [ -n "$const_value" ]; then
        echo "  ✓ $const_name = $const_value"
    else
        echo "  ✗ $const_name 未定義"
        TEST2_PASS=false
    fi
done

echo ""

if [ "$TEST2_PASS" = false ]; then
    echo "❌ 常數定義檢查失敗"
    exit 1
fi

# ============================================================
# 測試 3: 核心函式定義檢查
# ============================================================

echo "【測試 3】核心函式定義檢查"

TEST3_PASS=true

# 檢查必要函式是否定義
for func_name in \
    get_allowed_agents \
    get_forbidden_agents \
    is_agent_allowed \
    check_memory_access \
    show_acl_help
do
    if declare -f "$func_name" >/dev/null 2>&1; then
        echo "  ✓ 函式 '$func_name' 已定義"
    else
        echo "  ✗ 函式 '$func_name' 未定義"
        TEST3_PASS=false
    fi
done

echo ""

if [ "$TEST3_PASS" = false ]; then
    echo "❌ 核心函式定義檢查失敗"
    exit 1
fi

# ============================================================
# 測試 4: CLI 命令測試 - help
# ============================================================

echo "【測試 4】CLI 命令測試 - help"

HELP_OUTPUT=$(bash "$SCRIPT_UNDER_TEST" help 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✓ help 命令執行成功"
else
    echo "  ✗ help 命令執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

# 檢查輸出包含關鍵資訊
if echo "$HELP_OUTPUT" | grep -q "用法" && \
   echo "$HELP_OUTPUT" | grep -q "check_memory_access" && \
   echo "$HELP_OUTPUT" | grep -q "allowed_agents"; then
    echo "  ✓ help 輸出包含預期資訊"
else
    echo "  ✗ help 輸出不完整"
    exit 1
fi

echo ""

# ============================================================
# 測試 5: 建立測試記憶檔案
# ============================================================

echo "【測試 5】建立測試記憶檔案"

cat > "$TEST_MEMORY_FILE" <<'EOF'
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
EOF

if [ -f "$TEST_MEMORY_FILE" ]; then
    echo "  ✓ 測試記憶檔案建立成功: $TEST_MEMORY_FILE"
else
    echo "  ✗ 測試記憶檔案建立失敗"
    exit 1
fi

echo ""

# ============================================================
# 測試 6: get_allowed_agents 函式
# ============================================================

echo "【測試 6】get_allowed_agents 函式"

ALLOWED_AGENTS=$(get_allowed_agents "$TEST_MEMORY_FILE" 2>/dev/null)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✓ get_allowed_agents 執行成功"
else
    echo "  ✗ get_allowed_agents 執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

# 檢查是否包含預期的 Agent
if echo "$ALLOWED_AGENTS" | grep -q "reviewer" && \
   echo "$ALLOWED_AGENTS" | grep -q "tester"; then
    echo "  ✓ 找到預期的 allowed_agents (reviewer, tester)"
else
    echo "  ✗ allowed_agents 解析錯誤"
    echo "  得到: $ALLOWED_AGENTS"
    exit 1
fi

echo ""

# ============================================================
# 測試 7: get_forbidden_agents 函式
# ============================================================

echo "【測試 7】get_forbidden_agents 函式"

FORBIDDEN_AGENTS=$(get_forbidden_agents "$TEST_MEMORY_FILE" 2>/dev/null)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✓ get_forbidden_agents 執行成功"
else
    echo "  ✗ get_forbidden_agents 執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

# 檢查是否包含預期的 Agent
if echo "$FORBIDDEN_AGENTS" | grep -q "developer"; then
    echo "  ✓ 找到預期的 forbidden_agents (developer)"
else
    echo "  ✗ forbidden_agents 解析錯誤"
    echo "  得到: $FORBIDDEN_AGENTS"
    exit 1
fi

echo ""

# ============================================================
# 測試 8: is_agent_allowed 函式 - 允許的 Agent
# ============================================================

echo "【測試 8】is_agent_allowed 函式 - 允許的 Agent"

# 測試 reviewer (在 allowed_agents 中)
if is_agent_allowed "reviewer" "$ALLOWED_AGENTS" "$FORBIDDEN_AGENTS"; then
    echo "  ✓ reviewer 允許存取"
else
    echo "  ✗ reviewer 應該允許存取"
    exit 1
fi

# 測試 tester (在 allowed_agents 中)
if is_agent_allowed "tester" "$ALLOWED_AGENTS" "$FORBIDDEN_AGENTS"; then
    echo "  ✓ tester 允許存取"
else
    echo "  ✗ tester 應該允許存取"
    exit 1
fi

echo ""

# ============================================================
# 測試 9: is_agent_allowed 函式 - 禁止的 Agent
# ============================================================

echo "【測試 9】is_agent_allowed 函式 - 禁止的 Agent"

# 測試 developer (在 forbidden_agents 中)
if ! is_agent_allowed "developer" "$ALLOWED_AGENTS" "$FORBIDDEN_AGENTS"; then
    echo "  ✓ developer 拒絕存取"
else
    echo "  ✗ developer 應該拒絕存取"
    exit 1
fi

echo ""

# ============================================================
# 測試 10: is_agent_allowed 函式 - 不在列表中的 Agent
# ============================================================

echo "【測試 10】is_agent_allowed 函式 - 不在列表中的 Agent"

# 測試 architect (不在 allowed_agents 中，應拒絕)
if ! is_agent_allowed "architect" "$ALLOWED_AGENTS" "$FORBIDDEN_AGENTS"; then
    echo "  ✓ architect 拒絕存取（不在 allowed_agents）"
else
    echo "  ✗ architect 應該拒絕存取"
    exit 1
fi

echo ""

# ============================================================
# 測試 11: check_memory_access 函式 - 允許存取
# ============================================================

echo "【測試 11】check_memory_access 函式 - 允許存取"

# 使用 CLI 模式避免函式調用問題
bash "$SCRIPT_UNDER_TEST" check "reviewer" "$TEST_MEMORY_FILE" >/dev/null 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq $ACL_EXIT_ALLOWED ]; then
    echo "  ✓ reviewer 存取檢查通過"
else
    echo "  ✗ reviewer 存取檢查失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

echo ""

# ============================================================
# 測試 12: check_memory_access 函式 - 拒絕存取
# ============================================================

echo "【測試 12】check_memory_access 函式 - 拒絕存取"

# 使用 CLI 模式避免函式調用問題
bash "$SCRIPT_UNDER_TEST" check "developer" "$TEST_MEMORY_FILE" >/dev/null 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq $ACL_EXIT_DENIED ]; then
    echo "  ✓ developer 存取檢查正確拒絕"
else
    echo "  ✗ developer 存取檢查失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

echo ""

# ============================================================
# 測試 13: check_memory_access 函式 - 檔案不存在
# ============================================================

echo "【測試 13】check_memory_access 函式 - 檔案不存在"

# 使用 CLI 模式避免函式調用問題
bash "$SCRIPT_UNDER_TEST" check "reviewer" "/nonexistent/file.md" >/dev/null 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq $ACL_EXIT_FILE_ERROR ]; then
    echo "  ✓ 檔案不存在時返回檔案錯誤"
else
    echo "  ✗ 檔案錯誤處理失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

echo ""

# ============================================================
# 測試 14: CLI 命令測試 - check
# ============================================================

echo "【測試 14】CLI 命令測試 - check"

# 測試允許的 Agent
bash "$SCRIPT_UNDER_TEST" check "reviewer" "$TEST_MEMORY_FILE" 2>/dev/null
EXIT_CODE=$?

if [ $EXIT_CODE -eq $ACL_EXIT_ALLOWED ]; then
    echo "  ✓ CLI check 命令測試通過（允許）"
else
    echo "  ✗ CLI check 命令測試失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

# 測試拒絕的 Agent
bash "$SCRIPT_UNDER_TEST" check "developer" "$TEST_MEMORY_FILE" 2>/dev/null
EXIT_CODE=$?

if [ $EXIT_CODE -eq $ACL_EXIT_DENIED ]; then
    echo "  ✓ CLI check 命令測試通過（拒絕）"
else
    echo "  ✗ CLI check 命令測試失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

echo ""

# ============================================================
# 測試 15: CLI 命令測試 - allowed
# ============================================================

echo "【測試 15】CLI 命令測試 - allowed"

ALLOWED_OUTPUT=$(bash "$SCRIPT_UNDER_TEST" allowed "$TEST_MEMORY_FILE" 2>/dev/null)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✓ CLI allowed 命令執行成功"
else
    echo "  ✗ CLI allowed 命令執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

if echo "$ALLOWED_OUTPUT" | grep -q "reviewer" && \
   echo "$ALLOWED_OUTPUT" | grep -q "tester"; then
    echo "  ✓ CLI allowed 輸出包含預期 Agent"
else
    echo "  ✗ CLI allowed 輸出錯誤"
    exit 1
fi

echo ""

# ============================================================
# 測試 16: CLI 命令測試 - forbidden
# ============================================================

echo "【測試 16】CLI 命令測試 - forbidden"

FORBIDDEN_OUTPUT=$(bash "$SCRIPT_UNDER_TEST" forbidden "$TEST_MEMORY_FILE" 2>/dev/null)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✓ CLI forbidden 命令執行成功"
else
    echo "  ✗ CLI forbidden 命令執行失敗 (exit code: $EXIT_CODE)"
    exit 1
fi

if echo "$FORBIDDEN_OUTPUT" | grep -q "developer"; then
    echo "  ✓ CLI forbidden 輸出包含預期 Agent"
else
    echo "  ✗ CLI forbidden 輸出錯誤"
    exit 1
fi

echo ""

# ============================================================
# 測試 17: 無 frontmatter 的檔案（無限制）
# ============================================================

echo "【測試 17】無 frontmatter 的檔案（無限制）"

NO_FM_FILE="$TEST_DIR/no-frontmatter.md"
cat > "$NO_FM_FILE" <<'EOF'
# 無 frontmatter 的記憶檔案

所有 Agent 都可存取。
EOF

# 任何 Agent 都應該允許存取
for agent in "developer" "reviewer" "tester" "architect"; do
    # 使用 CLI 模式
    if bash "$SCRIPT_UNDER_TEST" check "$agent" "$NO_FM_FILE" >/dev/null 2>&1; then
        echo "  ✓ $agent 允許存取（無限制）"
    else
        echo "  ✗ $agent 應該允許存取"
        exit 1
    fi
done

echo ""

# ============================================================
# 測試 18: 大小寫不敏感
# ============================================================

echo "【測試 18】大小寫不敏感"

# 測試大寫 REVIEWER
if bash "$SCRIPT_UNDER_TEST" check "REVIEWER" "$TEST_MEMORY_FILE" >/dev/null 2>&1; then
    echo "  ✓ REVIEWER（大寫）允許存取"
else
    echo "  ✗ 大小寫不敏感失敗"
    exit 1
fi

# 測試大寫 DEVELOPER
if ! bash "$SCRIPT_UNDER_TEST" check "DEVELOPER" "$TEST_MEMORY_FILE" >/dev/null 2>&1; then
    echo "  ✓ DEVELOPER（大寫）拒絕存取"
else
    echo "  ✗ 大小寫不敏感失敗"
    exit 1
fi

echo ""

# ============================================================
# 總結
# ============================================================

echo "═══════════════════════════════════════════════════"
echo "測試摘要"
echo "═══════════════════════════════════════════════════"
echo ""

echo "✓ 基礎檢查："
echo "  - 腳本存在: PASS"
echo "  - 語法正確: PASS"
echo "  - 函式庫載入: PASS"
echo ""

echo "✓ 組件驗證："
echo "  - 常數定義: PASS (3 個返回碼常數)"
echo "  - 核心函式: PASS (5 個核心函式)"
echo "  - CLI 命令: PASS (help, check, allowed, forbidden)"
echo ""

echo "✓ 功能測試："
echo "  - get_allowed_agents: PASS"
echo "  - get_forbidden_agents: PASS"
echo "  - is_agent_allowed: PASS"
echo "  - check_memory_access: PASS"
echo "  - 無 frontmatter 處理: PASS"
echo "  - 大小寫不敏感: PASS"
echo ""

echo "✅ TS-067 PASS: Agent 存取控制 (ACL) 函式庫功能正確"
exit 0
