# 常見可複用模式參考

本文件列出軟體開發中常見的可複用模式，幫助 ARCHITECT 和 DEVELOPER 識別何時應該複用現有程式碼，何時應該抽取共用功能。

## 工具函式類型

### 日期與時間

| 功能 | 典型命名 | 使用場景 |
|------|----------|----------|
| 格式化日期 | `formatDate`, `toDateString` | 顯示日期給用戶 |
| 解析日期 | `parseDate`, `fromDateString` | 處理用戶輸入 |
| 日期計算 | `addDays`, `diffDays`, `isBefore` | 業務邏輯計算 |
| 相對時間 | `timeAgo`, `fromNow` | 社交功能、通知 |
| 時區轉換 | `toUTC`, `toLocalTime` | 多時區應用 |

**判斷標準**：
- ✅ 應抽取：日期格式化、解析出現 2+ 次
- ❌ 不需要：一次性的特殊日期邏輯

### 字串處理

| 功能 | 典型命名 | 使用場景 |
|------|----------|----------|
| 大小寫轉換 | `capitalize`, `toCamelCase`, `toKebabCase` | 資料轉換 |
| 修剪空白 | `trim`, `removeWhitespace` | 清理用戶輸入 |
| 字串截斷 | `truncate`, `ellipsis` | UI 顯示 |
| 字串比對 | `includes`, `startsWith`, `fuzzyMatch` | 搜尋功能 |
| 模板替換 | `template`, `interpolate` | 動態文字生成 |

**判斷標準**：
- ✅ 應抽取：複雜的字串轉換邏輯（> 3 行）重複使用
- ❌ 不需要：簡單的 `str.trim()` 或 `str.toLowerCase()`

### 陣列與集合

| 功能 | 典型命名 | 使用場景 |
|------|----------|----------|
| 去重 | `unique`, `deduplicate` | 資料處理 |
| 分組 | `groupBy`, `partition` | 資料聚合 |
| 排序 | `sortBy`, `orderBy` | 列表顯示 |
| 分頁 | `paginate`, `chunk` | 大資料處理 |
| 搜尋 | `findBy`, `filter` | 查詢功能 |

**判斷標準**：
- ✅ 應抽取：自訂排序邏輯、複雜過濾條件
- ❌ 不需要：原生方法足夠（`array.map`, `array.filter`）

### 數字與計算

| 功能 | 典型命名 | 使用場景 |
|------|----------|----------|
| 格式化數字 | `formatNumber`, `toCurrency` | 金額顯示 |
| 數學計算 | `sum`, `average`, `clamp` | 統計分析 |
| 隨機數 | `randomInt`, `randomFloat`, `uuid` | ID 生成 |
| 精度處理 | `round`, `toFixed`, `toPrecision` | 財務計算 |

**判斷標準**：
- ✅ 應抽取：金額格式化（需考慮貨幣符號、千分位）
- ✅ 應抽取：精度計算（避免浮點數誤差）
- ❌ 不需要：簡單的 `Math.round()` 或 `Math.max()`

### 驗證與檢查

| 功能 | 典型命名 | 使用場景 |
|------|----------|----------|
| Email 驗證 | `isValidEmail` | 表單驗證 |
| URL 驗證 | `isValidURL` | 連結檢查 |
| 電話驗證 | `isValidPhone` | 用戶資料驗證 |
| 身份證驗證 | `isValidID` | KYC 流程 |
| 密碼強度 | `checkPasswordStrength` | 註冊/修改密碼 |

**判斷標準**：
- ✅ 應抽取：驗證邏輯複雜（正則表達式、演算法）
- ✅ 應抽取：驗證規則會變動（集中管理）
- ❌ 不需要：一次性的簡單檢查

## UI 元件模式

### 基礎元件

| 元件類型 | 可複用性 | 建議 |
|----------|----------|------|
| Button | 🟢 極高 | 必須共用，支援多種變體 |
| Input | 🟢 極高 | 必須共用，包含驗證狀態 |
| Select | 🟢 極高 | 必須共用，支援搜尋 |
| Checkbox/Radio | 🟢 極高 | 必須共用，統一樣式 |
| Modal/Dialog | 🟢 極高 | 必須共用，統一開關邏輯 |
| Tooltip | 🟢 極高 | 必須共用，統一定位邏輯 |
| Loading Spinner | 🟢 極高 | 必須共用，品牌一致性 |

