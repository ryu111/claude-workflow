#!/bin/bash
# test-ts-072.sh - 記憶更新合併工具測試
# 驗證: memory-merge.sh 核心功能

echo "=== TS-072: 記憶更新合併工具測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_UNDER_TEST="$PROJECT_ROOT/hooks/scripts/lib/memory-merge.sh"
TEMP_DIR="/tmp/test-memory-merge-$$"

# 清理函式
cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

# 檢查腳本存在
if [ ! -f "$SCRIPT_UNDER_TEST" ]; then
    echo "❌ memory-merge.sh 不存在，路徑: $SCRIPT_UNDER_TEST"
    exit 1
fi

echo "✓ memory-merge.sh 已找到"
echo ""

# 建立測試環境
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# 載入腳本
source "$SCRIPT_UNDER_TEST"

# ============================================================
# 測試 1: 腳本語法正確性
# ============================================================

echo "【測試 1】腳本語法正確性"

if bash -n "$SCRIPT_UNDER_TEST" 2>/dev/null; then
    echo "  ✓ 語法檢查通過"
else
    echo "  ✗ 語法錯誤"
    exit 1
fi

echo ""

# ============================================================
# 測試 2: 常數定義 - MERGE_ 前綴
# ============================================================

echo "【測試 2】常數定義 - MERGE_ 前綴"

# 檢查 MERGE_ 前綴的常數
MERGE_CONSTANTS=$(grep -E '^readonly (MERGE_|SOURCE_PRIORITY_)' "$SCRIPT_UNDER_TEST" | wc -l | tr -d '[:space:]')

if [ "$MERGE_CONSTANTS" -ge 5 ]; then
    echo "  ✓ MERGE_ 相關常數數量正確 ($MERGE_CONSTANTS 個)"
else
    echo "  ✗ MERGE_ 相關常數不足 (預期 >= 5，實際 $MERGE_CONSTANTS)"
    exit 1
fi

# 檢查必要常數
REQUIRED_CONSTANTS=(
    "MERGE_SUCCESS"
    "MERGE_ERROR"
    "MERGE_INVALID_INPUT"
    "SOURCE_PRIORITY_USER"
    "SOURCE_PRIORITY_AGENT"
    "SOURCE_PRIORITY_SYSTEM"
)

for const in "${REQUIRED_CONSTANTS[@]}"; do
    if grep -q "^readonly $const=" "$SCRIPT_UNDER_TEST"; then
        echo "    ✓ $const 已定義"
    else
        echo "    ✗ $const 未定義"
        exit 1
    fi
done

echo ""

# ============================================================
# 測試 3: 核心函式定義
# ============================================================

echo "【測試 3】核心函式定義"

# 檢查核心函式
REQUIRED_FUNCTIONS=(
    "get_merge_timestamp"
    "json_get_field"
    "json_get_array"
    "merge_tags"
    "update_timestamp"
    "increment_access_count"
    "get_source_priority"
    "get_higher_priority_source"
    "merge_memory"
    "show_merge_help"
)

for func in "${REQUIRED_FUNCTIONS[@]}"; do
    if grep -q "^${func}()" "$SCRIPT_UNDER_TEST" || grep -q "^${func} ()" "$SCRIPT_UNDER_TEST"; then
        echo "  ✓ 函式 '$func' 已定義"
    else
        echo "  ✗ 函式 '$func' 未定義"
        exit 1
    fi
done

echo ""

# ============================================================
# 測試 4: CLI 命令 - help
# ============================================================

echo "【測試 4】CLI 命令 - help"

# 測試 help 命令
if bash "$SCRIPT_UNDER_TEST" help 2>&1 | grep -q "記憶更新合併工具"; then
    echo "  ✓ help 命令正常運作"
else
    echo "  ✗ help 命令失敗"
    exit 1
fi

echo ""

# ============================================================
# 測試 5: get_merge_timestamp 函式
# ============================================================

echo "【測試 5】get_merge_timestamp 函式"

timestamp=$(get_merge_timestamp 2>&1)

if echo "$timestamp" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
    echo "  ✓ 時間戳格式正確: $timestamp"
else
    echo "  ✗ 時間戳格式錯誤: $timestamp"
    exit 1
fi

echo ""

# ============================================================
# 測試 6: json_get_field 函式
# ============================================================

echo "【測試 6】json_get_field 函式"

json_test='{"content":"測試內容","access_count":5,"tags":"tag1,tag2"}'

# 測試字串欄位
content=$(json_get_field "$json_test" "content" 2>&1)
if [ "$content" = "測試內容" ]; then
    echo "  ✓ 字串欄位提取正確"
else
    echo "  ✗ 字串欄位提取失敗 (實際: $content)"
    exit 1
fi

# 測試數字欄位
access_count=$(json_get_field "$json_test" "access_count" 2>&1)
if [ "$access_count" = "5" ]; then
    echo "  ✓ 數字欄位提取正確"
else
    echo "  ✗ 數字欄位提取失敗 (實際: $access_count)"
    exit 1
fi

