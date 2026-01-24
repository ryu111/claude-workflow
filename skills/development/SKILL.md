---
name: development
description: |
  程式碼開發專業知識。自動載入於 DEVELOPER 實作、寫程式、重構相關任務時。
  觸發詞：開發, develop, 實作, implement, coding, 寫程式, 重構, refactor, 函式, function, class
user-invocable: false
disable-model-invocation: false
---

# 開發知識

## 程式碼品質標準

### 命名規則

| 類型 | 規則 | 範例 |
|------|------|------|
| 變數 | 小駝峰，描述用途 | `userName`, `totalCount` |
| 函式 | 動詞開頭，描述行為 | `getUserById`, `calculateTotal` |
| 類別 | 大駝峰，名詞 | `UserService`, `PaymentProcessor` |
| 常數 | 全大寫下劃線 | `MAX_RETRY_COUNT`, `API_BASE_URL` |
| 檔案 | kebab-case 或專案慣例 | `user-service.ts`, `UserService.ts` |

### 函式設計原則

- **單一職責**：一個函式只做一件事
- **適當長度**：一般不超過 50 行
- **參數數量**：一般不超過 4 個，多於 4 個用物件
- **提早返回**：優先處理錯誤情況

```typescript
// ✅ 提早返回模式
function processUser(user: User) {
  if (!user) return null;
  if (!user.isActive) return null;
  return doSomething(user);
}
```

### 錯誤處理

```typescript
try {
  const result = await riskyOperation();
  return result;
} catch (error) {
  if (error instanceof ValidationError) {
    throw new BadRequestError(error.message);
  }
  logger.error('Unexpected error', { error });
  throw error;
}
```

## 重構技術

### Extract Function
當一段程式碼可以獨立命名時，提取成函式。

### Replace Magic Number
將魔術數字替換為有意義的常數。

### Simplify Conditional
簡化複雜的條件判斷，提取為有意義的變數或函式。

## 最佳實踐

### 不可變性優先

```typescript
// ✅ 不可變
function addItem(cart, item) {
  return { ...cart, items: [...cart.items, item] };
}
```

### 依賴注入

```typescript
// ✅ 依賴注入
class UserService {
  constructor(private db: Database) {}
}
```

### 介面優於實作

```typescript
interface Repository<T> {
  findById(id: string): Promise<T | null>;
  save(entity: T): Promise<T>;
}

class UserService {
  constructor(private repo: Repository<User>) {}
}

## 資源

### Templates

- [function-template.ts](templates/function-template.ts) - 函式範本
- [service-template.ts](templates/service-template.ts) - Service 類別範本

### References

- [naming-conventions.md](references/naming-conventions.md) - 命名規範詳細說明
```