**判斷標準**：
- ✅ 應抽取：在 2+ 個頁面使用的 UI 元件
- ✅ 應抽取：有固定樣式規範的元件
- ❌ 不需要：頁面特定的一次性元件

### 組合元件

| 元件類型 | 可複用性 | 建議 |
|----------|----------|------|
| Form Field | 🟢 高 | Label + Input + Error，統一結構 |
| Card | 🟡 中 | 基礎卡片可共用，內容彈性化 |
| Table | 🟢 高 | 排序、分頁、篩選邏輯共用 |
| Pagination | 🟢 高 | 必須共用，邏輯一致 |
| Breadcrumb | 🟢 高 | 路由整合，統一導航 |
| Alert/Toast | 🟢 極高 | 全域通知系統 |

**判斷標準**：
- ✅ 應抽取：元件有固定的組成結構
- ✅ 應抽取：包含複雜的互動邏輯
- ⚠️ 謹慎：過度抽象導致 prop 過多

### 佈局元件

| 元件類型 | 可複用性 | 建議 |
|----------|----------|------|
| Container | 🟢 高 | 統一最大寬度、內距 |
| Grid/Flex | 🟢 高 | 響應式佈局系統 |
| Sidebar | 🟡 中 | 基礎結構可共用 |
| Header/Footer | 🟡 中 | 全域性元件 |
| Split Pane | 🟡 中 | 可調整大小的分割視圖 |

## 服務與邏輯模式

### HTTP 請求

| 功能 | 典型實作 | 使用場景 |
|------|----------|----------|
| HTTP Client | Axios/Fetch 封裝 | 統一請求攔截、錯誤處理 |
| 重試邏輯 | Retry with backoff | 網路不穩定環境 |
| 快取機制 | Request cache | 減少重複請求 |
| 取消請求 | AbortController | 避免競態條件 |

**判斷標準**：
- ✅ 應抽取：專案所有 API 請求共用一個 client
- ✅ 應抽取：統一的錯誤處理、Token 刷新
- ❌ 不需要：特殊的一次性請求邏輯

### 認證與授權

| 功能 | 典型實作 | 使用場景 |
|------|----------|----------|
| Auth Service | Token 管理 | 登入/登出/刷新 |
| Permission Check | 權限判斷 | 功能存取控制 |
| Route Guard | 路由攔截 | 保護頁面 |

**判斷標準**：
- ✅ 應抽取：認證邏輯必須集中管理
- ✅ 應抽取：Token 儲存/讀取/清除
- ✅ 應抽取：權限檢查邏輯

### 資料儲存

| 功能 | 典型實作 | 使用場景 |
|------|----------|----------|
| LocalStorage | Key-value 封裝 | 用戶偏好設定 |
| SessionStorage | Session 管理 | 臨時資料 |
| IndexedDB | 大資料儲存 | 離線應用 |
| Cookie | Cookie 操作 | 跨域認證 |

**判斷標準**：
- ✅ 應抽取：統一的序列化/反序列化邏輯
- ✅ 應抽取：統一的過期時間管理
- ❌ 不需要：簡單的 `localStorage.setItem()`

### 狀態管理

| 功能 | 典型實作 | 使用場景 |
|------|----------|----------|
| Global State | Redux/Zustand | 跨元件共享 |
| Form State | React Hook Form | 表單管理 |
| Async State | React Query | 資料獲取 |

**判斷標準**：
- ✅ 應抽取：共用的 state slice（user, settings）
- ✅ 應抽取：複雜的表單驗證邏輯
- ❌ 不需要：單一元件的 local state

## 業務邏輯模式

### 資料轉換

| 場景 | 典型模式 | 建議 |
|------|----------|------|
| API DTO → Model | Mapper/Transformer | 隔離前後端資料結構 |
| Model → View Model | Presenter | UI 顯示邏輯分離 |
| Form → API Payload | Serializer | 資料提交前處理 |

**判斷標準**：
- ✅ 應抽取：同一個 API 回應在多處使用
- ✅ 應抽取：複雜的資料結構轉換（> 10 行）
- ❌ 不需要：簡單的欄位對應

