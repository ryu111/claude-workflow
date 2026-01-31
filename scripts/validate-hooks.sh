#!/bin/bash
# validate-hooks.sh - 驗證 Hooks 配置
# 功能: 檢查 hooks.json 和所有腳本檔案

set -e

# 載入共用函式庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/validate-utils.sh"

# 計算路徑
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$PLUGIN_DIR/hooks"
HOOKS_JSON="$HOOKS_DIR/hooks.json"

# 計數器
TOTAL_HOOKS=0
VALID_HOOKS=0
ERRORS=0
WARNINGS=0

print_header "🔍 Hooks 配置驗證"

# 1. 檢查 hooks.json 是否存在
log_info "檢查 hooks.json..."
if ! check_file_exists "$HOOKS_JSON"; then
    log_fail "hooks.json 不存在: $HOOKS_JSON"
    ERRORS=$((ERRORS + 1))
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo -e "║              ${RED}❌ 驗證失敗${NC}                                      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    exit 1
fi
log_pass "hooks.json 存在"

# 2. 驗證 JSON 語法
echo ""
log_info "驗證 JSON 語法..."
if ! jq empty "$HOOKS_JSON" 2>/dev/null; then
    log_fail "JSON 語法錯誤"
    ERRORS=$((ERRORS + 1))
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo -e "║              ${RED}❌ 驗證失敗${NC}                                      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    exit 1
fi
log_pass "JSON 語法正確"

# 3. 檢查每個 Hook 事件
echo ""
log_info "檢查 Hook 事件..."

# 支援的事件類型
SUPPORTED_EVENTS="SessionStart PreToolUse PostToolUse SubagentStop Stop PreCompact SessionEnd Notification UserPromptSubmit"

# 取得 hooks.json 中的所有事件（支援新結構：.hooks 或舊結構：根層級）
if jq -e '.hooks' "$HOOKS_JSON" >/dev/null 2>&1; then
    EVENTS=$(jq -r '.hooks | keys[]' "$HOOKS_JSON")
    HOOKS_PATH=".hooks"
else
    EVENTS=$(jq -r 'keys[]' "$HOOKS_JSON")
    HOOKS_PATH=""
fi

