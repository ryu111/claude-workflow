# Task 雙向同步機制

## 概述

tasks.md 與 TaskList（Claude Code 內建的 todo 系統）之間的雙向同步機制。

## 同步架構

```
┌─────────────────┐                      ┌─────────────────┐
│    tasks.md     │ ←──── 雙向同步 ────→ │    TaskList     │
│   （持久化）     │                      │  （即時顯示）    │
└─────────────────┘                      └─────────────────┘
        ↑                                        ↑
        │                                        │
   ARCHITECT                              用戶即時查看
   規劃產出                               任務進度
```

## 同步時機

### 1. 啟動時（tasks.md → TaskList）

當執行「接手」或 `/loop` 時：

```javascript
// 1. 讀取 tasks.md
const content = Read("openspec/changes/{id}/tasks.md");

// 2. 解析任務
const tasks = parseTasksMd(content);
// 結果: [
//   { id: "1.1", name: "初始化專案", completed: true, agent: "developer", files: "..." },
//   { id: "1.2", name: "建立資料庫", completed: false, agent: "developer", files: "..." },
// ]

// 3. 建立 TaskList 項目
for (const task of tasks) {
  TaskCreate({
    subject: `Task ${task.id}: ${task.name}`,
    description: `Agent: ${task.agent}\nFiles: ${task.files}\nPhase: ${task.phase}`,
    activeForm: `處理 Task ${task.id}`
  });

  // 如果已完成，標記 completed
  if (task.completed) {
    TaskUpdate({ taskId: task.id, status: "completed" });
  }
}
```

### 2. 任務執行中（TaskList 狀態更新）

| 階段 | TaskUpdate 參數 |
|------|-----------------|
| 任務開始 | `{ status: "in_progress", activeForm: "開發 Task X.X" }` |
| DEVELOPER 完成 | `{ activeForm: "審查 Task X.X" }` |
| REVIEWER 完成 | `{ activeForm: "測試 Task X.X" }` |
| TESTER FAIL | `{ activeForm: "除錯 Task X.X" }` |

### 3. 任務完成時（雙向同步）

```javascript
// 1. 更新 TaskList
TaskUpdate({
  taskId: currentTask.id,
  status: "completed"
});

// 2. 更新 tasks.md（使用 Edit 工具）
Edit({
  file_path: "openspec/changes/{id}/tasks.md",
  old_string: `- [ ] ${task.id} ${task.name}`,
  new_string: `- [x] ${task.id} ${task.name}`
});

// 3. 更新 Progress 區塊
Edit({
  file_path: "openspec/changes/{id}/tasks.md",
  old_string: `- Completed: ${completed}`,
  new_string: `- Completed: ${completed + 1}`
});
```

## tasks.md 格式

```markdown
## Progress
- Total: 8 tasks
- Completed: 3
- Status: IN_PROGRESS

---

## 1. Foundation (sequential)
- [x] 1.1 初始化專案 | agent: developer | files: package.json
- [x] 1.2 建立資料庫 | agent: developer | files: src/db/
- [ ] 1.3 設定 Auth | agent: developer | files: src/auth/

## 2. Features (parallel)
- [ ] 2.1 User API | agent: developer | files: src/api/user.ts
- [ ] 2.2 Cart API | agent: developer | files: src/api/cart.ts
```

## 解析規則

### Checkbox 狀態

| 格式 | 狀態 |
|------|------|
| `- [ ]` | pending |
| `- [x]` | completed |

### 任務屬性

```
- [ ] 1.1 任務名稱 | agent: developer | files: src/xxx.ts
      │   │              │                  │
      │   │              │                  └─ 涉及檔案
      │   │              └─ 執行的 Agent
      │   └─ 任務名稱
      └─ 任務編號
```

### Phase 類型

| 類型 | 說明 |
|------|------|
| `(sequential)` | 依序執行 |
| `(parallel)` | 可並行執行 |
| `(depends: N)` | 依賴 Phase N |

## 同步範例

### 初始狀態

**tasks.md**:
```markdown
## Progress
- Total: 3
- Completed: 1

## 1. Setup (sequential)
- [x] 1.1 Init | agent: developer | files: package.json
- [ ] 1.2 DB | agent: developer | files: src/db/
- [ ] 1.3 Auth | agent: developer | files: src/auth/
```

**TaskList**:
```
ID: 1 | Task 1.1: Init | ✅ completed
ID: 2 | Task 1.2: DB   | ⏳ pending
ID: 3 | Task 1.3: Auth | ⏳ pending
```

### 執行 Task 1.2 後

**tasks.md**:
```markdown
## Progress
- Total: 3
- Completed: 2  ← 更新

## 1. Setup (sequential)
- [x] 1.1 Init | agent: developer | files: package.json
- [x] 1.2 DB | agent: developer | files: src/db/  ← 更新
- [ ] 1.3 Auth | agent: developer | files: src/auth/
```

**TaskList**:
```
ID: 1 | Task 1.1: Init | ✅ completed
ID: 2 | Task 1.2: DB   | ✅ completed  ← 更新
ID: 3 | Task 1.3: Auth | ⏳ pending
```

## 錯誤處理

| 情況 | 處理 |
|------|------|
| tasks.md 格式錯誤 | 嘗試自動修復，或提示用戶 |
| TaskList 與 tasks.md 不同步 | 以 tasks.md 為主重新同步 |
| 任務 ID 重複 | 使用完整 ID（如 "1.1"）避免衝突 |

## 相關工具

| 工具 | 用途 |
|------|------|
| `TaskCreate` | 建立新任務 |
| `TaskUpdate` | 更新任務狀態 |
| `TaskList` | 列出所有任務 |
| `TaskGet` | 取得任務詳情 |
| `Read` | 讀取 tasks.md |
| `Edit` | 更新 tasks.md |
