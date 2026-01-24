# [CHANGE-ID] Tasks

## Progress
- Total: X tasks
- Completed: 0
- Status: NOT_STARTED

---

## 1. [Phase 名稱] (sequential)

> 說明：[這個 Phase 要完成什麼]

- [ ] 1.1 [任務名稱] | agent: developer | files: src/xxx.ts
  - 描述：[詳細說明]
  - 驗收：[完成標準]

- [ ] 1.2 [任務名稱] | agent: developer | files: src/yyy.ts
  - 描述：[詳細說明]
  - 驗收：[完成標準]

---

## 2. [Phase 名稱] (parallel)

> 說明：[這個 Phase 要完成什麼，可並行執行]

- [ ] 2.1 [任務名稱] | agent: developer | files: src/aaa.ts
  - 描述：[詳細說明]
  - 驗收：[完成標準]

- [ ] 2.2 [任務名稱] | agent: developer | files: src/bbb.ts
  - 描述：[詳細說明]
  - 驗收：[完成標準]

---

## 3. Review & Test (sequential)

> 說明：最終審查與測試

- [ ] 3.1 整合審查 | agent: reviewer | files: [所有修改的檔案]
- [ ] 3.2 整合測試 | agent: tester | files: tests/

---

## Notes

### 依賴關係
- Phase 2 依賴 Phase 1 完成
- Task 2.1 和 2.2 可並行

### 風險項目
- [潛在風險和注意事項]
