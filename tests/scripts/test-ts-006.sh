#!/bin/bash
# test-ts-006.sh - LOW 風險快速通道測試
# 驗證: LOW 風險變更可跳過 REVIEWER

echo "=== TS-006: LOW 風險快速通道測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW_GATE="$PROJECT_ROOT/hooks/scripts/workflow-gate.sh"
STATE_DIR="$PROJECT_ROOT/.claude"
TEST_CHANGE_ID="test-006"
STATE_AUTO_DIR="$PROJECT_ROOT/drt-state-auto"
mkdir -p "$STATE_AUTO_DIR"
STATE_FILE="$STATE_AUTO_DIR/${TEST_CHANGE_ID}.json"

PASS=true

# Step 1: 建立 DEVELOPER 完成狀態
echo "Step 1: 建立 DEVELOPER 完成狀態..."

CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\",\"change_id\":\"$TEST_CHANGE_ID\"}" > "$STATE_FILE"

echo "狀態檔內容:"
cat "$STATE_FILE"
echo ""

# Step 2: 測試 LOW 風險（應允許 D→T）
echo "Step 2: 測試 LOW 風險檔案（README.md, docs/guide.txt）..."
echo ""

LOW_RISK_INPUT='{
  "hook_event_name": "PreToolUse",
  "tool_name": "Task",
  "tool_input": {
    "prompt": "測試修改 README.md 和 docs/guide.txt 檔案 [test-006]",
    "subagent_type": "claude-workflow:tester"
  }
}'

LOW_RESULT_STDERR=$(echo "$LOW_RISK_INPUT" | bash "$WORKFLOW_GATE" 2>&1 >/dev/null)
LOW_RESULT_JSON=$(echo "$LOW_RISK_INPUT" | bash "$WORKFLOW_GATE" 2>/dev/null)

echo "用戶訊息:"
echo "$LOW_RESULT_STDERR"
echo ""

# 驗證 LOW 風險不被阻擋
if echo "$LOW_RESULT_JSON" | grep -q '"decision":"block"'; then
    echo "❌ LOW 風險被錯誤阻擋"
    PASS=false
else
    echo "✅ LOW 風險未被阻擋（正確！）"
fi

if echo "$LOW_RESULT_STDERR" | grep -q "LOW 風險快速通道"; then
    echo "✅ 顯示 LOW 風險快速通道訊息"
else
    echo "⚠️ 未顯示快速通道訊息"
fi

# Step 3: 測試 MEDIUM 風險（應被阻擋）
echo ""
echo "Step 3: 測試 MEDIUM 風險檔案（app.ts, service.py）..."
echo ""

# 重建狀態
echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\",\"change_id\":\"$TEST_CHANGE_ID\"}" > "$STATE_FILE"

MEDIUM_RISK_INPUT='{
  "hook_event_name": "PreToolUse",
  "tool_name": "Task",
  "tool_input": {
    "prompt": "測試修改 app.ts 和 service.py 檔案 [test-006]",
    "subagent_type": "claude-workflow:tester"
  }
}'

MEDIUM_RESULT_STDERR=$(echo "$MEDIUM_RISK_INPUT" | bash "$WORKFLOW_GATE" 2>&1 >/dev/null)
MEDIUM_RESULT_JSON=$(echo "$MEDIUM_RISK_INPUT" | bash "$WORKFLOW_GATE" 2>/dev/null)

echo "用戶訊息:"
echo "$MEDIUM_RESULT_STDERR"
echo ""

# 驗證 MEDIUM 風險被阻擋
if echo "$MEDIUM_RESULT_JSON" | grep -q '"decision":"block"'; then
    echo "✅ MEDIUM 風險被正確阻擋"
else
    echo "❌ MEDIUM 風險未被阻擋（應該阻擋！）"
    PASS=false
fi

# Step 4: 測試 HIGH 風險（敏感路徑/檔案）
echo ""
echo "Step 4: 測試 HIGH 風險檔案（/auth/login.ts, .env）..."
echo ""

# 重建狀態
echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\",\"change_id\":\"$TEST_CHANGE_ID\"}" > "$STATE_FILE"

HIGH_RISK_INPUT='{
  "hook_event_name": "PreToolUse",
  "tool_name": "Task",
  "tool_input": {
    "prompt": "測試修改 src/auth/login.ts 和 .env 檔案 [test-006]",
    "subagent_type": "claude-workflow:tester"
  }
}'

HIGH_RESULT_STDERR=$(echo "$HIGH_RISK_INPUT" | bash "$WORKFLOW_GATE" 2>&1 >/dev/null)
HIGH_RESULT_JSON=$(echo "$HIGH_RISK_INPUT" | bash "$WORKFLOW_GATE" 2>/dev/null)

echo "用戶訊息:"
echo "$HIGH_RESULT_STDERR" | head -15
echo ""

# 驗證 HIGH 風險被阻擋
if echo "$HIGH_RESULT_JSON" | grep -q '"decision":"block"'; then
    echo "✅ HIGH 風險被正確阻擋"
else
    echo "❌ HIGH 風險未被阻擋（應該阻擋！）"
    PASS=false
fi

# Step 5: 測試 yaml 檔案（現在應該是 MEDIUM，不是 LOW）
echo ""
echo "Step 5: 測試 YAML 檔案（config.yaml）- 應為 MEDIUM..."
echo ""

# 重建狀態
echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\",\"change_id\":\"$TEST_CHANGE_ID\"}" > "$STATE_FILE"

YAML_INPUT='{
  "hook_event_name": "PreToolUse",
  "tool_name": "Task",
  "tool_input": {
    "prompt": "測試修改 config.yaml 檔案 [test-006]",
    "subagent_type": "claude-workflow:tester"
  }
}'

YAML_RESULT_JSON=$(echo "$YAML_INPUT" | bash "$WORKFLOW_GATE" 2>/dev/null)

# YAML 應該被阻擋（MEDIUM 風險）
if echo "$YAML_RESULT_JSON" | grep -q '"decision":"block"'; then
    echo "✅ YAML 檔案被正確阻擋（MEDIUM 風險）"
else
    echo "❌ YAML 檔案未被阻擋（應該是 MEDIUM 風險！）"
    PASS=false
fi

# 清理
rm -f "$STATE_FILE"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-006 PASS: LOW 風險快速通道正常運作"
    exit 0
else
    echo "❌ TS-006 FAIL"
    exit 1
fi
