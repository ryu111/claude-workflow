# E2E 測試框架

> Claude Workflow Plugin 的端對端測試系統

## 概述

此 E2E 測試框架用於驗證 D→R→T 工作流程的正確性和合規率。

## 執行方式

```bash
# 執行所有場景
bash tests/e2e/e2e-runner.sh --all

# 執行單一場景
bash tests/e2e/e2e-runner.sh E2E-001

# 列出可用場景
bash tests/e2e/e2e-runner.sh --list
```

## 測試場景

| 場景 | 名稱 | 驗證重點 |
|------|------|----------|
| E2E-001 | 簡單功能開發 | D→R→T 基本流程 |
| E2E-002 | 高風險功能開發 | HIGH 風險深度審查 |
| E2E-003 | 多任務並行開發 | Change ID 隔離 |
| E2E-004 | 違規檢測與修復 | 自動阻擋與修復 |
| E2E-005 | 重試機制測試 | 失敗後風險升級 |
| E2E-006 | CHANGE_ID 自動生成 | 無 ID 時自動生成 |
| E2E-007 | 狀態過期處理 | 30 分鐘過期阻擋 |
| E2E-008 | 並行競態條件 | 狀態隔離與原子寫入 |
| E2E-009 | REJECT 迴圈限制 | 連續 5 次後暫停 |
| E2E-010 | 全自動 HIGH RISK | 完整自動化流程 |

## 閉環退出條件

```
退出 = (合規率 >= 90%) AND (所有任務完成)
```

## 測試架構

```
tests/e2e/
├── e2e-runner.sh       # 測試運行器
├── checklist.yaml      # 驗證檢查清單
├── lib/                # 統計彙總庫
│   └── aggregate.sh
├── scenarios/          # 測試場景目錄（10 個）
│   ├── E2E-001/
│   ├── E2E-002/
│   └── ...
└── reports/            # 測試報告輸出
```

## 統計項目

### 合規率計算

- **合規行為**：正確執行 D→R→T 順序
- **違規行為**：跳過 REVIEWER、錯誤順序
- **合規率** = 合規次數 / (合規次數 + 違規次數) × 100%

### 追蹤指標

| 指標 | 說明 |
|------|------|
| DEVELOPER 啟動次數 | 程式碼實作階段觸發 |
| REVIEWER 啟動次數 | 程式碼審查階段觸發 |
| TESTER 啟動次數 | 測試執行階段觸發 |
| 違規次數 | 流程順序錯誤 |
| 阻擋次數 | workflow-gate.sh 自動阻擋 |

## 場景詳細說明

### E2E-001：簡單功能開發

- **目標**：驗證基本 D→R→T 流程
- **任務**：新增簡單 utility 函數
- **預期**：DEVELOPER → REVIEWER → TESTER → 完成

### E2E-002：高風險功能開發

- **目標**：驗證 HIGH RISK 深度審查
- **任務**：修改認證模組
- **預期**：風險自動升級 → 完整流程 → 人工確認建議

### E2E-003：多任務並行開發

- **目標**：驗證 Change ID 隔離機制
- **任務**：同時執行 3 個獨立任務
- **預期**：狀態不互相干擾

### E2E-004：違規檢測與修復

- **目標**：驗證自動阻擋機制
- **任務**：故意跳過 REVIEWER
- **預期**：workflow-gate.sh 阻擋 → 提示正確流程

### E2E-005：重試機制測試

- **目標**：驗證 REJECT/FAIL 重試邏輯
- **任務**：製造審查失敗場景
- **預期**：重試後風險升級

### E2E-006：CHANGE_ID 自動生成

- **目標**：驗證缺失 ID 時自動生成
- **任務**：不提供 CHANGE_ID
- **預期**：自動生成格式為 `CHG-YYYYMMDD-HHMM`

### E2E-007：狀態過期處理

- **目標**：驗證 30 分鐘過期邏輯
- **任務**：修改狀態檔時間戳
- **預期**：過期狀態被阻擋，要求重新執行

### E2E-008：並行競態條件

- **目標**：驗證多任務並行安全性
- **任務**：模擬並行寫入狀態檔
- **預期**：無狀態覆蓋，正確隔離

### E2E-009：REJECT 迴圈限制

- **目標**：驗證連續失敗保護機制
- **任務**：製造連續 REJECT
- **預期**：5 次後暫停並通知用戶

### E2E-010：全自動 HIGH RISK

- **目標**：驗證完整自動化流程
- **任務**：核心模組變更從頭到尾
- **預期**：自動執行 D → R(深度) → T(完整)

## 開發指南

### 新增測試場景

1. 在 `scenarios/` 建立新目錄：`E2E-XXX/`
2. 建立場景描述：`scenario.md`
3. 建立測試腳本：`test.sh`
4. 更新 `checklist.yaml`
5. 執行驗證：`bash e2e-runner.sh E2E-XXX`

### 檢查清單格式

```yaml
scenarios:
  E2E-001:
    name: "簡單功能開發"
    checks:
      - id: "drt-order"
        description: "D→R→T 順序正確"
        type: "compliance"
      - id: "no-skip-reviewer"
        description: "未跳過 REVIEWER"
        type: "violation"
```

## 相關文件

- [workflow-diagrams.md](../../docs/workflow-diagrams.md) - 工作流程圖
- [CLAUDE.md](../../CLAUDE.md) - 專案說明
- [D→R→T 規則](../../skills/drt-rules/SKILL.md) - 詳細規則

## 常見問題

### Q: 如何調整合規率閾值？

修改 `e2e-runner.sh` 中的 `COMPLIANCE_THRESHOLD` 變數（預設 90%）。

### Q: 測試報告存放在哪？

測試報告自動生成於 `tests/e2e/reports/` 目錄。

### Q: 如何調試失敗的測試？

1. 查看報告檔案：`reports/E2E-XXX-YYYYMMDD-HHMM.txt`
2. 檢查狀態檔：`.claude-drt/state/CHG-*.json`
3. 查看 Hook 日誌：`.claude-drt/logs/workflow-gate.log`

## 版本資訊

- **文件版本**：v1.0.0
- **對應 Plugin 版本**：v0.6.0
- **最後更新**：2026-01-29
- **維護者**：DEVELOPER Agent
