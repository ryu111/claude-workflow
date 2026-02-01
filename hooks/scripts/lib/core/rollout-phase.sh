#!/bin/bash
# rollout-phase.sh - Rollout Phase 配置管理
# 功能：管理記憶系統的漸進式發布階段 (A → B → C)
# 邏輯：根據 config.yaml 控制功能啟用

set -euo pipefail

# 載入共用工具函式
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

readonly CONFIG_FILE="${PWD}/.claude/memory/config.yaml"

# Phase 常數
readonly PHASE_A="A"
readonly PHASE_B="B"
readonly PHASE_C="C"

# 功能名稱常數（與 config.yaml 對應）
# Phase A 功能
readonly FEATURE_INJECT_STATIC="inject_static"

# Phase B 功能
readonly FEATURE_EXTRACT_EXPLICIT="extract_explicit"
readonly FEATURE_INDEX_BASIC="index_basic"
readonly FEATURE_EXTRACT_CORRECTION="extract_correction"

# Phase C 功能
readonly FEATURE_EXTRACT_IMPLICIT="extract_implicit"
readonly FEATURE_INJECT_DYNAMIC="inject_dynamic"
readonly FEATURE_DECAY="decay"

# 返回碼
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_CONFIG_NOT_FOUND=2
readonly EXIT_INVALID_PHASE=3

# ═══════════════════════════════════════════════════════════════
# 工具函式
# ═══════════════════════════════════════════════════════════════

# 檢查配置檔是否存在
# 用法: ensure_config_exists
# 返回: 0=存在，2=不存在
ensure_config_exists() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "錯誤：配置檔不存在: $CONFIG_FILE" >&2
        echo "提示：請執行 'bash scripts/init.sh' 初始化專案" >&2
        return $EXIT_CONFIG_NOT_FOUND
    fi
    return $EXIT_SUCCESS
}

# 使用 grep/sed 解析 YAML（避免依賴 yq）
# 用法: parse_yaml_value <key>
# 輸出: 對應的值（去除引號）
parse_yaml_value() {
    local key="${1:-}"

    if [ -z "$key" ]; then
        echo "錯誤：parse_yaml_value 需要提供 key" >&2
        return $EXIT_ERROR
    fi

    ensure_config_exists || return $?

    # 使用 grep + sed 提取值
    # 範例: "  phase: \"A\"" → "A"
    local value=$(grep "^[[:space:]]*${key}:" "$CONFIG_FILE" | head -1 | sed -E 's/.*:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/')

    if [ -z "$value" ]; then
        echo "錯誤：無法解析 key: $key" >&2
        return $EXIT_ERROR
    fi

    echo "$value"
}

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 取得當前 Rollout Phase
# 用法: phase=$(get_rollout_phase)
# 輸出: A | B | C
# 返回: 0=成功，其他=失敗
get_rollout_phase() {
    local phase
    phase=$(parse_yaml_value "phase") || return $?

    # 驗證 Phase 合法性
    case "$phase" in
        A|B|C)
            echo "$phase"
            return $EXIT_SUCCESS
            ;;
        *)
            echo "錯誤：無效的 Phase: $phase (有效值: A, B, C)" >&2
            return $EXIT_INVALID_PHASE
            ;;
    esac
}

# 檢查特定功能是否啟用
# 用法: is_feature_enabled <feature_name>
# 參數: feature_name - 功能名稱常數（如 $FEATURE_INJECT_STATIC）
# 返回: 0=啟用，1=未啟用
is_feature_enabled() {
    local feature="${1:-}"

    if [ -z "$feature" ]; then
        echo "錯誤：is_feature_enabled 需要提供功能名稱" >&2
        return $EXIT_ERROR
    fi

    local value
    value=$(parse_yaml_value "$feature") || return $EXIT_ERROR

    # 檢查是否為 true
    if [ "$value" = "true" ]; then
        return 0  # 啟用
    else
        return 1  # 未啟用
    fi
}

