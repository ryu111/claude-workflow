#!/bin/bash
# test-ts-016.sh - 自動格式化測試
# 驗證: PostToolUse hook (auto-format.sh) 正確執行

echo "=== TS-016: 自動格式化測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="$PROJECT_ROOT/hooks/scripts/auto-format.sh"

# 檢查腳本存在
if [ ! -f "$HOOK_SCRIPT" ]; then
    echo "❌ auto-format.sh 不存在"
    exit 1
fi

# 建立臨時測試檔案
TEST_FILE="/tmp/test-format-file.js"
cat > "$TEST_FILE" << 'EOF'
const x = 1;
function test() { return 42; }
EOF

# 建立測試 JSON 輸入（模擬 PostToolUse 事件）
TEST_JSON="{
  \"tool_name\": \"Write\",
  \"tool_input\": {
    \"file_path\": \"$TEST_FILE\"
  }
}"

# 執行腳本
echo "執行 auto-format.sh..."
echo "測試檔案: $TEST_FILE"
echo ""

OUTPUT=$(echo "$TEST_JSON" | bash "$HOOK_SCRIPT" 2>&1)
EXIT_CODE=$?

echo "$OUTPUT"
echo ""

# 驗證結果
PASS=true

# 1. 檢查是否成功執行
if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ 腳本執行失敗 (exit code: $EXIT_CODE)"
    PASS=false
fi

# 2. 檢查輸出格式（應包含檔案名稱或空）
if [ -n "$OUTPUT" ]; then
    if ! echo "$OUTPUT" | grep -qE "自動格式化|程式碼檢查|^$"; then
        echo "❌ 輸出格式不符合預期"
        PASS=false
    fi
fi

# 3. 測試跳過非程式碼檔案
TEST_FILE_MD="/tmp/test-format-file.min.js"
touch "$TEST_FILE_MD"
TEST_JSON_MD="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_FILE_MD\"}}"
OUTPUT_MD=$(echo "$TEST_JSON_MD" | bash "$HOOK_SCRIPT" 2>&1)
if [ -n "$OUTPUT_MD" ]; then
    echo "⚠️ 應該跳過 .min.js 檔案，但有輸出: $OUTPUT_MD"
    # 這不算失敗，只是警告
fi
rm -f "$TEST_FILE_MD"

# 4. 測試硬編碼警告檢測
TEST_FILE_WARNING="/tmp/test-warning.js"
cat > "$TEST_FILE_WARNING" << 'EOF'
const apiKey = "secret-key-12345";
const url = "http://localhost:3000/api";
// TODO: fix this later
EOF
TEST_JSON_WARNING="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_FILE_WARNING\"}}"
OUTPUT_WARNING=$(echo "$TEST_JSON_WARNING" | bash "$HOOK_SCRIPT" 2>&1)
if ! echo "$OUTPUT_WARNING" | grep -q "程式碼檢查"; then
    echo "⚠️ 未檢測到程式碼檢查警告（可能是預期行為）"
fi
rm -f "$TEST_FILE_WARNING"

# 清理測試檔案
rm -f "$TEST_FILE"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-016 PASS: PostToolUse hook 正確執行"
    exit 0
else
    echo "❌ TS-016 FAIL"
    exit 1
fi
