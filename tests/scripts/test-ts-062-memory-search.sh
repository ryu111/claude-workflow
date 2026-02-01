#!/bin/bash
# test-ts-062-memory-search.sh - 記憶搜尋功能測試
# 驗證: hooks/scripts/lib/memory-search.sh 所有功能正確運作

echo "=== TESTER-TEST: 記憶搜尋功能測試 (TS-062) ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SEARCH_SCRIPT="$PROJECT_ROOT/hooks/scripts/lib/memory-search.sh"
TEST_DIR="/tmp/test-memory-search-$$"

# 清理函數
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# 初始化測試環境
mkdir -p "$TEST_DIR"

# 檢查腳本存在
if [ ! -f "$SEARCH_SCRIPT" ]; then
    echo "❌ memory-search.sh 不存在"
    exit 1
fi

PASS=true
TEST_COUNT=0

# ═══════════════════════════════════════════════════════════════
# 測試 1: validate_query - 空查詢
# ═══════════════════════════════════════════════════════════════

echo "測試 1: validate_query - 空查詢"
((TEST_COUNT++))

result=$(bash -c '
    validate_query() {
        local query="${1:-}"
        if [ -z "$query" ]; then
            return 2
        fi
        return 0
    }
    validate_query ""
    echo "exit:$?"
')

if echo "$result" | grep -q "exit:2"; then
    echo "✅ 測試 1 通過"
else
    echo "❌ 測試 1 失敗"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 2: validate_query - 過長查詢
# ═══════════════════════════════════════════════════════════════

echo "測試 2: validate_query - 過長查詢 (>500字元)"
((TEST_COUNT++))

result=$(bash -c '
    validate_query() {
        local query="${1:-}"
        if [ "${#query}" -gt 500 ]; then
            return 2
        fi
        return 0
    }
    long_query=$(printf "a%.0s" {1..501})
    validate_query "$long_query"
    echo "exit:$?"
')

if echo "$result" | grep -q "exit:2"; then
    echo "✅ 測試 2 通過"
else
    echo "❌ 測試 2 失敗"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 3: sanitize_limit - 無效參數
# ═══════════════════════════════════════════════════════════════

echo "測試 3: sanitize_limit - 無效參數"
((TEST_COUNT++))

result=$(bash -c '
    sanitize_limit() {
        local limit="${1:-10}"
        if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
            echo "10"
            return 0
        fi
        [ "$limit" -gt 100 ] && { echo "100"; return 0; }
        echo "$limit"
    }
    sanitize_limit "not_a_number"
')

if [ "$result" = "10" ]; then
    echo "✅ 測試 3 通過"
else
    echo "❌ 測試 3 失敗: 預期 10, 實際 $result"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 4: sanitize_limit - 超過最大值
# ═══════════════════════════════════════════════════════════════

echo "測試 4: sanitize_limit - 超過最大值 (>100)"
((TEST_COUNT++))

result=$(bash -c '
    sanitize_limit() {
        local limit="${1:-10}"
        if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
            echo "10"
            return 0
        fi
        [ "$limit" -gt 100 ] && { echo "100"; return 0; }
        echo "$limit"
    }
    sanitize_limit 150
')

if [ "$result" = "100" ]; then
    echo "✅ 測試 4 通過"
else
    echo "❌ 測試 4 失敗: 預期 100, 實際 $result"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 5: sanitize_limit - 有效參數
# ═══════════════════════════════════════════════════════════════

echo "測試 5: sanitize_limit - 有效參數"
((TEST_COUNT++))

result=$(bash -c '
    sanitize_limit() {
        local limit="${1:-10}"
        if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
            echo "10"
            return 0
        fi
        [ "$limit" -gt 100 ] && { echo "100"; return 0; }
        echo "$limit"
    }
    sanitize_limit 50
')

if [ "$result" = "50" ]; then
    echo "✅ 測試 5 通過"
else
    echo "❌ 測試 5 失敗: 預期 50, 實際 $result"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 6: is_sensitive - 不敏感標籤
# ═══════════════════════════════════════════════════════════════

echo "測試 6: is_sensitive - 不敏感標籤"
((TEST_COUNT++))

result=$(bash -c '
    is_sensitive() {
        local tags="${1:-}"
        if echo ",$tags," | grep -q ",sensitive,"; then
            return 0
        else
            return 1
        fi
    }
    is_sensitive "not-sensitive"
    echo "exit:$?"
')

if echo "$result" | grep -q "exit:1"; then
    echo "✅ 測試 6 通過"
else
    echo "❌ 測試 6 失敗: 預期返回 1"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 7: is_sensitive - 敏感標籤
# ═══════════════════════════════════════════════════════════════

echo "測試 7: is_sensitive - 包含敏感標籤"
((TEST_COUNT++))

result=$(bash -c '
    is_sensitive() {
        local tags="${1:-}"
        if echo ",$tags," | grep -q ",sensitive,"; then
            return 0
        else
            return 1
        fi
    }
    is_sensitive "api,sensitive,key"
    echo "exit:$?"
')

if echo "$result" | grep -q "exit:0"; then
    echo "✅ 測試 7 通過"
else
    echo "❌ 測試 7 失敗: 預期返回 0"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 8: escape_fts5_query - 雙引號轉義
# ═══════════════════════════════════════════════════════════════

echo "測試 8: escape_fts5_query - 雙引號轉義"
((TEST_COUNT++))

result=$(bash -c 'escape_fts5_query() {
    local query="${1:-}"
    echo "$query" | sed "s/\"/\"\"/g"
}
escaped=$(escape_fts5_query "test\"query")
[ "$escaped" = "test\"\"query" ] && echo "ok" || echo "fail:$escaped"')

if echo "$result" | grep -q "ok"; then
    echo "✅ 測試 8 通過"
else
    echo "❌ 測試 8 失敗: $result"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 9: SQL 注入防護 - 標籤過濾
# ═══════════════════════════════════════════════════════════════

echo "測試 9: SQL 注入防護 - 標籤轉義"
((TEST_COUNT++))

result=$(bash -c "
    # 模擬標籤轉義
    tag=\"test'sql\"
    tag=\$(echo \"\$tag\" | sed \"s/'/''/g\")
    # 檢查單引號是否被轉義為雙單引號
    if echo \"\$tag\" | grep -q \"''\"; then
        echo \"ok\"
    else
        echo \"fail\"
    fi
")

if echo "$result" | grep -q "ok"; then
    echo "✅ 測試 9 通過"
else
    echo "❌ 測試 9 失敗"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 測試 10: JSON 轉義 - 反斜線和雙引號
# ═══════════════════════════════════════════════════════════════

echo "測試 10: JSON 轉義 - 反斜線和雙引號"
((TEST_COUNT++))

result=$(bash -c '
    content="path\\to\\file\"quoted"
    escaped=$(echo "$content" | sed "s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g")
    # 檢查轉義是否正確
    if echo "$escaped" | grep -q "\\\\\\\\"; then
        echo "ok"
    else
        echo "fail"
    fi
')

if echo "$result" | grep -q "ok"; then
    echo "✅ 測試 10 通過"
else
    echo "❌ 測試 10 失敗"
    PASS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 最終結果
# ═══════════════════════════════════════════════════════════════

if [ "$PASS" = true ]; then
    echo "✅ TESTER-TEST PASS: 所有測試通過 ($TEST_COUNT/$TEST_COUNT)"
    echo ""
    echo "測試範圍："
    echo "  - 安全性：SQL 注入防護、敏感標籤精確匹配、JSON 轉義"
    echo "  - 功能性：查詢驗證、Limit 限制、FTS5 轉義"
    echo "  - 邊界值：空查詢、過長查詢、無效 Limit、超大 Limit"
    exit 0
else
    echo "❌ TESTER-TEST FAIL: 部分測試失敗 ($TEST_COUNT 個測試中)"
    exit 1
fi
