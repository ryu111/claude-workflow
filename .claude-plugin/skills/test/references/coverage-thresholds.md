# 測試覆蓋率門檻

## 建議的覆蓋率標準

| 專案類型 | 行覆蓋率 | 分支覆蓋率 | 函式覆蓋率 |
|----------|----------|------------|------------|
| 核心庫/SDK | ≥ 90% | ≥ 85% | ≥ 95% |
| Web 應用 | ≥ 80% | ≥ 70% | ≥ 85% |
| CLI 工具 | ≥ 75% | ≥ 65% | ≥ 80% |
| 原型/POC | ≥ 60% | - | ≥ 70% |

## 關鍵路徑必須 100% 覆蓋

以下功能必須有完整的測試覆蓋：

- 認證/授權邏輯
- 支付/金融相關
- 資料加密/解密
- 用戶輸入驗證
- API 邊界檢查

## 框架配置範例

### Jest (jest.config.js)

```javascript
module.exports = {
  coverageThreshold: {
    global: {
      branches: 70,
      functions: 85,
      lines: 80,
      statements: 80
    },
    // 關鍵路徑更高標準
    './src/auth/**/*.ts': {
      branches: 90,
      functions: 100,
      lines: 95
    }
  }
};
```

### Pytest (pyproject.toml)

```toml
[tool.coverage.run]
branch = true
source = ["src"]

[tool.coverage.report]
fail_under = 80
exclude_lines = [
    "pragma: no cover",
    "if TYPE_CHECKING:",
    "raise NotImplementedError"
]
```

### Go (Makefile)

```makefile
test-coverage:
	go test -coverprofile=coverage.out ./...
	go tool cover -func=coverage.out | grep total | awk '{print $$3}'
	@coverage=$$(go tool cover -func=coverage.out | grep total | awk '{print $$3}' | tr -d '%'); \
	if [ $$(echo "$$coverage < 80" | bc) -eq 1 ]; then \
		echo "Coverage $$coverage% is below 80%"; exit 1; \
	fi
```

## 排除覆蓋率的情況

以下程式碼可以合理地排除在覆蓋率計算之外：

1. **產生的程式碼**：protobuf, OpenAPI clients
2. **測試輔助工具**：test fixtures, mocks
3. **開發工具**：scripts, migrations
4. **無法測試的程式碼**：平台特定代碼、panic handlers

## 覆蓋率報告格式

```markdown
## 🧪 覆蓋率報告

| 指標 | 目標 | 實際 | 狀態 |
|------|------|------|------|
| 行覆蓋率 | 80% | 85% | ✅ |
| 分支覆蓋率 | 70% | 68% | ⚠️ |
| 函式覆蓋率 | 85% | 92% | ✅ |

### 低覆蓋率檔案
- `src/utils/legacy.ts` - 45% (建議重構或補充測試)
- `src/config/env.ts` - 30% (環境相關，可排除)
```
