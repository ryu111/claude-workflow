# 範例：用戶認證功能

> 這是一個完整的 OpenSpec 規格範例，展示如何規劃一個用戶認證功能。

## 目錄結構

```
openspec/specs/user-auth-001/
├── proposal.md     # 提案文件
├── tasks.md        # 任務清單
└── notes.md        # 備註與決策
```

---

## proposal.md

```markdown
# user-auth-001 - 用戶登入與註冊功能

## 摘要

實作基本的用戶認證系統，包含註冊、登入、登出功能。

## 背景

### 問題描述
目前系統沒有用戶認證機制，所有功能都是公開的。

### 目標
- 用戶可以註冊新帳號
- 用戶可以使用帳號密碼登入
- 用戶可以登出

## 範圍

### 包含
- 用戶註冊 API
- 用戶登入 API
- Session 管理
- 密碼加密

### 不包含
- OAuth 社群登入
- 雙因素認證
- 忘記密碼功能

## 技術方案

### API 端點
- POST /api/auth/register
- POST /api/auth/login
- POST /api/auth/logout

### 資料模型
```typescript
interface User {
  id: string;
  email: string;
  passwordHash: string;
  createdAt: Date;
}
```

## 風險評估

| 風險 | 可能性 | 影響 | 緩解措施 |
|------|--------|------|----------|
| 密碼洩露 | 低 | 高 | 使用 bcrypt 加密 |
| Session 劫持 | 中 | 高 | 使用 httpOnly cookie |

## 驗收標準

- [ ] 用戶可以成功註冊
- [ ] 用戶可以成功登入
- [ ] 密碼以加密形式儲存
- [ ] 所有 API 有適當的錯誤處理
```

---

## tasks.md

```markdown
# user-auth-001 Tasks

## Progress
- Total: 8 tasks
- Completed: 0
- Status: NOT_STARTED

---

## 1. 資料層 (sequential)

> 建立用戶資料模型和資料庫 schema

- [ ] 1.1 建立 User model | agent: developer | files: src/models/user.ts
  - 描述：定義 User 介面和 Prisma schema
  - 驗收：schema 可以正常 migrate

- [ ] 1.2 建立資料庫 migration | agent: developer | files: prisma/migrations/
  - 描述：執行 prisma migrate 建立 users 表
  - 驗收：資料庫有 users 表

---

## 2. 服務層 (sequential)

> 實作認證相關的商業邏輯

- [ ] 2.1 建立 AuthService | agent: developer | files: src/services/auth.ts
  - 描述：實作 register, login, logout 方法
  - 驗收：所有方法可以正常執行

- [ ] 2.2 實作密碼加密 | agent: developer | files: src/utils/password.ts
  - 描述：使用 bcrypt 實作密碼加密和驗證
  - 驗收：密碼可以加密和驗證

---

## 3. API 層 (parallel)

> 實作 REST API 端點，可並行開發

- [ ] 3.1 註冊 API | agent: developer | files: src/routes/auth/register.ts
- [ ] 3.2 登入 API | agent: developer | files: src/routes/auth/login.ts
- [ ] 3.3 登出 API | agent: developer | files: src/routes/auth/logout.ts

---

## 4. Review & Test (sequential)

- [ ] 4.1 整合審查 | agent: reviewer | files: src/
- [ ] 4.2 整合測試 | agent: tester | files: tests/auth/
```

---

## 狀態轉換

```
specs/user-auth-001/  (規劃中)
        │
        │ 用戶確認 "接手 user-auth-001"
        ▼
changes/user-auth-001/  (執行中)
        │
        │ 所有任務完成
        ▼
archive/user-auth-001/  (已完成)
```