# 設定 Rollout Phase（用於測試和升級）
# 用法: set_rollout_phase <phase>
# 參數: phase - A | B | C
# 返回: 0=成功，1=失敗
set_rollout_phase() {
    local new_phase="${1:-}"

    # 檢查參數是否為空
    if [ -z "$new_phase" ]; then
        echo "錯誤：必須指定 Phase (有效值: A, B, C)" >&2
        return $EXIT_ERROR
    fi

    # 驗證參數
    case "$new_phase" in
        A|B|C)
            ;;  # 合法
        *)
            echo "錯誤：無效的 Phase: $new_phase (有效值: A, B, C)" >&2
            return $EXIT_INVALID_PHASE
            ;;
    esac

    ensure_config_exists || return $?

    # 使用 sed 替換 phase 值（跨平台相容）
    local temp_file="${CONFIG_FILE}.tmp.$$"

    # macOS 和 Linux sed 語法相容版本
    sed "s/^[[:space:]]*phase:[[:space:]]*\"[ABC]\"/  phase: \"$new_phase\"/" "$CONFIG_FILE" > "$temp_file"

    if [ ! -s "$temp_file" ]; then
        echo "錯誤：無法更新配置檔" >&2
        rm -f "$temp_file"
        return $EXIT_ERROR
    fi

    mv "$temp_file" "$CONFIG_FILE"

    # 根據新 Phase 自動更新功能開關
    update_features_for_phase "$new_phase"

    echo "✅ Phase 已更新為: $new_phase" >&2
    return $EXIT_SUCCESS
}

# 根據 Phase 自動更新功能開關
# 用法: update_features_for_phase <phase>
# 說明: 內部函式，由 set_rollout_phase 呼叫
update_features_for_phase() {
    local phase="$1"
    local temp_file="${CONFIG_FILE}.tmp.$$"

    cp "$CONFIG_FILE" "$temp_file"

    case "$phase" in
        A)
            # Phase A: 只啟用 inject_static
            sed -i.bak "s/^[[:space:]]*inject_static:[[:space:]]*false/    inject_static: true/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*extract_explicit:[[:space:]]*true/    extract_explicit: false/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*index_basic:[[:space:]]*true/    index_basic: false/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*extract_correction:[[:space:]]*true/    extract_correction: false/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*extract_implicit:[[:space:]]*true/    extract_implicit: false/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*inject_dynamic:[[:space:]]*true/    inject_dynamic: false/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*decay:[[:space:]]*true/    decay: false/" "$temp_file"
            ;;
        B)
            # Phase B: A 的功能 + B 專屬功能
            sed -i.bak "s/^[[:space:]]*inject_static:[[:space:]]*false/    inject_static: true/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*extract_explicit:[[:space:]]*false/    extract_explicit: true/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*index_basic:[[:space:]]*false/    index_basic: true/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*extract_correction:[[:space:]]*false/    extract_correction: true/" "$temp_file"
            # C 的功能保持關閉
            sed -i.bak "s/^[[:space:]]*extract_implicit:[[:space:]]*true/    extract_implicit: false/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*inject_dynamic:[[:space:]]*true/    inject_dynamic: false/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*decay:[[:space:]]*true/    decay: false/" "$temp_file"
            ;;
        C)
            # Phase C: 全部啟用
            sed -i.bak "s/^[[:space:]]*inject_static:[[:space:]]*false/    inject_static: true/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*extract_explicit:[[:space:]]*false/    extract_explicit: true/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*index_basic:[[:space:]]*false/    index_basic: true/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*extract_correction:[[:space:]]*false/    extract_correction: true/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*extract_implicit:[[:space:]]*false/    extract_implicit: true/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*inject_dynamic:[[:space:]]*false/    inject_dynamic: true/" "$temp_file"
            sed -i.bak "s/^[[:space:]]*decay:[[:space:]]*false/    decay: true/" "$temp_file"
            ;;
    esac

    # 清理備份檔案
    rm -f "${temp_file}.bak"

    mv "$temp_file" "$CONFIG_FILE"
}

