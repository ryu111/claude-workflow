#!/usr/bin/env bash
# memory-search.sh - 記憶關鍵字搜尋工具
# 功能：基於 SQLite FTS5 實作關鍵字搜尋功能
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-search.sh"
# Phase 限制：僅在 Phase B+ 啟用

set -euo pipefail

# 載入依賴
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
# memory-db-init.sh 已經 source common.sh 和 rollout-phase.sh
source "${SCRIPT_DIR}/db-init.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 返回碼（使用 MEMSEARCH_ 前綴避免衝突）
readonly MEMSEARCH_SUCCESS=0
readonly MEMSEARCH_ERROR=1
readonly MEMSEARCH_INVALID_INPUT=2
readonly MEMSEARCH_DB_NOT_READY=3
readonly MEMSEARCH_PHASE_DISABLED=4

# 預設值
readonly MEMSEARCH_DEFAULT_LIMIT=10
readonly MEMSEARCH_MAX_LIMIT=100
readonly MEMSEARCH_MAX_QUERY_LENGTH=500

# 敏感標籤
readonly MEMSEARCH_SENSITIVE_TAG="sensitive"

# ═══════════════════════════════════════════════════════════════
# Phase 檢查
# ═══════════════════════════════════════════════════════════════

# 檢查是否啟用 index_basic 功能
# 用法: check_search_phase_enabled
# 返回: 0=啟用，4=未啟用
check_search_phase_enabled() {
    if ! is_feature_enabled "$FEATURE_INDEX_BASIC" 2>/dev/null; then
        echo "資訊：記憶搜尋功能未啟用（需要 Phase B+）" >&2
        return $MEMSEARCH_PHASE_DISABLED
    fi
    return $MEMSEARCH_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 驗證查詢參數
# 用法: validate_query "query"
# 返回: 0=有效，2=無效
validate_query() {
    local query="${1:-}"

    if [ -z "$query" ]; then
        echo "錯誤：查詢字串不能為空" >&2
        return $MEMSEARCH_INVALID_INPUT
    fi

    # 限制查詢長度（防止 DoS）
    if [ "${#query}" -gt "$MEMSEARCH_MAX_QUERY_LENGTH" ]; then
        echo "錯誤：查詢字串過長（最大 $MEMSEARCH_MAX_QUERY_LENGTH 字元）" >&2
        return $MEMSEARCH_INVALID_INPUT
    fi

    return $MEMSEARCH_SUCCESS
}

# 驗證 limit 參數
# 用法: sanitize_limit <limit>
# 輸出: 有效的 limit 值（1-100）
sanitize_limit() {
    local limit="${1:-$MEMSEARCH_DEFAULT_LIMIT}"

    # 檢查是否為數字
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
        echo "$MEMSEARCH_DEFAULT_LIMIT"
        return 0
    fi

    # 限制範圍
    if [ "$limit" -lt 1 ]; then
        echo "1"
    elif [ "$limit" -gt "$MEMSEARCH_MAX_LIMIT" ]; then
        echo "$MEMSEARCH_MAX_LIMIT"
    else
        echo "$limit"
    fi
}

# 轉義 FTS5 查詢特殊字元
# 用法: escaped=$(escape_fts5_query "query")
# 說明: FTS5 MATCH 使用雙引號語法，需要轉義內部雙引號
escape_fts5_query() {
    local query="${1:-}"

    # 轉義雙引號
    echo "$query" | sed 's/"/""/g'
}

# 檢查是否包含 sensitive 標籤
# 用法: is_sensitive "tags"
# 返回: 0=包含，1=不包含
is_sensitive() {
    local tags="${1:-}"

    # 使用精確匹配：在 tags 前後加逗號，檢查 ",sensitive," 避免子字串誤判
    # 例如：tags="not-sensitive" 不會被誤判為包含 "sensitive"
    if echo ",$tags," | grep -q ",$MEMSEARCH_SENSITIVE_TAG,"; then
        return 0
    else
        return 1
    fi
}

# 格式化為 JSON 輸出（單一記憶）
# 用法: format_memory_json <id> <source_file> <section> <content> <tags> <score>
format_memory_json() {
    local id="$1"
    local source_file="$2"
    local section="${3:-}"
    local content="$4"
    local tags="${5:-}"
    local score="${6:-0}"

    # 轉義 JSON 特殊字元（反斜線、雙引號、換行、Tab、歸位字元等控制字元）
    # 必須先轉義反斜線，再轉義其他字元
    local escaped_source_file=$(echo "$source_file" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g')
    local escaped_section=$(echo "$section" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g')
    local escaped_content=$(echo "$content" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/$/\\n/g' | tr -d '\n' | sed 's/\\n$//')
    local escaped_tags=$(echo "$tags" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g')

    cat <<EOF
    {
      "id": $id,
      "source_file": "$escaped_source_file",
      "section": "$escaped_section",
      "content": "$escaped_content",
      "tags": "$escaped_tags",
      "score": $score
    }
EOF
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：關鍵字搜尋
# ═══════════════════════════════════════════════════════════════

# 搜尋記憶（主要函式）
# 用法: search_memory "query" [limit] [tags] [--include-sensitive]
# 參數:
#   query              - 搜尋關鍵字（必填）
#   limit              - 返回數量（預設 10，最大 100）
#   tags               - 標籤過濾（逗號分隔，可選）
#   --include-sensitive - 包含敏感標籤（預設過濾）
# 輸出: JSON 格式的搜尋結果
# 返回: 0=成功，1=失敗
search_memory() {
    local query="${1:-}"
    local limit="${2:-$MEMSEARCH_DEFAULT_LIMIT}"
    local tags="${3:-}"
    local include_sensitive=false

    # 解析參數（處理 --include-sensitive）
    shift 2 2>/dev/null || true
    while [ $# -gt 0 ]; do
        case "$1" in
            --include-sensitive)
                include_sensitive=true
                shift
                ;;
            *)
                # 其他參數作為 tags
                if [ -z "$tags" ]; then
                    tags="$1"
                fi
                shift
                ;;
        esac
    done

    # 驗證參數
    if ! validate_query "$query"; then
        return $MEMSEARCH_INVALID_INPUT
    fi

    limit=$(sanitize_limit "$limit")

    # 取得資料庫路徑
    local db_path
    db_path=$(get_db_path)

    if [ ! -f "$db_path" ]; then
        echo "錯誤：資料庫未初始化" >&2
        return $MEMSEARCH_DB_NOT_READY
    fi

    # 轉義查詢字串
    local escaped_query
    escaped_query=$(escape_fts5_query "$query")

    # 建立 SQL 查詢
    local sql_query
    sql_query=$(cat <<EOF
SELECT
    m.id,
    m.source_file,
    m.section,
    m.content,
    m.tags,
    bm25(fts) AS score
FROM memories m
INNER JOIN memories_fts fts ON m.id = fts.rowid
WHERE fts MATCH "$escaped_query"
EOF
)

    # 新增標籤過濾條件（防止 SQL 注入）
    if [ -n "$tags" ]; then
        # 將逗號分隔的標籤轉換為 SQL 條件
        IFS=',' read -ra tag_array <<< "$tags"
        for tag in "${tag_array[@]}"; do
            tag=$(echo "$tag" | xargs)  # 去除空白
            # 轉義單引號防止 SQL 注入：將 ' 替換為 ''
            tag=$(echo "$tag" | sed "s/'/''/g")
            sql_query="$sql_query AND m.tags LIKE '%$tag%'"
        done
    fi

    # 過濾 sensitive 標籤（除非允許）
    if [ "$include_sensitive" = false ]; then
        sql_query="$sql_query AND (m.tags IS NULL OR m.tags NOT LIKE '%$MEMSEARCH_SENSITIVE_TAG%')"
    fi

    # 新增排序和限制
    sql_query="$sql_query ORDER BY score LIMIT $limit;"

    # 執行查詢並解析結果
    local result_count=0
    local json_results=""

    # 使用換行符分隔的格式執行查詢
    while IFS='|' read -r id source_file section content tags score; do
        if [ $result_count -gt 0 ]; then
            json_results+=","
        fi

        json_results+=$(format_memory_json "$id" "$source_file" "$section" "$content" "$tags" "$score")
        ((result_count++))
    done < <(sqlite3 -separator '|' "$db_path" "$sql_query" 2>/dev/null)

    # 轉義 query 欄位用於 JSON 輸出
    local escaped_query_output=$(echo "$query" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g')

    # 輸出 JSON 格式
    cat <<EOF
{
  "results": [
$json_results
  ],
  "count": $result_count,
  "query": "$escaped_query_output"
}
EOF

    return $MEMSEARCH_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助搜尋函式
# ═══════════════════════════════════════════════════════════════

# 按區段搜尋
# 用法: search_by_section "section_name" [limit]
# 參數:
#   section_name - 區段名稱（如 "專案偏好"）
#   limit        - 返回數量（預設 10）
# 輸出: JSON 格式的搜尋結果
search_by_section() {
    local section_name="${1:-}"
    local limit="${2:-$MEMSEARCH_DEFAULT_LIMIT}"

    if [ -z "$section_name" ]; then
        echo "錯誤：section_name 不能為空" >&2
        return $MEMSEARCH_INVALID_INPUT
    fi

    limit=$(sanitize_limit "$limit")

    # 取得資料庫路徑
    local db_path
    db_path=$(get_db_path)

    if [ ! -f "$db_path" ]; then
        echo "錯誤：資料庫未初始化" >&2
        return $MEMSEARCH_DB_NOT_READY
    fi

    # 轉義 SQL 特殊字元
    local escaped_section
    escaped_section=$(echo "$section_name" | sed "s/'/''/g")

    # 建立 SQL 查詢
    local sql_query="SELECT id, source_file, section, content, tags, 1.0 AS score FROM memories WHERE section = '$escaped_section' LIMIT $limit;"

    # 執行查詢並解析結果
    local result_count=0
    local json_results=""

    while IFS='|' read -r id source_file section content tags score; do
        if [ $result_count -gt 0 ]; then
            json_results+=","
        fi

        json_results+=$(format_memory_json "$id" "$source_file" "$section" "$content" "$tags" "$score")
        ((result_count++))
    done < <(sqlite3 -separator '|' "$db_path" "$sql_query" 2>/dev/null)

    # 轉義 section_name 用於 JSON 輸出
    local escaped_section_output=$(echo "$section_name" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g')

    # 輸出 JSON 格式
    cat <<EOF
{
  "results": [
$json_results
  ],
  "count": $result_count,
  "query": "section:$escaped_section_output"
}
EOF

    return $MEMSEARCH_SUCCESS
}

# 按檔案搜尋
# 用法: search_by_file "file_path" [limit]
# 參數:
#   file_path - 檔案路徑（如 "MEMORY.md"）
#   limit     - 返回數量（預設 10）
# 輸出: JSON 格式的搜尋結果
search_by_file() {
    local file_path="${1:-}"
    local limit="${2:-$MEMSEARCH_DEFAULT_LIMIT}"

    if [ -z "$file_path" ]; then
        echo "錯誤：file_path 不能為空" >&2
        return $MEMSEARCH_INVALID_INPUT
    fi

    limit=$(sanitize_limit "$limit")

    # 取得資料庫路徑
    local db_path
    db_path=$(get_db_path)

    if [ ! -f "$db_path" ]; then
        echo "錯誤：資料庫未初始化" >&2
        return $MEMSEARCH_DB_NOT_READY
    fi

    # 轉義 SQL 特殊字元
    local escaped_file
    escaped_file=$(echo "$file_path" | sed "s/'/''/g")

    # 建立 SQL 查詢
    local sql_query="SELECT id, source_file, section, content, tags, 1.0 AS score FROM memories WHERE source_file = '$escaped_file' LIMIT $limit;"

    # 執行查詢並解析結果
    local result_count=0
    local json_results=""

    while IFS='|' read -r id source_file section content tags score; do
        if [ $result_count -gt 0 ]; then
            json_results+=","
        fi

        json_results+=$(format_memory_json "$id" "$source_file" "$section" "$content" "$tags" "$score")
        ((result_count++))
    done < <(sqlite3 -separator '|' "$db_path" "$sql_query" 2>/dev/null)

    # 轉義 file_path 用於 JSON 輸出
    local escaped_file_output=$(echo "$file_path" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g')

    # 輸出 JSON 格式
    cat <<EOF
{
  "results": [
$json_results
  ],
  "count": $result_count,
  "query": "file:$escaped_file_output"
}
EOF

    return $MEMSEARCH_SUCCESS
}

# 取得最近的記憶
# 用法: get_recent_memories [limit]
# 參數:
#   limit - 返回數量（預設 10）
# 輸出: JSON 格式的搜尋結果
get_recent_memories() {
    local limit="${1:-$MEMSEARCH_DEFAULT_LIMIT}"

    limit=$(sanitize_limit "$limit")

    # 取得資料庫路徑
    local db_path
    db_path=$(get_db_path)

    if [ ! -f "$db_path" ]; then
        echo "錯誤：資料庫未初始化" >&2
        return $MEMSEARCH_DB_NOT_READY
    fi

    # 建立 SQL 查詢（按 updated 時間排序）
    local sql_query="SELECT id, source_file, section, content, tags, 1.0 AS score FROM memories ORDER BY updated DESC LIMIT $limit;"

    # 執行查詢並解析結果
    local result_count=0
    local json_results=""

    while IFS='|' read -r id source_file section content tags score; do
        if [ $result_count -gt 0 ]; then
            json_results+=","
        fi

        json_results+=$(format_memory_json "$id" "$source_file" "$section" "$content" "$tags" "$score")
        ((result_count++))
    done < <(sqlite3 -separator '|' "$db_path" "$sql_query" 2>/dev/null)

    # 輸出 JSON 格式
    cat <<EOF
{
  "results": [
$json_results
  ],
  "count": $result_count,
  "query": "recent"
}
EOF

    return $MEMSEARCH_SUCCESS
}

# 按 ID 取得記憶
# 用法: get_memory_by_id <id>
# 參數:
#   id - 記憶 ID
# 輸出: JSON 格式的記憶（單筆）
get_memory_by_id() {
    local id="${1:-}"

    if [ -z "$id" ]; then
        echo "錯誤：id 不能為空" >&2
        return $MEMSEARCH_INVALID_INPUT
    fi

    # 檢查是否為數字
    if ! [[ "$id" =~ ^[0-9]+$ ]]; then
        echo "錯誤：id 必須為數字" >&2
        return $MEMSEARCH_INVALID_INPUT
    fi

    # 取得資料庫路徑
    local db_path
    db_path=$(get_db_path)

    if [ ! -f "$db_path" ]; then
        echo "錯誤：資料庫未初始化" >&2
        return $MEMSEARCH_DB_NOT_READY
    fi

    # 建立 SQL 查詢
    local sql_query="SELECT id, source_file, section, content, tags, 1.0 AS score FROM memories WHERE id = $id LIMIT 1;"

    # 執行查詢並解析結果
    local result_count=0
    local json_results=""

    while IFS='|' read -r id source_file section content tags score; do
        json_results=$(format_memory_json "$id" "$source_file" "$section" "$content" "$tags" "$score")
        result_count=1
    done < <(sqlite3 -separator '|' "$db_path" "$sql_query" 2>/dev/null)

    # 輸出 JSON 格式
    cat <<EOF
{
  "results": [
$json_results
  ],
  "count": $result_count,
  "query": "id:$id"
}
EOF

    return $MEMSEARCH_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_search_help() {
    cat <<'EOF'
記憶關鍵字搜尋工具 (Memory Search)

用法:
  source memory-search.sh

函式:
  search_memory <query> [limit] [tags] [--include-sensitive]
    搜尋記憶（FTS5 全文搜尋）
    參數:
      query               - 搜尋關鍵字（必填）
      limit               - 返回數量（預設 10，最大 100）
      tags                - 標籤過濾（逗號分隔，可選）
      --include-sensitive - 包含敏感標籤（預設過濾）
    輸出: JSON 格式的搜尋結果
    返回: 0=成功，1=失敗

  search_by_section <section_name> [limit]
    按區段搜尋
    參數:
      section_name - 區段名稱（如 "專案偏好"）
      limit        - 返回數量（預設 10）
    輸出: JSON 格式的搜尋結果

  search_by_file <file_path> [limit]
    按檔案搜尋
    參數:
      file_path - 檔案路徑（如 "MEMORY.md"）
      limit     - 返回數量（預設 10）
    輸出: JSON 格式的搜尋結果

  get_recent_memories [limit]
    取得最近的記憶（按更新時間排序）
    參數:
      limit - 返回數量（預設 10）
    輸出: JSON 格式的搜尋結果

  get_memory_by_id <id>
    按 ID 取得記憶
    參數:
      id - 記憶 ID
    輸出: JSON 格式的記憶（單筆）

輔助函式:
  validate_query <query>
    驗證查詢字串
    返回: 0=有效，2=無效

  sanitize_limit <limit>
    驗證並限制 limit 範圍（1-100）
    輸出: 有效的 limit 值

  escape_fts5_query <query>
    轉義 FTS5 查詢特殊字元
    輸出: 轉義後的查詢字串

  is_sensitive <tags>
    檢查是否包含 sensitive 標籤
    返回: 0=包含，1=不包含

範例:
  # 基本搜尋
  search_memory "TypeScript"

  # 限制返回數量
  search_memory "測試" 5

  # 標籤過濾
  search_memory "專案偏好" 10 "preferences,project"

  # 包含敏感標籤
  search_memory "API" 10 "" --include-sensitive

  # 按區段搜尋
  search_by_section "專案偏好"

  # 按檔案搜尋
  search_by_file "MEMORY.md"

  # 取得最近記憶
  get_recent_memories 10

  # 按 ID 取得
  get_memory_by_id 123

FTS5 搜尋語法:
  - 基本搜尋: search_memory "typescript"
  - AND 搜尋: search_memory "typescript AND react"
  - OR 搜尋:  search_memory "typescript OR javascript"
  - NOT 搜尋: search_memory "typescript NOT react"
  - 片語搜尋: search_memory "\"unit test\""

JSON 輸出格式:
  {
    "results": [
      {
        "id": 1,
        "source_file": "MEMORY.md",
        "section": "專案偏好",
        "content": "...",
        "tags": "preference,project",
        "score": 0.85
      }
    ],
    "count": 1,
    "query": "TypeScript"
  }

安全過濾:
  - 預設過濾 tags 包含 "sensitive" 的記憶
  - 使用 --include-sensitive 選項可包含敏感記憶

Phase 限制:
  此功能僅在 Phase B+ 啟用（需要 index_basic 功能）

返回碼:
  0 - 成功
  1 - 一般錯誤
  2 - 無效的輸入參數
  3 - 資料庫未就緒
  4 - Phase 未啟用
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    # Phase 檢查
    if ! check_search_phase_enabled; then
        exit $MEMSEARCH_PHASE_DISABLED
    fi

    # 確保資料庫已初始化
    if ! check_db_exists || ! verify_db_schema 2>/dev/null; then
        echo "錯誤：記憶資料庫未初始化，請先執行 init_memory_db" >&2
        exit $MEMSEARCH_DB_NOT_READY
    fi

    case "${1:-}" in
        search)
            shift
            search_memory "$@"
            exit $?
            ;;
        search-section)
            shift
            search_by_section "$@"
            exit $?
            ;;
        search-file)
            shift
            search_by_file "$@"
            exit $?
            ;;
        recent)
            shift
            get_recent_memories "$@"
            exit $?
            ;;
        get-id)
            shift
            get_memory_by_id "$@"
            exit $?
            ;;
        help|--help|-h|*)
            show_search_help
            exit 0
            ;;
    esac
fi