for EVENT in $EVENTS; do
    # 跳過非事件類型的 key（如 description）
    if [ "$EVENT" = "description" ] || [ "$EVENT" = "version" ]; then
        continue
    fi

    echo ""
    echo -e "   ${BLUE}▸${NC} 事件: $EVENT"

    # 檢查是否為支援的事件類型
    if ! echo "$SUPPORTED_EVENTS" | grep -qw "$EVENT"; then
        log_warn "未知的事件類型"
        WARNINGS=$((WARNINGS + 1))
    fi

    # 取得該事件的 hooks 數量（支援新舊結構）
    if [ -n "$HOOKS_PATH" ]; then
        HOOK_COUNT=$(jq -r "${HOOKS_PATH}[\"$EVENT\"] | length" "$HOOKS_JSON")
    else
        HOOK_COUNT=$(jq -r ".[\"$EVENT\"] | length" "$HOOKS_JSON")
    fi

    for ((i=0; i<HOOK_COUNT; i++)); do
        if [ -n "$HOOKS_PATH" ]; then
            MATCHER=$(jq -r "${HOOKS_PATH}[\"$EVENT\"][$i].matcher // \".*\"" "$HOOKS_JSON")
            HOOKS_IN_ENTRY=$(jq -r "${HOOKS_PATH}[\"$EVENT\"][$i].hooks | length" "$HOOKS_JSON")
        else
            MATCHER=$(jq -r ".[\"$EVENT\"][$i].matcher // \".*\"" "$HOOKS_JSON")
            HOOKS_IN_ENTRY=$(jq -r ".[\"$EVENT\"][$i].hooks | length" "$HOOKS_JSON")
        fi

        echo -e "      Matcher: $MATCHER"

        for ((j=0; j<HOOKS_IN_ENTRY; j++)); do
            TOTAL_HOOKS=$((TOTAL_HOOKS + 1))

            if [ -n "$HOOKS_PATH" ]; then
                HOOK_TYPE=$(jq -r "${HOOKS_PATH}[\"$EVENT\"][$i].hooks[$j].type" "$HOOKS_JSON")
                COMMAND=$(jq -r "${HOOKS_PATH}[\"$EVENT\"][$i].hooks[$j].command" "$HOOKS_JSON")
                TIMEOUT=$(jq -r "${HOOKS_PATH}[\"$EVENT\"][$i].hooks[$j].timeout // \"(default)\"" "$HOOKS_JSON")
            else
                HOOK_TYPE=$(jq -r ".[\"$EVENT\"][$i].hooks[$j].type" "$HOOKS_JSON")
                COMMAND=$(jq -r ".[\"$EVENT\"][$i].hooks[$j].command" "$HOOKS_JSON")
                TIMEOUT=$(jq -r ".[\"$EVENT\"][$i].hooks[$j].timeout // \"(default)\"" "$HOOKS_JSON")
            fi

            echo -e "      Hook $((j+1)): type=$HOOK_TYPE, timeout=$TIMEOUT"

            # 檢查 command 類型的 hook
            if [ "$HOOK_TYPE" = "command" ]; then
                # 提取腳本路徑（替換 ${CLAUDE_PLUGIN_ROOT}）
                SCRIPT_PATH=$(echo "$COMMAND" | sed 's/bash //' | sed "s|\${CLAUDE_PLUGIN_ROOT}|$PLUGIN_DIR|g")

                # 檢查腳本是否存在
                if check_file_exists "$SCRIPT_PATH"; then
                    # 檢查是否有執行權限
                    if check_file_executable "$SCRIPT_PATH"; then
                        echo -e "         ${GREEN}✓${NC} 腳本存在且可執行"
                        VALID_HOOKS=$((VALID_HOOKS + 1))
                    else
                        echo -e "         ${YELLOW}⚠${NC} 腳本存在但無執行權限: $SCRIPT_PATH"
                        WARNINGS=$((WARNINGS + 1))
                        VALID_HOOKS=$((VALID_HOOKS + 1))
                    fi
                else
                    echo -e "         ${RED}✗${NC} 腳本不存在: $SCRIPT_PATH"
                    ERRORS=$((ERRORS + 1))
                fi

                # 檢查是否使用 ${CLAUDE_PLUGIN_ROOT}
                if ! echo "$COMMAND" | grep -q '\${CLAUDE_PLUGIN_ROOT}'; then
                    echo -e "         ${YELLOW}⚠${NC} 建議使用 \${CLAUDE_PLUGIN_ROOT} 變數"
                    WARNINGS=$((WARNINGS + 1))
                fi
            fi
        done
    done
done

# 4. 列出腳本目錄中的所有腳本
echo ""
log_info "檢查腳本目錄..."
SCRIPTS_DIR="$HOOKS_DIR/scripts"

if check_dir_exists "$SCRIPTS_DIR"; then
    log_pass "腳本目錄存在: $SCRIPTS_DIR"

    # 列出所有腳本
    SCRIPT_FILES=$(find "$SCRIPTS_DIR" -name "*.sh" -type f 2>/dev/null | sort)
    SCRIPT_COUNT=$(echo "$SCRIPT_FILES" | grep -c "\.sh$" || echo 0)

    echo -e "   找到 $SCRIPT_COUNT 個腳本檔案:"

    for SCRIPT in $SCRIPT_FILES; do
        SCRIPT_NAME=$(basename "$SCRIPT")
        if check_file_executable "$SCRIPT"; then
            echo -e "      ${GREEN}✓${NC} $SCRIPT_NAME (可執行)"
        else
            echo -e "      ${YELLOW}⚠${NC} $SCRIPT_NAME (無執行權限)"
        fi
    done
else
    log_fail "腳本目錄不存在: $SCRIPTS_DIR"
    ERRORS=$((ERRORS + 1))
fi

# 5. 摘要報告
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "                        驗證摘要"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "   總 Hooks 數: $TOTAL_HOOKS"
echo "   有效 Hooks: $VALID_HOOKS"
echo -e "   錯誤: ${RED}$ERRORS${NC}"
echo -e "   警告: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo -e "║              ${GREEN}✅ 所有 Hooks 驗證通過${NC}                          ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    exit 0
else
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo -e "║              ${RED}❌ 驗證失敗，請修復上述錯誤${NC}                      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    exit 1
fi
