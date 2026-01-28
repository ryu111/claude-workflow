---
name: orchestration
description: |
  Agent 調度與任務分配規則。自動載入於任務規劃、委派、並行執行決策時。
  觸發詞：委派, delegate, 分配, assign, 並行, parallel, 串行, sequential, 調度, dispatch, 啟動 Agent, 觸發
user-invocable: false
disable-model-invocation: false
---

# 任務調度規則

## ⚠️ Main Agent 強制顯示格式（最高優先級）

Main Agent 在委派任務和接收結果時**必須**使用放大顯示格式：

### 委派任務時
```
## ⚡ 🤖 MAIN 委派 [AGENT_NAME] 執行 [任務描述]
```

### 任務完成時
```
## ✅ 🤖 MAIN 收到 [AGENT_NAME] 完成報告
```

### 流程完成時
```
## 🎉 D→R→T 流程完成！任務 [Task X.X] 已通過所有階段
```

**⚠️ 違反後果**：用戶無法追蹤工作流進度，導致混亂。不遵循此格式將被視為任務失敗。

---

## 核心原則

Main Agent 是**監督者**，不是**執行者**。

## 委派矩陣

### 必須委派

| 任務類型 | 委派給 | 說明 |
|----------|--------|------|
| 寫程式碼 | DEVELOPER | 任何 code 變更 |
| 審查程式碼 | REVIEWER | 必須由非作者審查 |
| 執行測試 | TESTER | 驗證功能正確性 |
| 除錯分析 | DEBUGGER | 測試失敗後分析 |
| 系統設計 | ARCHITECT | 新功能規劃 |
| UI/UX 設計 | DESIGNER | 介面相關設計 |

### 可直接處理

Main 可直接處理以下內容（但仍需 R → T）：

- 文檔檔案：`*.md`
- 配置檔案：`*.json`, `*.yaml`, `*.toml`
- 環境變數：`.env`, `.env.*`
- OpenSpec 規格文件

## 並行執行（強制規則）

### ⚠️ 強制並行偵測

當 tasks.md 中的 Phase 標記為 `(parallel)` 時，**必須**並行執行該 Phase 的所有任務。

**tasks.md 範例**：
```
## 2. Core Services (parallel)
- [ ] 2.1 建立 UserService | agent: developer | files: src/user.ts
- [ ] 2.2 建立 ProductService | agent: developer | files: src/product.ts
- [ ] 2.3 建立 OrderService | agent: developer | files: src/order.ts
```

**偵測到 `(parallel)` 後的行為**：
1. 立即分析該 Phase 所有未完成任務
2. 確認任務間無衝突（不同檔案、無依賴）
3. **單一訊息中**發送多個 Task 呼叫

### 並行判斷標準

| 條件 | 執行方式 | 說明 |
|------|----------|------|
| Phase 標記 `(parallel)` | ✅ **強制並行** | 無視其他條件，直接並行 |
| 任務間無依賴 | ✅ 建議並行 | 分析 files: 欄位確認 |
| 不同檔案、不同模組 | ✅ 建議並行 | 無檔案衝突 |
| Task B 需要 Task A 的輸出 | ❌ 必須串行 | 有資料依賴 |
| 多個任務修改同一檔案 | ❌ 必須串行 | 檔案衝突 |

### 並行啟動格式

**顯示格式（必須）**：
```
## ⚡ 並行啟動 3 個 DEVELOPER

| Task | 檔案 | 功能 |
|------|------|------|
| 2.1 | src/user.ts | 建立 UserService |
| 2.2 | src/product.ts | 建立 ProductService |
| 2.3 | src/order.ts | 建立 OrderService |
```

**技術實作（單一訊息多個 Task）**：

⚠️ **關鍵**：必須在**同一個回應**中發送所有 Task 呼叫，而非分開發送。

範例：同一個 function_calls 區塊中包含多個 Task invoke。

### 並行錯誤處理

| 情況 | 處理方式 | 影響其他任務？ |
|------|----------|:--------------:|
| 其中一個 REJECT | 只重試該任務 | ❌ 不影響 |
| 其中一個 FAIL | 只 DEBUG 該任務 | ❌ 不影響 |
| 多個失敗 | 依序處理 | ❌ 不影響 |
| 共同依賴失敗 | 全部暫停 | ✅ 全部影響 |

### 並行與 Loop 模式整合

在 Loop 模式下偵測到 `(parallel)` Phase：

1. **自動並行啟動** - 不等待，立即啟動所有任務
2. **匯合等待** - 等待所有並行任務完成
3. **統一狀態更新** - 全部完成後一次更新所有 checkbox
4. **繼續下一 Phase** - 自動進入下一個 Phase

**Loop + 並行執行流程**：
```
偵測 (parallel) Phase
       ↓
並行啟動 N 個 Task
       ↓
等待全部完成 ←── 單一失敗：處理後繼續等待
       ↓
更新所有 checkbox [ ] → [x]
       ↓
自動進入下一 Phase（不詢問）
```

### 禁止行為

| 禁止 | 原因 |
|------|------|
| ❌ 逐一執行 `(parallel)` 任務 | 浪費時間，違反標記意圖 |
| ❌ 分開發送 Task 呼叫 | 無法真正並行 |
| ❌ 等待第一個完成才啟動第二個 | 這是串行，不是並行 |
| ❌ 忽略 `(parallel)` 標記 | 違反 tasks.md 規範 |

## 觸發詞識別

