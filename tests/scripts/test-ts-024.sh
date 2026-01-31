#!/bin/bash
# test-ts-024.sh - Global Workflow Guard 測試
# 驗證: global-workflow-guard.sh 正確阻擋 D→R→T 工作流違規

echo "=== TS-024: Global Workflow Guard 測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="$PROJECT_ROOT/hooks/scripts/global-workflow-guard.sh"

# 檢查腳本存在
if [ ! -f "$HOOK_SCRIPT" ]; then
    echo "❌ global-workflow-guard.sh 不存在"
    exit 1
fi

# 設定測試環境
export CLAUDE_SESSION_ID="test-session-$$"
STATE_FILE="/tmp/claude-agent-state-${CLAUDE_SESSION_ID}"
DEBUG_LOG="/tmp/claude-workflow-debug.log"

# 清理舊測試檔案
rm -f "$STATE_FILE"
rm -f "$DEBUG_LOG"

# 測試計數器
PASS=true
TEST_COUNT=0
PASS_COUNT=0

# ═══════════════════════════════════════════════════════════════
# 測試 1: 白名單工具允許通過 (Main Agent + Read)
# ═══════════════════════════════════════════════════════════════
TEST_COUNT=$((TEST_COUNT + 1))
echo "測試 1: Main Agent 使用 Read (應允許)..."

# 初始化為 main agent
echo "main" > "$STATE_FILE"

# 模擬 Read 工具輸入
INPUT_JSON='{"session_id":"'$CLAUDE_SESSION_ID'","tool_name":"Read","tool_input":{"file_path":"test.ts"}}'

OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOK_SCRIPT" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && ! echo "$OUTPUT" | grep -q "BLOCKED"; then
    echo "✅ 測試 1 通過: Read 工具允許"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "❌ 測試 1 失敗: Read 工具被阻擋"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 2: 程式碼檔案寫入被阻擋 (Main Agent + Write)
# ═══════════════════════════════════════════════════════════════
TEST_COUNT=$((TEST_COUNT + 1))
echo "測試 2: Main Agent 寫入程式碼檔案 (應阻擋)..."

# 確保為 main agent
echo "main" > "$STATE_FILE"

# 模擬 Write 工具輸入 (程式碼檔案)
INPUT_JSON='{"session_id":"'$CLAUDE_SESSION_ID'","tool_name":"Write","tool_input":{"file_path":"src/test.ts","content":"code"}}'

OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOK_SCRIPT" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "block"; then
    echo "✅ 測試 2 通過: 程式碼檔案寫入被阻擋"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "❌ 測試 2 失敗: 程式碼檔案寫入未被阻擋"
    echo "輸出: $OUTPUT"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 3: 保護目錄被阻擋 (Main Agent + Write to hooks/)
# ═══════════════════════════════════════════════════════════════
TEST_COUNT=$((TEST_COUNT + 1))
echo "測試 3: Main Agent 寫入保護目錄 (應阻擋)..."

# 確保為 main agent
echo "main" > "$STATE_FILE"

# 模擬 Write 工具輸入 (保護目錄)
INPUT_JSON='{"session_id":"'$CLAUDE_SESSION_ID'","tool_name":"Write","tool_input":{"file_path":"hooks/test.json","content":"data"}}'

OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOK_SCRIPT" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "block"; then
    echo "✅ 測試 3 通過: 保護目錄寫入被阻擋"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "❌ 測試 3 失敗: 保護目錄寫入未被阻擋"
    echo "輸出: $OUTPUT"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 4: 非程式碼檔案允許通過 (Main Agent + Write to .md)
# ═══════════════════════════════════════════════════════════════
TEST_COUNT=$((TEST_COUNT + 1))
echo "測試 4: Main Agent 寫入文檔檔案 (應允許)..."

# 確保為 main agent
echo "main" > "$STATE_FILE"

# 模擬 Write 工具輸入 (文檔檔案)
INPUT_JSON='{"session_id":"'$CLAUDE_SESSION_ID'","tool_name":"Write","tool_input":{"file_path":"docs/README.md","content":"doc"}}'

OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOK_SCRIPT" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && ! echo "$OUTPUT" | grep -q "block"; then
    echo "✅ 測試 4 通過: 文檔檔案寫入允許"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "❌ 測試 4 失敗: 文檔檔案寫入被阻擋"
    echo "輸出: $OUTPUT"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 5: Subagent 允許使用所有工具
# ═══════════════════════════════════════════════════════════════
TEST_COUNT=$((TEST_COUNT + 1))
echo "測試 5: DEVELOPER 寫入程式碼檔案 (應允許)..."

# 設定為 developer agent
echo "developer" > "$STATE_FILE"

# 模擬 Write 工具輸入 (程式碼檔案)
INPUT_JSON='{"session_id":"'$CLAUDE_SESSION_ID'","tool_name":"Write","tool_input":{"file_path":"src/test.ts","content":"code"}}'

OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOK_SCRIPT" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && ! echo "$OUTPUT" | grep -q "BLOCKED"; then
    echo "✅ 測試 5 通過: DEVELOPER 可寫入程式碼檔案"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "❌ 測試 5 失敗: DEVELOPER 被阻擋"
    echo "輸出: $OUTPUT"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 6: Bash 檔案寫入檢測
# ═══════════════════════════════════════════════════════════════
TEST_COUNT=$((TEST_COUNT + 1))
echo "測試 6: Main Agent 使用 Bash 檔案寫入 (應阻擋)..."

# 確保為 main agent
echo "main" > "$STATE_FILE"

# 模擬 Bash 工具輸入 (檔案寫入)
INPUT_JSON='{"session_id":"'$CLAUDE_SESSION_ID'","tool_name":"Bash","tool_input":{"command":"echo test > output.txt"}}'

OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOK_SCRIPT" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "block"; then
    echo "✅ 測試 6 通過: Bash 檔案寫入被阻擋"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "❌ 測試 6 失敗: Bash 檔案寫入未被阻擋"
    echo "輸出: $OUTPUT"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 7: Bash 唯讀命令允許通過
# ═══════════════════════════════════════════════════════════════
TEST_COUNT=$((TEST_COUNT + 1))
echo "測試 7: Main Agent 使用 Bash 唯讀命令 (應允許)..."

# 確保為 main agent
echo "main" > "$STATE_FILE"

# 模擬 Bash 工具輸入 (唯讀命令)
INPUT_JSON='{"session_id":"'$CLAUDE_SESSION_ID'","tool_name":"Bash","tool_input":{"command":"git status"}}'

OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOK_SCRIPT" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && ! echo "$OUTPUT" | grep -q "block"; then
    echo "✅ 測試 7 通過: Bash 唯讀命令允許"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "❌ 測試 7 失敗: Bash 唯讀命令被阻擋"
    echo "輸出: $OUTPUT"
    PASS=false
fi
echo ""

# 清理測試檔案
rm -f "$STATE_FILE"

# 結果統計
echo "════════════════════════════════════════════════════════════════"
echo "測試統計: $PASS_COUNT/$TEST_COUNT 通過"
echo "════════════════════════════════════════════════════════════════"
echo ""

if [ "$PASS" = true ]; then
    echo "✅ TS-024 PASS: global-workflow-guard.sh 工作流阻擋正確"
    exit 0
else
    echo "❌ TS-024 FAIL: 部分測試失敗"
    exit 1
fi