echo ""

# ============================================================
# 測試 7: merge_tags 函式
# ============================================================

echo "【測試 7】merge_tags 函式"

tags1="tag1,tag2"
tags2="tag2,tag3"

merged_tags=$(merge_tags "$tags1" "$tags2" 2>&1)

if echo "$merged_tags" | grep -q "tag1" && \
   echo "$merged_tags" | grep -q "tag2" && \
   echo "$merged_tags" | grep -q "tag3"; then
    echo "  ✓ 標籤合併正確: $merged_tags"

    # 驗證去重
    tag_count=$(echo "$merged_tags" | tr ',' '\n' | wc -l | tr -d '[:space:]')
    if [ "$tag_count" = "3" ]; then
        echo "    ✓ 標籤去重正確 (3 個標籤)"
    else
        echo "    ⚠️  標籤去重異常 (實際: $tag_count 個)"
    fi
else
    echo "  ✗ 標籤合併失敗: $merged_tags"
    exit 1
fi

echo ""

# ============================================================
# 測試 8: merge_tags - 空標籤處理
# ============================================================

echo "【測試 8】merge_tags - 空標籤處理"

# 兩者皆空
empty_result=$(merge_tags "" "" 2>&1)
if [ -z "$empty_result" ]; then
    echo "  ✓ 兩者皆空時返回空字串"
else
    echo "  ✗ 空標籤處理錯誤: $empty_result"
    exit 1
fi

# 一個空一個非空
result=$(merge_tags "tag1" "" 2>&1)
if [ "$result" = "tag1" ]; then
    echo "  ✓ 單一標籤保留正確"
else
    echo "  ✗ 單一標籤處理錯誤: $result"
    exit 1
fi

echo ""

# ============================================================
# 測試 9: update_timestamp 函式
# ============================================================

echo "【測試 9】update_timestamp 函式"

old_json='{"content":"測試","updated":"2024-01-01T00:00:00Z"}'

updated_json=$(update_timestamp "$old_json" 2>&1)

# 檢查 updated 欄位是否已更新
new_timestamp=$(json_get_field "$updated_json" "updated" 2>&1)

if echo "$new_timestamp" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'; then
    echo "  ✓ 時間戳更新成功: $new_timestamp"
else
    echo "  ✗ 時間戳更新失敗"
    exit 1
fi

echo ""

# ============================================================
# 測試 10: increment_access_count 函式
# ============================================================

echo "【測試 10】increment_access_count 函式"

old_json='{"content":"測試","access_count":5}'

# 累加 1
updated_json=$(increment_access_count "$old_json" 2>&1)
new_count=$(json_get_field "$updated_json" "access_count" 2>&1)

if [ "$new_count" = "6" ]; then
    echo "  ✓ access_count 累加 1 成功 (5 → 6)"
else
    echo "  ✗ access_count 累加失敗 (預期 6，實際 $new_count)"
    exit 1
fi

# 累加 3
updated_json=$(increment_access_count "$old_json" 3 2>&1)
new_count=$(json_get_field "$updated_json" "access_count" 2>&1)

if [ "$new_count" = "8" ]; then
    echo "  ✓ access_count 累加 3 成功 (5 → 8)"
else
    echo "  ✗ access_count 累加失敗 (預期 8，實際 $new_count)"
    exit 1
fi

echo ""

# ============================================================
# 測試 11: get_source_priority 函式
# ============================================================

echo "【測試 11】get_source_priority 函式"

user_priority=$(get_source_priority "user" 2>&1)
agent_priority=$(get_source_priority "agent" 2>&1)
system_priority=$(get_source_priority "system" 2>&1)

if [ "$user_priority" = "3" ] && \
   [ "$agent_priority" = "2" ] && \
   [ "$system_priority" = "1" ]; then
    echo "  ✓ 來源優先級正確 (user:3, agent:2, system:1)"
else
    echo "  ✗ 來源優先級錯誤 (user:$user_priority, agent:$agent_priority, system:$system_priority)"
    exit 1
fi

echo ""

# ============================================================
# 測試 12: get_higher_priority_source 函式
# ============================================================

echo "【測試 12】get_higher_priority_source 函式"

higher1=$(get_higher_priority_source "user" "system" 2>&1)
higher2=$(get_higher_priority_source "agent" "system" 2>&1)
higher3=$(get_higher_priority_source "system" "agent" 2>&1)

if [ "$higher1" = "user" ] && \
   [ "$higher2" = "agent" ] && \
   [ "$higher3" = "agent" ]; then
    echo "  ✓ 優先級比較正確"
else
    echo "  ✗ 優先級比較錯誤 (user-system:$higher1, agent-system:$higher2, system-agent:$higher3)"
    exit 1
fi

echo ""

# ============================================================
# 測試 13: merge_memory 函式
# ============================================================

echo "【測試 13】merge_memory 函式"

old_mem='{"content":"舊內容","tags":"tag1","access_count":5,"created":"2024-01-01T00:00:00Z","source_type":"system"}'
new_mem='{"content":"新內容","tags":"tag2","access_count":1,"source_type":"user"}'

