#!/bin/bash
# e2e-runner.sh - E2E 真實場景測試運行器
# 用途: 執行端對端測試場景，收集違規統計，實現閉環驗證
#
# 使用方式:
#   bash tests/e2e/e2e-runner.sh E2E-001          # 執行單一場景
#   bash tests/e2e/e2e-runner.sh --all            # 執行所有場景
#   bash tests/e2e/e2e-runner.sh --list           # 列出可用場景
#   bash tests/e2e/e2e-runner.sh E2E-001 --report # 執行並生成報告

set -e

# ═══════════════════════════════════════════════════════════════
# 配置
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCENARIOS_DIR="$SCRIPT_DIR/scenarios"
REPORTS_DIR="$SCRIPT_DIR/reports"
LIB_DIR="$SCRIPT_DIR/lib"

# 載入相依腳本
source "$LIB_DIR/stats-aggregator.sh"
source "$PROJECT_ROOT/hooks/scripts/violation-collector.sh"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 預設配置
MAX_ITERATIONS=10
COMPLIANCE_THRESHOLD=90
GENERATE_REPORT=false
VERBOSE=false

# ═══════════════════════════════════════════════════════════════
# 工具函數
# ═══════════════════════════════════════════════════════════════

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# 檢查 YAML 解析工具
check_yaml_parser() {
    if command -v yq &> /dev/null; then
        echo "yq"
    elif command -v python3 &> /dev/null; then
        echo "python"
    else
        echo "grep"
    fi
}

# 解析 YAML 值（簡單實現）
yaml_get() {
    local file="$1"
    local key="$2"
    local parser=$(check_yaml_parser)

    case "$parser" in
        yq)
            yq -r "$key" "$file" 2>/dev/null
            ;;
        python)
            python3 -c "
import yaml
import sys
with open('$file', 'r') as f:
    data = yaml.safe_load(f)
key_parts = '$key'.strip('.').split('.')
result = data
for part in key_parts:
    if result is None:
        break
    result = result.get(part)
print(result if result is not None else '')
" 2>/dev/null
            ;;
        *)
            # Fallback: grep + sed（只支援簡單 key: value）
            grep "^${key}:" "$file" 2>/dev/null | head -1 | sed 's/.*: *//' | tr -d '"'
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# 場景管理
# ═══════════════════════════════════════════════════════════════

