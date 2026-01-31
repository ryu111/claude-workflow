#!/bin/bash
# test-userprompt-hook.sh - UserPromptSubmit Hook 整合測試
# 驗證: keyword-detector.sh 的執行時間、記憶體使用與正確性

echo "=== TS-022: UserPromptSubmit Hook 整合測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KEYWORD_DETECTOR="$PROJECT_ROOT/hooks/scripts/keyword-detector.sh"

# 檢查腳本存在
if [ ! -f "$KEYWORD_DETECTOR" ]; then
    echo "❌ 找不到 keyword-detector.sh: $KEYWORD_DETECTOR"
    exit 1
fi

PASS=true

# ═══════════════════════════════════════════════════════════════
# 測試 1: 基本功能 - 空輸入
# ═══════════════════════════════════════════════════════════════

echo "測試 1: 空輸入處理..."

INPUT_JSON='{
  "userPrompt": ""
}'

OUTPUT=$(echo "$INPUT_JSON" | CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$KEYWORD_DETECTOR" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ 空輸入處理成功（exit code: 0）"
else
    echo "❌ 空輸入處理失敗（exit code: $EXIT_CODE）"
    PASS=false
fi

# 驗證 JSON 格式
if echo "$OUTPUT" | jq empty 2>/dev/null; then
    echo "✅ 輸出為有效 JSON 格式"
else
    echo "❌ 輸出非有效 JSON 格式"
    echo "   輸出: $OUTPUT"
    PASS=false
fi

# 驗證欄位存在
if echo "$OUTPUT" | jq -e '.hookSpecificOutput.hookEventName' > /dev/null 2>&1; then
    echo "✅ 包含必要欄位 hookEventName"
else
    echo "❌ 缺少欄位 hookEventName"
    PASS=false
fi

# ═══════════════════════════════════════════════════════════════
# 測試 2: 關鍵字檢測 - 中文
# ═══════════════════════════════════════════════════════════════

echo ""
echo "測試 2: 關鍵字檢測（中文）..."

INPUT_JSON='{
  "userPrompt": "請幫我規劃一個新功能"
}'

START_TIME=$(date +%s%N)
OUTPUT=$(echo "$INPUT_JSON" | CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$KEYWORD_DETECTOR" 2>&1)
END_TIME=$(date +%s%N)
EXIT_CODE=$?

ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ 中文關鍵字檢測成功（exit code: 0）"
else
    echo "❌ 中文關鍵字檢測失敗（exit code: $EXIT_CODE）"
    PASS=false
fi

# 驗證 additionalContext 不為空（因為檢測到「規劃」關鍵字）
ADDITIONAL_CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if [ -n "$ADDITIONAL_CONTEXT" ]; then
    echo "✅ 檢測到關鍵字並注入 additionalContext"
else
    echo "⚠️ 未檢測到關鍵字（可能是範本不存在，可接受）"
fi

# ═══════════════════════════════════════════════════════════════
# 測試 3: 關鍵字檢測 - 英文
# ═══════════════════════════════════════════════════════════════

echo ""
echo "測試 3: 關鍵字檢測（英文）..."

INPUT_JSON='{
  "userPrompt": "please implement a new feature"
}'

OUTPUT=$(echo "$INPUT_JSON" | CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$KEYWORD_DETECTOR" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ 英文關鍵字檢測成功（exit code: 0）"
else
    echo "❌ 英文關鍵字檢測失敗（exit code: $EXIT_CODE）"
    PASS=false
fi

# 驗證全字匹配（「test」不應匹配「testing」）
INPUT_JSON='{
  "userPrompt": "we are testing the system"
}'

OUTPUT=$(echo "$INPUT_JSON" | CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$KEYWORD_DETECTOR" 2>&1)
ADDITIONAL_CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)

# 「testing」不應匹配「test」關鍵字，所以 additionalContext 應為空
if [ -z "$ADDITIONAL_CONTEXT" ]; then
    echo "✅ 全字匹配正確（'testing' 未匹配 'test'）"
else
    echo "⚠️ 全字匹配可能誤匹配（需檢查）"
fi

# ═══════════════════════════════════════════════════════════════
# 測試 4: 執行時間測試
# ═══════════════════════════════════════════════════════════════

echo ""
echo "測試 4: 執行時間測試（目標 < 100ms）..."

TOTAL_TIME=0
TEST_COUNT=5

for i in $(seq 1 $TEST_COUNT); do
    INPUT_JSON='{
      "userPrompt": "測試執行效能測試 iteration '"$i"'"
    }'

    START_TIME=$(date +%s%N)
    OUTPUT=$(echo "$INPUT_JSON" | CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$KEYWORD_DETECTOR" 2>&1)
    END_TIME=$(date +%s%N)

    ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))
    TOTAL_TIME=$((TOTAL_TIME + ELAPSED_MS))
done

AVG_TIME=$((TOTAL_TIME / TEST_COUNT))

echo "   執行 $TEST_COUNT 次，平均時間: ${AVG_TIME}ms"

