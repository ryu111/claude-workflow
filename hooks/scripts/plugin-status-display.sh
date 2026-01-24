#!/bin/bash
# plugin-status-display.sh - Plugin 載入時提供 AI Context
# 事件: SessionStart
# 功能: 注入 D→R→T 工作流規則作為 AI context

# 輸出 JSON 格式的 AI context（提供有用的工作流規則）
cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "## Claude Workflow Plugin 已啟用\n\n### D→R→T 流程強制執行中\n\n所有程式碼變更必須遵循：\n1. **DEVELOPER** 實作程式碼\n2. **REVIEWER** 審查（APPROVE/REJECT）\n3. **TESTER** 測試（PASS/FAIL）\n\n### 風險等級判定\n- 🟢 LOW（文檔、設定）→ D→T\n- 🟡 MEDIUM（一般功能）→ D→R→T\n- 🔴 HIGH（安全、API）→ D→R(opus)→T\n\n### 禁止事項\n- 跳過 REVIEWER 直接進入 TESTER\n- 硬編碼魔術字串（使用 enum/常數）\n- REVIEWER/TESTER 不得修改程式碼\n\n### 可用指令\n- `/plan [feature]` - 規劃新功能\n- `/resume [change-id]` - 接手現有工作"
  }
}
EOF

exit 0