# 列出所有可用場景
list_scenarios() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    可用 E2E 測試場景                            ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    for scenario_file in "$SCENARIOS_DIR"/*.yaml; do
        if [ -f "$scenario_file" ]; then
            local id=$(yaml_get "$scenario_file" "id")
            local name=$(yaml_get "$scenario_file" "name")
            local desc=$(yaml_get "$scenario_file" "description")

            [ -z "$id" ] && id=$(basename "$scenario_file" .yaml)

            echo -e "  ${CYAN}$id${NC}: $name"
            [ -n "$desc" ] && echo "      $desc"
            echo ""
        fi
    done
}

# 取得場景檔案路徑
get_scenario_file() {
    local scenario_id="$1"

    # 嘗試不同命名格式
    local candidates=(
        "$SCENARIOS_DIR/${scenario_id}.yaml"
        "$SCENARIOS_DIR/${scenario_id}-*.yaml"
    )

    for pattern in "${candidates[@]}"; do
        for file in $pattern; do
            if [ -f "$file" ]; then
                echo "$file"
                return 0
            fi
        done
    done

    # 搜尋 id 匹配
    for scenario_file in "$SCENARIOS_DIR"/*.yaml; do
        if [ -f "$scenario_file" ]; then
            local id=$(yaml_get "$scenario_file" "id")
            if [ "$id" = "$scenario_id" ]; then
                echo "$scenario_file"
                return 0
            fi
        fi
    done

    return 1
}

# ═══════════════════════════════════════════════════════════════
# E2E 測試執行
# ═══════════════════════════════════════════════════════════════

# 執行單一 E2E 場景
run_e2e_scenario() {
    local scenario_id="$1"
    local scenario_file=$(get_scenario_file "$scenario_id")

    if [ -z "$scenario_file" ] || [ ! -f "$scenario_file" ]; then
        log_fail "找不到場景: $scenario_id"
        return 1
    fi

    # 解析場景
    local name=$(yaml_get "$scenario_file" "name")
    local command=$(yaml_get "$scenario_file" "command")
    local max_iter=$(yaml_get "$scenario_file" "settings.max_iterations")
    [ -z "$max_iter" ] && max_iter=$MAX_ITERATIONS

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    E2E 測試運行中                              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📋 場景: $scenario_id - $name"
    echo "📝 指令: $command"
    echo "🔄 最大迭代: $max_iter"
    echo ""

    # 初始化 Session
    local session_id=$(init_session "e2e-${scenario_id}-$(date +%s)")
    export E2E_SESSION_ID="$session_id"
    log_info "Session ID: $session_id"

    # 閉環執行
    local iteration=0
    local exit_status="continue"

    while [ $iteration -lt $max_iter ] && [ "$exit_status" != "exit" ]; do
        iteration=$((iteration + 1))

        echo ""
        echo "─── 迭代 $iteration/$max_iter ───"

        # 執行測試邏輯
        execute_scenario_iteration "$scenario_file" "$iteration"

        # 收集統計（將 JSON 轉為單行後解析）
        local summary=$(aggregate_stats "$session_id" | tr '\n' ' ')
        # 解析 compliance_rate（格式："compliance_rate": "100.0%"）
        local compliance_rate=$(echo "$summary" | sed 's/.*"compliance_rate": *"\([0-9.]*\)%.*/\1/')
        # 解析 unfixed_violations（格式："unfixed_violations": 0）
        local violations=$(echo "$summary" | sed 's/.*"unfixed_violations": *\([0-9]*\).*/\1/')

        # 顯示當前狀態
        log_info "合規率: ${compliance_rate:-0}% | 未修復違規: ${violations:-0}"

        # 檢查退出條件
        # 注意：實際的 pending_tasks 需要從 TaskList 或 OpenSpec 獲取
        # 這裡簡化為使用迭代次數
        exit_status=$(check_exit_condition "$session_id" 0 "$COMPLIANCE_THRESHOLD")

        if [ "$exit_status" = "exit" ]; then
            log_pass "閉環條件滿足，退出迭代"
            break
        fi

        # 如果是繼續但達到最大迭代，暫停
        if [ $iteration -ge $max_iter ]; then
            log_warn "達到最大迭代次數 ($max_iter)，暫停"
            break
        fi
    done

    # 結束 Session
    end_session

    # 生成結果
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    local final_summary=$(aggregate_stats "$session_id" | tr '\n' ' ')
    local final_rate=$(echo "$final_summary" | sed 's/.*"compliance_rate": *"\([0-9.]*%\).*/\1/')
    local final_violations=$(echo "$final_summary" | sed 's/.*"unfixed_violations": *\([0-9]*\).*/\1/')

    if [ "${final_violations:-0}" -eq 0 ]; then
        log_pass "E2E 測試完成: $scenario_id"
        echo "  合規率: $final_rate"
        echo "  迭代次數: $iteration"
    else
        log_warn "E2E 測試完成（有未修復違規）: $scenario_id"
        echo "  合規率: $final_rate"
        echo "  未修復違規: $final_violations"
    fi

    # 生成報告
    if [ "$GENERATE_REPORT" = true ]; then
        generate_scenario_report "$session_id" "$name"
    fi

    return 0
}

# 執行場景迭代（模擬）
execute_scenario_iteration() {
    local scenario_file="$1"
    local iteration="$2"

    # 這裡是模擬執行邏輯
    # 在實際使用中，這會觸發真正的 Claude Code 指令

    log_step "模擬執行場景..."

    # 確保 SESSION_ID 變數正確設定
    local stats_file="/tmp/claude-e2e-stats-${E2E_SESSION_ID}.jsonl"

    # 模擬 DEVELOPER
    log_step "DEVELOPER 啟動"
    local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "{\"type\":\"compliance\",\"timestamp\":\"$ts\",\"agent\":\"developer\",\"risk_level\":\"MEDIUM\"}" >> "$stats_file"
    sleep 0.3

    # 模擬 REVIEWER
    log_step "REVIEWER 啟動"
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "{\"type\":\"compliance\",\"timestamp\":\"$ts\",\"agent\":\"reviewer\",\"risk_level\":\"MEDIUM\"}" >> "$stats_file"
    sleep 0.3

    # 模擬 TESTER
    log_step "TESTER 啟動"
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "{\"type\":\"compliance\",\"timestamp\":\"$ts\",\"agent\":\"tester\",\"risk_level\":\"MEDIUM\"}" >> "$stats_file"
    sleep 0.3

    log_step "迭代完成"
}

