#!/bin/bash
# violation-collector.sh - E2E 測試違規/合規記錄收集器
# 用途: 收集 D→R→T 流程的違規和合規事件
# 輸出: JSON Lines 格式到 /tmp/claude-e2e-stats-{session_id}.jsonl
#
# 使用方式:
#   # 記錄違規
#   echo '{"type":"violation","agent":"tester","reason":"跳過 REVIEWER"}' | bash violation-collector.sh
#
#   # 記錄合規
#   echo '{"type":"compliance","agent":"developer"}' | bash violation-collector.sh
#
#   # 或直接呼叫函數
#   source violation-collector.sh
#   record_violation "tester" "跳過 REVIEWER" "MEDIUM"
#   record_compliance "developer" "MEDIUM"

# 預設 Session ID（可通過環境變數覆蓋）
SESSION_ID="${E2E_SESSION_ID:-default}"
STATS_FILE="/tmp/claude-e2e-stats-${SESSION_ID}.jsonl"
SUMMARY_FILE="/tmp/claude-e2e-summary-${SESSION_ID}.json"

# ═══════════════════════════════════════════════════════════════
# 記錄函數
# ═══════════════════════════════════════════════════════════════

# 記錄違規事件
# 參數: $1=agent, $2=reason, $3=risk_level, $4=change_id (可選)
record_violation() {
    local agent="$1"
    local reason="$2"
    local risk_level="${3:-MEDIUM}"
    local change_id="${4:-}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local json="{\"type\":\"violation\",\"timestamp\":\"$timestamp\",\"agent\":\"$agent\",\"reason\":\"$reason\",\"risk_level\":\"$risk_level\",\"fixed\":false,\"fix_iteration\":0"

    if [ -n "$change_id" ]; then
        json="$json,\"change_id\":\"$change_id\""
    fi

    json="$json}"

    echo "$json" >> "$STATS_FILE"

    # 更新摘要
    update_summary
}

# 記錄合規事件
# 參數: $1=agent, $2=risk_level, $3=change_id (可選)
record_compliance() {
    local agent="$1"
    local risk_level="${2:-MEDIUM}"
    local change_id="${3:-}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local json="{\"type\":\"compliance\",\"timestamp\":\"$timestamp\",\"agent\":\"$agent\",\"risk_level\":\"$risk_level\""

    if [ -n "$change_id" ]; then
        json="$json,\"change_id\":\"$change_id\""
    fi

    json="$json}"

    echo "$json" >> "$STATS_FILE"

    # 更新摘要
    update_summary
}

# 記錄違規已修復
# 參數: $1=violation_timestamp, $2=fix_iteration
record_fix() {
    local violation_ts="$1"
    local fix_iteration="${2:-1}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    echo "{\"type\":\"fix\",\"timestamp\":\"$timestamp\",\"violation_timestamp\":\"$violation_ts\",\"fix_iteration\":$fix_iteration}" >> "$STATS_FILE"

    # 更新摘要
    update_summary
}

# 記錄重試事件
# 參數: $1=agent, $2=reason, $3=retry_count
record_retry() {
    local agent="$1"
    local reason="$2"
    local retry_count="${3:-1}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    echo "{\"type\":\"retry\",\"timestamp\":\"$timestamp\",\"agent\":\"$agent\",\"reason\":\"$reason\",\"retry_count\":$retry_count}" >> "$STATS_FILE"
}

# ═══════════════════════════════════════════════════════════════
# 摘要計算
# ═══════════════════════════════════════════════════════════════

# 更新摘要檔案
update_summary() {
    if [ ! -f "$STATS_FILE" ]; then
        return
    fi

    # 計算統計（確保結果是純數字）
    local total_calls=$(grep -c '"type"' "$STATS_FILE" 2>/dev/null | tr -d '\n\r ' || echo 0)
    local violations=$(grep -c '"type":"violation"' "$STATS_FILE" 2>/dev/null | tr -d '\n\r ' || echo 0)
    local compliances=$(grep -c '"type":"compliance"' "$STATS_FILE" 2>/dev/null | tr -d '\n\r ' || echo 0)
    local fixes=$(grep -c '"type":"fix"' "$STATS_FILE" 2>/dev/null | tr -d '\n\r ' || echo 0)
    local retries=$(grep -c '"type":"retry"' "$STATS_FILE" 2>/dev/null | tr -d '\n\r ' || echo 0)

    # 確保是數字
    [[ ! "$violations" =~ ^[0-9]+$ ]] && violations=0
    [[ ! "$compliances" =~ ^[0-9]+$ ]] && compliances=0

    # 計算風險分布
    local low_risk=$(grep '"risk_level":"LOW"' "$STATS_FILE" 2>/dev/null | wc -l | tr -d ' \n\r')
    local medium_risk=$(grep '"risk_level":"MEDIUM"' "$STATS_FILE" 2>/dev/null | wc -l | tr -d ' \n\r')
    local high_risk=$(grep '"risk_level":"HIGH"' "$STATS_FILE" 2>/dev/null | wc -l | tr -d ' \n\r')

    # 確保是數字
    [[ ! "$low_risk" =~ ^[0-9]+$ ]] && low_risk=0
    [[ ! "$medium_risk" =~ ^[0-9]+$ ]] && medium_risk=0
    [[ ! "$high_risk" =~ ^[0-9]+$ ]] && high_risk=0

    # 計算合規率
    local agent_calls=$((violations + compliances))
    local compliance_rate="0.0"
    if [ "$agent_calls" -gt 0 ]; then
        # 使用 awk 計算百分比
        compliance_rate=$(awk "BEGIN {printf \"%.1f\", ($compliances / $agent_calls) * 100}")
    fi

    # 寫入摘要
    cat > "$SUMMARY_FILE" << EOF
{
  "session_id": "$SESSION_ID",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "summary": {
    "total_agent_calls": $agent_calls,
    "compliances": $compliances,
    "violations": $violations,
    "fixes": $fixes,
    "compliance_rate": "$compliance_rate%"
  },
  "risk_distribution": {
    "LOW": $low_risk,
    "MEDIUM": $medium_risk,
    "HIGH": $high_risk
  },
  "retry_stats": {
    "total_retries": $retries
  }
}
EOF
}

# ═══════════════════════════════════════════════════════════════
# Session 管理
# ═══════════════════════════════════════════════════════════════

# 初始化新 Session
init_session() {
    local session_id="${1:-$(date +%Y%m%d-%H%M%S)}"

    # 設定環境變數
    export E2E_SESSION_ID="$session_id"
    SESSION_ID="$session_id"
    STATS_FILE="/tmp/claude-e2e-stats-${SESSION_ID}.jsonl"
    SUMMARY_FILE="/tmp/claude-e2e-summary-${SESSION_ID}.json"

    # 清空舊檔案
    > "$STATS_FILE"

    # 記錄 session 開始
    echo "{\"type\":\"session_start\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"session_id\":\"$session_id\"}" >> "$STATS_FILE"

    echo "$session_id"
}

# 結束 Session
end_session() {
    echo "{\"type\":\"session_end\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "$STATS_FILE"
    update_summary
}

# 取得 Session 摘要
get_summary() {
    if [ -f "$SUMMARY_FILE" ]; then
        cat "$SUMMARY_FILE"
    else
        echo "{\"error\":\"No summary available\"}"
    fi
}

# 取得所有記錄
get_all_records() {
    if [ -f "$STATS_FILE" ]; then
        cat "$STATS_FILE"
    fi
}

# 取得違規列表
get_violations() {
    if [ -f "$STATS_FILE" ]; then
        grep '"type":"violation"' "$STATS_FILE" 2>/dev/null || true
    fi
}

# 檢查合規率是否達標
check_compliance_rate() {
    local threshold="${1:-90}"

    if [ ! -f "$SUMMARY_FILE" ]; then
        echo "false"
        return
    fi

    local rate=$(jq -r '.summary.compliance_rate' "$SUMMARY_FILE" 2>/dev/null | tr -d '%')

    if [ -z "$rate" ] || [ "$rate" = "null" ]; then
        echo "false"
        return
    fi

    # 比較（使用 awk 處理浮點數）
    local result=$(awk "BEGIN {print ($rate >= $threshold) ? \"true\" : \"false\"}")
    echo "$result"
}

# ═══════════════════════════════════════════════════════════════
# 主程式（從 stdin 讀取時執行）
# ═══════════════════════════════════════════════════════════════

# 如果有 stdin 輸入，處理它
if [ ! -t 0 ]; then
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            # 直接 append 到統計檔案
            echo "$line" >> "$STATS_FILE"
            update_summary
        fi
    done
fi
