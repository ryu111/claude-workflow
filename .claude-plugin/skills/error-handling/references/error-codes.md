# 錯誤碼參考

## 錯誤碼格式

```
[類別]-[子類別]-[編號]
例如: NET-CONN-001
```

---

## 網路錯誤 (NET)

### 連線錯誤 (NET-CONN)

| 錯誤碼 | 名稱 | 說明 | 處理策略 |
|--------|------|------|----------|
| NET-CONN-001 | ECONNREFUSED | 連線被拒絕 | 檢查服務是否啟動 |
| NET-CONN-002 | ETIMEDOUT | 連線超時 | 重試，檢查網路 |
| NET-CONN-003 | ENOTFOUND | DNS 解析失敗 | 檢查域名正確性 |
| NET-CONN-004 | ENETUNREACH | 網路不可達 | 檢查網路連線 |

### HTTP 錯誤 (NET-HTTP)

| 錯誤碼 | 名稱 | 說明 | 處理策略 |
|--------|------|------|----------|
| NET-HTTP-400 | Bad Request | 請求格式錯誤 | 檢查請求參數 |
| NET-HTTP-401 | Unauthorized | 未授權 | 檢查認證資訊 |
| NET-HTTP-403 | Forbidden | 禁止存取 | 檢查權限 |
| NET-HTTP-404 | Not Found | 資源不存在 | 檢查 URL |
| NET-HTTP-429 | Rate Limited | 請求過於頻繁 | 等待後重試 |
| NET-HTTP-500 | Server Error | 伺服器錯誤 | 重試，聯繫服務提供者 |
| NET-HTTP-502 | Bad Gateway | 閘道錯誤 | 重試 |
| NET-HTTP-503 | Unavailable | 服務不可用 | 等待後重試 |

---

## 檔案錯誤 (FILE)

| 錯誤碼 | 名稱 | 說明 | 處理策略 |
|--------|------|------|----------|
| FILE-001 | ENOENT | 檔案不存在 | 建立檔案或檢查路徑 |
| FILE-002 | EACCES | 權限不足 | 檢查檔案權限 |
| FILE-003 | EISDIR | 是目錄不是檔案 | 檢查路徑 |
| FILE-004 | ENOTDIR | 是檔案不是目錄 | 檢查路徑 |
| FILE-005 | ENOSPC | 磁碟空間不足 | 清理磁碟 |
| FILE-006 | EMFILE | 開啟檔案過多 | 關閉未使用的檔案 |

---

## 資料庫錯誤 (DB)

### 連線錯誤 (DB-CONN)

| 錯誤碼 | 名稱 | 說明 | 處理策略 |
|--------|------|------|----------|
| DB-CONN-001 | Connection Failed | 連線失敗 | 檢查連線字串 |
| DB-CONN-002 | Auth Failed | 認證失敗 | 檢查帳號密碼 |
| DB-CONN-003 | Pool Exhausted | 連線池耗盡 | 增加連線池或減少並發 |

### 查詢錯誤 (DB-QUERY)

| 錯誤碼 | 名稱 | 說明 | 處理策略 |
|--------|------|------|----------|
| DB-QUERY-001 | Syntax Error | SQL 語法錯誤 | 檢查 SQL |
| DB-QUERY-002 | Constraint Violation | 約束違反 | 檢查資料完整性 |
| DB-QUERY-003 | Timeout | 查詢超時 | 優化查詢或增加超時 |
| DB-QUERY-004 | Deadlock | 死鎖 | 重試 |

---

## 執行時錯誤 (RUNTIME)

### JavaScript/TypeScript

| 錯誤碼 | 名稱 | 說明 | 處理策略 |
|--------|------|------|----------|
| RUNTIME-JS-001 | TypeError | 類型錯誤 | 加入類型檢查 |
| RUNTIME-JS-002 | ReferenceError | 引用錯誤 | 檢查變數定義 |
| RUNTIME-JS-003 | RangeError | 範圍錯誤 | 檢查陣列索引 |
| RUNTIME-JS-004 | SyntaxError | 語法錯誤 | 檢查程式碼語法 |

### Python

| 錯誤碼 | 名稱 | 說明 | 處理策略 |
|--------|------|------|----------|
| RUNTIME-PY-001 | TypeError | 類型錯誤 | 加入類型檢查 |
| RUNTIME-PY-002 | ValueError | 值錯誤 | 驗證輸入值 |
| RUNTIME-PY-003 | KeyError | 字典鍵不存在 | 使用 .get() 或檢查鍵 |
| RUNTIME-PY-004 | IndexError | 索引越界 | 檢查陣列長度 |
| RUNTIME-PY-005 | ImportError | 匯入錯誤 | 安裝套件或檢查路徑 |

---

## 工作流錯誤 (WORKFLOW)

| 錯誤碼 | 名稱 | 說明 | 處理策略 |
|--------|------|------|----------|
| WF-001 | Task Not Found | 找不到任務 | 檢查任務 ID |
| WF-002 | Invalid State | 狀態不合法 | 檢查工作流狀態 |
| WF-003 | Retry Exceeded | 重試次數超過 | 請求用戶介入 |
| WF-004 | Dependency Failed | 依賴任務失敗 | 先修復依賴任務 |
| WF-005 | Checkpoint Corrupt | Checkpoint 損壞 | 重建或從頭開始 |

---

## 錯誤嚴重程度

| 等級 | 說明 | 自動處理 |
|------|------|----------|
| 🟢 INFO | 資訊，不影響執行 | 記錄 |
| 🟡 WARNING | 警告，可能有問題 | 記錄 + 通知 |
| 🟠 RETRYABLE | 可重試，暫時性問題 | 自動重試 |
| 🔴 RECOVERABLE | 可修復，需要調整 | 嘗試修復 |
| ⚫ FATAL | 致命，無法繼續 | 停止 + 通知用戶 |
