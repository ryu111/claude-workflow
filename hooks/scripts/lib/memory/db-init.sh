#!/usr/bin/env bash
# memory-db-init.sh - SQLite 記憶資料庫初始化工具
# 功能：建立基於 SQLite FTS5 的關鍵字搜尋索引資料庫
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-db-init.sh"
# Phase 限制：僅在 Phase B+ 啟用

set -euo pipefail

# 載入依賴
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/../core/common.sh"
source "${SCRIPT_DIR}/../core/rollout-phase.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 返回碼
readonly MEMDB_SUCCESS=0
readonly MEMDB_ERROR=1
readonly MEMDB_SQLITE_NOT_FOUND=2
readonly MEMDB_FTS5_NOT_SUPPORTED=3
readonly MEMDB_PHASE_DISABLED=4

# 資料庫路徑
readonly MEMDB_DIR="${PWD}/.claude/memory/.index"
readonly MEMDB_FILE="${MEMDB_DIR}/memory.db"
readonly MEMDB_PERMISSION="600"

# SQLite 最低版本（支援 FTS5）
readonly MEMDB_MIN_SQLITE_VERSION="3.9.0"

# 資料庫 Schema 版本
readonly MEMDB_SCHEMA_VERSION="1"

# ═══════════════════════════════════════════════════════════════
# Phase 檢查
# ═══════════════════════════════════════════════════════════════

# 檢查是否啟用 index_basic 功能
# 用法: check_db_phase_enabled
# 返回: 0=啟用，4=未啟用
check_db_phase_enabled() {
    if ! is_feature_enabled "$FEATURE_INDEX_BASIC" 2>/dev/null; then
        echo "資訊：記憶索引功能未啟用（需要 Phase B+）" >&2
        return $MEMDB_PHASE_DISABLED
    fi
    return $MEMDB_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# SQLite 環境檢查
# ═══════════════════════════════════════════════════════════════

# 檢查 sqlite3 是否可用
# 用法: check_sqlite3_available
# 返回: 0=可用，2=不可用
check_sqlite3_available() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo "錯誤：sqlite3 未安裝，無法使用記憶索引功能" >&2
        echo "提示：" >&2
        echo "  macOS:  brew install sqlite3" >&2
        echo "  Linux:  apt-get install sqlite3" >&2
        return $MEMDB_SQLITE_NOT_FOUND
    fi
    return $MEMDB_SUCCESS
}

# 檢查 SQLite 是否支援 FTS5
# 用法: check_fts5_support
# 返回: 0=支援，3=不支援
check_fts5_support() {
    local fts5_test
    fts5_test=$(sqlite3 --version 2>/dev/null | awk '{print $1}')

    if [ -z "$fts5_test" ]; then
        echo "錯誤：無法取得 sqlite3 版本資訊" >&2
        return $MEMDB_FTS5_NOT_SUPPORTED
    fi

    # 簡單版本檢查（3.9.0 或更高）
    local major minor patch
    major=$(echo "$fts5_test" | cut -d. -f1)
    minor=$(echo "$fts5_test" | cut -d. -f2)

    if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 9 ]; }; then
        echo "錯誤：SQLite 版本過低（需要 >= $MEMDB_MIN_SQLITE_VERSION，當前 $fts5_test）" >&2
        return $MEMDB_FTS5_NOT_SUPPORTED
    fi

    # 實際測試 FTS5 是否可用（建立測試表）
    local test_result
    test_result=$(sqlite3 ":memory:" "CREATE VIRTUAL TABLE test USING fts5(content);" "SELECT 'ok';" 2>&1)

    if [ "$test_result" != "ok" ]; then
        echo "錯誤：SQLite 未啟用 FTS5 支援" >&2
        return $MEMDB_FTS5_NOT_SUPPORTED
    fi

    return $MEMDB_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 資料庫檢查
# ═══════════════════════════════════════════════════════════════

# 檢查資料庫是否已存在
# 用法: check_db_exists
# 返回: 0=存在，1=不存在
check_db_exists() {
    if [ -f "$MEMDB_FILE" ]; then
        return 0
    fi
    return 1
}

# 取得資料庫檔案路徑
# 用法: db_path=$(get_db_path)
# 輸出: 資料庫檔案的絕對路徑
get_db_path() {
    echo "$MEMDB_FILE"
}