### 業務規則

| 場景 | 典型模式 | 建議 |
|------|----------|------|
| 價格計算 | Calculator | 統一計算邏輯 |
| 折扣規則 | Strategy Pattern | 多種折扣策略 |
| 工作流程 | State Machine | 訂單狀態流轉 |

**判斷標準**：
- ✅ 應抽取：業務規則在多處使用
- ✅ 應抽取：規則複雜且可能變動
- ✅ 應抽取：需要測試的關鍵邏輯

## 判斷是否應該抽取

### 決策流程圖

```
發現相似程式碼
    ↓
Q1: 是否重複 2+ 次？
    ├─ 否 → 暫不抽取，持續觀察
    └─ 是 ↓

Q2: 是否有共同模式？
    ├─ 否 → 可能只是巧合，不抽取
    └─ 是 ↓

Q3: 差異能否參數化？
    ├─ 否 → 評估是否強行抽取
    └─ 是 ↓

Q4: 抽取後是否更易維護？
    ├─ 否 → 可能過度設計，謹慎
    └─ 是 ↓

✅ 應該抽取
```

### 量化指標

| 指標 | 閾值 | 說明 |
|------|------|------|
| 重複次數 | ≥ 2 | 相同邏輯 |
| 重複次數 | ≥ 3 | 相似模式 |
| 程式碼行數 | ≥ 5 | 單次重複長度 |
| 相似度 | ≥ 70% | 程式碼相似度 |
| 變動頻率 | 高 | 經常需要修改 |

### 不應抽取的情況

| 情況 | 原因 | 範例 |
|------|------|------|
| 巧合相似 | 邏輯無關，只是程式碼長得像 | 兩個不同的 `for` 迴圈 |
| 領域特定 | 業務上不相關，強行抽取反而增加耦合 | 訂單計算 vs. 購物車計算 |
| 可能分化 | 未來可能朝不同方向演化 | 臨時功能 vs. 核心功能 |
| 過度抽象 | 為了抽取而抽取，導致難以理解 | 參數 > 5 個的通用函式 |

## 抽取等級建議

| 等級 | 說明 | 適用場景 |
|------|------|----------|
| 🔴 必須抽取 | 關鍵邏輯、安全相關 | 認證、支付、加密 |
| 🟡 建議抽取 | 重複 2+ 次、有維護價值 | 格式化、驗證 |
| 🟢 可選抽取 | 提升可讀性，但非必要 | 簡單工具函式 |
| ⚪ 不需抽取 | 巧合相似、一次性邏輯 | 特定業務流程 |

## 常見反模式

### ❌ 過度抽象

```javascript
// 錯誤：參數過多，難以理解
function universalProcessor(
  data,
  transform,
  validate,
  serialize,
  options,
  callbacks
) { ... }

// 正確：適度抽象
function transformUserData(data) { ... }
function transformProductData(data) { ... }
```

### ❌ 強行統一

```javascript
// 錯誤：兩個邏輯無關的功能強行合併
function processOrderOrUser(type, data) {
  if (type === 'order') {
    // 訂單邏輯
  } else {
    // 用戶邏輯
  }
}

// 正確：分開處理
function processOrder(order) { ... }
function processUser(user) { ... }
```

### ❌ 提早優化

```javascript
// 錯誤：只用了一次就抽取
function extractedOnce(data) { ... }

// 正確：等到第二次使用時再抽取
```

## 參考資源

### 設計原則

- **DRY (Don't Repeat Yourself)**：不要重複自己
- **KISS (Keep It Simple, Stupid)**：保持簡單
- **YAGNI (You Aren't Gonna Need It)**：不要過度設計
- **Rule of Three**：出現三次再抽取

### 檢查清單

在決定是否抽取前，問自己：

- [ ] 這段程式碼是否重複 2+ 次？
- [ ] 抽取後是否更容易測試？
- [ ] 抽取後是否更容易修改？
- [ ] 抽取後是否更容易理解？
- [ ] 抽取後是否不會引入不必要的複雜度？

如果有 3 個以上回答「是」，建議抽取。

---

**文件維護**：持續更新常見模式
**回饋**：發現新模式請記錄到此文件
