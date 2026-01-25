---
name: browser-automation
version: "1.0.0"
description: |
  瀏覽器自動化工具選擇與使用指南。自動載入於 E2E 測試、UI 驗證、網頁操作相關任務時。
  觸發詞：browser, E2E, UI 測試, 截圖, 網頁操作, 設計驗證, agent-browser, claude-in-chrome
---

# 瀏覽器自動化指南

## 工具選擇決策樹

```
需要瀏覽器自動化？
│
├─ 操作已登入網站？
│  └─ 是 → claude-in-chrome
│
├─ E2E 測試 / CI/CD？
│  └─ 是 → agent-browser
│
├─ 設計規格驗證？
│  └─ 是 → agent-browser（固定視窗）
│
├─ 即時互動調試？
│  └─ 是 → claude-in-chrome
│
└─ 其他 → claude-in-chrome（預設）
```

## 工具對照

| 場景 | claude-in-chrome | agent-browser |
|------|:----------------:|:-------------:|
| 日常網頁操作 | ✅ | |
| 已登入網站 | ✅ | |
| E2E 測試 | | ✅ |
| 視覺回歸測試 | | ✅ |
| CI/CD 自動化 | | ✅ |
| 設計驗證 | | ✅ |
| 即時調試 | ✅ | |
| 用戶可見操作 | ✅ | |

## D→R→T 工作流對應

| Agent | 推薦工具 | 用途 |
|-------|----------|------|
| TESTER | agent-browser | E2E 測試、回歸測試 |
| DESIGNER | agent-browser | 設計稿比對、視覺驗證 |
| DEBUGGER | claude-in-chrome | 即時重現 bug |
| 日常任務 | claude-in-chrome | 網頁操作、資料擷取 |

---

## claude-in-chrome MCP

**適用**：日常操作、已登入網站、即時互動

### 核心特點

- MCP 原生整合（直接工具呼叫）
- 保留用戶登入狀態
- 用戶可見操作過程

### 常用工具

| 工具 | 用途 |
|------|------|
| `tabs_context_mcp` | 取得分頁資訊（**必須先呼叫**） |
| `tabs_create_mcp` | 建立新分頁 |
| `navigate` | 導航到 URL |
| `read_page` | 取得頁面元素（含 ref_id） |
| `find` | 自然語言搜尋元素 |
| `computer` | 滑鼠鍵盤操作 |
| `form_input` | 表單填寫 |
| `javascript_tool` | 執行 JavaScript |
| `get_page_text` | 擷取頁面文字 |

### 基本流程

```
1. tabs_context_mcp → 取得現有分頁
2. tabs_create_mcp → 建立新分頁（或使用現有）
3. navigate → 前往目標 URL
4. read_page / find → 取得元素 ref_id
5. computer / form_input → 操作元素
6. 驗證結果
```

### 注意事項

- ⚠️ 每個 session 開始必須先呼叫 `tabs_context_mcp`
- ⚠️ 不要觸發 alert/confirm 對話框（會阻塞）
- ⚠️ ref_id 在頁面變化後可能失效

---

## agent-browser CLI

**適用**：E2E 測試、設計驗證、CI/CD

### 核心特點

- 專為 AI Agent 設計
- 乾淨環境（每次獨立）
- 可重複、確定性高

### 安裝

```bash
npm install -g agent-browser
agent-browser install  # 下載 Chromium
```

### 常用命令

| 命令 | 用途 |
|------|------|
| `open URL` | 導航到 URL |
| `snapshot -i` | 取得互動元素（含 @ref） |
| `click @ref` | 點擊元素 |
| `fill @ref "text"` | 填寫欄位 |
| `screenshot file.png` | 截圖存檔 |
| `set viewport W H` | 調整視窗大小 |
| `wait "text"` | 等待文字出現 |
| `eval "js"` | 執行 JavaScript |
| `close` | 關閉瀏覽器 |

### 基本流程

```bash
# 1. 開啟頁面
agent-browser open https://example.com

# 2. 取得元素 @ref
agent-browser snapshot -i

# 3. 操作元素
agent-browser fill @e2 "user@test.com"
agent-browser click @e1

# 4. 驗證
agent-browser snapshot -i

# 5. 清理
agent-browser close
```

### 注意事項

- ⚠️ 頁面變化後 @ref 會失效，需重新 `snapshot -i`
- ⚠️ 結束後務必 `close` 釋放資源
- ⚠️ 透過 Bash 工具執行（非 MCP 原生）

---

## 功能對照表

| 功能 | claude-in-chrome | agent-browser |
|------|------------------|---------------|
| 導航 | `navigate` | `open URL` |
| 讀取頁面 | `read_page` | `snapshot -i` |
| 點擊 | `computer` left_click | `click @ref` |
| 輸入 | `form_input` | `fill @ref "text"` |
| 截圖 | `computer` screenshot | `screenshot file.png` |
| 等待 | `computer` wait | `wait "text"` |
| 執行 JS | `javascript_tool` | `eval "js"` |
| 視窗大小 | `resize_window` | `set viewport W H` |

---

## 測試場景範例

### E2E 登入測試（agent-browser）

```bash
# 設定固定視窗
agent-browser set viewport 1920 1080

# 開啟登入頁
agent-browser open http://localhost:3000/login

# 取得元素
agent-browser snapshot -i

# 填寫表單
agent-browser fill @e1 "test@example.com"
agent-browser fill @e2 "password123"
agent-browser click @e3

# 驗證登入成功
agent-browser wait "Dashboard"
agent-browser screenshot login-success.png

# 清理
agent-browser close
```

### 即時調試（claude-in-chrome）

```
1. tabs_context_mcp → 取得分頁
2. navigate → 前往問題頁面
3. read_page → 檢查 DOM 結構
4. javascript_tool → 執行診斷腳本
5. computer screenshot → 截圖記錄
```

---

## 資源

- [references/testing-patterns.md](references/testing-patterns.md) - 測試模式與最佳實踐