# 驗證資料庫 Schema 是否正確
# 用法: verify_db_schema
# 返回: 0=正確，1=錯誤或不完整
verify_db_schema() {
    if ! check_db_exists; then
        echo "錯誤：資料庫檔案不存在: $MEMDB_FILE" >&2
        return $MEMDB_ERROR
    fi

    # 檢查必要的表格是否存在
    local tables
    tables=$(sqlite3 "$MEMDB_FILE" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;" 2>/dev/null)

    # 必須包含 memories 和 memories_fts
    if ! echo "$tables" | grep -q "memories"; then
        echo "錯誤：資料庫缺少 memories 表格" >&2
        return $MEMDB_ERROR
    fi

    if ! echo "$tables" | grep -q "memories_fts"; then
        echo "錯誤：資料庫缺少 memories_fts 表格" >&2
        return $MEMDB_ERROR
    fi

    # 檢查索引是否存在
    local indexes
    indexes=$(sqlite3 "$MEMDB_FILE" "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_memories_%' ORDER BY name;" 2>/dev/null)

    # 至少應該有 4 個索引
    local index_count
    index_count=$(echo "$indexes" | grep -c "idx_memories_" || echo "0")

    if [ "$index_count" -lt 4 ]; then
        echo "錯誤：資料庫索引不完整（預期 4 個，實際 $index_count 個）" >&2
        return $MEMDB_ERROR
    fi

    return $MEMDB_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 資料庫初始化
# ═══════════════════════════════════════════════════════════════

# 初始化記憶資料庫
# 用法: init_memory_db
# 返回: 0=成功，1=失敗
init_memory_db() {
    # Phase 檢查
    if ! check_db_phase_enabled; then
        return $MEMDB_PHASE_DISABLED
    fi

    # 環境檢查
    if ! check_sqlite3_available; then
        return $MEMDB_SQLITE_NOT_FOUND
    fi

    if ! check_fts5_support; then
        return $MEMDB_FTS5_NOT_SUPPORTED
    fi

    # 確保目錄存在
    if ! ensure_directory "$MEMDB_DIR"; then
        echo "錯誤：無法建立資料庫目錄: $MEMDB_DIR" >&2
        return $MEMDB_ERROR
    fi

    # 如果資料庫已存在且 Schema 正確，跳過初始化
    if check_db_exists && verify_db_schema 2>/dev/null; then
        echo "資訊：資料庫已存在且 Schema 正確，跳過初始化" >&2
        return $MEMDB_SUCCESS
    fi

    echo "初始化記憶資料庫: $MEMDB_FILE" >&2

    # 建立資料庫並執行 Schema
    local schema_sql
    schema_sql=$(cat <<'EOF'
-- 主要表格：儲存記憶元資料
CREATE TABLE IF NOT EXISTS memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_file TEXT NOT NULL,
    section TEXT,
    content TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    tags TEXT,
    source_type TEXT,
    priority TEXT DEFAULT 'normal',
    created TEXT NOT NULL,
    updated TEXT NOT NULL,
    last_accessed TEXT,
    access_count INTEGER DEFAULT 0
);

-- FTS5 全文搜尋虛擬表
CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
    content,
    section,
    tags,
    content='memories',
    content_rowid='id'
);

-- 觸發器：自動同步 FTS 索引（INSERT）
CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
    INSERT INTO memories_fts(rowid, content, section, tags)
    VALUES (new.id, new.content, new.section, new.tags);
END;

-- 觸發器：自動同步 FTS 索引（DELETE）
CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, content, section, tags)
    VALUES ('delete', old.id, old.content, old.section, old.tags);
END;

-- 觸發器：自動同步 FTS 索引（UPDATE）
CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, content, section, tags)
    VALUES ('delete', old.id, old.content, old.section, old.tags);
    INSERT INTO memories_fts(rowid, content, section, tags)
    VALUES (new.id, new.content, new.section, new.tags);
END;

-- 索引：加速常用查詢
CREATE INDEX IF NOT EXISTS idx_memories_source_file ON memories(source_file);
CREATE INDEX IF NOT EXISTS idx_memories_content_hash ON memories(content_hash);
CREATE INDEX IF NOT EXISTS idx_memories_source_type ON memories(source_type);
CREATE INDEX IF NOT EXISTS idx_memories_priority ON memories(priority);

