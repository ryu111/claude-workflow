# Bash 命令阻擋邏輯測試摘要

## 修復內容

修復 `hooks/scripts/global-workflow-guard.sh` 中的 Bash 命令阻擋 Bug。

### 問題

1. **Sanitize 正則不完整**：原始的 `sed -E 's/[0-9]*>(&[0-9]+|\/dev\/null)//g'` 無法匹配 `> /dev/null`（帶空格）
2. **FILE_WRITE_PATTERN 不完整**：原始的 `(>>?)` 無法匹配 `2>` 和 `2>>` 這類數字前綴的重定向

### 修復方案

#### 1. 修正 Sanitize 邏輯（第 99 行）

```bash
# 修正前
COMMAND_SANITIZED=$(echo "$COMMAND" | sed -E 's/[0-9]*>(&[0-9]+|\/dev\/null)//g')

# 修正後
COMMAND_SANITIZED=$(echo "$COMMAND" | sed -E 's/[0-9]*> *(&[0-9]+|\/dev\/null)//g' | sed -E 's/[0-9]*>> *\/dev\/null//g')
```

**變更**：
- 加上 ` *` 匹配 `>` 後的空格
- 新增 `sed` 處理 `>> /dev/null`

#### 2. 修正 FILE_WRITE_PATTERN（第 119 行）

```bash
# 修正前
FILE_WRITE_PATTERN='(^|[;&[:space:]])(>>?)[[:space:]]*[^&[:space:]]|[[:space:]]tee[[:space:]]'

# 修正後
FILE_WRITE_PATTERN='(^|[;&[:space:]])([0-9]*>>?)[[:space:]]*[^&[:space:]]|[[:space:]]tee[[:space:]]'
```

**變更**：
- `(>>?)` → `([0-9]*>>?)`：支援 `2>`, `2>>` 等數字前綴

## 測試驗證

### 執行測試

```bash
bash tests/unit/test-bash-pattern-logic.sh
```

### 測試覆蓋範圍

#### ✅ 應該允許（13 個案例）

| 測試案例 | 命令範例 | 原因 |
|----------|----------|------|
| stderr 到 /dev/null | `ls -la 2>/dev/null` | 安全重定向 |
| stderr 和 stdout 合併 | `git status 2>&1` | 流重定向 |
| stdout 到 /dev/null | `cat file.txt >/dev/null` | 安全重定向 |
| 邏輯 OR | `tail -50 file.log \|\| echo error` | 邏輯運算 |
| 邏輯 AND | `npm install && npm test` | 邏輯運算 |
| 管道 | `git log \| head` | 資料流轉 |
| 命令替換 $() | `echo $(cat file)` | 讀取操作 |
| 命令替換 \`\` | `echo \`whoami\`` | 讀取操作 |
| 管道鏈 | `cat file \| grep test \| wc -l` | 資料流轉 |

#### ❌ 應該阻擋（6 個案例）

| 測試案例 | 命令範例 | 原因 |
|----------|----------|------|
| 覆寫檔案 | `echo 'test' > file.txt` | 檔案寫入 |
| 追加檔案 | `ls >> output.log` | 檔案寫入 |
| tee 寫入 | `cat file.txt \| tee backup.txt` | 檔案寫入 |
| stderr 寫入到檔案 | `command 2> error.log` | 檔案寫入 |
| stderr 追加到檔案 | `command 2>> error.log` | 檔案寫入 |

## 符合 v0.7 原則

此修復符合 **v0.7 最小必要阻擋原則**：

> 只阻擋「檔案寫入」操作（`>`, `>>`, `tee`），其他全部允許

### 允許的操作

- ✅ 管道 `|`
- ✅ 邏輯運算 `||` `&&`
- ✅ 命令替換 `$()` `` ` ``
- ✅ 流重定向 `2>&1` `1>&2`
- ✅ 安全重定向 `>/dev/null` `2>/dev/null`
- ✅ 所有讀取命令（`cat`, `grep`, `find`, `git`, `npm` 等）

### 阻擋的操作

- ❌ `> file` 覆寫寫入
- ❌ `>> file` 追加寫入
- ❌ `tee file` 寫入檔案
- ❌ `2> file` stderr 寫入
- ❌ `2>> file` stderr 追加

## 測試結果

```
═══════════════════════════════════════════════════════════════
  Bash 命令阻擋邏輯單元測試
═══════════════════════════════════════════════════════════════

測試原則：v0.7 最小必要阻擋
  ✅ 允許：管道、邏輯運算、命令替換、安全重定向
  ❌ 阻擋：檔案寫入（>, >>, tee）

【應該允許的命令】：13 個 ✅
【應該阻擋的命令】：6 個 ✅

═══════════════════════════════════════════════════════════════
✅ 所有測試通過 (0 failed)
═══════════════════════════════════════════════════════════════
```

## 修改檔案清單

1. **hooks/scripts/global-workflow-guard.sh**
   - Line 99: 修正 Sanitize 正則
   - Line 119: 修正 FILE_WRITE_PATTERN

2. **tests/unit/test-bash-pattern-logic.sh** （新建）
   - 單元測試：驗證 Bash 命令阻擋邏輯
   - 19 個測試案例（13 允許 + 6 阻擋）

3. **tests/test-bash-whitelist-fix.sh** （修正）
   - 修正不符合 v0.7 原則的測試案例
   - 移除「命令替換」和「反引號」的阻擋測試（應該允許）

## 後續建議

1. **刪除不符合設計的測試**：`tests/test-bash-whitelist-fix.sh` 的設計依賴 Hook 系統，建議移除或重寫為單元測試
2. **統一測試框架**：建議使用 `tests/unit/` 目錄存放單元測試，避免整合測試的複雜性
