#!/bin/bash
# run-all-tests.sh - 執行所有 Claude Workflow Plugin 測試
# 用法: bash tests/scripts/run-all-tests.sh [--verbose]

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 專案根目錄
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TESTS_DIR="$PROJECT_ROOT/tests"
SCRIPTS_DIR="$TESTS_DIR/scripts"
RESULTS_DIR="$TESTS_DIR/results"

# 選項
VERBOSE=false
if [ "$1" = "--verbose" ] || [ "$1" = "-v" ]; then
    VERBOSE=true
fi

# 初始化結果
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

# 測試結果陣列
declare -a TEST_RESULTS

# 輔助函數
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

# 執行單一測試
run_test() {
    local test_id=$1
    local test_script="$SCRIPTS_DIR/test-${test_id}.sh"

    TOTAL=$((TOTAL + 1))

    if [ ! -f "$test_script" ]; then
        log_skip "$test_id: 測試腳本不存在"
        SKIPPED=$((SKIPPED + 1))
        TEST_RESULTS+=("$test_id|SKIP|腳本不存在")
        return
    fi

    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "  執行: $test_id"
        echo "═══════════════════════════════════════════════════════════════"
    fi

    # 執行測試並捕獲輸出
    local output
    local exit_code

    cd "$PROJECT_ROOT"
    output=$(bash "$test_script" 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}

    if [ "$VERBOSE" = true ]; then
        echo "$output"
    fi

    # 判斷結果
    if [ $exit_code -eq 0 ] && echo "$output" | grep -q "✅"; then
        log_pass "$test_id"
        PASSED=$((PASSED + 1))
        TEST_RESULTS+=("$test_id|PASS|")
    elif [ $exit_code -eq 2 ]; then
        log_skip "$test_id: 需要手動測試"
        SKIPPED=$((SKIPPED + 1))
        TEST_RESULTS+=("$test_id|SKIP|需要手動測試")
    else
        log_fail "$test_id"
        FAILED=$((FAILED + 1))
        # 擷取錯誤訊息（最後一行非空行）
        local error_msg=$(echo "$output" | grep -v "^$" | tail -1 | head -c 50)
        TEST_RESULTS+=("$test_id|FAIL|$error_msg")
    fi
}

