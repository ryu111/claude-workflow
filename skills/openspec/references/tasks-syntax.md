# tasks.md 語法詳解

## 任務行格式

```
- [ ] X.Y 任務名稱 | agent: AGENT | files: 路徑 | output: URL
```

### 欄位說明

| 欄位 | 必填 | 說明 | 範例 |
|------|------|------|------|
| `[ ]` | ✅ | 狀態標記 | `[ ]` 待做, `[x]` 完成 |
| `X.Y` | ✅ | 任務編號 (Phase.Task) | `1.1`, `2.3` |
| 任務名稱 | ✅ | 描述要做什麼 | `建立 UserService` |
| `agent` | ✅ | 執行的 Agent | `developer`, `designer` |
| `files` | ✅ | 涉及的檔案/目錄 | `src/services/user.ts` |
| `output` | ❌ | 完成後可預覽的 URL | `http://localhost:3000/api/users` |
| `depends` | ❌ | 依賴的其他任務 | `depends: 1.1` |

## Phase 標記語法

```markdown
## N. Phase名稱 (執行方式)
## N. Phase名稱 (執行方式, depends: M)
```

### 執行方式

| 標記 | 行為 |
|------|------|
| `sequential` | 依序執行，1.1 完成後才做 1.2 |
| `parallel` | 可同時執行所有任務 |
| `depends: N` | 等待 Phase N 全部完成 |

## Progress 區塊

```markdown
## Progress
- Total: 8 tasks
- Completed: 3
- Status: IN_PROGRESS
```

必須放在檔案開頭，`---` 分隔線之前。

## 完整範例

```markdown
## Progress
- Total: 6 tasks
- Completed: 2
- Status: IN_PROGRESS

---

## 1. Foundation (sequential)
- [x] 1.1 Setup database | agent: developer | files: src/db/index.ts
- [x] 1.2 Create models | agent: developer | files: src/models/
- [ ] 1.3 Setup auth | agent: developer | files: src/auth/

## 2. Features (parallel)
- [ ] 2.1 User API | agent: developer | files: src/api/user.ts | output: http://localhost:3000/api/users
- [ ] 2.2 Cart API | agent: developer | files: src/api/cart.ts

## 3. Integration (sequential, depends: 2)
- [ ] 3.1 Export all APIs | agent: developer | files: src/api/index.ts
```

## 解析規則

1. 讀取 Progress 區塊判斷整體狀態
2. 找到第一個 `[ ]`（未完成）任務
3. 檢查 Phase 類型決定執行方式
4. 檢查 `depends` 確認前置條件
5. 執行任務，完成後更新 checkbox
