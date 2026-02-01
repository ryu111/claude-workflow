#!/usr/bin/env bash
# memory-decay.sh - 記憶清理邏輯
# 功能：根據記憶分數決定 keep / archive / delete
# Hook: SessionEnd（低頻執行）
# Phase: C only（僅 Phase C 啟用）

set -uo pipefail

# 載入依賴模組
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 使用 Bash 3.2 相容的方式：先關閉 errexit，然後靜默載入
set +e  # 暫時關閉錯誤中斷
set +u  # 暫時關閉未定義變數檢查

# 載入模組（stderr 導向 /dev/null 忽略 readonly 警告）
. "${LIB_DIR}/core/common.sh" 2>/dev/null
. "${LIB_DIR}/core/rollout-phase.sh" 2>/dev/null
. "${LIB_DIR}/memory/audit.sh" 2>/dev/null

# 恢復 set 選項
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 返回碼
readonly DECAY_SUCCESS=0
readonly DECAY_ERROR=1
readonly DECAY_SKIPPED=2

# 目錄路徑
readonly DECAY_MEMORY_DIR="${PWD}/.claude/memory"
readonly DECAY_EXPERIENCES_DIR="${DECAY_MEMORY_DIR}/experiences"
readonly DECAY_ARCHIVE_DIR="${DECAY_MEMORY_DIR}/.archive"

# 分數閾值
readonly DECAY_THRESHOLD_KEEP=50        # >= 50: keep（保留）
readonly DECAY_THRESHOLD_ARCHIVE=20     # 20-49: archive（歸檔）
                                        # < 20: delete（刪除）

# 保護期限
readonly DECAY_PROTECTED_DAYS=7         # 7 天內建立的記憶不刪除

# 審計動作類型（複用 memory-audit.sh 的常數）
readonly ACTION_ARCHIVE="archive"
readonly ACTION_DELETE="delete"

# ═══════════════════════════════════════════════════════════════
# 內部輔助函式
# ═══════════════════════════════════════════════════════════════

# 檢查記憶系統是否禁用（通過 CLI）
# 用法: if is_decay_memory_disabled; then ...
is_decay_memory_disabled() {
    bash "${LIB_DIR}/core/kill-switch.sh" check >/dev/null 2>&1
    local status=$?
    [ $status -eq 1 ]  # 返回碼 1 表示完全禁用
}

# 檢查熔斷器是否開啟（通過 CLI）
# 用法: if is_decay_circuit_breaker_open; then ...
is_decay_circuit_breaker_open() {
    bash "${LIB_DIR}/core/circuit-breaker.sh" is-open >/dev/null 2>&1
}

# 記錄失敗到熔斷器（通過 CLI）
# 用法: record_decay_failure
record_decay_failure() {
    bash "${LIB_DIR}/core/circuit-breaker.sh" record-failure >/dev/null 2>&1
}

# 檢查是否為 Phase C
# 用法: if is_phase_c; then ...
is_phase_c() {
    local current_phase
    current_phase=$(bash "${LIB_DIR}/core/rollout-phase.sh" get-phase 2>/dev/null)
    [ "$current_phase" = "C" ]
}

# 檢查記憶是否受保護（用戶標記重要或 7 天內建立）
# 用法: is_memory_protected "$memory_file"
# 返回: 0=受保護，1=不受保護
is_memory_protected() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ] || [ ! -f "$memory_file" ]; then
        return 1
    fi

    # 檢查 frontmatter 是否標記為重要
    if grep -q "^important: *true" "$memory_file" 2>/dev/null; then
        return 0  # 受保護
    fi

    # 檢查建立時間（7 天內）
    local file_age_days
    local current_time
    local file_mtime

    current_time=$(get_unix_timestamp)

    # 跨平台檔案修改時間取得
    if stat -f "%m" "$memory_file" >/dev/null 2>&1; then
        # macOS
        file_mtime=$(stat -f "%m" "$memory_file")
    else
        # Linux
        file_mtime=$(stat -c "%Y" "$memory_file")
    fi

    file_age_days=$(( (current_time - file_mtime) / 86400 ))

    if [ "$file_age_days" -lt "$DECAY_PROTECTED_DAYS" ]; then
        return 0  # 受保護
    fi

    return 1  # 不受保護
}

