# 原子性寫入工具遷移指南

## 概述

`lib/atomic-write.sh` 提供通用的原子性檔案寫入功能，整合自 `workflow-gate.sh` 和 `subagent-validator.sh` 的 `atomic_write_state()` 函式。

## 核心功能

| 功能 | 說明 | 選項 |
|------|------|------|
| 原子性寫入 | 使用 tmp + mv 模式確保原子性 | 預設啟用 |
| 自動備份 | 寫入前備份現有檔案 | `-b, --backup` |
| 內容驗證 | 寫入後 sha256 驗證 | `-v, --verify` |
| 權限設定 | 強制檔案權限 | `-p, --permission` (預設 600) |
| 檔案鎖定 | flock 鎖定測試 | `-l, --lock` |

## 快速開始

### 1. 載入函式庫

```bash
#!/bin/bash
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/lib/atomic-write.sh"
```

### 2. 基本使用

```bash
# 簡單寫入
atomic_write "/path/to/file.json" "$json_content"

# 高可靠性寫入（建議用於關鍵狀態檔案）
atomic_write -b -v "/path/to/state.json" "$state_content"
```

## 現有腳本遷移

### workflow-gate.sh（第 287 行）

**原始程式碼：**
```bash
atomic_write_state() {
    local content="$1"
    local target_file="$2"
    local temp_file="${target_file}.tmp.$$"

    echo "$content" > "$temp_file"
    mv "$temp_file" "$target_file"

    if command -v flock &> /dev/null; then
        flock -x "$target_file" -c "cat $target_file > /dev/null"
    fi
}
```

**遷移後：**
```bash
# 載入函式庫
source "${SCRIPT_DIR}/lib/atomic-write.sh"

# 替換所有 atomic_write_state 呼叫
# 原本: atomic_write_state "$content" "$STATE_FILE"
# 改為: atomic_write -l "$STATE_FILE" "$content"
```

**參數順序變更：**
- 舊版：`atomic_write_state "$content" "$file"`
- 新版：`atomic_write "$file" "$content"`

### subagent-validator.sh（第 158 行）

**原始程式碼：**
```bash
atomic_write_state() {
    local content="$1"
    local target_file="$2"
    local temp_file="${target_file}.tmp.$$"

    echo "$content" > "$temp_file"
    mv "$temp_file" "$target_file"

    if command -v flock &> /dev/null; then
        flock -x "$target_file" -c "cat $target_file > /dev/null"
    fi
}
```

**遷移後：**
```bash
# 載入函式庫
source "${SCRIPT_DIR}/lib/atomic-write.sh"

# 替換所有 atomic_write_state 呼叫
# 原本: atomic_write_state "$new_state" "$STATE_FILE"
# 改為: atomic_write -b -v "$STATE_FILE" "$new_state"
```

**建議選項：**
- `-b`: 備份舊狀態（方便除錯）
- `-v`: 驗證寫入正確性

## 遷移檢查清單

### 步驟 1：更新檔案頭部

```bash
# 在 set -euo pipefail 之後加入
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/lib/atomic-write.sh"
```

### 步驟 2：移除舊函式定義

刪除腳本內的 `atomic_write_state()` 函式定義。

### 步驟 3：更新所有呼叫

使用搜尋替換（注意參數順序）：

```bash
# 搜尋模式
atomic_write_state "\$([^"]+)" "\$([^"]+)"

# 替換為
atomic_write -l "\$\2" "\$\1"
```

**重要提醒：**
- 新版函式參數順序為：`file_path content`
- 舊版函式參數順序為：`content file_path`
- 務必調換順序！

### 步驟 4：選擇適當選項

根據使用場景選擇：

| 場景 | 建議選項 | 原因 |
|------|----------|------|
| DRT 狀態檔案 | `-b -v` | 可備份 + 驗證正確性 |
| 臨時檔案 | 無 | 不需額外保護 |
| 關鍵配置 | `-b -v -p 600` | 完整保護 |
| 高頻寫入 | `-l` | 僅鎖定，避免開銷 |

### 步驟 5：測試驗證

```bash
# 執行腳本並檢查
bash hooks/scripts/workflow-gate.sh

# 驗證狀態檔案正確寫入
cat .drt-state/.drt-workflow-state
```

## 錯誤處理

### 返回碼

| 碼 | 意義 | 處理方式 |
|----|------|----------|
| 0 | 成功 | 繼續執行 |
| 1 | 寫入失敗 | 檢查權限/路徑 |
| 2 | 驗證失敗 | 重試或報錯 |
| 3 | 鎖定失敗 | 等待後重試 |

### 範例

```bash
if atomic_write -b -v "$STATE_FILE" "$state_content"; then
    echo "✅ 狀態已儲存"
else
    case $? in
        1) echo "❌ 寫入失敗" ;;
        2) echo "❌ 驗證失敗" ;;
        3) echo "❌ 鎖定失敗" ;;
    esac
    exit 1
fi
```

## 遷移時程建議

### 階段 1：新腳本優先（立即）

所有新建立的腳本直接使用 `lib/atomic-write.sh`。

### 階段 2：高優先級腳本（本週）

遷移以下關鍵腳本：
- `workflow-gate.sh` - 核心流程控制
- `subagent-validator.sh` - Agent 驗證
- `drt-state-cleanup.sh` - 狀態管理

### 階段 3：其他腳本（下週）

遷移其他使用 `atomic_write_state` 的腳本。

### 階段 4：驗證與清理（完成後）

1. 搜尋確認無殘留舊函式：`grep -r "atomic_write_state()" hooks/scripts/`
2. 執行完整測試套件
3. 更新相關文件

## 優勢

### 相較於舊實作

| 項目 | 舊實作 | 新實作 |
|------|--------|--------|
| 功能 | 僅原子寫入 + 鎖定 | 原子寫入 + 備份 + 驗證 + 鎖定 |
| 可設定性 | 無 | 選項式設定 |
| 錯誤處理 | 基本 | 詳細錯誤碼 |
| 維護性 | 分散在各腳本 | 集中在 lib/ |
| 測試覆蓋 | 無 | 10 個單元測試 |

### 未來擴展

- 支援重試機制
- 支援壓縮備份
- 支援備份輪換
- 支援異步寫入

## 疑難排解

### Q: 為什麼我的腳本找不到 atomic_write？

A: 確認已正確載入函式庫：
```bash
source "${SCRIPT_DIR}/lib/atomic-write.sh"
```

### Q: 為什麼驗證總是失敗？

A: 檢查內容中是否有特殊字元需要跳脫，或使用 `cat <<EOF` 語法：
```bash
content=$(cat <<EOF
{
  "key": "value"
}
EOF
)
atomic_write -v "$file" "$content"
```

### Q: macOS 上沒有 flock 怎麼辦？

A: 安裝 GNU coreutils：
```bash
brew install coreutils
```

或者不使用 `-l` 選項（鎖定功能是可選的）。

## 參考資源

- 測試腳本：`tests/scripts/test-lib-atomic-write.sh`
- 使用範例：`hooks/scripts/lib/atomic-write-example.sh`
- 原始碼：`hooks/scripts/lib/atomic-write.sh`
