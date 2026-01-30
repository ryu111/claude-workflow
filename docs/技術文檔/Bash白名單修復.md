# Bash 命令檢查機制

## 版本資訊
- **當前版本**：v0.7.0（POSIX 兼容版）
- **更新日期**：2026-01-31

## 設計原則

**核心理念**：只阻擋「檔案寫入」操作，其他全部允許。

```
問自己：這個命令會「寫入檔案」嗎？
  │
  ├─ 否 → 允許執行
  │
  └─ 是 → 阻擋（需委派 DEVELOPER）
```

## 阻擋規則

### ❌ 阻擋的操作

| 操作 | 範例 | 原因 |
|------|------|------|
| 覆寫寫入 | `echo "x" > file.txt` | 寫入檔案 |
| 追加寫入 | `cat x >> file.txt` | 寫入檔案 |
| tee 寫入 | `echo "x" \| tee file.txt` | 寫入檔案 |

### ✅ 允許的操作

| 操作 | 範例 | 原因 |
|------|------|------|
| 管道 | `git log \| head -10` | 不寫入檔案 |
| 命令替換 | `ls -la $(pwd)` | 不寫入檔案 |
| 所有 git 命令 | `git add/commit/push` | 版本控制必要 |
| 測試命令 | `npm test`, `pytest` | 驗證必要 |
| 重定向到 /dev/null | `cmd 2>/dev/null` | 丟棄輸出，不寫入 |
| 流合併 | `cmd 2>&1` | 合併輸出流，不寫入 |

## 技術實作

### 檔案寫入偵測正則（v0.7 - POSIX 兼容版）

```bash
FILE_WRITE_PATTERN='(^|[;&[:space:]])(>>?)[[:space:]]*[^&[:space:]]|[[:space:]]tee[[:space:]]'
```

**說明**：
- `(^|[;&[:space:]])(>>?)[[:space:]]*[^&[:space:]]` - 檔案重定向（排除 `&` 流合併）
  - 使用 `[:space:]` 代替 `\s`（POSIX 兼容）
  - `>>?` 匹配 `>` 或 `>>`
- `[[:space:]]tee[[:space:]]` - tee 命令（簡化檢測）
  - 只要出現 `tee` 命令就阻擋，由 DEVELOPER 處理

### 安全重定向清理

執行偵測前，先移除安全的重定向：

```bash
# 移除 2>/dev/null, >/dev/null, 2>&1 等安全模式
COMMAND_SANITIZED=$(echo "$COMMAND" | sed -E 's/[0-9]*>(&[0-9]+|\/dev\/null)//g')
```

**清理模式**：
- `2>/dev/null` - stderr 重定向到 /dev/null
- `1>/dev/null` - stdout 重定向到 /dev/null
- `>/dev/null` - 預設 stdout 重定向到 /dev/null
- `2>&1` - stderr 重定向到 stdout
- `1>&2` - stdout 重定向到 stderr

## 測試案例

### ✅ 應該允許的命令

| 命令 | 說明 |
|------|------|
| `ls -la 2>/dev/null` | stderr 重定向 |
| `git status 2>&1` | stderr 合併到 stdout |
| `cat file.txt >/dev/null` | stdout 重定向 |
| `find . -name '*.ts' 2>/dev/null` | 查找命令抑制錯誤 |
| `git log \| head -10` | 管道操作 |
| `echo $(cat file.txt)` | 命令替換 |

### ❌ 應該阻擋的命令

| 命令 | 說明 |
|------|------|
| `echo 'test' > file.txt` | 寫入檔案 |
| `ls >> output.log` | 追加到檔案 |
| `cat file.txt \| tee backup.txt` | tee 寫入 |
| `ls -la > /tmp/output.txt` | 重定向到非 /dev/null |
| `command 2>> error.log` | stderr 追加到檔案 |

## 驗證方式

### 快速驗證指令（v0.7）

```bash
# 測試允許的命令（應回傳 exit 0）
export CLAUDE_SESSION_ID="test-verify"
rm -f "/tmp/claude-agent-state-test-verify"

echo '{"tool_name":"Bash","tool_input":{"command":"ls -la 2>/dev/null"}}' | \
  bash hooks/scripts/global-workflow-guard.sh

# 測試阻擋的命令（應回傳 JSON 包含 "decision": "block"）
echo '{"tool_name":"Bash","tool_input":{"command":"echo test > file.txt"}}' | \
  bash hooks/scripts/global-workflow-guard.sh

# 測試 tee 阻擋（v0.7 會阻擋所有 tee 命令）
echo '{"tool_name":"Bash","tool_input":{"command":"cat file.txt | tee backup.txt"}}' | \
  bash hooks/scripts/global-workflow-guard.sh
```

### Debug 日誌檢查

```bash
tail -f /tmp/claude-workflow-debug.log
```

查看是否包含：
- `Sanitized command: ls -la ` - 成功移除 `2>/dev/null`
- `Bash command allowed (no file write)` - 允許命令
- `Bash command blocked (file write detected)` - 阻擋寫入命令

## v0.7.0 變更摘要

### 核心改進

| 改進項目 | v0.6.0 | v0.7.0 |
|----------|--------|--------|
| 正則表達式語法 | `\s`, `\b` (Perl 語法) | `[:space:]` (POSIX 語法) |
| Bash 檢查邏輯 | ~50 行 | ~28 行 |
| tee 檢測 | 複雜規則（排除 `-a`, 絕對路徑） | 簡化為單純檢測 `tee` 命令 |
| 兼容性 | 依賴 GNU grep 或擴展正則 | POSIX 標準，跨平台兼容 |