# 計算記憶分數（呼叫 memory-score.sh）
# 用法: score=$(calculate_memory_score "$memory_file")
# 輸出: 0-100 的整數分數
calculate_memory_score() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ] || [ ! -f "$memory_file" ]; then
        echo "0"
        return
    fi

    # 呼叫 memory-score.sh 計算分數
    # 注意：memory-score.sh 使用 score 子命令
    local score
    score=$(bash "${LIB_DIR}/memory/score.sh" score "$memory_file" 2>/dev/null || echo "0")

    # 驗證分數為數字
    if ! [[ "$score" =~ ^[0-9]+$ ]]; then
        score=0
    fi

    echo "$score"
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：記憶分類
# ═══════════════════════════════════════════════════════════════

# 分類記憶檔案（keep / archive / delete）
# 用法: classify_memories
# 輸出: JSON 格式分類結果
# {"keep":["file1"],"archive":["file2"],"delete":["file3"]}
classify_memories() {
    # 確保目錄存在
    if [ ! -d "$DECAY_EXPERIENCES_DIR" ]; then
        echo '{"keep":[],"archive":[],"delete":[]}'
        return $DECAY_SUCCESS
    fi

    # 使用臨時檔案收集分類結果（避免子 shell 問題）
    local temp_keep="${TMPDIR:-/tmp}/decay_keep_$$.txt"
    local temp_archive="${TMPDIR:-/tmp}/decay_archive_$$.txt"
    local temp_delete="${TMPDIR:-/tmp}/decay_delete_$$.txt"

    # 清空臨時檔案
    > "$temp_keep"
    > "$temp_archive"
    > "$temp_delete"

    # 遍歷所有記憶檔案
    find "$DECAY_EXPERIENCES_DIR" -name "*.md" -type f 2>/dev/null | while IFS= read -r memory_file; do
        # 檢查是否受保護
        if is_memory_protected "$memory_file"; then
            echo "$memory_file" >> "$temp_keep"
            continue
        fi

        # 計算分數
        local score
        score=$(calculate_memory_score "$memory_file")

        # 根據分數分類
        if [ "$score" -ge "$DECAY_THRESHOLD_KEEP" ]; then
            echo "$memory_file" >> "$temp_keep"
        elif [ "$score" -ge "$DECAY_THRESHOLD_ARCHIVE" ]; then
            echo "$memory_file" >> "$temp_archive"
        else
            echo "$memory_file" >> "$temp_delete"
        fi
    done

    # 構建 JSON 輸出
    echo -n '{"keep":['
    if [ -s "$temp_keep" ]; then
        local first=true
        while IFS= read -r file; do
            local escaped_file
            escaped_file=$(echo "$file" | sed 's/"/\\"/g')
            if [ "$first" = true ]; then
                echo -n "\"$escaped_file\""
                first=false
            else
                echo -n ",\"$escaped_file\""
            fi
        done < "$temp_keep"
    fi
    echo -n '],"archive":['

    if [ -s "$temp_archive" ]; then
        local first=true
        while IFS= read -r file; do
            local escaped_file
            escaped_file=$(echo "$file" | sed 's/"/\\"/g')
            if [ "$first" = true ]; then
                echo -n "\"$escaped_file\""
                first=false
            else
                echo -n ",\"$escaped_file\""
            fi
        done < "$temp_archive"
    fi
    echo -n '],"delete":['

    if [ -s "$temp_delete" ]; then
        local first=true
        while IFS= read -r file; do
            local escaped_file
            escaped_file=$(echo "$file" | sed 's/"/\\"/g')
            if [ "$first" = true ]; then
                echo -n "\"$escaped_file\""
                first=false
            else
                echo -n ",\"$escaped_file\""
            fi
        done < "$temp_delete"
    fi
    echo ']}'

    # 清理臨時檔案
    rm -f "$temp_keep" "$temp_archive" "$temp_delete" 2>/dev/null || true

    return $DECAY_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：記憶處理
# ═══════════════════════════════════════════════════════════════

# 歸檔記憶（移動到 .archive/）
# 用法: archive_memory "$memory_file"
# 返回: 0=成功，1=失敗
archive_memory() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ] || [ ! -f "$memory_file" ]; then
        echo "錯誤：archive_memory 需要提供有效的記憶檔案" >&2
        return 1
    fi

    # 確保歸檔目錄存在
    ensure_directory "$DECAY_ARCHIVE_DIR" || {
        echo "錯誤：無法建立歸檔目錄: $DECAY_ARCHIVE_DIR" >&2
        return 1
    }

    # 取得檔案名稱
    local filename
    filename=$(basename "$memory_file")

    # 建立歸檔檔名（加上時間戳避免衝突）
    local timestamp
    timestamp=$(get_timestamp | sed 's/[:-]//g; s/T/_/; s/Z$//')
    local archive_name="${timestamp}_${filename}"
    local archive_path="${DECAY_ARCHIVE_DIR}/${archive_name}"

    # 移動到歸檔目錄
    if mv "$memory_file" "$archive_path" 2>/dev/null; then
        # 記錄到審計日誌
        if command -v audit_memory_write >/dev/null 2>&1; then
            audit_memory_write "$ACTION_ARCHIVE" "$memory_file" "" "decay" "system" "" 2>/dev/null || true
        fi
        return 0
    else
        echo "錯誤：無法歸檔記憶: $memory_file" >&2
        return 1
    fi
}

