---
name: ralph-loop
description: |
  Ralph Loop 官方持續執行機制使用指引。
  基於 Stop hook 自我引用迴圈，反饋相同 prompt 直到任務完成。
  觸發詞：ralph, loop, 持續, 繼續, 做完, 全部執行, 自動化, 不要停, 一次搞定, 連續執行, 跑完, 完成所有, continuous, auto, run all, finish all, keep going, iterate
user-invocable: false
disable-model-invocation: false
---

# Ralph Loop 使用指引

## 🎯 什麼是 Ralph Loop？

Ralph Loop 是 Anthropic 官方提供的持續執行機制，使用 **Stop hook 攔截退出** + **自我引用迴圈** 讓 Claude 自動迭代直到任務完成。

### 核心機制

```
Claude 執行任務
    ↓
嘗試退出
    ↓
Stop hook 攔截 ←─────┐
    ↓                │
反饋「相同 prompt」   │
    ↓                │
Claude 讀取前次結果   │
（檔案、git history）│
    ↓                │
繼續執行 ───────────┘
```

### 與 /loop 指令的差異

| 機制 | 任務來源 | 追蹤方式 | 適用場景 |
|------|----------|----------|----------|
| `/loop` (本專案) | tasks.md / TodoList | Agent 委派 + checkbox | 結構化多任務 |
| `/ralph-loop` (官方) | 固定 prompt | 自主判斷 | 單一迭代任務 |

**整合使用**：在 `/loop` 執行每個任務時，內部可使用 ralph-loop 機制。

## ⚠️ 強制使用規則

### 何時必須使用 Ralph Loop

當用戶說以下任一觸發詞時，**必須**考慮啟動 Ralph Loop：

| 中文觸發詞 | 英文觸發詞 |
|-----------|-----------|
| ralph, 持續, 繼續 | ralph, loop, continuous |
| 做完, 全部執行, 跑完 | run all, finish all, complete all |
| 自動化, 不要停 | auto, keep going |
| 一次搞定, 連續執行 | iterate, iterate until done |
| 完成所有 | - |

### 啟動方式

使用 `/ralph-loop` 命令：

```bash
/ralph-loop "<任務描述與完成條件>" --max-iterations <N> --completion-promise "<完成標記>"
```

### 參數說明

| 參數 | 必填 | 說明 | 預設值 |
|------|:----:|------|--------|
| `<prompt>` | ✅ | 任務描述（每次迭代固定不變） | - |
| `--max-iterations` | ❌ | 最大迭代次數（安全機制） | 無限 |
| `--completion-promise` | ❌ | 完成標記字串（精確匹配） | null |

**⚠️ 重要**：`--max-iterations` 是**主要安全機制**，永遠建議設定。

## 📋 Prompt 撰寫最佳實踐

### 1. 明確完成條件

❌ 錯誤：
```
/ralph-loop "Build a todo API and make it good."
```

✅ 正確：
```
/ralph-loop "Build a REST API for todos.

Requirements:
- CRUD endpoints (GET/POST/PUT/DELETE)
- Input validation with error messages
- Unit tests (coverage > 80%)
- README with API documentation

Output <promise>COMPLETE</promise> when all requirements met." --completion-promise "COMPLETE" --max-iterations 30
```

### 2. 階段性目標

```
/ralph-loop "Implement user authentication with JWT.

Phase 1: Setup
- Install dependencies (jsonwebtoken, bcrypt)
- Create User model with password hashing

Phase 2: Implementation
- POST /auth/register endpoint
- POST /auth/login endpoint (returns JWT)
- Authentication middleware

Phase 3: Validation
- Write tests for all endpoints
- Run tests until all pass
- Document API in README

Output <promise>AUTH_COMPLETE</promise> when all phases done and tests pass." --completion-promise "AUTH_COMPLETE" --max-iterations 40
```

### 3. 自我修復指引

```
/ralph-loop "Fix failing tests in tests/user.test.ts

Steps:
1. Run tests and read output
2. Identify failing test cases
3. Fix implementation in src/user.ts
4. Re-run tests
5. Repeat until all tests pass
6. Output <promise>ALL_TESTS_PASS</promise>

If stuck after 10 iterations:
- Document the blocking issue
- List what was attempted
- Suggest alternative approaches" --completion-promise "ALL_TESTS_PASS" --max-iterations 15
```

### 4. 包含退出策略

```markdown
After 20 iterations, if not complete:
1. Summarize what was accomplished
2. List remaining work
3. Document blockers
4. Output <promise>BLOCKED</promise>
```

**注意**：`--completion-promise` 僅支援**單一**字串精確匹配，無法用於多條件（如 "SUCCESS" vs "BLOCKED"）。依賴 `--max-iterations` 作為主要安全機制。