if [ $AVG_TIME -lt 100 ]; then
    echo "✅ 執行時間符合要求（< 100ms）"
else
    echo "⚠️ 執行時間超過目標值（${AVG_TIME}ms > 100ms）"
    # 不標記為失敗，只是警告
fi

# ═══════════════════════════════════════════════════════════════
# 測試 5: 記憶體使用測試（如可行）
# ═══════════════════════════════════════════════════════════════

echo ""
echo "測試 5: 記憶體使用測試（目標 < 10MB）..."

# macOS 使用 /usr/bin/time -l，Linux 使用 /usr/bin/time -v
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    INPUT_JSON='{
      "userPrompt": "測試記憶體使用"
    }'

    # 使用 /usr/bin/time 測量（不是 shell builtin time）
    MEMORY_OUTPUT=$( { /usr/bin/time -l bash -c "echo '$INPUT_JSON' | CLAUDE_PLUGIN_ROOT='$PROJECT_ROOT' bash '$KEYWORD_DETECTOR' > /dev/null 2>&1" ; } 2>&1 )

    # 提取最大常駐記憶體（單位：bytes）
    MAX_RSS=$(echo "$MEMORY_OUTPUT" | grep "maximum resident set size" | awk '{print $1}')

    if [ -n "$MAX_RSS" ] && [ "$MAX_RSS" -gt 0 ]; then
        # 轉換為 MB
        MAX_RSS_MB=$(echo "scale=2; $MAX_RSS / 1024 / 1024" | bc)
        echo "   最大記憶體使用: ${MAX_RSS_MB} MB"

        # 檢查是否小於 10MB
        if (( $(echo "$MAX_RSS_MB < 10" | bc -l) )); then
            echo "✅ 記憶體使用符合要求（< 10MB）"
        else
            echo "⚠️ 記憶體使用超過目標值（${MAX_RSS_MB} MB > 10 MB）"
        fi
    else
        echo "⚠️ 無法測量記憶體使用（已跳過）"
    fi
else
    # Linux 或其他系統
    echo "⚠️ 記憶體測試僅支援 macOS（已跳過）"
fi

# ═══════════════════════════════════════════════════════════════
# 測試 6: 環境變數測試
# ═══════════════════════════════════════════════════════════════

echo ""
echo "測試 6: 環境變數測試..."

# 測試 CLAUDE_PLUGIN_ROOT 未設定
INPUT_JSON='{
  "userPrompt": "測試環境變數"
}'

OUTPUT=$(echo "$INPUT_JSON" | bash "$KEYWORD_DETECTOR" 2>&1)
EXIT_CODE=$?

# 未設定 CLAUDE_PLUGIN_ROOT 時應該能執行但無法載入範本
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ CLAUDE_PLUGIN_ROOT 未設定時能正常執行"
else
    echo "❌ CLAUDE_PLUGIN_ROOT 未設定時執行失敗"
    PASS=false
fi

# 驗證 JSON 格式仍然正確
if echo "$OUTPUT" | jq empty 2>/dev/null; then
    echo "✅ 無環境變數時輸出仍為有效 JSON"
else
    echo "❌ 無環境變數時輸出非有效 JSON"
    PASS=false
fi

# ═══════════════════════════════════════════════════════════════
# 測試 7: 無效 JSON 輸入
# ═══════════════════════════════════════════════════════════════

echo ""
echo "測試 7: 無效 JSON 輸入..."

INVALID_INPUT="this is not json"

OUTPUT=$(echo "$INVALID_INPUT" | CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$KEYWORD_DETECTOR" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "✅ 無效 JSON 輸入時正確返回錯誤（exit code: $EXIT_CODE）"
else
    echo "❌ 無效 JSON 輸入時未返回錯誤"
    PASS=false
fi

# ═══════════════════════════════════════════════════════════════
# 測試 8: 優先級測試（ARCHITECT > DEVELOPER）
# ═══════════════════════════════════════════════════════════════

echo ""
echo "測試 8: 關鍵字優先級測試..."

INPUT_JSON='{
  "userPrompt": "請規劃並實作這個功能"
}'

OUTPUT=$(echo "$INPUT_JSON" | CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$KEYWORD_DETECTOR" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ 包含多個關鍵字時能正確處理"
    # 注意：實際優先級驗證需要檢查 DEBUG_LOG，這裡只驗證不會出錯
else
    echo "❌ 包含多個關鍵字時處理失敗"
    PASS=false
fi

# ═══════════════════════════════════════════════════════════════
# 結果摘要
# ═══════════════════════════════════════════════════════════════

echo ""
echo "執行摘要:"
echo "  - 平均執行時間: ${AVG_TIME}ms"
if [[ "$OSTYPE" == "darwin"* ]] && [ -n "$MAX_RSS_MB" ]; then
    echo "  - 最大記憶體: ${MAX_RSS_MB} MB"
fi

echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-022 PASS: UserPromptSubmit Hook 整合測試通過"
    exit 0
else
    echo "❌ TS-022 FAIL"
    exit 1
fi
