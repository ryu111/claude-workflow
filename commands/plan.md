---
name: plan
description: 規劃新功能，建立 OpenSpec 規格文件。觸發詞：規劃、plan、設計功能、新功能
argument-hint: "<feature-name> - 功能名稱"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - Task
  - TaskList
  - TaskGet
  - TaskUpdate
  - TaskCreate
---

# /plan Command

使用 ARCHITECT agent 規劃新功能，建立完整的 OpenSpec 規格文件。

## 使用方式

```
/plan add-user-authentication
/plan implement-payment-system
/plan refactor-database-layer
```

## 執行步驟

### Phase 1: 需求分析

```
委派 ARCHITECT agent
├── 分析專案結構
├── 理解現有架構
└── 確認技術棧
```

### Phase 2: 建立 OpenSpec

```
openspec/specs/{change-id}/
├── proposal.md    # 提案文件（目標、範圍、風險）
└── tasks.md       # 任務清單（Phase + 任務分解）
```

### Phase 3: 等待審核

```
OpenSpec 建立在 specs/ = 待審核狀態
用戶審核後：
├── 通過 → /resume {change-id} 開始執行
└── 修改 → 調整 proposal.md 或 tasks.md
```

## 進度顯示

```
╔════════════════════════════════════════════════════════════════╗
║                    📋 規劃進度: add-user-auth                  ║
╚════════════════════════════════════════════════════════════════╝

├── [1/3] 分析專案結構... ✅
├── [2/3] 設計系統架構... 🔄
└── [3/3] 生成 OpenSpec... ⏳

完成後：
├── 總任務數：8
├── Phase 數：3
└── 預估檔案：12
```

## OpenSpec 目錄流程

```
openspec/
├── specs/      # 待審核（/plan 產出）
│   └── add-user-auth/
│       ├── proposal.md
│       └── tasks.md
│
├── changes/    # 進行中（審核通過後）
│   └── ...
│
└── archive/    # 已完成（全部任務完成後）
    └── ...
```

## tasks.md 格式

```markdown
# add-user-auth Tasks

## 1. Foundation (sequential)
- [ ] 1.1 建立 User Model | agent: developer | files: src/models/user.ts
- [ ] 1.2 建立 Auth Service | agent: developer | files: src/services/auth.ts
- [ ] 1.3 設定資料庫 Migration | agent: developer | files: prisma/migrations/

## 2. Features (parallel)
- [ ] 2.1 實作登入 API | agent: developer | files: src/api/login.ts
- [ ] 2.2 實作註冊 API | agent: developer | files: src/api/register.ts
- [ ] 2.3 實作登出 API | agent: developer | files: src/api/logout.ts

## 3. Integration (sequential)
- [ ] 3.1 整合測試 | agent: developer | files: tests/auth.test.ts
- [ ] 3.2 文檔更新 | agent: developer | files: docs/api.md
```

## 後續步驟

| 動作 | 指令 |
|------|------|
| 開始執行（單步） | `/resume add-user-auth` |
| 持續執行直到完成 | `/loop add-user-auth` |
| 修改規格 | 直接編輯 `openspec/specs/add-user-auth/` |

## 錯誤處理

| 情況 | 處理 |
|------|------|
| change-id 已存在於 `specs/` | 詢問是否覆蓋或使用新名稱 |
| change-id 已存在於 `changes/` | 提示使用 `/resume` 繼續執行 |
| change-id 已存在於 `archive/` | 提示已完成，詢問是否重新規劃 |
| 無法分析專案結構 | ARCHITECT 詢問用戶提供更多資訊 |
| 功能描述不清楚 | ARCHITECT 詢問澄清需求 |

## 口語觸發

以下說法都會觸發 `/plan`：

```
"規劃一個用戶登入功能"
"幫我設計 payment system"
"plan add-user-auth"
"我想新增一個功能..."
```

## 提示

- 規格放在 `specs/` 表示待審核，**不會自動執行**
- 審核通過後使用 `/resume` 或 `/loop` 開始執行
- 可以手動移動到 `changes/` 表示審核通過
- ARCHITECT 會根據專案類型自動選擇適合的任務分解方式
