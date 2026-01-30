# Claude Workflow 工作流程圖

> 此文件展示所有可能的工作流程，確保用戶和 AI 理解一致。

---

## 目錄

1. [核心 D→R→T 流程](#1-核心-drt-流程)
2. [風險等級與流程選擇](#2-風險等級與流程選擇)
3. [REJECT 重試流程](#3-reject-重試流程)
4. [FAIL 除錯流程](#4-fail-除錯流程)
5. [並行與串行執行流程](#5-並行與串行執行流程)
6. [Loop 持續執行流程](#6-loop-持續執行流程)
7. [ARCHITECT 規劃流程](#7-architect-規劃流程)
8. [DESIGNER 設計流程](#8-designer-設計流程)
9. [完整任務生命週期](#9-完整任務生命週期)

---

## 1. 核心 D→R→T 流程

**最基本的程式碼變更流程**

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  DEVELOPER  │────▶│  REVIEWER   │────▶│   TESTER    │
│   💻 實作    │     │   🔍 審查    │     │   🧪 測試    │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │
       ▼                   ▼                   ▼
   程式碼變更          APPROVE/REJECT        PASS/FAIL
```

### 流程說明

| 階段 | 角色 | 輸入 | 輸出 |
|------|------|------|------|
| D | DEVELOPER | 任務描述 | 程式碼變更 |
| R | REVIEWER | 程式碼變更 | APPROVE 或 REJECT |
| T | TESTER | 已審查的程式碼 | PASS 或 FAIL |

### 關鍵原則

- **順序強制**：不可跳過 REVIEWER 直接到 TESTER
- **唯讀審查**：REVIEWER 不可修改程式碼
- **完整測試**：TESTER 必須執行實際測試，不可只檢查語法

### 搭配 Loop 模式

```
/ralph-loop "完成所有開發任務" --max-iterations 20

Loop 中的 D→R→T：
┌─────────────┐
│   Loop 迴圈  │
│  ┌────────┐ │
│  │ D→R→T  │ ├──▶ 完成一個任務
│  └────────┘ │
│      ↓      │
│  自動下一個  │
└─────────────┘
```

- Loop 不改變 D→R→T 順序，只是自動化連續執行
- 每個任務仍完整經過 DEVELOPER → REVIEWER → TESTER

---

## 2. 風險等級與流程選擇

**根據風險等級選擇不同流程**

```
                    ┌─────────────────┐
                    │   評估風險等級   │
                    └────────┬────────┘
                             │
          ┌──────────────────┼──────────────────┐
          ▼                  ▼                  ▼
    ┌───────────┐      ┌───────────┐      ┌───────────┐
    │  🟢 LOW   │      │ 🟡 MEDIUM │      │  🔴 HIGH  │
    │ 文檔、配置 │      │  一般功能  │      │ 核心、安全 │
    └─────┬─────┘      └─────┬─────┘      └─────┬─────┘
          │                  │                  │
          ▼                  ▼                  ▼
    ┌───────────┐      ┌───────────┐      ┌───────────┐
    │ Main → T  │      │  D → R → T │      │D → R(深度)│
    │ 快速通道   │      │  標準流程  │      │  → T(完整) │
    └───────────┘      └───────────┘      └───────────┘
```

### 風險判定標準

| 風險 | 條件 | 流程 |
|:----:|------|------|
| 🟢 LOW | 文檔 `*.md`、配置 `*.json/*.yaml`、格式調整 | Main → T |
| 🟡 MEDIUM | 一般功能、< 100 行、非核心模組 | D → R → T |
| 🔴 HIGH | 安全相關、API、核心邏輯、資料庫 | D → R(opus) → T(完整) |

### 自動升級為 HIGH RISK

```
檔案路徑包含：
- /auth/, /security/, /payment/
- /api/, /public/
- /migration/, /schema/

檔案類型：
- *.sql, *.prisma (資料庫)
- Dockerfile, *.yml (CI/CD)
- .env*, secrets* (敏感配置)

變更特徵：
- 修改 > 5 個檔案
- 刪除 > 50 行程式碼
- 修改公開 API 簽名
```

### 搭配 Loop 模式

```
Loop 中的風險等級處理：

┌─────────────────────────────┐
│       Loop 迴圈啟動          │
│              │              │
│    ┌─────────┴─────────┐    │
│    ▼                   ▼    │
│ 🟢 LOW              🟡 MED   │
│ Main→T              D→R→T   │
│    │                   │    │
│    └─────────┬─────────┘    │
│              ▼              │
│        自動下一任務          │
└─────────────────────────────┘
```

- Loop 模式會根據每個任務自動判定風險等級
- 🟢 LOW 任務：走快速通道（Main→T）
- 🟡 MEDIUM/🔴 HIGH 任務：完整 D→R→T
- 風險等級不影響 Loop 的連續執行

---

## 3. REJECT 重試流程

**REVIEWER 拒絕時的處理**

```
DEVELOPER ──▶ REVIEWER
                 │
         ┌──────┴──────┐
         ▼             ▼
     APPROVE        REJECT
         │             │
         ▼             ▼
      TESTER     ┌─────────────┐
                 │  回到       │
                 │  DEVELOPER  │
                 │  修改程式碼  │
                 └──────┬──────┘
                        │
                        ▼
                    REVIEWER ◀─┐
                        │       │
                ┌───────┴───────┤
                ▼               │
            APPROVE          REJECT
                │            (重複)
                ▼
             TESTER
```

### 連續 REJECT 處理

| 次數 | 行為 | 風險調整 |
|:----:|------|----------|
| 1-2 次 | 正常修改重試 | 維持原風險等級 |
| 3 次 | 提示問題可能較複雜 | 考慮升級風險 |
| 5 次 | 暫停並詢問用戶 | 自動升級為 HIGH RISK |

### REJECT 原因分類

```
安全問題 → 立即升級 HIGH RISK
效能問題 → 要求優化方案
邏輯錯誤 → 返回 DEVELOPER
風格問題 → APPROVE with MINOR
```

### 搭配 Loop 模式

```
Loop 中的 REJECT 處理：

任務 N ──▶ D ──▶ R ──▶ REJECT
                         │
                         ▼
                    自動返回 D
                         │
                         ▼
                    D ──▶ R ──▶ APPROVE ──▶ T
                                            │
                                            ▼
                                     自動進入任務 N+1
```

- Loop 模式下 REJECT 不會中斷整體流程
- 自動重試直到 APPROVE 或達到連續 5 次 REJECT 上限

---

## 4. FAIL 除錯流程

**TESTER 失敗時的處理**

```
                    TESTER
                       │
               ┌───────┴───────┐
               ▼               ▼
             PASS            FAIL
               │               │
               ▼               ▼
            完成 ✅      ┌──────────┐
                        │ DEBUGGER │
                        │  🔧 分析  │
                        └────┬─────┘
                             │
                             ▼
                     ┌──────────────┐
                     │   分析報告    │
                     │ - 根本原因    │
                     │ - 修復建議    │
                     │ - 測試建議    │
                     └──────┬───────┘
                            │
                            ▼
                      DEVELOPER
                            │
                            ▼
                 重新進入 D → R → T
```

### DEBUGGER 分析內容

| 項目 | 說明 |
|------|------|
| 錯誤訊息解析 | 解讀測試失敗的具體原因 |
| 根本原因分析 | 使用 5 Whys 找出真正問題 |
| 修復方案建議 | 提供 2-3 個可能的修復方向 |
| 測試覆蓋建議 | 建議需要新增的測試案例 |

### FAIL 類型與處理

```
測試無法執行 → 修復測試環境
斷言失敗    → DEBUGGER 分析邏輯
超時       → 效能優化
依賴錯誤    → 修復依賴配置
```

### 搭配 Loop 模式

```
Loop 中的 FAIL 處理：

任務 N ──▶ D→R→T ──▶ FAIL
                      │
                      ▼
                  DEBUGGER
                      │
                      ▼
                  DEVELOPER
                      │
                      ▼
                  重新 D→R→T
                      │
                      ▼
                    PASS
                      │
                      ▼
               自動進入任務 N+1
```

- FAIL 觸發 DEBUGGER 分析後自動修復
- 修復後重新執行 D→R→T，不中斷 Loop

---

## 5. 並行與串行執行流程

**tasks.md 中的執行模式標記**

### 串行 vs 並行對比範例

```
## 1. Foundation (sequential)          ← 串行：必須按順序
- [ ] 1.1 建立資料庫 Schema
- [ ] 1.2 建立基礎 Service 類         ← 依賴 1.1
- [ ] 1.3 建立共用工具函數             ← 依賴 1.2

## 2. Core Services (parallel)         ← 並行：可同時執行
- [ ] 2.1 建立 UserService    | files: src/user.ts
- [ ] 2.2 建立 ProductService | files: src/product.ts
- [ ] 2.3 建立 OrderService   | files: src/order.ts

## 3. Integration (sequential, depends: 2)  ← 串行：等待 Phase 2 完成
- [ ] 3.1 整合所有 Services
- [ ] 3.2 建立 API Routes              ← 依賴 3.1
```

### 執行流程圖

```
Phase 1 (sequential)
┌─────┐   ┌─────┐   ┌─────┐
│ 1.1 │──▶│ 1.2 │──▶│ 1.3 │
└─────┘   └─────┘   └─────┘
    必須等待前一個完成
            │
            ▼
Phase 2 (parallel)
┌─────┐   ┌─────┐   ┌─────┐
│ 2.1 │   │ 2.2 │   │ 2.3 │
└──┬──┘   └──┬──┘   └──┬──┘
   │         │         │
   └────┬────┴────┬────┘
        ▼
   同時啟動，互不等待
        │
        ▼
    匯合等待
  全部完成才繼續
        │
        ▼
Phase 3 (sequential)
┌─────┐   ┌─────┐
│ 3.1 │──▶│ 3.2 │
└─────┘   └─────┘
```

### 判斷標準

| 標記 | 條件 | 執行方式 |
|------|------|----------|
| `(sequential)` | 任務間有依賴 | 按順序逐一執行 |
| `(parallel)` | 任務間無依賴、不同檔案 | 同時啟動多個 Task |
| `depends: N` | 依賴前一個 Phase | 等待該 Phase 完成 |

### 串行執行時機

```
什麼時候用 (sequential)？

✅ Task B 需要 Task A 的輸出
✅ 多個任務修改同一檔案
✅ 有明確的先後順序要求
✅ 初始化、設定類任務
```

### 並行執行時機

```
什麼時候用 (parallel)？

✅ 任務間完全獨立
✅ 不同檔案、不同模組
✅ 無資料依賴
✅ 可同時開發不互相影響
```

### 並行錯誤處理

```
    並行執行中
         │
    ┌────┼────┐
    ▼    ▼    ▼
   ✅    ❌    ✅
 PASS  FAIL  PASS
         │
         ▼
   單獨 DEBUG
   不影響其他
         │
         ▼
   修復後繼續等待
         │
         ▼
   全部完成 → 下一 Phase
```

### 實際規劃範例

**電商平台開發 tasks.md**

```markdown
## 1. 基礎架構 (sequential)
- [ ] 1.1 設計資料庫 Schema | agent: architect
- [ ] 1.2 建立 ORM 模型 | agent: developer | files: src/models/

## 2. 核心服務 (parallel)
- [ ] 2.1 用戶服務 | agent: developer | files: src/services/user.ts
- [ ] 2.2 商品服務 | agent: developer | files: src/services/product.ts
- [ ] 2.3 訂單服務 | agent: developer | files: src/services/order.ts
- [ ] 2.4 支付服務 | agent: developer | files: src/services/payment.ts

## 3. API 層 (parallel, depends: 2)
- [ ] 3.1 用戶 API | agent: developer | files: src/routes/user.ts
- [ ] 3.2 商品 API | agent: developer | files: src/routes/product.ts
- [ ] 3.3 訂單 API | agent: developer | files: src/routes/order.ts

## 4. 測試 (sequential, depends: 3)
- [ ] 4.1 單元測試 | agent: tester
- [ ] 4.2 整合測試 | agent: tester
```

**執行順序**：
1. Phase 1：1.1 → 1.2（串行）
2. Phase 2：2.1 + 2.2 + 2.3 + 2.4（並行，同時 4 個 DEVELOPER）
3. Phase 3：3.1 + 3.2 + 3.3（並行，等 Phase 2 全部完成後）
4. Phase 4：4.1 → 4.2（串行）

### 搭配 Loop 模式

```
Loop 中的並行/串行處理：

tasks.md:
## 1. Setup (sequential)      ← Loop 串行執行
- [ ] 1.1 初始化
- [ ] 1.2 配置

## 2. Features (parallel)     ← Loop 並行啟動
- [ ] 2.1 功能 A
- [ ] 2.2 功能 B
- [ ] 2.3 功能 C

Loop 執行流程：
┌────────────────────────────────────┐
│ Phase 1 (sequential)               │
│ 1.1 ──▶ 1.2                        │
│         │                          │
│         ▼                          │
│ Phase 2 (parallel)                 │
│ ┌─────┬─────┬─────┐               │
│ │ 2.1 │ 2.2 │ 2.3 │  同時啟動     │
│ └──┬──┴──┬──┴──┬──┘               │
│    └─────┼─────┘                   │
│          ▼                         │
│    匯合等待全部完成                  │
│          │                         │
│          ▼                         │
│    自動進入下一 Phase               │
└────────────────────────────────────┘
```

- Loop 會自動識別 `(parallel)` 和 `(sequential)` 標記
- 並行 Phase：同時啟動多個 Task，等待全部完成
- 串行 Phase：依序執行，一個完成再下一個
- Phase 間依賴（`depends:`）會被正確處理

---

## 6. Loop 持續執行流程

**自動持續執行直到完成**

```
      用戶觸發 /loop 或觸發詞
                │
                ▼
    ┌───────────────────────┐
    │   讀取任務來源         │
    │ (TodoList 或 tasks.md) │
    └───────────┬───────────┘
                │
        ┌───────┴───────┐
        ▼               ▼
   有未完成任務?     無任務
        │               │
        ▼               ▼
   ┌─────────┐     ✅ 完成！
   │執行任務  │     清除 .loop-active
   │ D→R→T   │
   └────┬────┘
        │
   ┌────┴────┐
   ▼         ▼
 PASS      FAIL
   │         │
   │         ▼
   │     DEBUGGER
   │         │
   │         ▼
   │     DEVELOPER
   │         │
   └────┬────┘
        │
        ▼
   更新 checkbox
   [ ] → [x]
        │
        ▼
   ⚠️ 禁止詢問
   立即返回頂部 ↑
```

### Loop 關鍵特性

| 特性 | 說明 |
|------|------|
| 自動迭代 | 不詢問用戶，自動執行下一任務 |
| 狀態追蹤 | 透過 `.loop-active` 標記 |
| 錯誤處理 | FAIL → DEBUG → 修復 → 繼續 |
| 退出條件 | 所有 checkbox 標記為 `[x]` |

### Ralph Loop 使用指引

**重要**：Loop 機制只有一個 — **Ralph Loop**（官方 plugin）。

本專案的 `skills/ralph-loop/SKILL.md` 是**使用指引**，目的是：
- ✅ 教導正確的使用方式
- ✅ 避免 agent 陷入無限迴圈
- ✅ 確保與 D→R→T 流程正確整合

**常見錯誤與預防**：

| 錯誤 | 後果 | 預防方式 |
|------|------|----------|
| 忘記設定 `--max-iterations` | 無限迴圈 | 強制要求設定上限 |
| 虛假的完成承諾 | 提前退出 | 禁止輸出假 `<promise>` |
| 無任務來源 | 空轉 | 配合 TodoList/tasks.md |
| 忽略 D→R→T | 未審查的程式碼 | 在 Loop 中仍執行 D→R→T |

---

## 7. ARCHITECT 規劃流程

**新功能規劃流程**

```
    用戶說「規劃」「plan」
              │
              ▼
    ┌─────────────────┐
    │   ARCHITECT     │
    │   🏗️ 系統設計    │
    └────────┬────────┘
             │
             ▼
    ┌─────────────────────────────┐
    │  建立 OpenSpec               │
    │  openspec/specs/[change-id]/ │
    │  ├── proposal.md            │
    │  ├── tasks.md               │
    │  └── notes.md               │
    └────────────┬────────────────┘
                 │
                 ▼
         用戶審核 proposal
                 │
         ┌───────┴───────┐
         ▼               ▼
       通過            需修改
         │               │
         ▼               ▼
    移動到 changes/    修改 proposal
         │               │
         ▼               └──▶ 重新審核
    開始執行任務
    (D→R→T 或 Loop)
```

### OpenSpec 目錄結構

```
openspec/
├── specs/      # Backlog - 待審核
│   └── CHG-001/
│       ├── proposal.md   # 功能提案
│       ├── tasks.md      # 任務分解
│       └── notes.md      # 設計筆記
│
├── changes/    # WIP - 執行中
│   └── CHG-001/
│       └── (同上結構)
│
└── archive/    # Done - 已完成
    └── CHG-001/
        └── (同上結構)
```

### ARCHITECT 輸出規範

```markdown
## proposal.md
- 功能概述
- 技術選型
- 架構設計
- 風險評估

## tasks.md
- Phase 劃分（sequential/parallel）
- 任務細分（<= 1 小時/任務）
- 依賴關係
- 風險等級標記

## notes.md
- 設計決策記錄
- 備選方案
- 已知限制
```

### 搭配 Loop 模式

```
/ralph-loop "完成 CHG-001 所有任務" --max-iterations 50

ARCHITECT 完成規劃後：

OpenSpec 建立完成
        │
        ▼
移動到 changes/
        │
        ▼
┌──────────────────┐
│   Loop 自動啟動   │
│                  │
│  讀取 tasks.md   │
│        ↓        │
│  執行任務 1.1    │
│   (D→R→T)       │
│        ↓        │
│  執行任務 1.2    │
│        ↓        │
│      ...        │
│        ↓        │
│  所有任務完成    │
└──────────────────┘
        │
        ▼
   移動到 archive/
```

- 規劃後可立即啟動 Loop 執行所有任務
- Loop 會按照 tasks.md 的順序和 parallel/sequential 標記執行

---

## 8. DESIGNER 設計流程

**UI/UX 相關任務流程**

```
    用戶說「設計」「UI」「UX」
              │
              ▼
    ┌─────────────────┐
    │    DESIGNER     │
    │    🎨 UI 設計    │
    └────────┬────────┘
             │
             ▼
    ┌─────────────────┐
    │  設計規格/原型    │
    │  - 線框圖        │
    │  - 元件規格      │
    │  - 互動流程      │
    │  - 響應式規劃    │
    └────────┬────────┘
             │
             ▼
       用戶審核設計
             │
     ┌───────┴───────┐
     ▼               ▼
   通過            需修改
     │               │
     ▼               └──▶ 修改設計
┌─────────────────────────┐
│   進入 D → R → T        │
│   DEVELOPER 實作設計    │
└─────────────────────────┘
```

### DESIGNER 輸出規範

| 項目 | 內容 |
|------|------|
| 線框圖 | ASCII 或 Mermaid 圖表 |
| 元件規格 | Props、State、事件 |
| 樣式規範 | 顏色、間距、字體 |
| 互動流程 | 用戶操作路徑 |
| 響應式 | 各斷點的佈局調整 |

### Design → D → R → T 路徑

```
DESIGNER 完成設計
       │
       ▼
DEVELOPER 實作
       │
       ▼
REVIEWER 審查
  - 設計符合度
  - 程式碼品質
       │
       ▼
TESTER 測試
  - 視覺測試
  - 互動測試
  - 響應式測試
```

### 搭配 Loop 模式

```
Loop 中的設計任務：

tasks.md:
- [ ] 2.1 設計登入頁面 | agent: designer
- [ ] 2.2 實作登入頁面 | agent: developer
- [ ] 2.3 設計註冊頁面 | agent: designer
- [ ] 2.4 實作註冊頁面 | agent: developer

Loop 執行流程：
DESIGNER(2.1) → D→R→T(2.2) → DESIGNER(2.3) → D→R→T(2.4)
```

- DESIGNER 任務完成後，Loop 自動進入對應的實作任務
- 設計 → 實作的順序由 tasks.md 定義

---

## 9. 完整任務生命週期

**從需求到完成的完整流程**

```
                    ┌─────────────┐
                    │  用戶需求   │
                    └──────┬──────┘
                           │
                           ▼
              ┌────────────────────────┐
              │    判斷任務類型        │
              └────────────┬───────────┘
                           │
     ┌─────────────────────┼─────────────────────┐
     ▼                     ▼                     ▼
┌─────────┐          ┌─────────┐          ┌─────────┐
│ 簡單任務 │          │ 複雜功能 │          │ UI 任務 │
│ 直接執行 │          │ 需要規劃 │          │ 需要設計 │
└────┬────┘          └────┬────┘          └────┬────┘
     │                    │                    │
     │                    ▼                    ▼
     │              ┌─────────┐          ┌─────────┐
     │              │ARCHITECT│          │ DESIGNER│
     │              │  規劃   │          │  設計   │
     │              └────┬────┘          └────┬────┘
     │                   │                    │
     │                   ▼                    │
     │              建立 OpenSpec             │
     │                   │                    │
     │                   ▼                    │
     └────────┬──────────┴────────────────────┘
              │
              ▼
    ┌─────────────────────┐
    │   評估風險等級       │
    │ 🟢 LOW / 🟡 MED / 🔴 HIGH │
    └──────────┬──────────┘
               │
               ▼
    ┌─────────────────────┐
    │    D → R → T        │
    │  (根據風險選擇流程)  │
    └──────────┬──────────┘
               │
       ┌───────┴───────┐
       ▼               ▼
     PASS            FAIL
       │               │
       ▼               ▼
    ✅ 完成      DEBUGGER 分析
    移至 archive       │
                       ▼
                 返回 DEVELOPER
                       │
                       ▼
                 重新 D→R→T
```

### 任務類型判定

```
簡單任務（直接執行）：
- 單一檔案修改
- 文檔更新
- 配置調整
- Bug 修復（範圍明確）

複雜功能（需 ARCHITECT）：
- 新模組開發
- 架構變更
- 多檔案協作
- 跨系統整合

UI 任務（需 DESIGNER）：
- 新頁面/元件
- 設計改版
- 互動流程變更
- 響應式優化
```

### 搭配 Loop 模式

```
完整任務生命週期 + Loop：

用戶需求
    │
    ▼
判斷任務類型
    │
    ├──▶ ARCHITECT ──▶ OpenSpec
    │                     │
    │                     ▼
    │              ┌────────────┐
    │              │ /ralph-loop│
    │              │ 啟動 Loop  │
    │              └─────┬──────┘
    │                    │
    │         ┌──────────┴──────────┐
    │         ▼                     ▼
    │    (sequential)          (parallel)
    │    串行執行任務          並行執行任務
    │         │                     │
    │         └──────────┬──────────┘
    │                    ▼
    │            每個任務 D→R→T
    │                    │
    │              ┌─────┴─────┐
    │              ▼           ▼
    │            PASS        FAIL
    │              │           │
    │              │      DEBUGGER
    │              │           │
    │              └─────┬─────┘
    │                    ▼
    │             自動下一任務
    │                    │
    └────────────────────┴──▶ 全部完成
                               │
                               ▼
                          移至 archive/
                          Loop 結束
```

- Loop 模式可在任務生命週期的任何階段啟動
- 最常見：ARCHITECT 完成規劃後立即啟動 Loop
- Loop 會完整執行每個任務的 D→R→T 流程
- 全部任務完成後自動結束並歸檔

---

## 快速參考

### 觸發詞對照表

| 觸發詞 | 啟動流程 |
|--------|----------|
| 規劃、plan、架構 | ARCHITECT → OpenSpec |
| 設計、design、UI | DESIGNER → D→R→T |
| 實作、implement、開發 | D → R → T |
| 審查、review | R → T |
| 測試、test | T |
| debug、除錯 | DEBUGGER → D→R→T |
| loop、持續、做完 | Loop 模式 |
| 接手、resume | 恢復 OpenSpec |

### Agent 工具權限

| Agent | 可用工具 | 權限限制 |
|-------|----------|----------|
| ARCHITECT | Read, Glob, Grep, Write, Task | 唯創建規劃文件 |
| DESIGNER | Read, Glob, Grep, Write, Task | 唯創建設計文件 |
| DEVELOPER | Read, Glob, Grep, Write, Edit, Bash, Task | 完整開發權限 |
| REVIEWER | Read, Glob, Grep | **唯讀**，不可修改 |
| TESTER | Read, Glob, Grep, Bash | 可執行測試，不可修改程式碼 |
| DEBUGGER | Read, Glob, Grep, Write, Task | 可寫分析報告 |

### 控制機制 (v0.7)

**最小必要阻擋原則**：只阻擋真正需要 D→R→T 審查的操作。

```
┌─────────────────────────────────────────────────────────┐
│                    Main Agent 操作                      │
├─────────────────────────────────────────────────────────┤
│  ✅ 允許                    │  ❌ 阻擋（需委派 Agent）   │
│  ─────────────────────────  │  ─────────────────────────│
│  • 所有讀取操作              │  • 程式碼檔案寫入          │
│  • 文檔寫入 (*.md)          │    (.ts, .js, .py, .sh    │
│  • 配置檔寫入 (*.json等)    │     .go, .rs, .java 等)   │
│  • Git 操作                 │  • hooks/ 目錄下任何寫入   │
│  • 一般 Bash 命令           │                           │
└─────────────────────────────────────────────────────────┘
```

**強制執行層級**：

| 層級 | 機制 | 說明 |
|:----:|------|------|
| 1 | `tools:` 白名單 | Agent 定義中允許的工具 |
| 2 | Hook 阻擋 | 程式碼寫入 → 必須經過 D→R→T |

> 📝 v0.7 移除了 `disallowedTools` 黑名單，簡化為「白名單 + Hook 阻擋」兩層控制。

### 狀態流轉總表

```
                    ┌──────────┐
                    │  START   │
                    └────┬─────┘
                         │
            ┌────────────┼────────────┐
            ▼            ▼            ▼
       ARCHITECT     DESIGNER     DEVELOPER
            │            │            │
            └────────────┼────────────┘
                         │
                         ▼
                    DEVELOPER
                         │
                         ▼
                     REVIEWER
                         │
                ┌────────┴────────┐
                ▼                 ▼
            APPROVE            REJECT
                │                 │
                ▼                 └──▶ DEVELOPER
             TESTER
                │
        ┌───────┴───────┐
        ▼               ▼
      PASS            FAIL
        │               │
        ▼               ▼
     COMPLETE       DEBUGGER
                         │
                         └──▶ DEVELOPER
```

---

## 附錄：流程圖圖例

### 符號說明

```
┌─────┐
│ 角色 │  = Agent 或階段
└─────┘

   │
   ▼      = 單向流程

   │
  ─┼─     = 分支點
   │

  ✅      = 成功/通過
  ❌      = 失敗/拒絕
  ⚠️      = 警告/注意
  🟢      = 低風險
  🟡      = 中風險
  🔴      = 高風險
```

### 流程類型

| 類型 | 符號 | 說明 |
|------|------|------|
| 順序流程 | `A → B → C` | 必須依序執行 |
| 並行流程 | `A ┬─ B` <br> `  └─ C` | 可同時執行 |
| 條件分支 | `A ─┬─ B(條件1)` <br> `   └─ C(條件2)` | 根據條件選擇 |
| 迴圈流程 | `A → B ──▶ A` | 可能重複執行 |

---

## 版本資訊

- **文件版本**：v1.2.0
- **對應 Plugin 版本**：v0.7.0
- **最後更新**：2026-01-31
- **維護者**：DEVELOPER Agent

---

## 相關文件

- [CLAUDE.md](../CLAUDE.md) - 專案總覽
- [D→R→T 規則](../skills/drt-rules/SKILL.md) - 詳細規則
- [Ralph Loop 指引](../skills/ralph-loop/SKILL.md) - Loop 使用指引
- [E2E 測試](../tests/e2e/README.md) - 流程驗證測試
