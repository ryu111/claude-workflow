# 常見錯誤參考

## JavaScript / TypeScript

### TypeError

| 錯誤訊息 | 常見原因 | 解決方案 |
|----------|----------|----------|
| `undefined is not a function` | 呼叫不存在的方法 | 檢查方法名稱拼寫，確認物件有該方法 |
| `Cannot read property 'x' of undefined` | 存取 undefined 的屬性 | 使用可選鏈 `obj?.x` 或檢查 null |
| `x is not a constructor` | 用 new 呼叫非 constructor | 檢查 import 是否正確 |
| `Cannot set property 'x' of null` | 設定 null 的屬性 | 確保物件已初始化 |

### ReferenceError

| 錯誤訊息 | 常見原因 | 解決方案 |
|----------|----------|----------|
| `x is not defined` | 變數未宣告 | 檢查變數名稱，確認 import |
| `Cannot access 'x' before initialization` | 存取 TDZ 中的變數 | 調整程式碼順序，let/const 先宣告 |

### SyntaxError

| 錯誤訊息 | 常見原因 | 解決方案 |
|----------|----------|----------|
| `Unexpected token` | 語法錯誤 | 檢查括號、引號配對 |
| `Unexpected end of JSON` | JSON 格式錯誤 | 驗證 JSON 格式 |
| `Missing initializer in const` | const 未賦值 | 給 const 一個初始值 |

### RangeError

| 錯誤訊息 | 常見原因 | 解決方案 |
|----------|----------|----------|
| `Maximum call stack size exceeded` | 無限遞迴 | 檢查遞迴終止條件 |
| `Invalid array length` | 負數或過大的陣列長度 | 驗證陣列長度參數 |

---

## Node.js

### 系統錯誤 (System Errors)

| 錯誤碼 | 說明 | 解決方案 |
|--------|------|----------|
| `ENOENT` | 檔案或目錄不存在 | 檢查路徑，建立檔案/目錄 |
| `EACCES` | 權限不足 | 檢查檔案權限，使用 sudo |
| `EADDRINUSE` | 端口已被佔用 | 更換端口或結束佔用程序 |
| `ECONNREFUSED` | 連線被拒絕 | 確認服務已啟動 |
| `ETIMEDOUT` | 連線超時 | 檢查網路，增加超時時間 |
| `EMFILE` | 開啟檔案過多 | 關閉未用的檔案，增加 ulimit |

### HTTP 錯誤

| 狀態碼 | 說明 | 常見原因 |
|--------|------|----------|
| 400 | Bad Request | 請求格式錯誤、參數無效 |
| 401 | Unauthorized | 缺少認證、token 過期 |
| 403 | Forbidden | 權限不足 |
| 404 | Not Found | 路徑錯誤、資源不存在 |
| 422 | Unprocessable Entity | 驗證失敗 |
| 429 | Too Many Requests | Rate limit |
| 500 | Internal Server Error | 伺服器端錯誤 |
| 502 | Bad Gateway | 上游服務錯誤 |
| 503 | Service Unavailable | 服務暫時不可用 |
| 504 | Gateway Timeout | 上游服務超時 |

---

## Python

### 常見 Exception

| Exception | 常見原因 | 解決方案 |
|-----------|----------|----------|
| `TypeError` | 類型不匹配 | 檢查參數類型 |
| `ValueError` | 值不合法 | 驗證輸入值 |
| `KeyError` | 字典鍵不存在 | 使用 `.get()` 或檢查鍵 |
| `IndexError` | 索引越界 | 檢查列表長度 |
| `AttributeError` | 屬性不存在 | 檢查物件類型 |
| `ImportError` | 匯入失敗 | 安裝套件，檢查路徑 |
| `FileNotFoundError` | 檔案不存在 | 檢查路徑 |
| `PermissionError` | 權限不足 | 檢查檔案權限 |
| `ConnectionError` | 連線失敗 | 檢查網路和服務狀態 |
| `TimeoutError` | 操作超時 | 增加超時或檢查服務 |

---

## Database

### PostgreSQL

| 錯誤碼 | 說明 | 解決方案 |
|--------|------|----------|
| 23505 | 唯一約束違反 | 檢查重複值 |
| 23503 | 外鍵約束違反 | 確保關聯記錄存在 |
| 23502 | 非空約束違反 | 提供必要欄位值 |
| 42P01 | 表不存在 | 執行 migration |
| 42703 | 欄位不存在 | 檢查欄位名稱 |
| 57014 | 查詢取消（超時） | 優化查詢或增加超時 |
| 40001 | 序列化失敗（死鎖） | 重試事務 |

### MySQL

| 錯誤碼 | 說明 | 解決方案 |
|--------|------|----------|
| 1062 | 重複鍵 | 檢查唯一值 |
| 1452 | 外鍵約束失敗 | 確保關聯記錄存在 |
| 1048 | 不能為 NULL | 提供必要欄位值 |
| 1146 | 表不存在 | 執行 migration |
| 1054 | 未知欄位 | 檢查欄位名稱 |
| 1205 | 鎖等待超時 | 優化事務或重試 |
| 1213 | 死鎖 | 重試事務 |

---

## 常見模式錯誤

### 非同步相關

```typescript
// ❌ 忘記 await
const user = getUserById(id);  // Promise, not User
user.name;  // undefined

// ✅ 正確
const user = await getUserById(id);
user.name;
```

```typescript
// ❌ forEach 中使用 await
items.forEach(async (item) => {
  await processItem(item);  // 不會等待
});

// ✅ 使用 for...of 或 Promise.all
for (const item of items) {
  await processItem(item);
}
```

### 空值相關

```typescript
// ❌ 未檢查空值
return user.profile.avatar;

// ✅ 使用可選鏈
return user?.profile?.avatar ?? defaultAvatar;
```

### 類型相關

```typescript
// ❌ 字串數字混淆
const count = "10";
const total = count + 5;  // "105"

// ✅ 明確轉換
const count = parseInt("10", 10);
const total = count + 5;  // 15
```

---

## 快速診斷流程

```
錯誤發生
    │
    ├─ 是否有明確的錯誤訊息？
    │   ├─ 是 → 查表找對應解決方案
    │   └─ 否 → 加入 console.log / debugger
    │
    ├─ 能否重現？
    │   ├─ 是 → 建立最小重現案例
    │   └─ 否 → 檢查環境差異、時序問題
    │
    └─ 是否為已知錯誤模式？
        ├─ 是 → 套用已知解決方案
        └─ 否 → 使用 5 Whys 深入分析
```
