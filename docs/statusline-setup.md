# Status Line 設定說明

## 功能

在 Claude Code 的狀態列動態顯示當前執行的 Agent 名稱。

## 安裝

Status Line 腳本已安裝至：
```
~/.claude/statusline.sh
```

Claude Code 會自動偵測並定期執行此腳本來更新狀態列。

## 顯示映射

| Agent 狀態 | 顯示文字 |
|-----------|---------|
| main | 🤖 MAIN |
| developer | 💻 DEVELOPER |
| reviewer | 🔍 REVIEWER |
| tester | 🧪 TESTER |
| debugger | 🐛 DEBUGGER |
| architect | 🏗️ ARCHITECT |
| designer | 🎨 DESIGNER |
| (其他) | 🤖 [名稱大寫] |

## 運作機制

1. **SubagentStart 事件**：當 Agent 啟動時，`agent-status-display.sh` 將 agent 名稱寫入狀態檔案
2. **SessionStart 事件**：初始化狀態為 `main`
3. **Status Line 讀取**：`statusline.sh` 讀取狀態檔案並輸出對應的顯示文字
4. **SessionEnd 事件**：清理狀態檔案

## 狀態檔案位置

```
/tmp/claude-agent-state-${CLAUDE_SESSION_ID}
```

每個 session 獨立維護自己的狀態。

## 測試

```bash
# 手動測試腳本
bash ~/.claude/statusline.sh

# 模擬不同 agent 狀態
echo "reviewer" > /tmp/claude-agent-state-${CLAUDE_SESSION_ID}
bash ~/.claude/statusline.sh
# 應輸出: 🔍 REVIEWER
```

## 維護

如需修改顯示樣式或新增 agent 類型，編輯：
```bash
vi ~/.claude/statusline.sh
```

修改後無需重啟 Claude Code，下次執行時自動生效。