# 刪除記憶
# 用法: delete_memory "$memory_file"
# 返回: 0=成功，1=失敗
delete_memory() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ] || [ ! -f "$memory_file" ]; then
        echo "錯誤：delete_memory 需要提供有效的記憶檔案" >&2
        return 1
    fi

    # 刪除檔案
    if rm -f "$memory_file" 2>/dev/null; then
        # 記錄到審計日誌
        if command -v audit_memory_write >/dev/null 2>&1; then
            audit_memory_write "$ACTION_DELETE" "$memory_file" "" "decay" "system" "" 2>/dev/null || true
        fi
        return 0
    else
        echo "錯誤：無法刪除記憶: $memory_file" >&2
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：記憶衰退執行
# ═══════════════════════════════════════════════════════════════

# 執行記憶衰退
# 用法: decay_memory [--dry-run]
# 返回: 0=成功，1=失敗，2=跳過
decay_memory() {
    local dry_run=false

    # 解析參數
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                echo "錯誤：無效的參數: $1" >&2
                return $DECAY_ERROR
                ;;
        esac
    done

    # 檢查 Kill Switch
    if is_decay_memory_disabled; then
        echo "⚠️  記憶系統已禁用，跳過記憶衰退" >&2
        return $DECAY_SKIPPED
    fi

    # 檢查熔斷器
    if is_decay_circuit_breaker_open; then
        echo "⚠️  熔斷器已開啟，跳過記憶衰退" >&2
        return $DECAY_SKIPPED
    fi

    # 檢查 Phase C（僅 Phase C 啟用）
    if ! is_phase_c; then
        echo "⚠️  記憶衰退僅在 Phase C 啟用，當前未啟用" >&2
        return $DECAY_SKIPPED
    fi

    echo "🧹 開始記憶衰退..." >&2

    # 分類記憶
    local classification
    classification=$(classify_memories)

    if [ $? -ne 0 ]; then
        echo "錯誤：無法分類記憶" >&2
        record_decay_failure
        return $DECAY_ERROR
    fi

    # 統計數量
    local keep_count
    local archive_count
    local delete_count

    keep_count=$(echo "$classification" | grep -o '"keep":\[[^]]*\]' | grep -o ',' | wc -l | tr -d ' ')
    keep_count=$((keep_count + 1))
    if echo "$classification" | grep -q '"keep":\[\]'; then
        keep_count=0
    fi

    archive_count=$(echo "$classification" | grep -o '"archive":\[[^]]*\]' | grep -o ',' | wc -l | tr -d ' ')
    archive_count=$((archive_count + 1))
    if echo "$classification" | grep -q '"archive":\[\]'; then
        archive_count=0
    fi

    delete_count=$(echo "$classification" | grep -o '"delete":\[[^]]*\]' | grep -o ',' | wc -l | tr -d ' ')
    delete_count=$((delete_count + 1))
    if echo "$classification" | grep -q '"delete":\[\]'; then
        delete_count=0
    fi

    echo "📊 分類結果：保留 $keep_count，歸檔 $archive_count，刪除 $delete_count" >&2

    if [ "$dry_run" = true ]; then
        echo "🔍 乾跑模式：僅顯示不執行" >&2
        echo "$classification" | jq '.' 2>/dev/null || echo "$classification"
        return $DECAY_SUCCESS
    fi

    # 執行歸檔
    if [ "$archive_count" -gt 0 ]; then
        echo "📦 歸檔記憶..." >&2
        echo "$classification" | grep -o '"archive":\[[^]]*\]' | sed 's/"archive":\[//;s/\]//' | sed 's/","/\n/g' | sed 's/^"//;s/"$//' | while IFS= read -r file; do
            if [ -n "$file" ]; then
                archive_memory "$file" && echo "  ✅ 已歸檔: $file" >&2 || echo "  ❌ 歸檔失敗: $file" >&2
            fi
        done
    fi

    # 執行刪除
    if [ "$delete_count" -gt 0 ]; then
        echo "🗑️  刪除記憶..." >&2
        echo "$classification" | grep -o '"delete":\[[^]]*\]' | sed 's/"delete":\[//;s/\]//' | sed 's/","/\n/g' | sed 's/^"//;s/"$//' | while IFS= read -r file; do
            if [ -n "$file" ]; then
                delete_memory "$file" && echo "  ✅ 已刪除: $file" >&2 || echo "  ❌ 刪除失敗: $file" >&2
            fi
        done
    fi

    echo "✅ 記憶衰退完成" >&2
    return $DECAY_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# Hook 整合介面
# ═══════════════════════════════════════════════════════════════

# SessionEnd Hook 入口函式
# 用法: handle_session_end_hook [json_input]
# 參數: json_input - Hook 傳入的 JSON 格式輸入（可選，從 stdin 讀取）
# 返回: 0=成功，1=失敗，2=跳過
handle_session_end_hook() {
    local json_input="${1:-}"

    # 如果沒有提供 JSON 輸入，從 stdin 讀取
    if [ -z "$json_input" ]; then
        json_input=$(cat)
    fi

    # 容錯執行（即使失敗也返回成功，確保不阻擋 SessionEnd 流程）
    if decay_memory 2>/dev/null; then
        return $DECAY_SUCCESS
    else
        echo "⚠️  記憶衰退失敗，但不阻擋 SessionEnd 流程" >&2
        return $DECAY_SUCCESS  # 返回成功以不阻擋 SessionEnd
    fi
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_decay_help() {
    cat <<'EOF'
Memory Decay - 記憶清理邏輯

用法:
  # Hook 模式（由 SessionEnd Hook 自動觸發）
  echo '{"session_id":"abc123"}' | memory-decay.sh hook

  # 手動執行
  memory-decay.sh run

  # 乾跑模式（只顯示不執行）
  memory-decay.sh run --dry-run

  # 僅分類（測試模式）
  memory-decay.sh classify

  # 幫助
  memory-decay.sh help

指令:
  hook                  處理 SessionEnd Hook 輸入（從 stdin 讀取 JSON）
  run [--dry-run]       手動執行記憶衰退
  classify              僅顯示分類結果（不執行操作）
  help                  顯示此說明

清理邏輯:
  1. 計算每個記憶的分數（0-100）
  2. 根據閾值分類：
     - score >= 50: keep（保留）
     - 20 <= score < 50: archive（歸檔到 .archive/）
     - score < 20: delete（刪除）
  3. 例外處理（不刪除）：
     - 用戶標記重要（frontmatter 有 important: true）
     - 7 天內建立

分數計算:
  - 呼叫 memory-score.sh 計算分數
  - 考慮因素：access_count、recency、relevance 等

目錄結構:
  .claude/memory/experiences/        - 活躍記憶
  .claude/memory/.archive/           - 歸檔記憶

安全機制:
  - Kill Switch 檢查（.disabled 檔案）
  - 熔斷器檢查（連續失敗自動停用）
  - Phase C 檢查（僅 Phase C 啟用）
  - 容錯執行（不阻擋 SessionEnd 流程）
  - 審計日誌（記錄所有操作）

乾跑模式:
  - 使用 --dry-run 可以查看將執行的操作，但不實際執行
  - 輸出 JSON 格式的分類結果

返回碼:
  0 - 成功
  1 - 失敗
  2 - 跳過（Kill Switch、熔斷器、或非 Phase C）

範例:
  # 手動執行記憶衰退
  bash hooks/scripts/memory-decay.sh run

  # 僅查看分類結果
  bash hooks/scripts/memory-decay.sh classify

  # 乾跑模式（測試）
  bash hooks/scripts/memory-decay.sh run --dry-run

  # 模擬 SessionEnd Hook
  echo '{"session_id":"test"}' | \
    bash hooks/scripts/memory-decay.sh hook
EOF
}

# 命令行介面入口
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        hook)
            handle_session_end_hook
            exit $?
            ;;
        run)
            shift
            decay_memory "$@"
            exit $?
            ;;
        classify)
            classify_memories | jq '.' 2>/dev/null || classify_memories
            exit $?
            ;;
        help|--help|-h)
            show_decay_help
            exit 0
            ;;
        *)
            show_decay_help
            exit 0
            ;;
    esac
fi