### 簡化的機制

#### 1. Bash 命令檢查（第 88-128 行）

**v0.6.0 的問題**：
```bash
# 複雜的 tee 檢測邏輯
FILE_WRITE_PATTERN='(^|[;&\s])(>|>>)\s*[^&\s]|\btee\s+([^-/]|$)|\btee\s+-[^a]\s*[^/]'
```
- 需要處理 `tee -a`（追加模式）
- 需要排除絕對路徑
- 使用非 POSIX 語法 `\s`, `\b`

**v0.7.0 的解決方案**：
```bash
# 簡化且 POSIX 兼容
FILE_WRITE_PATTERN='(^|[;&[:space:]])(>>?)[[:space:]]*[^&[:space:]]|[[:space:]]tee[[:space:]]'
```
- 統一使用 `[:space:]` 字符類別
- 不再區分 `tee -a`，一律阻擋（由 DEVELOPER 處理）
- 邏輯清晰，易於理解

#### 2. 黑名單檢查（第 130-159 行）

**v0.6.0 的問題**：
```bash
# 分散在多處的檔案類型判斷
if [[ "$FILE_PATH" =~ \.ts$ ]] || [[ "$FILE_PATH" =~ \.tsx$ ]] || ...
```
- 需要逐一列舉副檔名
- 程式碼重複，難以維護

**v0.7.0 的解決方案**：
```bash
# 統一的正則表達式模式
CODE_FILE_PATTERN='\.(ts|tsx|js|jsx|py|sh|go|java|c|cpp|h|hpp|cs|sql|rs|rb|swift|kt|scala|php|lua|pl|r)$'
PROTECTED_DIRS='(^|/)hooks/|(^|/)agents/|(^|/)\.claude-plugin/'

# 統一的檢查函式
needs_drt() {
    local file_path="$1"
    [[ "$file_path" =~ $PROTECTED_DIRS ]] && return 0
    [[ "$file_path" =~ $CODE_FILE_PATTERN ]] && return 0
    return 1
}
```

### 新舊機制對比

| 項目 | v0.6.0 | v0.7.0 |
|------|--------|--------|
| **Bash 檢查** | | |
| 檔案重定向 | `(^|[;&\s])(>|>>)\s*[^&\s]` | `(^|[;&[:space:]])(>>?)[[:space:]]*[^&[:space:]]` |
| tee 檢測 | `\btee\s+([^-/]|$)\|\btee\s+-[^a]\s*[^/]` | `[[:space:]]tee[[:space:]]` |
| 總行數 | ~50 行 | ~28 行 |
| **黑名單檢查** | | |
| 程式碼檔案 | 分散的條件判斷 | `CODE_FILE_PATTERN` 正則 |
| 保護目錄 | 多個獨立判斷 | `PROTECTED_DIRS` 正則 |
| 檢查函式 | 內聯邏輯 | `needs_drt()` 統一函式 |

### POSIX 字符類別說明

| POSIX | 說明 | 等效 Perl 語法 |
|-------|------|----------------|
| `[:space:]` | 空白字符（空格、tab、換行） | `\s` |
| `[:alnum:]` | 字母和數字 | `\w`（部分） |
| `[:alpha:]` | 字母 | `[A-Za-z]` |
| `[:digit:]` | 數字 | `\d` |

**為什麼使用 POSIX**：
- ✅ 跨平台兼容（macOS, Linux, BSD）
- ✅ 不依賴 GNU grep 或 PCRE
- ✅ POSIX 標準，永久穩定

## 版本演進

| 版本 | 機制 | 說明 |
|------|------|------|
| v0.5.x | 白名單 + 黑名單 | 複雜、難維護、誤判多 |
| v0.6.0 | 只阻擋檔案寫入 | 簡單、準確，但正則表達式複雜 |
| **v0.7.0** | POSIX 兼容簡化版 | 使用 `[:space:]` 等 POSIX 字符類別，從 ~50 行簡化至 ~28 行 |

## 為什麼選擇簡化方案？

### 優點（v0.7 加強版）
1. **直觀**：一句話說明規則「不允許寫入檔案」
2. **準確**：正則表達式清晰，不誤判
3. **可維護**：規則集中，易於理解和擴展
4. **相容性**：使用 POSIX 標準，跨平台穩定
5. **精簡**：從 v0.6 的 ~50 行簡化至 ~28 行

### 替代方案（未採用）
複雜的白名單維護：
```bash
# ❌ 未採用：需要列舉所有允許的命令
WHITELIST="git|npm|ls|cat|grep|find|..."
```

**不採用原因**：
- 無法窮舉所有合法命令
- 新增合法命令需修改腳本
- 維護成本高

## 影響範圍

### 直接影響
- Main Agent 執行唯讀 Bash 命令時不再被誤阻擋
- 提升工作流程的流暢度（減少不必要的 subagent 呼叫）

### 無影響
- Subagent 內的 Bash 命令（本來就允許）
- Write/Edit 工具的黑名單檢查
- 其他 Hook 邏輯

## 相關檔案

- `hooks/scripts/global-workflow-guard.sh` - 實作位置
  - Bash 命令檢查：第 88-128 行
  - 黑名單檢查：第 130-159 行
- `skills/drt-rules/SKILL.md` - Main Agent Bash 使用規則
- `tests/test-bash-whitelist-fix.sh` - 自動化驗證測試
