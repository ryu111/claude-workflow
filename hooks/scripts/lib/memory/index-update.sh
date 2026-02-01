#!/usr/bin/env bash
# memory-index-update.sh - 記憶索引更新工具
# 功能：實作記憶內容索引到 SQLite FTS5 的功能
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-index-update.sh"
# Phase 限制：僅在 Phase B+ 啟用

set -euo pipefail

# 載入依賴
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
# memory-db-init.sh 已經 source common.sh 和 rollout-phase.sh，不需重複載入
source "${SCRIPT_DIR}/db-init.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 返回碼（使用 MEMIDX_ 前綴避免衝突）
readonly MEMIDX_SUCCESS=0
readonly MEMIDX_ERROR=1
readonly MEMIDX_INVALID_INPUT=2
readonly MEMIDX_DB_NOT_READY=3
readonly MEMIDX_PHASE_DISABLED=4

# Markdown 區段分隔符
readonly MEMIDX_SECTION_DELIMITER="^## "

# ═══════════════════════════════════════════════════════════════
# Phase 檢查
# ═══════════════════════════════════════════════════════════════

# 檢查是否啟用 index_basic 功能
# 用法: check_index_phase_enabled
# 返回: 0=啟用，4=未啟用
check_index_phase_enabled() {
    if ! is_feature_enabled "$FEATURE_INDEX_BASIC" 2>/dev/null; then
        echo "資訊：記憶索引更新功能未啟用（需要 Phase B+）" >&2
        return $MEMIDX_PHASE_DISABLED
    fi
    return $MEMIDX_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 計算內容雜湊（SHA256）
# 用法: hash=$(compute_content_hash "content")
# 輸出: SHA256 雜湊值（16進位）
compute_content_hash() {
    local content="${1:-}"

    if [ -z "$content" ]; then
        echo "錯誤：compute_content_hash 需要提供內容" >&2
        return $MEMIDX_ERROR
    fi

    # 使用 shasum 計算 SHA256
    echo -n "$content" | shasum -a 256 | awk '{print $1}'
}

# 解析 Markdown 檔案的區段
# 用法: 此函式會被 index_file_sections 呼叫
# 實作：使用 Bash 直接處理，避免 AWK 的換行問題
parse_sections_to_file() {
    local file_path="${1:-}"
    local output_file="${2:-}"

    if [ -z "$file_path" ] || [ -z "$output_file" ]; then
        echo "錯誤：parse_sections_to_file 需要提供 file_path 和 output_file" >&2
        return $MEMIDX_INVALID_INPUT
    fi

    if [ ! -f "$file_path" ]; then
        echo "錯誤：檔案不存在: $file_path" >&2
        return $MEMIDX_ERROR
    fi

    # 清空輸出檔案
    > "$output_file"

    local current_section="_intro"
    local current_content=""
    local in_section=false

    # 逐行讀取檔案
    while IFS= read -r line || [ -n "$line" ]; do
        # 檢查是否為 ## 標題
        if [[ "$line" == "## "* ]]; then
            # 儲存前一個區段
            if [ -n "$current_section" ]; then
                echo "$current_section" >> "$output_file"
                echo "$current_content" >> "$output_file"
                echo "---SECTION_END---" >> "$output_file"
            fi

            # 開始新區段（去掉 "## " 前綴）
            current_section="${line:3}"  # 從第 4 個字元開始（0-based index）
            current_content=""
        else
            # 累積內容
            if [ -z "$current_content" ]; then
                current_content="$line"
            else
                current_content="$current_content"$'\n'"$line"
            fi
        fi
    done < "$file_path"

    # 儲存最後一個區段
    if [ -n "$current_section" ]; then
        echo "$current_section" >> "$output_file"
        echo "$current_content" >> "$output_file"
        echo "---SECTION_END---" >> "$output_file"
    fi
}

# 檢查記憶是否已存在（根據 content_hash）
# 用法: memory_id=$(get_existing_memory_id "source_file" "section" "content_hash")
# 輸出: memory_id（存在時），否則輸出空字串
# 返回: 0=存在，1=不存在
get_existing_memory_id() {
    local source_file="${1:-}"
    local section="${2:-}"
    local content_hash="${3:-}"

    if [ -z "$source_file" ] || [ -z "$content_hash" ]; then
        echo "錯誤：get_existing_memory_id 需要提供 source_file 和 content_hash" >&2
        return $MEMIDX_ERROR
    fi

    local db_path
    db_path=$(get_db_path)

    # 查詢資料庫
    local memory_id
    memory_id=$(sqlite3 "$db_path" \
        "SELECT id FROM memories WHERE source_file = '$source_file' AND section = '$section' AND content_hash = '$content_hash' LIMIT 1;" \
        2>/dev/null || echo "")

    if [ -n "$memory_id" ]; then
        echo "$memory_id"
        return 0
    else
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：索引單一區段
# ═══════════════════════════════════════════════════════════════

# 索引單一區段
# 用法: index_section "source_file" "section_title" "section_content" [tags] [source_type] [priority]
# 參數:
#   source_file     - 來源檔案路徑（相對於專案根目錄）
#   section_title   - 區段標題
#   section_content - 區段內容
#   tags           - 可選，標籤（逗號分隔）
#   source_type    - 可選，來源類型（預設 "manual"）
#   priority       - 可選，優先級（預設 "normal"）
# 返回: 0=成功（新增或更新），1=失敗
index_section() {
    local source_file="${1:-}"
    local section_title="${2:-}"
    local section_content="${3:-}"
    local tags="${4:-}"
    local source_type="${5:-manual}"
    local priority="${6:-normal}"

    # 驗證必要參數
    if [ -z "$source_file" ] || [ -z "$section_content" ]; then
        echo "錯誤：index_section 需要提供 source_file 和 section_content" >&2
        return $MEMIDX_INVALID_INPUT
    fi

    # 計算內容雜湊
    local content_hash
    content_hash=$(compute_content_hash "$section_content") || return $MEMIDX_ERROR

    # 檢查是否已存在
    local existing_id
    if existing_id=$(get_existing_memory_id "$source_file" "$section_title" "$content_hash"); then
        # 已存在且內容相同，跳過更新
        echo "資訊：記憶已存在，內容未變更（ID: $existing_id），跳過更新" >&2
        return $MEMIDX_SUCCESS
    fi

    # 取得資料庫路徑
    local db_path
    db_path=$(get_db_path)

    # 取得當前時間戳
    local timestamp
    timestamp=$(get_timestamp)

    # 轉義 SQL 特殊字元
    local escaped_content
    escaped_content=$(echo "$section_content" | sed "s/'/''/g")

    local escaped_section
    escaped_section=$(echo "$section_title" | sed "s/'/''/g")

    local escaped_tags
    escaped_tags=$(echo "$tags" | sed "s/'/''/g")

    # 檢查是否已有相同 source_file + section 的記憶（不同內容）
    local old_memory_id
    old_memory_id=$(sqlite3 "$db_path" \
        "SELECT id FROM memories WHERE source_file = '$source_file' AND section = '$escaped_section' LIMIT 1;" \
        2>/dev/null || echo "")

    if [ -n "$old_memory_id" ]; then
        # 更新現有記憶
        local sql_update
        sql_update=$(cat <<EOF
UPDATE memories SET
    content = '$escaped_content',
    content_hash = '$content_hash',
    tags = '$escaped_tags',
    source_type = '$source_type',
    priority = '$priority',
    updated = '$timestamp'
WHERE id = $old_memory_id;
EOF
)

        if ! echo "$sql_update" | sqlite3 "$db_path" 2>&1; then
            echo "錯誤：無法更新記憶索引（ID: $old_memory_id）" >&2
            return $MEMIDX_ERROR
        fi

        echo "✅ 記憶索引已更新（ID: $old_memory_id, Section: $section_title）" >&2
    else
        # 插入新記憶
        local sql_insert
        sql_insert=$(cat <<EOF
INSERT INTO memories (source_file, section, content, content_hash, tags, source_type, priority, created, updated, access_count)
VALUES ('$source_file', '$escaped_section', '$escaped_content', '$content_hash', '$escaped_tags', '$source_type', '$priority', '$timestamp', '$timestamp', 0);
EOF
)

        if ! echo "$sql_insert" | sqlite3 "$db_path" 2>&1; then
            echo "錯誤：無法插入記憶索引" >&2
            return $MEMIDX_ERROR
        fi

        local new_id
        new_id=$(sqlite3 "$db_path" "SELECT last_insert_rowid();" 2>/dev/null)

        echo "✅ 記憶索引已建立（ID: $new_id, Section: $section_title）" >&2
    fi

    return $MEMIDX_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：索引整個檔案
# ═══════════════════════════════════════════════════════════════

# 索引整個檔案（自動解析區段）
# 用法: index_file "file_path" [tags] [source_type] [priority]
# 參數:
#   file_path   - 檔案路徑
#   tags        - 可選，標籤（逗號分隔）
#   source_type - 可選，來源類型（預設 "manual"）
#   priority    - 可選，優先級（預設 "normal"）
# 返回: 0=成功，1=失敗
index_file() {
    local file_path="${1:-}"
    local tags="${2:-}"
    local source_type="${3:-manual}"
    local priority="${4:-normal}"

    # 驗證參數
    if [ -z "$file_path" ]; then
        echo "錯誤：index_file 需要提供檔案路徑" >&2
        return $MEMIDX_INVALID_INPUT
    fi

    if [ ! -f "$file_path" ]; then
        echo "錯誤：檔案不存在: $file_path" >&2
        return $MEMIDX_ERROR
    fi

    # 解析區段
    echo "解析檔案區段: $file_path" >&2

    local section_count=0
    local success_count=0
    local skip_count=0

    # 使用臨時檔案儲存解析結果
    local temp_sections="/tmp/memory-sections-$$.txt"
    parse_sections_to_file "$file_path" "$temp_sections"

    # 讀取區段並索引
    local section_title=""
    local section_content=""
    local read_mode="title"  # title | content

    while IFS= read -r line; do
        if [ "$line" = "---SECTION_END---" ]; then
            # 處理完一個區段
            if [ -n "$section_title" ]; then
                ((section_count++))

                # 索引區段
                if index_section "$file_path" "$section_title" "$section_content" "$tags" "$source_type" "$priority" 2>&1 | grep -q "跳過更新"; then
                    ((skip_count++))
                else
                    ((success_count++))
                fi
            fi

            # 重置狀態
            section_title=""
            section_content=""
            read_mode="title"
        elif [ "$read_mode" = "title" ]; then
            section_title="$line"
            read_mode="content"
        else
            # 累積內容
            if [ -z "$section_content" ]; then
                section_content="$line"
            else
                section_content="$section_content"$'\n'"$line"
            fi
        fi
    done < "$temp_sections"

    # 清理臨時檔案
    rm -f "$temp_sections"

    echo "" >&2
    echo "📊 索引完成:" >&2
    echo "  檔案: $file_path" >&2
    echo "  區段總數: $section_count" >&2
    echo "  新增/更新: $success_count" >&2
    echo "  跳過: $skip_count" >&2

    return $MEMIDX_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：索引單一記憶（整體）
# ═══════════════════════════════════════════════════════════════

# 索引單一記憶（不分區段）
# 用法: index_memory "file_path" "content" [tags] [source_type] [priority]
# 參數:
#   file_path   - 來源檔案路徑
#   content     - 記憶內容
#   tags        - 可選，標籤（逗號分隔）
#   source_type - 可選，來源類型（預設 "manual"）
#   priority    - 可選，優先級（預設 "normal"）
# 返回: 0=成功，1=失敗
index_memory() {
    local file_path="${1:-}"
    local content="${2:-}"
    local tags="${3:-}"
    local source_type="${4:-manual}"
    local priority="${5:-normal}"

    # 驗證參數
    if [ -z "$file_path" ] || [ -z "$content" ]; then
        echo "錯誤：index_memory 需要提供 file_path 和 content" >&2
        return $MEMIDX_INVALID_INPUT
    fi

    # 直接索引為單一區段（section = ""）
    index_section "$file_path" "" "$content" "$tags" "$source_type" "$priority"
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：更新現有記憶索引
# ═══════════════════════════════════════════════════════════════

# 更新現有記憶索引
# 用法: update_memory_index "memory_id" "new_content" [new_tags]
# 參數:
#   memory_id   - 記憶 ID
#   new_content - 新內容
#   new_tags    - 可選，新標籤
# 返回: 0=成功，1=失敗
update_memory_index() {
    local memory_id="${1:-}"
    local new_content="${2:-}"
    local new_tags="${3:-}"

    # 驗證參數
    if [ -z "$memory_id" ] || [ -z "$new_content" ]; then
        echo "錯誤：update_memory_index 需要提供 memory_id 和 new_content" >&2
        return $MEMIDX_INVALID_INPUT
    fi

    # 計算新內容雜湊
    local new_hash
    new_hash=$(compute_content_hash "$new_content") || return $MEMIDX_ERROR

    # 取得資料庫路徑
    local db_path
    db_path=$(get_db_path)

    # 取得當前時間戳
    local timestamp
    timestamp=$(get_timestamp)

    # 轉義 SQL 特殊字元
    local escaped_content
    escaped_content=$(echo "$new_content" | sed "s/'/''/g")

    local escaped_tags
    escaped_tags=$(echo "$new_tags" | sed "s/'/''/g")

    # 更新記憶
    local sql_update
    if [ -n "$new_tags" ]; then
        sql_update="UPDATE memories SET content = '$escaped_content', content_hash = '$new_hash', tags = '$escaped_tags', updated = '$timestamp' WHERE id = $memory_id;"
    else
        sql_update="UPDATE memories SET content = '$escaped_content', content_hash = '$new_hash', updated = '$timestamp' WHERE id = $memory_id;"
    fi

    if ! echo "$sql_update" | sqlite3 "$db_path" 2>&1; then
        echo "錯誤：無法更新記憶索引（ID: $memory_id）" >&2
        return $MEMIDX_ERROR
    fi

    echo "✅ 記憶索引已更新（ID: $memory_id）" >&2
    return $MEMIDX_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：刪除記憶索引
# ═══════════════════════════════════════════════════════════════

# 刪除記憶索引
# 用法: delete_memory_index "memory_id"
# 參數:
#   memory_id - 記憶 ID
# 返回: 0=成功，1=失敗
delete_memory_index() {
    local memory_id="${1:-}"

    # 驗證參數
    if [ -z "$memory_id" ]; then
        echo "錯誤：delete_memory_index 需要提供 memory_id" >&2
        return $MEMIDX_INVALID_INPUT
    fi

    # 取得資料庫路徑
    local db_path
    db_path=$(get_db_path)

    # 刪除記憶
    local sql_delete="DELETE FROM memories WHERE id = $memory_id;"

    if ! echo "$sql_delete" | sqlite3 "$db_path" 2>&1; then
        echo "錯誤：無法刪除記憶索引（ID: $memory_id）" >&2
        return $MEMIDX_ERROR
    fi

    echo "✅ 記憶索引已刪除（ID: $memory_id）" >&2
    return $MEMIDX_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 高階功能：刪除檔案的所有記憶
# ═══════════════════════════════════════════════════════════════

# 刪除特定檔案的所有記憶索引
# 用法: delete_file_memories "file_path"
# 參數:
#   file_path - 檔案路徑
# 返回: 0=成功，1=失敗
delete_file_memories() {
    local file_path="${1:-}"

    # 驗證參數
    if [ -z "$file_path" ]; then
        echo "錯誤：delete_file_memories 需要提供檔案路徑" >&2
        return $MEMIDX_INVALID_INPUT
    fi

    # 取得資料庫路徑
    local db_path
    db_path=$(get_db_path)

    # 先查詢有多少記憶
    local count
    count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM memories WHERE source_file = '$file_path';" 2>/dev/null || echo "0")

    if [ "$count" -eq 0 ]; then
        echo "資訊：沒有找到該檔案的記憶索引" >&2
        return $MEMIDX_SUCCESS
    fi

    # 刪除記憶
    local sql_delete="DELETE FROM memories WHERE source_file = '$file_path';"

    if ! echo "$sql_delete" | sqlite3 "$db_path" 2>&1; then
        echo "錯誤：無法刪除檔案的記憶索引" >&2
        return $MEMIDX_ERROR
    fi

    echo "✅ 已刪除 $count 條記憶索引（檔案: $file_path）" >&2
    return $MEMIDX_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_index_help() {
    cat <<'EOF'
記憶索引更新工具 (Memory Index Update)

用法:
  source memory-index-update.sh

函式:
  index_section <source_file> <section_title> <section_content> [tags] [source_type] [priority]
    索引單一區段
    參數:
      source_file     - 來源檔案路徑
      section_title   - 區段標題
      section_content - 區段內容
      tags            - 可選，標籤（逗號分隔）
      source_type     - 可選，來源類型（預設 "manual"）
      priority        - 可選，優先級（預設 "normal"）
    返回: 0=成功，1=失敗

  index_file <file_path> [tags] [source_type] [priority]
    索引整個檔案（自動解析 Markdown 區段）
    參數:
      file_path   - 檔案路徑
      tags        - 可選，標籤（逗號分隔）
      source_type - 可選，來源類型（預設 "manual"）
      priority    - 可選，優先級（預設 "normal"）
    返回: 0=成功，1=失敗

  index_memory <file_path> <content> [tags] [source_type] [priority]
    索引單一記憶（不分區段）
    參數:
      file_path   - 來源檔案路徑
      content     - 記憶內容
      tags        - 可選，標籤（逗號分隔）
      source_type - 可選，來源類型（預設 "manual"）
      priority    - 可選，優先級（預設 "normal"）
    返回: 0=成功，1=失敗

  update_memory_index <memory_id> <new_content> [new_tags]
    更新現有記憶索引
    參數:
      memory_id   - 記憶 ID
      new_content - 新內容
      new_tags    - 可選，新標籤
    返回: 0=成功，1=失敗

  delete_memory_index <memory_id>
    刪除記憶索引
    參數:
      memory_id - 記憶 ID
    返回: 0=成功，1=失敗

  delete_file_memories <file_path>
    刪除特定檔案的所有記憶索引
    參數:
      file_path - 檔案路徑
    返回: 0=成功，1=失敗

輔助函式:
  compute_content_hash <content>
    計算內容雜湊（SHA256）
    參數: content - 內容
    輸出: SHA256 雜湊值

  parse_sections <file_path>
    解析 Markdown 檔案的區段
    參數: file_path - 檔案路徑
    輸出: 每行格式為 "section_title|section_content"

  get_existing_memory_id <source_file> <section> <content_hash>
    檢查記憶是否已存在
    輸出: memory_id（存在時），否則輸出空字串
    返回: 0=存在，1=不存在

範例:
  # 索引整個檔案（自動解析區段）
  index_file ".claude/memory/MEMORY.md" "project,preferences" "manual" "high"

  # 索引單一區段
  index_section ".claude/memory/MEMORY.md" "專案偏好" "我偏好使用 TypeScript" "preferences" "user" "high"

  # 索引單一記憶（不分區段）
  index_memory ".claude/memory/sessions/2024-01-01.jsonl" "完成任務 X" "session" "system" "normal"

  # 更新現有記憶
  update_memory_index 123 "更新後的內容" "new,tags"

  # 刪除記憶
  delete_memory_index 123

  # 刪除檔案的所有記憶
  delete_file_memories ".claude/memory/MEMORY.md"

分塊策略:
  - 使用 "## " 作為區段分隔符
  - 每個區段獨立索引
  - 使用 content_hash 檢查重複
  - 內容相同時跳過更新

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
    if ! check_index_phase_enabled; then
        exit $MEMIDX_PHASE_DISABLED
    fi

    # 確保資料庫已初始化
    if ! check_db_exists || ! verify_db_schema 2>/dev/null; then
        echo "錯誤：記憶資料庫未初始化，請先執行 init_memory_db" >&2
        exit $MEMIDX_DB_NOT_READY
    fi

    case "${1:-}" in
        index-file)
            shift
            index_file "$@"
            exit $?
            ;;
        index-section)
            shift
            index_section "$@"
            exit $?
            ;;
        index-memory)
            shift
            index_memory "$@"
            exit $?
            ;;
        update)
            shift
            update_memory_index "$@"
            exit $?
            ;;
        delete)
            shift
            delete_memory_index "$@"
            exit $?
            ;;
        delete-file)
            shift
            delete_file_memories "$@"
            exit $?
            ;;
        help|--help|-h|*)
            show_index_help
            exit 0
            ;;
    esac
fi
