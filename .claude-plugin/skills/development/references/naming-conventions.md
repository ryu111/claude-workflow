# 命名規範

## 通用規則

### 變數命名

| 類型 | 規則 | 範例 |
|------|------|------|
| 布林值 | is/has/can/should 開頭 | `isActive`, `hasPermission`, `canEdit` |
| 陣列 | 複數名詞 | `users`, `items`, `results` |
| 計數 | count/num/total 開頭或結尾 | `userCount`, `totalItems` |
| 暫存值 | temp/tmp 開頭（避免使用） | 盡量用有意義的名稱 |

### 函式命名

| 行為 | 前綴 | 範例 |
|------|------|------|
| 獲取資料 | get/fetch/retrieve | `getUserById`, `fetchOrders` |
| 設定值 | set/update | `setUserName`, `updateProfile` |
| 布林檢查 | is/has/can/should | `isValid`, `hasAccess` |
| 計算 | calculate/compute | `calculateTotal`, `computeHash` |
| 轉換 | to/parse/format | `toJSON`, `parseDate` |
| 建立 | create/build/make | `createUser`, `buildQuery` |
| 刪除 | delete/remove | `deleteUser`, `removeItem` |
| 驗證 | validate/verify/check | `validateEmail`, `verifyToken` |

### 類別/介面命名

| 類型 | 規則 | 範例 |
|------|------|------|
| 類別 | 大駝峰名詞 | `UserService`, `PaymentProcessor` |
| 介面 | 大駝峰，可加 I 前綴 | `User`, `IRepository` |
| 抽象類 | Abstract 前綴 | `AbstractHandler` |
| 實作類 | 具體描述 | `PostgresUserRepository` |
| 工廠 | Factory 後綴 | `UserFactory` |

## 語言特定規範

### TypeScript/JavaScript

```typescript
// 常數：全大寫下劃線
const MAX_RETRY_COUNT = 3;
const API_BASE_URL = 'https://api.example.com';

// 枚舉：大駝峰
enum UserStatus {
  Active = 'active',
  Inactive = 'inactive',
  Pending = 'pending'
}

// 類型：大駝峰
type UserRole = 'admin' | 'user' | 'guest';

// 泛型：單字母大寫
function identity<T>(value: T): T {
  return value;
}
```

### Python

```python
# 變數和函式：小寫下劃線
user_name = "John"
def get_user_by_id(user_id: int) -> User:
    pass

# 類別：大駝峰
class UserService:
    pass

# 常數：全大寫下劃線
MAX_RETRY_COUNT = 3

# 私有變數/方法：單下劃線前綴
class MyClass:
    def __init__(self):
        self._private_var = 1

    def _private_method(self):
        pass
```

### Go

```go
// 公開：大寫開頭
func GetUserByID(id string) (*User, error) {}

// 私有：小寫開頭
func validateInput(input string) bool {}

// 介面：-er 後綴
type Reader interface {
    Read(p []byte) (n int, err error)
}

// 常數
const (
    MaxRetryCount = 3
    defaultTimeout = 30 * time.Second
)
```

## 避免的命名

| 避免 | 原因 | 改用 |
|------|------|------|
| `data`, `info` | 太模糊 | 具體描述如 `userData` |
| `temp`, `tmp` | 沒有意義 | 描述用途 |
| `foo`, `bar` | 測試用名稱 | 真實名稱 |
| `x`, `y`, `z` | 太短（除非是座標） | 有意義的名稱 |
| `handle`, `process` | 太通用 | 具體動作如 `validateInput` |
