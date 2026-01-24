# 並行執行範例

## 範例場景

用戶需求：建立一個電商平台的核心服務層

## OpenSpec 任務清單

```markdown
## 1. Foundation (sequential)
- [x] 1.1 建立基礎 Service 抽象類 | agent: developer | files: src/services/base.ts

## 2. Core Services (parallel)
- [ ] 2.1 建立 UserService | agent: developer | files: src/services/user.ts
- [ ] 2.2 建立 ProductService | agent: developer | files: src/services/product.ts
- [ ] 2.3 建立 OrderService | agent: developer | files: src/services/order.ts
- [ ] 2.4 建立 PaymentService | agent: developer | files: src/services/payment.ts

## 3. Integration (sequential, depends: 2)
- [ ] 3.1 整合所有服務 | agent: developer | files: src/services/index.ts
```

---

## 調度決策過程

### Step 1: 分析 Phase 2

```markdown
## 📊 Phase 2 分析

**執行類型**: parallel
**任務數量**: 4
**依賴關係**: 全部依賴 Phase 1 完成，彼此無依賴
```

### Step 2: 確認可並行

| 檢查項目 | 結果 | 說明 |
|----------|------|------|
| 檔案衝突 | ✅ 無 | 四個任務修改不同檔案 |
| 資料依賴 | ✅ 無 | 服務間無直接依賴 |
| 共享資源 | ✅ 無 | 無共用狀態 |

**結論**: 可以並行執行

### Step 3: 啟動並行任務

```markdown
## ⚡ 並行啟動 4 個 DEVELOPER

### Task 2.1 - UserService
**檔案**: src/services/user.ts
**功能**: 用戶 CRUD、認證相關
**參考**: src/services/base.ts

### Task 2.2 - ProductService
**檔案**: src/services/product.ts
**功能**: 商品 CRUD、庫存管理
**參考**: src/services/base.ts

### Task 2.3 - OrderService
**檔案**: src/services/order.ts
**功能**: 訂單建立、狀態管理
**參考**: src/services/base.ts

### Task 2.4 - PaymentService
**檔案**: src/services/payment.ts
**功能**: 支付處理、退款
**參考**: src/services/base.ts
```

---

## 並行執行中的狀態追蹤

```markdown
## 🔄 Phase 2 執行狀態

| Task | Agent | 狀態 | 進度 |
|------|-------|------|------|
| 2.1 | DEVELOPER-A | ✅ 完成 | D→R→T ✓ |
| 2.2 | DEVELOPER-B | 🔄 審查中 | D→R... |
| 2.3 | DEVELOPER-C | ❌ 測試失敗 | D→R→T✗ |
| 2.4 | DEVELOPER-D | 🔄 開發中 | D... |

### 處理 Task 2.3 失敗
- 啟動 DEBUGGER 分析 Task 2.3
- 不影響其他任務繼續執行
- 修復後重新進入 D→R→T
```

---

## 錯誤處理範例

### 情況 1: 單一任務失敗

```markdown
## ❌ Task 2.3 測試失敗

**錯誤**: OrderService.createOrder 未處理庫存不足
**處理**:
1. 其他任務繼續執行
2. 啟動 DEBUGGER 分析 Task 2.3
3. DEBUGGER 完成後 → DEVELOPER 修復 → REVIEWER → TESTER
```

### 情況 2: 多任務失敗

```markdown
## ❌ 多任務失敗

**失敗任務**: 2.3, 2.4
**處理策略**: 依序處理，避免複雜度爆炸
1. 先處理 Task 2.3 (影響範圍較小)
2. Task 2.3 修復後，處理 Task 2.4
```

### 情況 3: 發現跨任務問題

```markdown
## ⚠️ 發現共同問題

**問題**: base.ts 的 validate 方法有 bug
**影響**: 2.1, 2.2, 2.3, 2.4 全部受影響
**處理**:
1. 暫停所有 Phase 2 任務
2. 回到 Phase 1，修復 base.ts
3. 重新開始 Phase 2
```

---

## 匯合點管理

```markdown
## 🎯 Phase 2 完成確認

**狀態**: 全部完成
| Task | 結果 |
|------|------|
| 2.1 | ✅ PASS |
| 2.2 | ✅ PASS |
| 2.3 | ✅ PASS (重試後) |
| 2.4 | ✅ PASS |

**下一步**: 開始 Phase 3 (depends: 2)
```

---

## 關鍵原則

1. **獨立性確認**: 並行前必須確認任務間無依賴
2. **隔離錯誤**: 單一失敗不影響其他任務
3. **依序修復**: 多任務失敗時依序處理
4. **匯合等待**: 所有並行任務完成才進入下一 Phase
