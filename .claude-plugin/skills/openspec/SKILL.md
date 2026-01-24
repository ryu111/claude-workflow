---
name: openspec
description: |
  OpenSpec 規格文件格式與工作流狀態管理。自動載入於規格建立、任務追蹤、進度管理時。
  觸發詞：OpenSpec, 規格, spec, tasks.md, proposal, 接手, resume, 歸檔, archive, 進度, progress, Phase
user-invocable: false
disable-model-invocation: false
---

# OpenSpec 工作流

## 狀態機

```
specs/          changes/          archive/
(Backlog)   →    (WIP)     →     (Done)
 待審核          進行中            已歸檔
```

### 狀態轉換

| 觸發 | 從 | 到 | 動作 |
|------|----|----|------|
| 用戶說「接手」或 `/resume` | specs/ | changes/ | 移動目錄，開始執行 |
| 所有任務 [x] 完成 | changes/ | archive/ | 歸檔，生成報告 |

## 目錄結構

```
openspec/
├── specs/           # Backlog - 待審核的規格
│   └── [change-id]/
│       ├── proposal.md
│       ├── tasks.md
│       └── notes.md
├── changes/         # WIP - 進行中的工作
│   └── [change-id]/
│       ├── proposal.md
│       ├── tasks.md
│       ├── notes.md
│       └── ui-specs/    # 如有 UI 任務
└── archive/         # Done - 已完成的工作
    └── [change-id]/
```

## tasks.md 格式

詳細語法見 [tasks-syntax.md](references/tasks-syntax.md)。

```markdown
## Progress
- Total: 8 tasks
- Completed: 3
- Status: IN_PROGRESS

---

## 1. Foundation (sequential)
- [x] 1.1 任務名稱 | agent: developer | files: src/file.ts
- [ ] 1.2 下一個任務 | agent: developer | files: src/other.ts

## 2. Features (parallel)
- [ ] 2.1 獨立任務 A | agent: developer | files: src/a.ts
- [ ] 2.2 獨立任務 B | agent: developer | files: src/b.ts

## 3. Integration (sequential, depends: 2)
- [ ] 3.1 整合任務 | agent: developer | files: src/index.ts
```

## Phase 類型

| 類型 | 說明 |
|------|------|
| `sequential` | 依序執行，等前一個完成 |
| `parallel` | 可同時啟動多個 Agent |
| `depends: N` | 等待 Phase N 全部完成後才開始 |

## Status 值

| Status | 意義 | 下一步 |
|--------|------|--------|
| `NOT_STARTED` | 尚未開始 | 等待 `/resume` |
| `IN_PROGRESS` | 執行中 | 繼續 D→R→T |
| `COMPLETED` | 全部完成 | 自動歸檔 |
| `BLOCKED` | 卡住了 | 需要用戶介入 |

## 進度保存

每個任務完成後：

1. 更新 checkbox：`[ ]` → `[x]`
2. 更新 Progress 區塊的計數
3. Git commit：`progress: Task X.X [任務名稱]`

## 歸檔流程

所有任務完成後：

1. 移動到 `openspec/archive/[change-id]/`
2. 生成 Session Report
3. Git commit：`chore: archive [change-id]`

## 資源

### Templates

使用範本建立新的規格文件：

- [proposal.md](templates/proposal.md) - 提案文件範本
- [tasks.md](templates/tasks.md) - 任務清單範本
- [notes.md](templates/notes.md) - 備註文件範本

### References

- [tasks-syntax.md](references/tasks-syntax.md) - tasks.md 詳細語法說明

### Examples

- [user-auth-feature.md](examples/user-auth-feature.md) - 完整的用戶認證功能規格範例
