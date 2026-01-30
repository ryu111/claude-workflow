# Bash 命令檢查機制

## 版本資訊
- **當前版本**：v0.6.0（簡化版）
- **更新日期**：2026-01-30

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

### 檔案寫入偵測正則

```bash
FILE_WRITE_PATTERN='(^|[;&\s])(>|>>)\s*[^&\s]|\btee\s+([^-/]|$)|\btee\s+-[^a]\s*[^/]'
```

**說明**：
- `(^|[;&\s])(>|>>)\s*[^&\s]` - 檔案重定向（排除 `&` 流合併）
- `\btee\s+([^-/]|$)` - tee 寫入（排除 `-a` 和絕對路徑）
- `\btee\s+-[^a]\s*[^/]` - tee 帶非 `-a` 選項的寫入

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

### 快速驗證指令

```bash
# 測試允許的命令（應回傳 exit 0）
export CLAUDE_SESSION_ID="test-verify"
rm -f "/tmp/claude-agent-state-test-verify"

echo '{"tool_name":"Bash","tool_input":{"command":"ls -la 2>/dev/null"}}' | \
  bash hooks/scripts/global-workflow-guard.sh

# 測試阻擋的命令（應回傳 JSON 包含 "decision": "block"）
echo '{"tool_name":"Bash","tool_input":{"command":"echo test > file.txt"}}' | \
  bash hooks/scripts/global-workflow-guard.sh
```

### Debug 日誌檢查

```bash
tail -f /tmp/claude-workflow-debug.log
```

查看是否包含：
- `Sanitized command: ls -la ` - 成功移除 `2>/dev/null`
- `Bash command allowed (no file write)` - 允許命令

## 版本演進

| 版本 | 機制 | 問題 |
|------|------|------|
| v0.5.x | 白名單 + 黑名單 | 複雜、難維護、誤判多 |
| **v0.6.0** | 只阻擋檔案寫入 | 簡單、準確、易理解 |

## 為什麼選擇簡化方案？

### 優點
1. **直觀**：一句話說明規則「不允許寫入檔案」
2. **準確**：正則表達式清晰，不誤判
3. **可維護**：規則集中，易於理解和擴展
4. **相容性**：不依賴特定 grep 版本或 Bash 功能

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

- `hooks/scripts/global-workflow-guard.sh` - 實作位置（第 88-128 行）
- `skills/drt-rules/SKILL.md` - Main Agent Bash 使用規則