merged=$(merge_memory "$old_mem" "$new_mem" 2>&1)

# 驗證合併結果
merged_content=$(json_get_field "$merged" "content" 2>&1)
merged_tags=$(json_get_field "$merged" "tags" 2>&1)
merged_count=$(json_get_field "$merged" "access_count" 2>&1)
merged_source=$(json_get_field "$merged" "source_type" 2>&1)
merged_created=$(json_get_field "$merged" "created" 2>&1)

# 驗證各欄位
TEST13_PASS=true

if [ "$merged_content" = "新內容" ]; then
    echo "  ✓ content: 使用新記憶的內容"
else
    echo "  ✗ content 錯誤 (預期: 新內容，實際: $merged_content)"
    TEST13_PASS=false
fi

if echo "$merged_tags" | grep -q "tag1" && echo "$merged_tags" | grep -q "tag2"; then
    echo "  ✓ tags: 正確合併"
else
    echo "  ✗ tags 錯誤 (實際: $merged_tags)"
    TEST13_PASS=false
fi

if [ "$merged_count" = "6" ]; then
    echo "  ✓ access_count: 正確累加 (5 + 1 = 6)"
else
    echo "  ✗ access_count 錯誤 (預期: 6，實際: $merged_count)"
    TEST13_PASS=false
fi

if [ "$merged_source" = "user" ]; then
    echo "  ✓ source_type: 保留較高優先級 (user)"
else
    echo "  ✗ source_type 錯誤 (預期: user，實際: $merged_source)"
    TEST13_PASS=false
fi

if [ "$merged_created" = "2024-01-01T00:00:00Z" ]; then
    echo "  ✓ created: 保留舊記憶的時間"
else
    echo "  ✗ created 錯誤 (預期: 2024-01-01T00:00:00Z，實際: $merged_created)"
    TEST13_PASS=false
fi

if [ "$TEST13_PASS" = false ]; then
    exit 1
fi

echo ""

# ============================================================
# 測試 14: CLI 模式 - merge-tags
# ============================================================

echo "【測試 14】CLI 模式 - merge-tags"

result=$(bash "$SCRIPT_UNDER_TEST" merge-tags "tag1,tag2" "tag2,tag3" 2>&1)

if echo "$result" | grep -q "tag1" && \
   echo "$result" | grep -q "tag2" && \
   echo "$result" | grep -q "tag3"; then
    echo "  ✓ CLI merge-tags 命令正常"
else
    echo "  ✗ CLI merge-tags 命令失敗: $result"
    exit 1
fi

echo ""

# ============================================================
# 測試 15: CLI 模式 - get-priority
# ============================================================

echo "【測試 15】CLI 模式 - get-priority"

result=$(bash "$SCRIPT_UNDER_TEST" get-priority "user" 2>&1)

if [ "$result" = "3" ]; then
    echo "  ✓ CLI get-priority 命令正常"
else
    echo "  ✗ CLI get-priority 命令失敗 (預期 3，實際 $result)"
    exit 1
fi

echo ""

# ============================================================
# 測試 16: CLI 模式 - higher-priority
# ============================================================

echo "【測試 16】CLI 模式 - higher-priority"

result=$(bash "$SCRIPT_UNDER_TEST" higher-priority "user" "system" 2>&1)

if [ "$result" = "user" ]; then
    echo "  ✓ CLI higher-priority 命令正常"
else
    echo "  ✗ CLI higher-priority 命令失敗 (預期 user，實際 $result)"
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

echo "✓ 基本檢查："
echo "  - 腳本語法: PASS"
echo "  - 常數定義 (MERGE_): PASS"
echo "  - 核心函式定義: PASS"
echo "  - CLI help 命令: PASS"
echo ""

echo "✓ 時間戳功能："
echo "  - get_merge_timestamp: PASS"
echo "  - update_timestamp: PASS"
echo ""

echo "✓ JSON 處理："
echo "  - json_get_field (字串): PASS"
echo "  - json_get_field (數字): PASS"
echo ""

echo "✓ 標籤合併："
echo "  - merge_tags (基本): PASS"
echo "  - merge_tags (空標籤): PASS"
echo ""

echo "✓ 存取計數："
echo "  - increment_access_count (累加 1): PASS"
echo "  - increment_access_count (累加 N): PASS"
echo ""

echo "✓ 來源優先級："
echo "  - get_source_priority: PASS"
echo "  - get_higher_priority_source: PASS"
echo ""

echo "✓ 記憶合併："
echo "  - merge_memory: PASS"
echo "    - content: PASS"
echo "    - tags: PASS"
echo "    - access_count: PASS"
echo "    - source_type: PASS"
echo "    - created: PASS"
echo ""

echo "✓ CLI 模式："
echo "  - merge-tags 命令: PASS"
echo "  - get-priority 命令: PASS"
echo "  - higher-priority 命令: PASS"
echo ""

echo "✅ TS-072 PASS: 記憶更新合併工具功能正確"
exit 0