# ═══════════════════════════════════════════════════════════════
# 查詢功能
# ═══════════════════════════════════════════════════════════════

# 顯示當前配置狀態
# 用法: show_config_status
show_config_status() {
    ensure_config_exists || return $?

    local current_phase
    current_phase=$(get_rollout_phase) || return $?

    echo "📊 Rollout Phase 配置狀態"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "當前 Phase: $current_phase"
    echo ""

    # Phase A 功能
    echo "🔵 Phase A 功能 (只讀模式)"
    print_feature_status "$FEATURE_INJECT_STATIC" "靜態注入 MEMORY.md"
    echo ""

    # Phase B 功能
    echo "🟡 Phase B 功能 (有限寫入)"
    print_feature_status "$FEATURE_EXTRACT_EXPLICIT" "顯式提取（用戶說「記住」）"
    print_feature_status "$FEATURE_INDEX_BASIC" "基礎索引（關鍵字搜尋）"
    print_feature_status "$FEATURE_EXTRACT_CORRECTION" "用戶修正提取"
    echo ""

    # Phase C 功能
    echo "🟢 Phase C 功能 (全功能)"
    print_feature_status "$FEATURE_EXTRACT_IMPLICIT" "隱式提取（自動）"
    print_feature_status "$FEATURE_INJECT_DYNAMIC" "動態注入"
    print_feature_status "$FEATURE_DECAY" "記憶衰退"
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📁 配置檔: $CONFIG_FILE"
}

# 輔助函式：打印功能狀態
# 用法: print_feature_status <feature_name> <description>
print_feature_status() {
    local feature="$1"
    local description="$2"

    if is_feature_enabled "$feature" 2>/dev/null; then
        echo "  ✅ $description"
    else
        echo "  ⬜ $description"
    fi
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_help() {
    cat <<'EOF'
用法: $0 <command> [options]

指令:
  get-phase              取得當前 Rollout Phase (A/B/C)
  set-phase <phase>      設定 Rollout Phase (A/B/C)
  check-feature <name>   檢查特定功能是否啟用
  status                 顯示完整配置狀態（人類可讀格式）

功能名稱常數:
  inject_static          靜態注入 MEMORY.md (Phase A)
  extract_explicit       顯式提取 (Phase B)
  index_basic            基礎索引 (Phase B)
  extract_correction     用戶修正提取 (Phase B)
  extract_implicit       隱式提取 (Phase C)
  inject_dynamic         動態注入 (Phase C)
  decay                  記憶衰退 (Phase C)

範例:
  # 取得當前 Phase
  $0 get-phase

  # 升級到 Phase B
  $0 set-phase B

  # 檢查功能是否啟用
  $0 check-feature inject_static
  echo $?  # 0=啟用, 1=未啟用

  # 顯示完整狀態
  $0 status

返回碼:
  0 - 成功
  1 - 一般錯誤
  2 - 配置檔不存在
  3 - 無效的 Phase 值
EOF
}

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        get-phase)
            get_rollout_phase
            exit $?
            ;;
        set-phase)
            if [ -z "${2:-}" ]; then
                echo "錯誤：必須指定 Phase (A/B/C)" >&2
                exit $EXIT_ERROR
            fi
            set_rollout_phase "$2"
            exit $?
            ;;
        check-feature)
            if [ -z "${2:-}" ]; then
                echo "錯誤：必須指定功能名稱" >&2
                exit $EXIT_ERROR
            fi
            if is_feature_enabled "$2"; then
                echo "enabled"
                exit 0
            else
                echo "disabled"
                exit 1
            fi
            ;;
        status)
            show_config_status
            exit $?
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "錯誤：無效的指令 '${1:-}'" >&2
            echo "" >&2
            show_help
            exit $EXIT_ERROR
            ;;
    esac
fi