| 用戶輸入關鍵字 | 觸發 Agent | 啟動流程 |
|----------------|------------|----------|
| 規劃, plan, 架構 | ARCHITECT | 建立 OpenSpec |
| 設計, design, UI | DESIGNER | Design → D → R → T |
| 實作, implement, 開發, 寫 | DEVELOPER | D → R → T |
| 審查, review, 檢查 | REVIEWER | R → T |
| 測試, test, 驗證 | TESTER | T |
| debug, 除錯, 修復 bug | DEBUGGER | Debug → D → R → T |
| 接手, resume | - | 恢復 OpenSpec |
| loop, 持續 | - | 持續執行模式 |

## 自動執行規則

### ARCHITECT 完成後必須自動執行

當 ARCHITECT 完成規劃後，Main Agent **必須**立即執行以下步驟，**不得等待用戶指令**：

| 步驟 | 操作 | 工具 |
|:----:|------|------|
| 1 | 移動規格 | `Bash: mv openspec/specs/[change-id] openspec/changes/` |
| 2 | 讀取任務 | `Read: openspec/changes/[change-id]/tasks.md` |
| 3 | 找到第一個 `[ ]` 任務 | 解析 tasks.md |
| 4 | 啟動對應 Agent | `Task(developer)` 或其他 |

### 中斷條件

**僅**在以下情況下暫停自動執行：
- 用戶明確說「暫停」、「停」、「等一下」、「先讓我看看」
- ARCHITECT 在 `notes.md` 中標記「需要用戶確認」
- 檢測到 `.drt-bypass` 檔案

### 執行範例

```markdown
## ✅ 🤖 MAIN 收到 ARCHITECT 完成報告

### 📋 自動執行步驟

1. 移動規格到執行目錄
   mv openspec/specs/auth-feature openspec/changes/

2. 讀取任務清單
   - 檔案：openspec/changes/auth-feature/tasks.md
   - 第一個任務：1.1 建立 AuthService | agent: developer

3. 委派 DEVELOPER 執行第一個任務

## ⚡ 🤖 MAIN 委派 DEVELOPER 執行 [建立 AuthService]
```

### 失敗處理

如果自動執行步驟失敗：
- **mv 失敗**：檢查目錄是否存在，報告給用戶
- **tasks.md 不存在**：報告給用戶，請求手動檢查
- **無法解析任務**：顯示 tasks.md 內容，請求用戶協助

## 狀態顯示格式

**注意：** 完整的狀態顯示格式規範請參考 `skills/drt-rules/references/status-display.md`。

所有 Agent（Main 和 Subagent）必須使用增強版放大格式（Markdown 標題格式）。

## 不確定性處理（互動式澄清）

### 強制原則

當遇到不確定情況時，**必須**使用 `AskUserQuestion` 工具詢問用戶，**不可猜測**。

### 觸發條件

| 情況 | 範例 | 必須詢問 |
|------|------|:--------:|
| **需求不明確** | 「加入登入功能」但未說明 OAuth/JWT | ✅ |
| **技術選擇** | 多個可行方案（Redux vs Context） | ✅ |
| **風險判定** | 無法確定 LOW/MEDIUM/HIGH | ✅ |
| **範圍邊界** | 不清楚是否包含某功能 | ✅ |
| **架構決策** | 微服務 vs 單體 | ✅ |
| **UI/UX 方向** | 多種設計風格 | ✅ |

### 使用格式

```javascript
AskUserQuestion({
  questions: [{
    question: "關於 [主題]，請選擇實作方式",
    header: "技術選擇",  // 12字以內
    options: [
      { label: "方案 A（推薦）", description: "優點：X｜缺點：Y" },
      { label: "方案 B", description: "優點：X｜缺點：Y" },
      { label: "方案 C", description: "優點：X｜缺點：Y" }
    ],
    multiSelect: false
  }]
})
```

### 範例場景

**場景 1：用戶說「加入用戶認證」**
```javascript
AskUserQuestion({
  questions: [{
    question: "請選擇認證方式",
    header: "認證方案",
    options: [
      { label: "JWT（推薦）", description: "無狀態、適合 API、易於擴展" },
      { label: "Session", description: "有狀態、傳統方式、需要 Redis" },
      { label: "OAuth 2.0", description: "第三方登入、複雜度較高" }
    ]
  }]
})
```

**場景 2：無法判定風險等級**
```javascript
AskUserQuestion({
  questions: [{
    question: "此變更涉及 [範圍]，請確認風險等級",
    header: "風險確認",
    options: [
      { label: "🟢 LOW", description: "快速通道，無需 REVIEWER" },
      { label: "🟡 MEDIUM（推薦）", description: "標準 D→R→T 流程" },
      { label: "🔴 HIGH", description: "強化流程 + 人工確認" }
    ]
  }]
})
```

### 禁止行為

```
❌ 遇到不確定時自行假設
❌ 猜測用戶意圖
❌ 選擇「最可能」的方案而不詢問
❌ 在重要決策上使用預設值
```

### 記錄決策

用戶選擇後，記錄到 `openspec/changes/[id]/notes.md`：

```markdown
## 💡 設計決策

### 決策 1: 認證方式
- **背景**: 用戶要求加入認證功能
- **選項**: JWT / Session / OAuth 2.0
- **決定**: JWT
- **原因**: 用戶選擇，適合 API 場景
```

---

## 資源

### References

- [agent-capabilities.md](references/agent-capabilities.md) - 各 Agent 能力說明與選擇指南

### Templates

- [dispatch-decision.md](templates/dispatch-decision.md) - 調度決策範本

### Examples

- [parallel-execution.md](examples/parallel-execution.md) - 並行執行完整範例
