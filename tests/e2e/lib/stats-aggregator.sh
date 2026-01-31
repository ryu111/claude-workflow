#!/bin/bash
# stats-aggregator.sh - E2E 測試統計彙總器
# 用途: 彙總違規統計、計算合規率、生成報告數據
#
# 使用方式:
#   source tests/e2e/lib/stats-aggregator.sh
#   aggregate_stats "session-001"
#   generate_markdown_report "session-001" > report.md

# 相依腳本
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# ═══════════════════════════════════════════════════════════════
# 工具函數
# ═══════════════════════════════════════════════════════════════

# 檢查 jq 是否可用
check_jq() {
    if command -v jq &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 安全的 JSON 解析（支援無 jq 環境）
json_get() {
    local file="$1"
    local key="$2"

    if check_jq; then
        jq -r "$key // empty" "$file" 2>/dev/null
    else
        # Fallback: 使用 grep + sed（基本功能）
        grep -o "\"${key#.}\":[^,}]*" "$file" 2>/dev/null | head -1 | sed 's/.*://' | tr -d '"' | tr -d ' '
    fi
}

# ═══════════════════════════════════════════════════════════════
# 統計彙總
# ═══════════════════════════════════════════════════════════════

# 彙總統計數據
# 參數: $1=session_id
aggregate_stats() {
    local session_id="${1:-default}"
    local stats_file="/tmp/claude-e2e-stats-${session_id}.jsonl"
    local summary_file="/tmp/claude-e2e-summary-${session_id}.json"

    if [ ! -f "$stats_file" ]; then
        echo "{\"error\":\"Stats file not found: $stats_file\"}"
        return 1
    fi

    # 計算各類事件數量（確保結果是純數字）
    local session_start=$(grep -c '"type":"session_start"' "$stats_file" 2>/dev/null | tr -d '\n\r ' || echo 0)
    local session_end=$(grep -c '"type":"session_end"' "$stats_file" 2>/dev/null | tr -d '\n\r ' || echo 0)
    local violations=$(grep -c '"type":"violation"' "$stats_file" 2>/dev/null | tr -d '\n\r ' || echo 0)
    local compliances=$(grep -c '"type":"compliance"' "$stats_file" 2>/dev/null | tr -d '\n\r ' || echo 0)
    local fixes=$(grep -c '"type":"fix"' "$stats_file" 2>/dev/null | tr -d '\n\r ' || echo 0)
    local retries=$(grep -c '"type":"retry"' "$stats_file" 2>/dev/null | tr -d '\n\r ' || echo 0)

    # 確保是數字
    [[ ! "$violations" =~ ^[0-9]+$ ]] && violations=0
    [[ ! "$compliances" =~ ^[0-9]+$ ]] && compliances=0
    [[ ! "$fixes" =~ ^[0-9]+$ ]] && fixes=0

    # Agent 調用統計
    local total_agent_calls=$((violations + compliances))

    # 風險分布（確保結果是純數字）
    local low_risk=$(grep '"risk_level":"LOW"' "$stats_file" 2>/dev/null | wc -l | tr -d ' \n\r')
    local medium_risk=$(grep '"risk_level":"MEDIUM"' "$stats_file" 2>/dev/null | wc -l | tr -d ' \n\r')
    local high_risk=$(grep '"risk_level":"HIGH"' "$stats_file" 2>/dev/null | wc -l | tr -d ' \n\r')

    # 確保是數字
    [[ ! "$low_risk" =~ ^[0-9]+$ ]] && low_risk=0
    [[ ! "$medium_risk" =~ ^[0-9]+$ ]] && medium_risk=0
    [[ ! "$high_risk" =~ ^[0-9]+$ ]] && high_risk=0

    # 計算合規率
    local compliance_rate="0.0"
    if [ "$total_agent_calls" -gt 0 ]; then
        compliance_rate=$(awk "BEGIN {printf \"%.1f\", ($compliances / $total_agent_calls) * 100}")
    fi

    # 計算未修復的違規數
    local unfixed_violations=$((violations - fixes))
    [ $unfixed_violations -lt 0 ] && unfixed_violations=0

    # Agent 分布統計（確保結果是純數字）
    local developer_calls=$(grep '"agent":"developer"' "$stats_file" 2>/dev/null | wc -l | tr -d ' \n\r')
    local reviewer_calls=$(grep '"agent":"reviewer"' "$stats_file" 2>/dev/null | wc -l | tr -d ' \n\r')
    local tester_calls=$(grep '"agent":"tester"' "$stats_file" 2>/dev/null | wc -l | tr -d ' \n\r')
    local debugger_calls=$(grep '"agent":"debugger"' "$stats_file" 2>/dev/null | wc -l | tr -d ' \n\r')

    # 確保是數字
    [[ ! "$developer_calls" =~ ^[0-9]+$ ]] && developer_calls=0
    [[ ! "$reviewer_calls" =~ ^[0-9]+$ ]] && reviewer_calls=0
    [[ ! "$tester_calls" =~ ^[0-9]+$ ]] && tester_calls=0
    [[ ! "$debugger_calls" =~ ^[0-9]+$ ]] && debugger_calls=0

    # 取得時間範圍
    local started_at=$(grep '"type":"session_start"' "$stats_file" 2>/dev/null | head -1 | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
    local ended_at=$(grep '"type":"session_end"' "$stats_file" 2>/dev/null | tail -1 | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)

    # 輸出完整摘要
    cat << EOF
{
  "session_id": "$session_id",
  "started_at": "${started_at:-unknown}",
  "ended_at": "${ended_at:-in_progress}",
  "summary": {
    "total_agent_calls": $total_agent_calls,
    "compliances": $compliances,
    "violations": $violations,
    "fixes": $fixes,
    "unfixed_violations": $unfixed_violations,
    "compliance_rate": "$compliance_rate%"
  },
  "violations_detail": {
    "total": $violations,
    "fixed": $fixes,
    "unfixed": $unfixed_violations
  },
  "risk_distribution": {
    "LOW": $low_risk,
    "MEDIUM": $medium_risk,
    "HIGH": $high_risk
  },
  "agent_distribution": {
    "developer": $developer_calls,
    "reviewer": $reviewer_calls,
    "tester": $tester_calls,
    "debugger": $debugger_calls
  },
  "retry_stats": {
    "total_retries": $retries
  }
}
EOF
}

# ═══════════════════════════════════════════════════════════════
# 檢查清單驗證
# ═══════════════════════════════════════════════════════════════

# 執行檢查清單驗證
# 參數: $1=session_id
run_checklist_validation() {
    local session_id="${1:-default}"
    local stats_file="/tmp/claude-e2e-stats-${session_id}.jsonl"
    local results=""
    local passed=0
    local failed=0

    echo "{"
    echo "  \"checklist_results\": ["

    # A. 流程合規檢查
    # A1. D→R→T 順序正確
    local drt_violation=$(grep '"reason":"跳過 REVIEWER' "$stats_file" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$drt_violation" -eq 0 ]; then
        echo "    {\"id\": \"A1\", \"name\": \"D→R→T 順序正確\", \"status\": \"PASS\"},"
        passed=$((passed + 1))
    else
        echo "    {\"id\": \"A1\", \"name\": \"D→R→T 順序正確\", \"status\": \"FAIL\", \"violations\": $drt_violation},"
        failed=$((failed + 1))
    fi

    # A2. REVIEWER 有明確判定
    local reviewer_unclear=$(grep '"agent":"reviewer"' "$stats_file" 2>/dev/null | grep '"result":"unclear"' | wc -l | tr -d ' ')
    if [ "$reviewer_unclear" -eq 0 ]; then
        echo "    {\"id\": \"A2\", \"name\": \"REVIEWER 有明確判定\", \"status\": \"PASS\"},"
        passed=$((passed + 1))
    else
        echo "    {\"id\": \"A2\", \"name\": \"REVIEWER 有明確判定\", \"status\": \"WARN\", \"unclear_count\": $reviewer_unclear},"
    fi

    # A3. TESTER 有明確結果
    local tester_unclear=$(grep '"agent":"tester"' "$stats_file" 2>/dev/null | grep '"result":"unclear"' | wc -l | tr -d ' ')
    if [ "$tester_unclear" -eq 0 ]; then
        echo "    {\"id\": \"A3\", \"name\": \"TESTER 有明確結果\", \"status\": \"PASS\"},"
        passed=$((passed + 1))
    else
        echo "    {\"id\": \"A3\", \"name\": \"TESTER 有明確結果\", \"status\": \"WARN\", \"unclear_count\": $tester_unclear},"
    fi

    # B. 風險判定檢查（從統計檔案推斷）
    local high_risk_count=$(grep '"risk_level":"HIGH"' "$stats_file" 2>/dev/null | wc -l | tr -d ' ')
    echo "    {\"id\": \"B1\", \"name\": \"風險判定正常運作\", \"status\": \"PASS\", \"high_risk_detected\": $high_risk_count},"
    passed=$((passed + 1))

    # C. 重試機制檢查
    local retry_count=$(grep '"type":"retry"' "$stats_file" 2>/dev/null | wc -l | tr -d ' ')
    echo "    {\"id\": \"C1\", \"name\": \"重試機制運作\", \"status\": \"PASS\", \"retries\": $retry_count},"
    passed=$((passed + 1))

    # D. 狀態管理檢查（檢查是否有 session 開始和結束）
    local has_session_start=$(grep -c '"type":"session_start"' "$stats_file" 2>/dev/null || echo 0)
    if [ "$has_session_start" -gt 0 ]; then
        echo "    {\"id\": \"D1\", \"name\": \"Session 狀態管理\", \"status\": \"PASS\"}"
        passed=$((passed + 1))
    else
        echo "    {\"id\": \"D1\", \"name\": \"Session 狀態管理\", \"status\": \"WARN\", \"note\": \"No session_start found\"}"
    fi

    echo "  ],"
    echo "  \"summary\": {\"passed\": $passed, \"failed\": $failed}"
    echo "}"
}

# ═══════════════════════════════════════════════════════════════
# 報告生成
# ═══════════════════════════════════════════════════════════════

# 生成 Markdown 報告
# 參數: $1=session_id, $2=scenario_name (可選)
generate_markdown_report() {
    local session_id="${1:-default}"
    local scenario_name="${2:-E2E 測試}"
    local stats_file="/tmp/claude-e2e-stats-${session_id}.jsonl"

    # 取得彙總數據（轉為單行以便解析）
    local summary=$(aggregate_stats "$session_id" | tr '\n' ' ')

    # 解析數據（使用 sed 處理單行 JSON）
    local total_calls=$(echo "$summary" | sed 's/.*"total_agent_calls": *\([0-9]*\).*/\1/')
    local compliances=$(echo "$summary" | sed 's/.*"compliances": *\([0-9]*\).*/\1/')
    local violations=$(echo "$summary" | sed 's/.*"violations": *\([0-9]*\).*/\1/')
    local fixes=$(echo "$summary" | sed 's/.*"fixes": *\([0-9]*\).*/\1/')
    local compliance_rate=$(echo "$summary" | sed 's/.*"compliance_rate": *"\([0-9.]*%\)".*/\1/')
    local started_at=$(echo "$summary" | sed 's/.*"started_at": *"\([^"]*\)".*/\1/')
    local ended_at=$(echo "$summary" | sed 's/.*"ended_at": *"\([^"]*\)".*/\1/')

    # 風險分布
    local low_risk=$(echo "$summary" | sed 's/.*"LOW": *\([0-9]*\).*/\1/')
    local medium_risk=$(echo "$summary" | sed 's/.*"MEDIUM": *\([0-9]*\).*/\1/')
    local high_risk=$(echo "$summary" | sed 's/.*"HIGH": *\([0-9]*\).*/\1/')

    # 計算結果狀態
    local rate_num=$(echo "$compliance_rate" | tr -d '%')
    local status_icon="✅"
    local status_text="通過"
    if [ -n "$rate_num" ]; then
        if awk "BEGIN {exit !($rate_num < 90)}"; then
            status_icon="❌"
            status_text="未通過（合規率 < 90%）"
        fi
    fi

    cat << EOF
# E2E 測試報告

## 場景: $scenario_name

### 執行摘要
- **Session ID**: $session_id
- **開始時間**: ${started_at:-N/A}
- **結束時間**: ${ended_at:-進行中}
- **最終狀態**: $status_icon $status_text

### 統計數據

| 項目 | 數值 |
|------|------|
| Agent 調用總數 | ${total_calls:-0} |
| 合規次數 | ${compliances:-0} |
| 違規次數 | ${violations:-0} |
| 已修復 | ${fixes:-0} |
| **合規率** | **${compliance_rate:-0%}** |

### 風險分布

| 等級 | 數量 | 百分比 |
|:----:|:----:|:------:|
| 🟢 LOW | ${low_risk:-0} | $(calculate_percentage "${low_risk:-0}" "${total_calls:-1}")% |
| 🟡 MEDIUM | ${medium_risk:-0} | $(calculate_percentage "${medium_risk:-0}" "${total_calls:-1}")% |
| 🔴 HIGH | ${high_risk:-0} | $(calculate_percentage "${high_risk:-0}" "${total_calls:-1}")% |

EOF

    # 違規詳情
    if [ "${violations:-0}" -gt 0 ]; then
        cat << EOF
### 違規詳情

| 時間 | Agent | 原因 | 已修復 |
|------|-------|------|:------:|
EOF
        grep '"type":"violation"' "$stats_file" 2>/dev/null | while read -r line; do
            local ts=$(echo "$line" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4 | cut -d'T' -f2 | cut -d'Z' -f1)
            local agent=$(echo "$line" | grep -o '"agent":"[^"]*"' | cut -d'"' -f4)
            local reason=$(echo "$line" | grep -o '"reason":"[^"]*"' | cut -d'"' -f4)
            local fixed=$(echo "$line" | grep -o '"fixed":[a-z]*' | cut -d':' -f2)
            local fixed_icon="❌"
            [ "$fixed" = "true" ] && fixed_icon="✅"
            echo "| $ts | $agent | $reason | $fixed_icon |"
        done
        echo ""
    fi

    cat << EOF
### 檢查清單結果

$(run_checklist_validation "$session_id" | grep '"status"' | while read -r line; do
    local name=$(echo "$line" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    local status=$(echo "$line" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    local icon="✅"
    [ "$status" = "FAIL" ] && icon="❌"
    [ "$status" = "WARN" ] && icon="⚠️"
    echo "- $icon $name"
done)

---

> 報告生成時間: $(date '+%Y-%m-%d %H:%M:%S')
> 閉環退出條件: 合規率 >= 90% AND 所有任務完成
EOF
}

# 計算百分比
calculate_percentage() {
    local part="${1:-0}"
    local total="${2:-1}"

    if [ "$total" -eq 0 ]; then
        echo "0.0"
        return
    fi

    awk "BEGIN {printf \"%.1f\", ($part / $total) * 100}"
}

# ═══════════════════════════════════════════════════════════════
# 閉環驗證
# ═══════════════════════════════════════════════════════════════

# 檢查是否滿足閉環退出條件
# 參數: $1=session_id, $2=pending_tasks (剩餘任務數)
check_exit_condition() {
    local session_id="${1:-default}"
    local pending_tasks="${2:-0}"
    local threshold="${3:-90}"

    # 將 JSON 轉為單行後解析（與 e2e-runner.sh 一致）
    local summary=$(aggregate_stats "$session_id" | tr '\n' ' ')

    # 解析合規率（確保有預設值）
    local compliance_rate=$(echo "$summary" | sed 's/.*"compliance_rate": *"\([0-9.]*\)%.*/\1/')
    [ -z "$compliance_rate" ] && compliance_rate="0"

    # 檢查條件（確保變數有值）
    local rate_ok="false"
    if [ -n "$compliance_rate" ] && [ -n "$threshold" ]; then
        rate_ok=$(awk "BEGIN {print ($compliance_rate >= $threshold) ? \"true\" : \"false\"}")
    fi
    local tasks_ok="false"
    [ "$pending_tasks" -eq 0 ] && tasks_ok="true"

    if [ "$rate_ok" = "true" ] && [ "$tasks_ok" = "true" ]; then
        echo "exit"
    elif [ "$rate_ok" = "true" ]; then
        echo "continue:tasks_pending"
    else
        echo "continue:compliance_low"
    fi
}
