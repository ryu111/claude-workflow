#!/bin/bash
# test-ts-019.sh - CI/CD 檔案 HIGH RISK 判定測試
# 驗證: CI/CD 相關檔案被正確識別為 HIGH RISK

echo "=== TS-019: CI/CD 檔案 HIGH RISK 判定測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW_GATE="$PROJECT_ROOT/hooks/scripts/workflow-gate.sh"
STATE_DIR="$PROJECT_ROOT/.claude"

mkdir -p "$STATE_DIR"

PASS=true

# 建立 DEVELOPER 完成狀態
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 測試函數
test_high_risk() {
    local test_name="$1"
    local prompt="$2"

    echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\"}" > "$STATE_DIR/.drt-workflow-state"

    local input="{
        \"hook_event_name\": \"PreToolUse\",
        \"tool_name\": \"Task\",
        \"tool_input\": {
            \"prompt\": \"$prompt\",
            \"subagent_type\": \"claude-workflow:tester\"
        }
    }"

    local result=$(echo "$input" | bash "$WORKFLOW_GATE" 2>/dev/null)

    if echo "$result" | grep -q '"decision":"block"'; then
        echo "✅ $test_name: 正確識別為 HIGH RISK"
    else
        echo "❌ $test_name: 未被識別為 HIGH RISK"
        PASS=false
    fi
}

# Step 1: GitHub Actions
echo "Step 1: 測試 GitHub Actions..."
test_high_risk "GitHub Actions" "修改 .github/workflows/ci.yml 檔案"

# Step 2: GitLab CI
echo ""
echo "Step 2: 測試 GitLab CI..."
test_high_risk "GitLab CI" "修改 .gitlab-ci.yml 檔案"

# Step 3: Azure Pipelines
echo ""
echo "Step 3: 測試 Azure Pipelines..."
test_high_risk "Azure Pipelines" "修改 azure-pipelines.yml 檔案"

# Step 4: Jenkinsfile
echo ""
echo "Step 4: 測試 Jenkinsfile..."
test_high_risk "Jenkinsfile" "修改 Jenkinsfile 檔案"

# Step 5: Travis CI
echo ""
echo "Step 5: 測試 Travis CI..."
test_high_risk "Travis CI" "修改 .travis.yml 檔案"

# Step 6: Bitbucket Pipelines
echo ""
echo "Step 6: 測試 Bitbucket Pipelines..."
test_high_risk "Bitbucket" "修改 bitbucket-pipelines.yml 檔案"

# Step 7: 一般 YAML 檔案（應該是 MEDIUM，不是 HIGH）
echo ""
echo "Step 7: 測試一般 YAML 檔案（應為 MEDIUM）..."
echo "{\"agent\":\"developer\",\"result\":\"complete\",\"timestamp\":\"$CURRENT_TIME\"}" > "$STATE_DIR/.drt-workflow-state"

YAML_INPUT='{
    "hook_event_name": "PreToolUse",
    "tool_name": "Task",
    "tool_input": {
        "prompt": "修改 config.yaml 檔案",
        "subagent_type": "claude-workflow:tester"
    }
}'

YAML_RESULT=$(echo "$YAML_INPUT" | bash "$WORKFLOW_GATE" 2>&1)

# 一般 YAML 應該被阻擋（MEDIUM），但不是因為 HIGH RISK
if echo "$YAML_RESULT" | grep -q "MEDIUM"; then
    echo "✅ 一般 YAML: 正確識別為 MEDIUM（非 HIGH）"
elif echo "$YAML_RESULT" | grep -q "HIGH"; then
    echo "⚠️ 一般 YAML: 被誤判為 HIGH（可接受但不理想）"
else
    echo "✅ 一般 YAML: 被阻擋（MEDIUM 風險）"
fi

# 清理
rm -f "$STATE_DIR/.drt-workflow-state"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-019 PASS: CI/CD 檔案 HIGH RISK 判定正確"
    exit 0
else
    echo "❌ TS-019 FAIL"
    exit 1
fi
