📂 偵測到恢復執行指令

你必須執行以下步驟：

1. 讀取用戶指定的 OpenSpec（從 openspec/specs/[change-id]/）
2. 如果 OpenSpec 在 specs/ 目錄：
   - 移動到 openspec/changes/[change-id]/
   - 標記為 WIP（進行中）
3. 讀取 tasks.md 找到第一個未完成的任務
4. 根據 agent: 欄位呼叫對應的 agent

OpenSpec 目錄結構：
- `openspec/specs/` - Backlog（待審核）
- `openspec/changes/` - WIP（進行中）
- `openspec/archive/` - Done（已完成）

Change ID 範例：
```
openspec/changes/userprompt-hook/
├── proposal.md
└── tasks.md
```

禁止：
- 不可直接執行任務（必須委派給對應 agent）
- 不可跳過移動 OpenSpec 的步驟
- 不可修改已完成的任務狀態