-- 儲存 Schema 版本
CREATE TABLE IF NOT EXISTS schema_version (
    version TEXT NOT NULL,
    created TEXT NOT NULL
);

INSERT OR IGNORE INTO schema_version (version, created)
VALUES ('1', datetime('now'));
EOF
)

    # 執行 Schema
    if ! echo "$schema_sql" | sqlite3 "$MEMDB_FILE" 2>&1; then
        echo "錯誤：無法建立資料庫 Schema" >&2
        # 清理失敗的資料庫檔案
        rm -f "$MEMDB_FILE"
        return $MEMDB_ERROR
    fi

    # 設定檔案權限
    chmod "$MEMDB_PERMISSION" "$MEMDB_FILE" 2>/dev/null || {
        echo "警告：無法設定資料庫檔案權限為 $MEMDB_PERMISSION" >&2
    }

    # 驗證 Schema
    if ! verify_db_schema; then
        echo "錯誤：資料庫 Schema 驗證失敗" >&2
        return $MEMDB_ERROR
    fi

    echo "✅ 記憶資料庫初始化完成" >&2
    return $MEMDB_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 資料庫重置
# ═══════════════════════════════════════════════════════════════

# 重置資料庫（危險操作，需要確認）
# 用法: reset_db [--force]
# 返回: 0=成功，1=失敗或取消
reset_db() {
    local force=false

    # 解析參數
    while [ $# -gt 0 ]; do
        case "$1" in
            --force)
                force=true
                shift
                ;;
            *)
                echo "錯誤：未知的參數: $1" >&2
                return $MEMDB_ERROR
                ;;
        esac
    done

    # 如果沒有 --force，要求確認
    if [ "$force" = false ]; then
        echo "⚠️  警告：此操作將刪除所有記憶索引資料" >&2
        echo "資料庫路徑: $MEMDB_FILE" >&2
        echo "" >&2
        echo "如果要繼續，請使用 --force 參數" >&2
        return $MEMDB_ERROR
    fi

    # 刪除資料庫檔案
    if check_db_exists; then
        echo "刪除資料庫: $MEMDB_FILE" >&2
        if ! rm -f "$MEMDB_FILE"; then
            echo "錯誤：無法刪除資料庫檔案" >&2
            return $MEMDB_ERROR
        fi
        echo "✅ 資料庫已刪除" >&2
    else
        echo "資訊：資料庫檔案不存在，無需刪除" >&2
    fi

    # 重新初始化
    echo "重新初始化資料庫..." >&2
    init_memory_db
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示資料庫狀態
# 用法: show_db_status
show_db_status() {
    echo "═══════════════════════════════════════"
    echo "記憶資料庫狀態"
    echo "═══════════════════════════════════════"

    # Phase 檢查
    if ! check_db_phase_enabled 2>/dev/null; then
        echo "狀態: ⬜ 未啟用（需要 Phase B+）"
        echo "═══════════════════════════════════════"
        return $MEMDB_SUCCESS
    fi

    # SQLite 檢查
    if ! check_sqlite3_available 2>/dev/null; then
        echo "SQLite: ❌ 未安裝"
        echo "═══════════════════════════════════════"
        return $MEMDB_SUCCESS
    fi

    local sqlite_version
    sqlite_version=$(sqlite3 --version 2>/dev/null | awk '{print $1}')
    echo "SQLite 版本: $sqlite_version"

    # FTS5 檢查
    if check_fts5_support 2>/dev/null; then
        echo "FTS5 支援: ✅"
    else
        echo "FTS5 支援: ❌"
    fi

    # 資料庫檢查
    echo ""
    echo "資料庫路徑: $MEMDB_FILE"

    if check_db_exists; then
        echo "資料庫存在: ✅"

        # 檔案大小
        if command -v stat >/dev/null 2>&1; then
            local file_size
            file_size=$(stat -f%z "$MEMDB_FILE" 2>/dev/null || stat -c%s "$MEMDB_FILE" 2>/dev/null)
            if [ -n "$file_size" ]; then
                # 轉換為人類可讀格式
                if [ "$file_size" -lt 1024 ]; then
                    echo "資料庫大小: ${file_size}B"
                elif [ "$file_size" -lt 1048576 ]; then
                    echo "資料庫大小: $((file_size / 1024))KB"
                else
                    echo "資料庫大小: $((file_size / 1048576))MB"
                fi
            fi
        fi

        # Schema 驗證
        if verify_db_schema 2>/dev/null; then
            echo "Schema 狀態: ✅"

            # 記憶數量
            local memory_count
            memory_count=$(sqlite3 "$MEMDB_FILE" "SELECT COUNT(*) FROM memories;" 2>/dev/null || echo "0")
            echo "記憶數量: $memory_count"

            # 最後更新時間
            local last_updated
            last_updated=$(sqlite3 "$MEMDB_FILE" "SELECT MAX(updated) FROM memories;" 2>/dev/null || echo "")
            if [ -n "$last_updated" ] && [ "$last_updated" != "" ]; then
                echo "最後更新: $last_updated"
            fi
        else
            echo "Schema 狀態: ❌ 不完整或損壞"
        fi
    else
        echo "資料庫存在: ⬜ 尚未初始化"
    fi

    echo "═══════════════════════════════════════"
}