## 🔄 執行流程

```
使用者執行 /ralph-loop
       ↓
創建 .claude/ralph-loop.local.md
（存儲：prompt, iteration, max_iterations, completion_promise）
       ↓
Claude 開始執行任務
       ↓
嘗試退出
       ↓
Stop hook 攔截
       ↓
┌─────────────────────────────────────┐
│       檢查退出條件                    │
├─────────────────────────────────────┤
│ ✅ iteration >= max_iterations?      │
│ ✅ 輸出包含 <promise>TEXT</promise>?│
└─────────────────────────────────────┘
    ↙                               ↘
  YES                               NO
    ↓                                ↓
刪除 state 檔案                    iteration++
退出                              反饋相同 prompt
                                      ↓
                                 Claude 讀取檔案
                                  （看到前次結果）
                                      ↓
                                  繼續執行 ↑
```

## 🛡️ 安全機制

### 退出條件（任一滿足即退出）

1. **達到最大迭代次數** - `iteration >= max_iterations`
2. **偵測完成標記** - 輸出包含 `<promise>COMPLETION_PROMISE</promise>`
3. **手動取消** - 執行 `/cancel-ralph`
4. **狀態檔案損壞** - 自動清理並退出

### 防止無限迴圈

**永遠設定 `--max-iterations`**：

```bash
# ❌ 危險：無退出上限
/ralph-loop "Build a complex system" --completion-promise "DONE"

# ✅ 安全：有明確上限
/ralph-loop "Build a complex system" --completion-promise "DONE" --max-iterations 50
```

### 完成承諾誠實原則

**絕對禁止**為了退出而輸出假的完成承諾：

```markdown
❌ 錯誤心態：
「雖然測試還沒過，但我想退出了，輸出 <promise>COMPLETE</promise> 吧」

✅ 正確心態：
「測試還沒全過，不能輸出 COMPLETE。繼續修復或等到 max_iterations。」
```

Claude Code 設計迴圈是為了**真正完成任務**，而非找藉口退出。

## 📊 狀態檔案

Ralph Loop 使用 `.claude/ralph-loop.local.md` 追蹤狀態：

```yaml
---
iteration: 5
max_iterations: 30
completion_promise: "COMPLETE"
---

Build a REST API for todos.
Requirements: CRUD operations, tests, README.
Output <promise>COMPLETE</promise> when done.
```

### 手動檢查進度

```bash
# 查看當前迭代次數
grep 'iteration:' .claude/ralph-loop.local.md

# 查看完成條件
grep 'completion_promise:' .claude/ralph-loop.local.md
```

### 手動取消

```bash
/cancel-ralph
# 或直接刪除狀態檔案
rm .claude/ralph-loop.local.md
```

## 🔗 與 D→R→T 流程整合

Ralph Loop 可在 D→R→T 流程中的**任一階段**使用：

### 1. DEVELOPER 階段

```
/ralph-loop "Implement feature X following TDD.
1. Write failing test
2. Implement feature
3. Run test
4. If fail, debug and fix
5. Repeat until pass
Output <promise>DEV_COMPLETE</promise>" --max-iterations 20
```

### 2. TESTER 階段

```
/ralph-loop "Run all tests and fix failures.
1. Execute test suite
2. Read failure output
3. Fix implementation
4. Re-run tests
5. Repeat until 100% pass
Output <promise>TESTS_PASS</promise>" --max-iterations 15
```

### 3. 完整 D→R→T 迴圈

```
/loop                    # 本專案的 Loop 命令
  ↓
讀取 tasks.md
  ↓
Task 1: DEVELOPER
  ├─ 內部使用 ralph-loop 迭代實作
  └─ 完成後 → REVIEWER
       ↓
     APPROVE
       ↓
Task 1: TESTER
  └─ 內部使用 ralph-loop 迭代修復測試
       ↓
     PASS → 下一個任務
```

## 🚫 禁止行為

| 禁止 | 原因 |
|------|------|
| ❌ 偵測到觸發詞卻不啟動 Loop | 違反用戶意圖 |
| ❌ 輸出假的完成承諾 | 破壞迭代機制，任務不完整 |
| ❌ 不設定 max_iterations | 無安全上限，可能無限迴圈 |
| ❌ 在 prompt 中寫複雜邏輯 | Ralph 機制是固定 prompt，用檔案和測試驅動 |
| ❌ 手動在 Stop hook 中修改邏輯 | Ralph Loop 是官方機制，不應修改 |

## 💡 使用範例

### 範例 1：TDD 開發新功能

