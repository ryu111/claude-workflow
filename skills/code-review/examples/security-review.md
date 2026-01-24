# 安全審查範例

## 場景

審查一個用戶登入功能的實作。

## 待審查程式碼

```typescript
// src/services/auth.ts
import { db } from '../db';
import jwt from 'jsonwebtoken';

export async function login(email: string, password: string) {
  // 查詢用戶
  const user = await db.query(
    `SELECT * FROM users WHERE email = '${email}'`
  );

  if (!user) {
    throw new Error('User not found');
  }

  // 驗證密碼
  if (user.password !== password) {
    throw new Error('Invalid password');
  }

  // 生成 token
  const token = jwt.sign(
    { userId: user.id, email: user.email, isAdmin: user.isAdmin },
    'my-secret-key',
    { expiresIn: '7d' }
  );

  return { token, user };
}
```

---

## 審查報告

### 摘要

| 類別 | 數量 |
|------|------|
| 🔴 Critical | 3 |
| 🟡 Important | 2 |
| 🟢 Minor | 1 |

**決定**: ❌ REJECT

---

### 🔴 Critical Issues

#### Issue 1: SQL 注入漏洞

**位置**: src/services/auth.ts:8

**問題**:
```typescript
const user = await db.query(
  `SELECT * FROM users WHERE email = '${email}'`
);
```

直接將用戶輸入嵌入 SQL 查詢，可被注入攻擊。

**攻擊範例**:
```
email: "admin'--"
// 結果 SQL: SELECT * FROM users WHERE email = 'admin'--'
```

**修復建議**:
```typescript
const user = await db.query(
  'SELECT * FROM users WHERE email = $1',
  [email]
);
```

---

#### Issue 2: 明文密碼比較

**位置**: src/services/auth.ts:15

**問題**:
```typescript
if (user.password !== password) {
```

1. 密碼以明文儲存（推測）
2. 使用簡單字串比較，可能受時序攻擊

**修復建議**:
```typescript
import bcrypt from 'bcrypt';

// 儲存時
const hashedPassword = await bcrypt.hash(password, 12);

// 驗證時
const isValid = await bcrypt.compare(password, user.hashedPassword);
if (!isValid) {
  throw new Error('Invalid credentials');
}
```

---

#### Issue 3: 硬編碼密鑰

**位置**: src/services/auth.ts:21

**問題**:
```typescript
'my-secret-key'
```

JWT 密鑰硬編碼在程式碼中，可被洩露。

**修復建議**:
```typescript
const token = jwt.sign(
  payload,
  process.env.JWT_SECRET!,
  { expiresIn: '7d' }
);
```

並確保 `.env` 檔案不被 commit。

---

### 🟡 Important Issues

#### Issue 4: 錯誤訊息洩露資訊

**位置**: src/services/auth.ts:11-16

**問題**:
```typescript
throw new Error('User not found');
throw new Error('Invalid password');
```

不同的錯誤訊息讓攻擊者可以枚舉有效的 email。

**修復建議**:
```typescript
// 統一錯誤訊息
throw new Error('Invalid credentials');
```

---

#### Issue 5: Token 包含敏感資訊

**位置**: src/services/auth.ts:19-20

**問題**:
```typescript
{ userId: user.id, email: user.email, isAdmin: user.isAdmin }
```

`isAdmin` 不應放在 client-side token 中，可能被篡改。

**修復建議**:
- 只在 token 中包含必要的識別資訊
- 權限檢查應在 server-side 進行

```typescript
{ userId: user.id }
// 在需要時從資料庫查詢權限
```

---

### 🟢 Minor Issues

#### Issue 6: 缺少輸入驗證

**位置**: src/services/auth.ts:5

**問題**:
函式未驗證 email 格式。

**修復建議**:
```typescript
import { z } from 'zod';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});

export async function login(email: string, password: string) {
  loginSchema.parse({ email, password });
  // ...
}
```

---

## 修復後的程式碼

```typescript
// src/services/auth.ts
import { db } from '../db';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcrypt';
import { z } from 'zod';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});

export async function login(email: string, password: string) {
  // 輸入驗證
  loginSchema.parse({ email, password });

  // 使用參數化查詢
  const user = await db.query(
    'SELECT id, email, hashed_password FROM users WHERE email = $1',
    [email]
  );

  if (!user) {
    // 統一錯誤訊息
    throw new Error('Invalid credentials');
  }

  // 安全的密碼比較
  const isValid = await bcrypt.compare(password, user.hashed_password);
  if (!isValid) {
    throw new Error('Invalid credentials');
  }

  // 使用環境變數
  const token = jwt.sign(
    { userId: user.id },
    process.env.JWT_SECRET!,
    { expiresIn: '7d' }
  );

  return {
    token,
    user: { id: user.id, email: user.email }
  };
}
```

---

## 審查結論

必須修復所有 Critical 和 Important 問題後才能 APPROVE。

建議在修復後：
1. 新增單元測試覆蓋安全場景
2. 進行安全掃描（如 npm audit）
3. 考慮加入 rate limiting 防止暴力破解