# 主程式
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║       Claude Workflow Plugin - 測試套件                        ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # 確保結果目錄存在
    mkdir -p "$RESULTS_DIR"

    # 清理舊狀態
    log_info "清理測試狀態..."
    rm -f "$PROJECT_ROOT/.claude/.drt-"* 2>/dev/null || true

    echo ""
    log_info "開始執行測試..."
    echo ""

    # A. 基礎流程測試
    echo "─── A. 基礎流程測試 ───"
    run_test "ts-001"  # Session 啟動
    run_test "ts-002"  # 標準 D→R→T 流程
    run_test "ts-003"  # 違規阻擋
    echo ""

    # B. 反向流程測試
    echo "─── B. 反向流程測試 ───"
    run_test "ts-004"  # REVIEWER REJECT
    run_test "ts-005"  # TESTER FAIL
    echo ""

    # C. 風險等級測試
    echo "─── C. 風險等級測試 ───"
    run_test "ts-006"  # LOW 風險快速通道
    run_test "ts-007"  # HIGH 風險深度審查
    echo ""

    # D. 進階場景測試
    echo "─── D. 進階場景測試 ───"
    run_test "ts-008"  # 並行任務隔離
    run_test "ts-009"  # OpenSpec 生命週期
    run_test "ts-010"  # /loop 持續執行
    run_test "ts-011"  # Session 結束報告
    run_test "ts-012"  # 狀態過期處理
    echo ""

    # E. 組件驗證測試
    echo "─── E. 組件驗證測試 ───"
    run_test "ts-013"  # browser-automation Skill 驗證
    run_test "ts-014"  # Agent Skills 引用一致性
    run_test "ts-015"  # Agent 狀態顯示測試 (agent-status-display.sh)
    run_test "ts-016"  # 自動格式化測試 (auto-format.sh)
    run_test "ts-017"  # 關鍵字檢測測試 (keyword-detector.sh)
    echo ""

    # F. 風險判定進階測試
    echo "─── F. 風險判定進階測試 ───"
    run_test "ts-018"  # 多檔案變更 HIGH RISK 判定
    run_test "ts-019"  # CI/CD 檔案 HIGH RISK 判定
    run_test "ts-020"  # 重試機制與自動升級
    run_test "ts-021"  # HIGH RISK 人工確認步驟
    echo ""

    # G. Hook 進階測試
    echo "─── G. Hook 進階測試 ───"
    run_test "ts-022"  # Session State Init 測試
    run_test "ts-023"  # Session State Cleanup 測試
    run_test "ts-024"  # Global Workflow Guard 測試
    run_test "ts-025"  # Architect Agent 驗證
    echo ""

    # H. Agent 定義驗證測試
    echo "─── H. Agent 定義驗證測試 ───"
    run_test "ts-026"  # Designer Agent 驗證
    run_test "ts-027"  # Debugger Agent 驗證
    echo ""

    # I. Command 驗證測試
    echo "─── I. Command 驗證測試 ───"
    run_test "ts-036"  # /plan 指令測試
    run_test "ts-037"  # /resume 指令驗證
    run_test "ts-038"  # /loop 指令驗證
    run_test "ts-039"  # /validate-agents 指令測試
    run_test "ts-040"  # /validate-skills 指令測試
    run_test "ts-041"  # /validate-hooks 指令測試
    run_test "ts-042"  # /validate-hooks 指令驗證
    echo ""

    # 輸出摘要
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  測試結果摘要"
    echo ""
    echo "  總計: $TOTAL"
    echo -e "  ${GREEN}通過: $PASSED${NC}"
    echo -e "  ${RED}失敗: $FAILED${NC}"
    echo -e "  ${YELLOW}跳過: $SKIPPED${NC}"
    echo ""

    # 產生報告
    local report_file="$RESULTS_DIR/test-report-$(date +%Y%m%d-%H%M%S).md"
    generate_report "$report_file"

    log_info "報告已產生: $report_file"

    # 返回結果
    if [ $FAILED -gt 0 ]; then
        echo ""
        log_fail "有 $FAILED 個測試失敗"
        exit 1
    else
        echo ""
        log_pass "所有測試通過！"
        exit 0
    fi
}

# 產生 Markdown 報告
generate_report() {
    local report_file=$1

    cat > "$report_file" << EOF
# 測試報告

> 執行時間: $(date '+%Y-%m-%d %H:%M:%S')
> 專案: Claude Workflow Plugin

## 摘要

| 項目 | 數量 |
|------|------|
| 總計 | $TOTAL |
| 通過 | $PASSED |
| 失敗 | $FAILED |
| 跳過 | $SKIPPED |

## 詳細結果

| ID | 狀態 | 備註 |
|:--:|:----:|------|
EOF

    for result in "${TEST_RESULTS[@]}"; do
        local id=$(echo "$result" | cut -d'|' -f1)
        local status=$(echo "$result" | cut -d'|' -f2)
        local note=$(echo "$result" | cut -d'|' -f3)

        local status_icon
        case "$status" in
            PASS) status_icon="✅" ;;
            FAIL) status_icon="❌" ;;
            SKIP) status_icon="⏳" ;;
        esac

        echo "| $id | $status_icon | $note |" >> "$report_file"
    done

    cat >> "$report_file" << EOF

## 環境資訊

- 作業系統: $(uname -s) $(uname -r)
- 專案路徑: $PROJECT_ROOT
- Bash 版本: $BASH_VERSION

## 執行指令

\`\`\`bash
bash tests/scripts/run-all-tests.sh
\`\`\`
EOF
}

# 執行主程式
main "$@"
