---
description: 載入 Local LLM 模型（從 🔴 紅燈變成 🟢 綠燈）
user-invocable: true
allowed-tools:
  - Bash
---

# LLM Model Warmup

載入 Local LLM 模型到記憶體。

## 執行步驟

使用 LLM Service Manager 執行 warmup：

```bash
# 檢查狀態
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/llm-service-manager.sh" status

# 執行 warmup（載入模型）
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/llm-service-manager.sh" warmup
```

## 可用指令

| 指令 | 說明 |
|------|------|
| `status` | 檢查 LLM Service 狀態 |
| `start` | 啟動 Menu Bar App |
| `stop` | 停止 Menu Bar App |
| `restart` | 重啟 Menu Bar App |
| `warmup` | 載入模型到記憶體 |

## 狀態說明

| 狀態 | 圖示 | 說明 |
|------|:----:|------|
| 模型已就緒 | 🟢 | 可直接使用 |
| 待命中 | 🔴 | Service 運行但模型未載入 |
| 啟動中 | 🟡 | Menu Bar App 運行，Service 啟動中 |
| 啟動失敗 | ❌ | 需檢查日誌 |

## 注意事項

- 模型約 25GB，載入需要數秒
- 載入後會佔用約 25GB RAM
- 載入完成後狀態變為 🟢 綠燈
- 若服務未啟動，SessionStart 會自動啟動 Menu Bar App
- 日誌位置：`~/.local-llm-mcp/app.log`
