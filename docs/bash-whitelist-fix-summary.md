# Bash 白名單修復摘要

## 問題描述

**Bug**: `2>/dev/null` 等安全的重定向被誤判為危險操作而被阻擋

**原因**: `DANGEROUS_OPERATORS` 正則表達式 `>|>>|...` 中的 `>` 會匹配到 `2>/dev/null` 中的 `>`

**影響**: 合法的唯讀命令（如 `ls -la 2>/dev/null || echo "..."`）無法執行

## 修復方案

### 採用的方案：命令清理（Sanitization）

在檢查危險運算符之前，先移除安全的重定向模式：

```bash
# 先移除安全的重定向模式，再檢查危險運算符
# 安全的重定向：2>/dev/null, 2>&1, >/dev/null, 1>/dev/null
COMMAND_SANITIZED=$(echo "$COMMAND" | sed -E 's/[0-9]*>(&[0-9]+|\/dev\/null)//g')
echo "[$(date)] Sanitized command: $COMMAND_SANITIZED" >> "$DEBUG_LOG"

# 檢查是否包含寫入運算符（即使命令本身在白名單中）
DANGEROUS_OPERATORS=">|>>|\\|.*tee|\\\`|\\$\\("
if echo "$COMMAND_SANITIZED" | grep -qE "$DANGEROUS_OPERATORS"; then
    echo "[$(date)] Bash command blocked (contains dangerous operators)" >> "$DEBUG_LOG"
    # 繼續執行阻擋邏輯（不 exit 0）
else
    # 繼續白名單檢查...
fi
```

### 清理規則說明

正則表達式 `[0-9]*>(&[0-9]+|\/dev\/null)` 會移除：

1. **`2>/dev/null`** → stderr 重定向到 /dev/null
2. **`1>/dev/null`** → stdout 重定向到 /dev/null
3. **`>/dev/null`** → 預設 stdout 重定向到 /dev/null
4. **`2>&1`** → stderr 重定向到 stdout
5. **`1>&2`** → stdout 重定向到 stderr

## 測試結果

### ✅ 應該允許的命令（安全的重定向）

| 命令 | 結果 | 說明 |
|------|------|------|
| `ls -la 2>/dev/null` | ✅ 允許 | stderr 重定向 |
| `git status 2>&1` | ✅ 允許 | stderr 合併到 stdout |
| `cat file.txt >/dev/null` | ✅ 允許 | stdout 重定向 |
| `find . -name '*.ts' 2>/dev/null` | ✅ 允許 | 查找命令抑制錯誤 |
| `ls -la /nonexistent 2>/dev/null \|\| echo 'not found'` | ✅ 允許 | 帶錯誤處理 |

### ❌ 應該阻擋的命令（危險的寫入操作）

| 命令 | 結果 | 說明 |
|------|------|------|
| `echo 'test' > file.txt` | ✅ 阻擋 | 寫入檔案 |
| `ls >> output.log` | ✅ 阻擋 | 追加到檔案 |
| `cat file.txt \| tee backup.txt` | ✅ 阻擋 | tee 寫入 |
| `ls -la > /tmp/output.txt` | ✅ 阻擋 | 重定向到非 /dev/null |
| `command 2>> error.log` | ✅ 阻擋 | stderr 追加到檔案 |
| `echo $(cat secrets.txt)` | ✅ 阻擋 | 命令替換 |

## 修改的檔案

- `hooks/scripts/global-workflow-guard.sh` - 新增命令清理邏輯（第 117-127 行）

## 驗證方式

### 快速驗證指令

```bash
# 測試允許的命令
export CLAUDE_SESSION_ID="test-verify"
rm -f "/tmp/claude-agent-state-test-verify"

echo '{"tool_name":"Bash","tool_input":{"command":"ls -la 2>/dev/null"}}' | \
  bash hooks/scripts/global-workflow-guard.sh

# 應該返回 exit code 0（允許）

# 測試阻擋的命令
echo '{"tool_name":"Bash","tool_input":{"command":"echo test > file.txt"}}' | \
  bash hooks/scripts/global-workflow-guard.sh

# 應該返回 JSON 包含 "decision": "block"
```

### Debug 日誌檢查

```bash
tail -f /tmp/claude-workflow-debug.log
```

查看是否包含：
- `Sanitized command: ls -la ` - 成功移除 `2>/dev/null`
- `Bash command allowed (read-only)` - 允許唯讀命令

## 為什麼選擇清理方案？

### 優點
1. **穩健**: 明確列出允許的重定向模式
2. **可維護**: 正則表達式清晰易懂
3. **可擴展**: 未來可輕鬆新增其他安全模式
4. **不影響現有邏輯**: 只在檢查前預處理，不修改核心邏輯

### 替代方案（未採用）
修改 `DANGEROUS_OPERATORS` 正則表達式排除 `/dev/null`：
```bash
# ❌ 未採用：正則表達式過於複雜，難以維護
DANGEROUS_OPERATORS="[^2]>[^/&]|[^2]>>[^/]|\\|.*tee|\\`|\\$\\("
```

**不採用原因**：
- 正則表達式複雜度高，容易出錯
- 負向斷言（negative lookbehind）在某些 grep 版本不支援
- 難以閱讀和維護

## 影響範圍

### 直接影響
- Main Agent 執行唯讀 Bash 命令時不再被誤阻擋
- 提升工作流程的流暢度（減少不必要的 subagent 呼叫）

### 無影響
- Subagent 內的 Bash 命令（本來就允許）
- Write/Edit 工具的黑名單檢查
- 其他 Hook 邏輯

## 後續建議

### 測試覆蓋
- ✅ 手動測試：已完成
- ⏸️ E2E 測試：可加入 E2E 場景驗證

### 文件更新
- ✅ 修復摘要：已建立（本文件）
- 可考慮更新：`hooks/scripts/README.md`（如有）

## 版號更新

完成後需更新 `.claude-plugin/plugin.json`：
- **PATCH 版本**：Bug 修復
- 建議版本：`0.5.3` → `0.5.4`