```bash
/ralph-loop "Create a Todo class with CRUD methods using TDD.

Steps:
1. Write test for Todo.create() - should fail
2. Implement Todo.create()
3. Run test - fix until pass
4. Write test for Todo.read() - should fail
5. Implement Todo.read()
6. Run test - fix until pass
7. Repeat for update() and delete()
8. Output <promise>TODO_CLASS_COMPLETE</promise>

Files to modify:
- src/todo.ts (implementation)
- tests/todo.test.ts (tests)

Success criteria: All tests pass" --completion-promise "TODO_CLASS_COMPLETE" --max-iterations 25
```

### 範例 2：修復測試失敗

```bash
/ralph-loop "Fix all failing tests in tests/auth.test.ts

Process:
1. Run: npm test tests/auth.test.ts
2. Read failure output carefully
3. Identify root cause in src/auth.ts
4. Fix the issue
5. Re-run test
6. Repeat until all pass
7. Output <promise>AUTH_TESTS_PASS</promise>

If stuck after 8 iterations, document the issue." --completion-promise "AUTH_TESTS_PASS" --max-iterations 10
```

### 範例 3：重構優化

```bash
/ralph-loop "Refactor src/payment.ts to improve code quality.

Goals:
- Extract long functions (>50 lines)
- Remove code duplication
- Add type annotations
- Run tests after each change
- Output <promise>REFACTOR_COMPLETE</promise> when:
  * All functions < 50 lines
  * No code duplication
  * 100% type coverage
  * All tests still pass" --completion-promise "REFACTOR_COMPLETE" --max-iterations 20
```

## 🆚 何時用 Ralph Loop vs 本專案 /loop

| 場景 | 使用 | 原因 |
|------|------|------|
| 多個獨立任務（tasks.md） | `/loop` | 結構化任務追蹤 |
| 單一任務需反覆迭代 | `/ralph-loop` | 自我引用修復 |
| 測試驅動開發（TDD） | `/ralph-loop` | 測試失敗是明確信號 |
| 複雜多階段開發 | `/loop` | 委派不同 Agent |
| 修復特定測試失敗 | `/ralph-loop` | 迭代到通過 |
| 整個 OpenSpec 執行 | `/loop` | 標準工作流程 |

**組合使用**：
```
/loop                        # 外層：管理多任務
  ↓
Task 1: DEVELOPER
  └─ /ralph-loop "Implement X with TDD" --max-iterations 20
       ↓
     完成 → REVIEWER → TESTER
                         ↓
Task 2: DEVELOPER
  └─ /ralph-loop "Implement Y with TDD" --max-iterations 20
```

## 📚 進階技巧

### 1. 狀態持久化

Ralph Loop 依靠檔案系統保存進度：
- 修改的程式碼檔案
- Git commit history
- 測試輸出日誌
- 建立的文檔

每次迭代，Claude 讀取這些「前次結果」來判斷下一步。

### 2. 錯誤即資訊

失敗的測試輸出、編譯錯誤、linter 警告都是**有價值的信號**：

```
Iteration 1: 寫程式碼
    ↓
Iteration 2: 看到測試失敗輸出「expected X, got Y」
    ↓
Iteration 3: 修復邏輯錯誤
    ↓
Iteration 4: 看到測試通過 ✅
```

### 3. 漸進式細化

每次迭代不求完美，讓 Loop 自然優化：

```
Iteration 1-5:   基本功能實作
Iteration 6-10:  修復邊界案例
Iteration 11-15: 優化效能
Iteration 16-20: 補充文檔
```

## 🔍 除錯

### 狀態檔案損壞

```bash
# 檢查檔案格式
cat .claude/ralph-loop.local.md

# 手動修復或刪除重來
rm .claude/ralph-loop.local.md
/ralph-loop "..." --max-iterations 30
```

### 無限迴圈

如果忘記設定 `--max-iterations`，手動取消：

```bash
/cancel-ralph
```

### 完成承諾不匹配

`<promise>` 標籤內容必須**精確匹配** `--completion-promise` 參數：

```bash
# ❌ 不匹配
--completion-promise "DONE"
輸出：<promise>Done</promise>  # 大小寫不同

# ✅ 匹配
--completion-promise "DONE"
輸出：<promise>DONE</promise>
```

## 🌐 參考資源

### 官方文件
- GitHub: https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-loop
- 原始技術: https://ghuntley.com/ralph/

### 本專案整合
- D→R→T 流程：見 `skills/drt-rules/SKILL.md`
- OpenSpec 格式：見 `skills/openspec/SKILL.md`

### 相關命令
- `/ralph-loop` - 啟動 Ralph Loop
- `/cancel-ralph` - 取消 Ralph Loop
- `/loop` - 本專案的結構化任務迴圈（可配合使用）