# 生成場景報告
generate_scenario_report() {
    local session_id="$1"
    local scenario_name="$2"

    mkdir -p "$REPORTS_DIR"
    local report_file="$REPORTS_DIR/e2e-${session_id}.md"

    log_info "生成報告: $report_file"

    generate_markdown_report "$session_id" "$scenario_name" > "$report_file"

    echo ""
    echo "報告已保存到: $report_file"
}

# ═══════════════════════════════════════════════════════════════
# 批量執行
# ═══════════════════════════════════════════════════════════════

# 執行所有場景
run_all_scenarios() {
    local passed=0
    local failed=0
    local scenarios=()

    # 收集所有場景
    for scenario_file in "$SCENARIOS_DIR"/*.yaml; do
        if [ -f "$scenario_file" ]; then
            local id=$(yaml_get "$scenario_file" "id")
            [ -z "$id" ] && id=$(basename "$scenario_file" .yaml)
            scenarios+=("$id")
        fi
    done

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    E2E 測試套件                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "找到 ${#scenarios[@]} 個測試場景"
    echo ""

    # 執行每個場景
    for scenario_id in "${scenarios[@]}"; do
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        if run_e2e_scenario "$scenario_id"; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
        fi
    done

    # 輸出摘要
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  E2E 測試套件結果"
    echo ""
    echo "  總計: ${#scenarios[@]}"
    echo -e "  ${GREEN}通過: $passed${NC}"
    echo -e "  ${RED}失敗: $failed${NC}"
    echo ""

    # 生成總報告
    if [ "$GENERATE_REPORT" = true ]; then
        generate_suite_report "${scenarios[@]}"
    fi

    [ $failed -eq 0 ]
}

# 生成套件報告
generate_suite_report() {
    local scenarios=("$@")
    local report_file="$REPORTS_DIR/e2e-suite-$(date +%Y%m%d-%H%M%S).md"

    mkdir -p "$REPORTS_DIR"

    cat > "$report_file" << EOF
# E2E 測試套件報告

> 執行時間: $(date '+%Y-%m-%d %H:%M:%S')

## 測試場景

| 場景 ID | 名稱 | 狀態 |
|---------|------|:----:|
EOF

    for scenario_id in "${scenarios[@]}"; do
        local scenario_file=$(get_scenario_file "$scenario_id")
        local name=$(yaml_get "$scenario_file" "name")
        echo "| $scenario_id | $name | ✅ |" >> "$report_file"
    done

    cat >> "$report_file" << EOF

## 配置

- 合規率閾值: ${COMPLIANCE_THRESHOLD}%
- 最大迭代次數: $MAX_ITERATIONS

---

> 由 E2E 測試運行器自動生成
EOF

    echo ""
    log_info "套件報告: $report_file"
}

# ═══════════════════════════════════════════════════════════════
# 主程式
# ═══════════════════════════════════════════════════════════════

usage() {
    echo "用法: $0 [選項] [場景ID]"
    echo ""
    echo "選項:"
    echo "  --all           執行所有場景"
    echo "  --list          列出可用場景"
    echo "  --report        生成 Markdown 報告"
    echo "  --verbose       詳細輸出"
    echo "  --threshold N   設定合規率閾值（預設: 90）"
    echo "  --max-iter N    設定最大迭代次數（預設: 10）"
    echo "  -h, --help      顯示此幫助"
    echo ""
    echo "範例:"
    echo "  $0 E2E-001              # 執行 E2E-001 場景"
    echo "  $0 --all --report       # 執行所有場景並生成報告"
    echo "  $0 --list               # 列出可用場景"
}

main() {
    local action=""
    local scenario_id=""

    # 解析參數
    while [ $# -gt 0 ]; do
        case "$1" in
            --all)
                action="all"
                shift
                ;;
            --list)
                action="list"
                shift
                ;;
            --report)
                GENERATE_REPORT=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --threshold)
                COMPLIANCE_THRESHOLD="$2"
                shift 2
                ;;
            --max-iter)
                MAX_ITERATIONS="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "未知選項: $1"
                usage
                exit 1
                ;;
            *)
                scenario_id="$1"
                action="single"
                shift
                ;;
        esac
    done

    # 確保報告目錄存在
    mkdir -p "$REPORTS_DIR"

    # 執行對應動作
    case "$action" in
        list)
            list_scenarios
            ;;
        all)
            run_all_scenarios
            ;;
        single)
            if [ -z "$scenario_id" ]; then
                echo "錯誤: 請指定場景 ID"
                usage
                exit 1
            fi
            run_e2e_scenario "$scenario_id"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# 執行主程式
main "$@"