# 顯示使用說明
show_db_help() {
    cat <<'EOF'
記憶資料庫初始化工具 (Memory Database Init)

用法:
  source memory-db-init.sh

函式:
  init_memory_db
    初始化記憶資料庫（建立 Schema、索引、觸發器）
    返回: 0=成功，1=失敗

  check_db_exists
    檢查資料庫是否已存在
    返回: 0=存在，1=不存在

  get_db_path
    取得資料庫檔案路徑
    輸出: 資料庫檔案的絕對路徑

  verify_db_schema
    驗證資料庫 Schema 是否正確
    返回: 0=正確，1=錯誤或不完整

  reset_db [--force]
    重置資料庫（危險操作）
    參數: --force - 強制執行，不詢問確認
    返回: 0=成功，1=失敗或取消

  show_db_status
    顯示資料庫狀態資訊

環境檢查函式:
  check_db_phase_enabled
    檢查是否啟用 index_basic 功能（Phase B+）
    返回: 0=啟用，4=未啟用

  check_sqlite3_available
    檢查 sqlite3 是否可用
    返回: 0=可用，2=不可用

  check_fts5_support
    檢查 SQLite 是否支援 FTS5
    返回: 0=支援，3=不支援

範例:
  # 初始化資料庫
  if init_memory_db; then
      echo "資料庫初始化成功"
  fi

  # 檢查資料庫是否存在
  if check_db_exists; then
      echo "資料庫已存在"
  fi

  # 取得資料庫路徑
  db_path=$(get_db_path)
  echo "資料庫路徑: $db_path"

  # 驗證 Schema
  if verify_db_schema; then
      echo "Schema 正確"
  fi

  # 顯示狀態
  show_db_status

  # 重置資料庫（需要確認）
  reset_db --force

資料庫結構:
  主表格:
    - memories: 儲存記憶元資料
    - memories_fts: FTS5 全文搜尋虛擬表
    - schema_version: Schema 版本資訊

  索引:
    - idx_memories_source_file: 來源檔案索引
    - idx_memories_content_hash: 內容雜湊索引
    - idx_memories_source_type: 來源類型索引
    - idx_memories_priority: 優先級索引

  觸發器:
    - memories_ai: INSERT 時同步 FTS 索引
    - memories_ad: DELETE 時同步 FTS 索引
    - memories_au: UPDATE 時同步 FTS 索引

資料庫位置:
  .claude/memory/.index/memory.db

Phase 限制:
  此功能僅在 Phase B+ 啟用（需要 index_basic 功能）

返回碼:
  0 - 成功
  1 - 一般錯誤
  2 - sqlite3 未安裝
  3 - SQLite 不支援 FTS5
  4 - Phase 未啟用
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        init)
            init_memory_db
            exit $?
            ;;
        check)
            if check_db_exists; then
                echo "exists"
                exit 0
            else
                echo "not_exists"
                exit 1
            fi
            ;;
        path)
            get_db_path
            exit 0
            ;;
        verify)
            verify_db_schema
            exit $?
            ;;
        reset)
            shift
            reset_db "$@"
            exit $?
            ;;
        status)
            show_db_status
            exit 0
            ;;
        help|--help|-h|*)
            show_db_help
            exit 0
            ;;
    esac
fi
