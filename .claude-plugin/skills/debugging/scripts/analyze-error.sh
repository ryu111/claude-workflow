#!/bin/bash
# analyze-error.sh - 分析錯誤訊息並提供診斷建議
# 用法: ./analyze-error.sh "error message"

ERROR_MSG="$1"

echo "🔍 Analyzing error..."
echo "---"

# 常見錯誤模式識別
analyze_error() {
    local msg="$1"

    # JavaScript/TypeScript 錯誤
    if echo "$msg" | grep -qi "undefined is not a function"; then
        echo "💡 診斷: 呼叫了不存在的方法"
        echo "可能原因:"
        echo "  1. 物件為 undefined 或 null"
        echo "  2. 方法名稱拼寫錯誤"
        echo "  3. 方法尚未定義"
        echo "建議: 檢查物件是否正確初始化"
    elif echo "$msg" | grep -qi "Cannot read property.*of null\|Cannot read property.*of undefined"; then
        echo "💡 診斷: 存取 null/undefined 的屬性"
        echo "可能原因:"
        echo "  1. 物件未初始化"
        echo "  2. 非同步操作未完成就存取"
        echo "  3. API 返回 null"
        echo "建議: 使用可選鏈 (?.) 或空值合併 (??)"
    elif echo "$msg" | grep -qi "Maximum call stack exceeded"; then
        echo "💡 診斷: 無限遞迴"
        echo "可能原因:"
        echo "  1. 遞迴沒有終止條件"
        echo "  2. 終止條件永遠不會滿足"
        echo "建議: 檢查遞迴函式的終止條件"

    # 網路錯誤
    elif echo "$msg" | grep -qi "ECONNREFUSED"; then
        echo "💡 診斷: 連線被拒絕"
        echo "可能原因:"
        echo "  1. 服務未啟動"
        echo "  2. 端口號錯誤"
        echo "  3. 防火牆阻擋"
        echo "建議: 確認目標服務正在運行"
    elif echo "$msg" | grep -qi "ETIMEDOUT"; then
        echo "💡 診斷: 連線超時"
        echo "可能原因:"
        echo "  1. 網路問題"
        echo "  2. 服務回應過慢"
        echo "  3. 超時設定太短"
        echo "建議: 檢查網路連線和服務狀態"

    # 檔案錯誤
    elif echo "$msg" | grep -qi "ENOENT"; then
        echo "💡 診斷: 檔案或目錄不存在"
        echo "可能原因:"
        echo "  1. 路徑錯誤"
        echo "  2. 檔案尚未建立"
        echo "  3. 權限問題"
        echo "建議: 檢查檔案路徑是否正確"
    elif echo "$msg" | grep -qi "EACCES\|Permission denied"; then
        echo "💡 診斷: 權限不足"
        echo "可能原因:"
        echo "  1. 檔案/目錄權限設定"
        echo "  2. 使用者權限不足"
        echo "建議: 檢查檔案權限 (ls -la)"

    # Python 錯誤
    elif echo "$msg" | grep -qi "ImportError\|ModuleNotFoundError"; then
        echo "💡 診斷: 模組匯入錯誤"
        echo "可能原因:"
        echo "  1. 套件未安裝"
        echo "  2. 虛擬環境未啟用"
        echo "  3. 路徑設定錯誤"
        echo "建議: pip install <package> 或檢查 PYTHONPATH"
    elif echo "$msg" | grep -qi "TypeError.*NoneType"; then
        echo "💡 診斷: 對 None 進行不支援的操作"
        echo "可能原因:"
        echo "  1. 函式返回 None"
        echo "  2. 變數未正確賦值"
        echo "建議: 加入 None 檢查"

    else
        echo "💡 無法自動診斷此錯誤"
        echo "建議:"
        echo "  1. 搜尋完整錯誤訊息"
        echo "  2. 檢查堆疊追蹤的起始點"
        echo "  3. 使用除錯器逐步執行"
    fi
}

analyze_error "$ERROR_MSG"

echo "---"
echo "📚 更多資源:"
echo "  - Stack Overflow: https://stackoverflow.com/search?q=$(echo "$ERROR_MSG" | head -c 100 | sed 's/ /+/g')"
