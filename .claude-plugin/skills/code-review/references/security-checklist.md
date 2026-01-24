# 安全性審查清單

## OWASP Top 10 檢查項目

### 1. 注入攻擊 (Injection)

**SQL 注入**
```typescript
// ❌ 危險
const query = `SELECT * FROM users WHERE id = ${userId}`;

// ✅ 安全 - 參數化查詢
const query = `SELECT * FROM users WHERE id = $1`;
await db.query(query, [userId]);
```

**命令注入**
```typescript
// ❌ 危險
exec(`ls ${userInput}`);

// ✅ 安全 - 白名單驗證
const allowedDirs = ['home', 'docs'];
if (allowedDirs.includes(userInput)) {
  exec(`ls ${userInput}`);
}
```

### 2. 跨站腳本 (XSS)

```typescript
// ❌ 危險
element.innerHTML = userInput;

// ✅ 安全 - 使用 textContent 或編碼
element.textContent = userInput;
// 或
element.innerHTML = escapeHtml(userInput);
```

### 3. 敏感資料洩露

**檢查項目**
- [ ] 密碼使用強加密（bcrypt, argon2）
- [ ] API Key 不在前端代碼中
- [ ] 日誌不包含敏感資料
- [ ] 錯誤訊息不洩露系統資訊

```typescript
// ❌ 危險 - 日誌包含密碼
logger.info(`User login: ${email}, password: ${password}`);

// ✅ 安全
logger.info(`User login attempt: ${email}`);
```

### 4. 身份驗證問題

**檢查項目**
- [ ] Session token 足夠隨機
- [ ] 密碼強度要求
- [ ] 登入失敗限制
- [ ] Session 過期機制

### 5. 權限控制

```typescript
// ❌ 危險 - 缺少權限檢查
app.delete('/api/users/:id', async (req, res) => {
  await deleteUser(req.params.id);
});

// ✅ 安全 - 包含權限檢查
app.delete('/api/users/:id', requireAuth, requireRole('admin'), async (req, res) => {
  await deleteUser(req.params.id);
});
```

## 程式碼審查時的紅旗

| 紅旗 | 風險 |
|------|------|
| `eval()`, `Function()` | 代碼注入 |
| `innerHTML` | XSS |
| 字串串接 SQL | SQL 注入 |
| `exec()`, `spawn()` 使用用戶輸入 | 命令注入 |
| 硬編碼的密碼/API Key | 憑證洩露 |
| `console.log` 包含用戶資料 | 資料洩露 |
| 缺少 `await` 在資料庫操作 | 競態條件 |
| `any` 類型在輸入驗證 | 類型繞過 |

## 安全依賴檢查

```bash
# npm
npm audit
npm audit fix

# Python
pip-audit
safety check

# Go
go list -m all | nancy sleuth
```
