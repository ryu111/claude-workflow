---
name: test
description: |
  測試專業知識。自動載入於 TESTER 執行測試、驗證功能相關任務時。
  觸發詞：test, 測試, 驗證, verify, PASS, FAIL, pytest, jest, coverage, 覆蓋率
user-invocable: false
disable-model-invocation: false
---

# 測試知識

## 測試金字塔

```
        /\
       /  \     E2E Tests (少量)
      /────\
     /      \   Integration Tests (適量)
    /────────\
   /          \  Unit Tests (大量)
  /────────────\
```

## 測試優先順序

1. **回歸測試** - 確保現有功能不被破壞
2. **功能測試** - 驗證新功能正確
3. **邊界測試** - 測試邊界情況
4. **錯誤測試** - 測試錯誤處理

## 框架指令

### Python (pytest)
```bash
pytest                              # 執行所有測試
pytest tests/test_user.py           # 執行特定檔案
pytest tests/test_user.py::test_x   # 執行特定測試
pytest -v                           # 詳細輸出
pytest --cov=src                    # 覆蓋率
pytest -x                           # 失敗時停止
```

### JavaScript/TypeScript (Jest/Vitest)
```bash
npm test                            # 執行所有測試
npm test -- user.test.ts            # 執行特定檔案
npm test -- -t "should create"      # 執行特定測試
npm test -- --coverage              # 覆蓋率
npm test -- --watch                 # Watch 模式
```

### Go
```bash
go test ./...                       # 執行所有測試
go test ./pkg/user                  # 執行特定套件
go test -v ./...                    # 詳細輸出
go test -cover ./...                # 覆蓋率
```

### Rust
```bash
cargo test                          # 執行所有測試
cargo test test_name                # 執行特定測試
cargo test -- --nocapture           # 顯示 println
```

## 測試模式

### Arrange-Act-Assert (AAA)
```typescript
test('should calculate total', () => {
  // Arrange
  const items = [{ price: 10, quantity: 2 }];
  // Act
  const total = calculateTotal(items);
  // Assert
  expect(total).toBe(20);
});
```

## 邊界測試案例

| 類型 | 測試案例 |
|------|----------|
| 空值 | null, undefined, 空字串, 空陣列 |
| 極限值 | 0, -1, MAX_INT, 最大長度 |
| 特殊字元 | 空白, 換行, Unicode, emoji |
| 格式 | 不正確的 email, 無效日期 |

## 測試報告格式

```markdown
## 🧪 測試報告

### 執行摘要
- 總測試數：XXX
- 通過：XXX ✅ (XX%)
- 失敗：XXX ❌ (XX%)
- 執行時間：X.XXs

### 失敗的測試
#### test_name
**錯誤訊息：** ...
**位置：** tests/test_file.py:42

### 覆蓋率
- 總覆蓋率：XX%
```

## 資源

### Scripts

- [detect-framework.sh](scripts/detect-framework.sh) - 自動偵測專案使用的測試框架
- [run-tests.sh](scripts/run-tests.sh) - 統一的測試執行腳本

### Templates

- [test-report.md](templates/test-report.md) - 測試報告範本

### References

- [coverage-thresholds.md](references/coverage-thresholds.md) - 覆蓋率門檻參考
