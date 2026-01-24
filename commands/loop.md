---
name: loop
description: 持續執行直到所有任務完成（通用模式）。觸發詞：loop、持續執行、自動完成、做到完
argument-hint: "[task-source] - 可選，指定任務來源（change-id 或 'todo'）"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - Task
  - Bash
  - TaskList
  - TaskGet
  - TaskUpdate
  - TaskCreate
---

# /loop Command

**持續執行模式** - 自動完成所有任務，直到沒有待辦事項。

## 核心理念

Loop 不只是 OpenSpec 專用 — 它是一個**通用的持續執行模式**，可以在任何情況下使用。

## 使用方式

```
/loop                    # 自動偵測任務來源（TodoList 或 OpenSpec）
/loop todo               # 明確使用 TodoList 作為任務來源
/loop add-user-auth      # 指定特定的 OpenSpec change-id
```

## 任務來源優先順序

```
1. 如果指定了 change-id → 使用 OpenSpec tasks.md
2. 如果指定 'todo' → 使用 TodoList
3. 自動偵測：
   - 有 pending 的 TodoList 任務 → 使用 TodoList
   - 有進行中的 OpenSpec → 使用 OpenSpec tasks.md
   - 都沒有 → 詢問用戶要做什麼
```

## 執行步驟

### Phase 1: 確定任務來源

```
TaskList 有待處理任務？ → 使用 TodoList
openspec/changes/ 有進行中？ → 使用 OpenSpec
都沒有 → 詢問用戶
```

### Phase 2: 持續迴圈

```
while (有未完成的任務) {
  1. 取得下一個待處理任務
  2. 判斷風險等級（LOW/MEDIUM/HIGH）
  3. 根據風險等級執行對應流程：
     - LOW:    D → 完成
     - MEDIUM: D → R → T → 完成
     - HIGH:   D → R(深度) → T(完整) → 完成
  4. 標記任務完成
  5. 如果有程式碼變更，commit
}
```

### Phase 3: 完成處理

```
如果是 OpenSpec → 移動到 archive/
生成完成報告
提示所有任務已完成
```

## 進度顯示

### TodoList 模式

```
╔════════════════════════════════════════════════════════════════╗
║                    🔁 Loop 模式運行中（TodoList）               ║
╚════════════════════════════════════════════════════════════════╝

📊 總體進度: 3/7 任務完成 (42.9%)

🔄 當前任務:
├── #4: 實作登入 API endpoint
├── 風險: 🟡 MEDIUM → D→R→T 流程
└── D→R→T: DEVELOPER ✅ → REVIEWER 🔄 → TESTER ⏳

⏳ 剩餘: 4 個任務
```

### OpenSpec 模式

```
╔════════════════════════════════════════════════════════════════╗
║                    🔁 Loop 模式運行中（OpenSpec）               ║
╚════════════════════════════════════════════════════════════════╝

📁 Change: add-user-auth
📊 總體進度: 5/12 任務完成 (41.7%)
├── ✅ Phase 1: Foundation   - 3/3 完成
├── 🔄 Phase 2: Features     - 2/5 進行中
└── ⏳ Phase 3: Integration  - 0/4 待處理

🔄 當前: Task 2.3 建立 PaymentService
├── D→R→T: DEVELOPER ✅ → REVIEWER 🔄 → TESTER ⏳
└── 剩餘: 7 個任務
```

## 中斷處理

| 操作 | 效果 |
|------|------|
| `Ctrl+C` | 安全中斷，進度自動保存 |
| `/loop` | 重新進入 Loop 模式，從上次中斷處繼續 |
| `/resume` | 單步執行模式（不持續） |

## 任務選取邏輯

### TodoList 模式
1. 按 TaskList 順序執行 pending 任務
2. 如果任務有 `blockedBy`，等待依賴完成
3. 可並行執行無依賴的任務

### OpenSpec 模式
1. **Phase 順序**：按 Phase 編號順序（1 → 2 → 3）
2. **任務順序**：
   - `(sequential)` Phase：按任務編號順序
   - `(parallel)` Phase：可並行執行多個任務
3. **依賴處理**：如果任務有 `blocked-by`，等待依賴完成

## 風險判定與流程

| 風險等級 | 判定條件 | 流程 |
|:--------:|----------|------|
| 🟢 LOW | 文檔、配置、格式 | D → 完成 |
| 🟡 MEDIUM | 一般功能、< 100 行 | D → R → T |
| 🔴 HIGH | 核心邏輯、安全、API | D → R(opus) → T(完整) |

## 錯誤處理

| 情況 | 處理 |
|------|------|
| REVIEWER REJECT | 自動委派 DEVELOPER 修復 → 重新 D→R→T |
| TESTER FAIL | DEBUGGER 分析 → DEVELOPER 修復 → 重新 D→R→T |
| 連續失敗 3 次 | 暫停並詢問用戶 |
| 無任務可執行 | 提示完成或詢問下一步 |

## 範例流程

### 範例 1: TodoList 模式

```
用戶: 幫我實作用戶登入功能，包含 API、前端頁面、測試

AI: 我來建立任務清單...
    [TaskCreate: 實作登入 API]
    [TaskCreate: 建立登入頁面]
    [TaskCreate: 撰寫整合測試]

用戶: /loop

AI: 偵測到 TodoList 有 3 個待處理任務
    進入 Loop 模式...

    🔄 任務 #1: 實作登入 API
    └── 風險: 🟡 MEDIUM → 執行 D→R→T...

    ...（持續執行直到完成）...

    🎉 所有任務完成！
```

### 範例 2: OpenSpec 模式

```
用戶: /loop add-user-auth

AI: 找到 OpenSpec: openspec/changes/add-user-auth/
    📊 總體進度: 0/8 任務完成 (0%)

    開始執行...

    ...（持續執行直到完成）...

    🎉 所有任務完成！
    已歸檔: openspec/archive/add-user-auth/
```

## 與其他指令的關係

| 指令 | 用途 | 與 /loop 的差異 |
|------|------|----------------|
| `/plan` | 建立新的 OpenSpec | 規劃階段，不執行 |
| `/resume` | 恢復進行中的工作 | 單步執行，不持續 |
| `/loop` | 持續執行直到完成 | **全自動模式** |

## 口語觸發

以下說法都會觸發 `/loop`：

```
"持續執行直到完成"
"自動完成所有任務"
"做到完"
"loop"
"/loop add-user-auth"
```

## 適用場景

- ✅ 有明確任務清單需要逐一完成
- ✅ 長時間開發任務，希望自動持續進行
- ✅ OpenSpec 功能開發的完整執行
- ✅ 批量處理多個小任務
- ❌ 探索性任務（不確定要做什麼）
- ❌ 需要頻繁人工決策的任務
