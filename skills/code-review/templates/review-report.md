# 🔍 審查報告

**審查時間**: YYYY-MM-DD HH:MM
**審查者**: REVIEWER Agent
**風險等級**: 🟢 LOW / 🟡 MEDIUM / 🔴 HIGH

---

## Verdict: ✅ APPROVED / 🔄 REQUEST CHANGES / ❌ REJECTED

---

## 審查範圍

| 指標 | 數值 |
|------|------|
| 檔案數 | X |
| 新增行數 | +XXX |
| 刪除行數 | -XXX |
| 修改函式數 | X |

### 修改的檔案
- `src/xxx.ts`
- `src/yyy.ts`

---

## Issues Found

### 🔴 Critical (必須修復)

> 無 / 有以下問題：

#### Issue 1: [問題類型]
- **位置**: `src/file.ts:42`
- **問題**: [具體描述]
- **風險**: [潛在影響]
- **建議修復**:
```typescript
// 修改前
const result = data.value;

// 修改後
const result = data?.value ?? defaultValue;
```

### 🟡 Important (建議修復)

> 無 / 有以下問題：

#### Issue 1: [問題類型]
- **位置**: `src/file.ts:100`
- **問題**: [具體描述]
- **建議**: [改進方向]

### 🟢 Minor (可選修復)

> 無 / 有以下建議：

- [建議 1]
- [建議 2]

---

## 優點

- [做得好的地方 1]
- [做得好的地方 2]

---

## 安全性檢查

- [ ] 無 SQL 注入風險
- [ ] 無 XSS 風險
- [ ] 無敏感資料洩露
- [ ] 輸入驗證完整
- [ ] 適當的權限檢查

---

## Action Required

**如果 APPROVED：**
→ 請 TESTER 進行測試

**如果 REQUEST CHANGES：**
→ 請 DEVELOPER 修復以下問題：
1. [具體修復指示 1]
2. [具體修復指示 2]

**如果 REJECTED：**
→ 需要重大修改，請參考以下建議：
1. [建議 1]
2. [建議 2]
