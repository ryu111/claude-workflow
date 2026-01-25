#!/bin/bash
# llm-service-manager.sh - LLM Service 自動啟動與狀態管理
# 功能:
#   1. 檢查 LLM Service 狀態
#   2. 檢查 Menu Bar App 是否運行
#   3. 避免重複啟動
#   4. 自動啟動 Menu Bar App（會自動啟動 Service）

# ═══════════════════════════════════════════════════════════════
# 配置
# ═══════════════════════════════════════════════════════════════

LLM_SERVICE_URL="${LOCAL_LLM_SERVICE_URL:-http://127.0.0.1:8765}"

# PROJECT_PATH 優先順序：
# 1. 環境變數 LOCAL_LLM_MCP_PATH
# 2. 配置檔案 ~/.config/local-llm-mcp/path
# 3. 預設路徑 ~/local-llm-mcp
_load_project_path() {
    # 優先使用環境變數
    if [ -n "$LOCAL_LLM_MCP_PATH" ]; then
        echo "$LOCAL_LLM_MCP_PATH"
        return
    fi

    # 其次讀取配置檔案
    local config_file="$HOME/.config/local-llm-mcp/path"
    if [ -f "$config_file" ]; then
        cat "$config_file"
        return
    fi

    # 預設路徑
    echo "$HOME/local-llm-mcp"
}

PROJECT_PATH="$(_load_project_path)"
LOG_DIR="$HOME/.local-llm-mcp"
LOG_FILE="$LOG_DIR/service.log"
APP_LOG_FILE="$LOG_DIR/app.log"
PID_FILE="$LOG_DIR/menubar.pid"

# Menu Bar App 進程識別
# 實際運行時進程名是 "Local LLM MCP"（GUI 應用程式名稱）
MENUBAR_PROCESS_NAME="Local LLM MCP"
MENUBAR_PYTHON_MODULE="local_llm_mcp.menubar_app"

# 超時設定
STARTUP_TIMEOUT=8  # 等待啟動的最大秒數
HEALTH_CHECK_TIMEOUT=2  # 健康檢查超時

# ═══════════════════════════════════════════════════════════════
# 輔助函數
# ═══════════════════════════════════════════════════════════════

# 確保目錄存在
ensure_dirs() {
    mkdir -p "$LOG_DIR"
}

# 檢查 LLM Service 是否運行
check_service_health() {
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$HEALTH_CHECK_TIMEOUT" "${LLM_SERVICE_URL}/health" 2>/dev/null)
    [ "$response" = "200" ]
}

# 檢查模型是否已載入
check_model_loaded() {
    local status
    status=$(curl -s --connect-timeout "$HEALTH_CHECK_TIMEOUT" "${LLM_SERVICE_URL}/status" 2>/dev/null)
    echo "$status" | grep -q '"model_loaded":true'
}

# 檢查 Menu Bar App 是否運行
# 注意：只匹配 "Local LLM MCP" 但不匹配 "Proxy" 或 "Service"
check_menubar_running() {
    # 使用 grep 管道精確匹配
    ps aux 2>/dev/null | grep "$MENUBAR_PROCESS_NAME" | grep -v "Proxy" | grep -v "Service" | grep -v grep > /dev/null 2>&1
}

# 獲取 Menu Bar App PID
get_menubar_pid() {
    ps aux 2>/dev/null | grep "$MENUBAR_PROCESS_NAME" | grep -v "Proxy" | grep -v "Service" | grep -v grep | awk '{print $2}' | head -1
}

# 清理孤兒鎖文件（進程不存在但鎖文件存在）
cleanup_orphan_lock() {
    local lock_file="$LOG_DIR/menubar.lock"

    if [ -f "$lock_file" ] && ! check_menubar_running; then
        # 鎖文件存在但進程不存在 = 孤兒鎖
        rm -f "$lock_file" 2>/dev/null
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 清理孤兒鎖文件" >> "$LOG_FILE"
    fi
}

# 啟動 Menu Bar App
start_menubar_app() {
    # 再次確認沒有運行中的實例
    if check_menubar_running; then
        return 0  # 已經運行
    fi

    # 檢查 PROJECT_PATH 是否存在
    if [ ! -d "$PROJECT_PATH" ]; then
        echo -e "\033[31m❌ Local LLM MCP 路徑不存在: $PROJECT_PATH\033[0m" >&2
        echo -e "\033[90m   設定方式：\033[0m" >&2
        echo -e "\033[90m   1. export LOCAL_LLM_MCP_PATH=\"/path/to/local-llm-mcp\"\033[0m" >&2
        echo -e "\033[90m   2. echo \"/path/to/local-llm-mcp\" > ~/.config/local-llm-mcp/path\033[0m" >&2
        return 1
    fi

    # 清理可能存在的孤兒鎖文件
    cleanup_orphan_lock

    # 使用 nohup 在背景啟動（更可靠的方式）
    cd "$PROJECT_PATH" && \
    PYTHONPATH="${PROJECT_PATH}/src" nohup python3 -m "$MENUBAR_PYTHON_MODULE" >> "$APP_LOG_FILE" 2>&1 &

    # 記錄啟動時間
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Menu Bar App 啟動請求 (PID: $!)" >> "$LOG_FILE"
}

# 等待 Service 啟動
wait_for_service() {
    local max_attempts=$((STARTUP_TIMEOUT * 2))  # 每 0.5 秒檢查一次
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if check_service_health; then
            return 0
        fi
        sleep 0.5
        attempt=$((attempt + 1))
    done

    return 1  # 超時
}

# ═══════════════════════════════════════════════════════════════
# 主要邏輯
# ═══════════════════════════════════════════════════════════════

main() {
    ensure_dirs

    local service_running=false
    local menubar_running=false
    local model_loaded=false

    # 檢查各組件狀態
    check_service_health && service_running=true
    check_menubar_running && menubar_running=true
    [ "$service_running" = true ] && check_model_loaded && model_loaded=true

    # 情況 1: 全部就緒
    if [ "$service_running" = true ] && [ "$menubar_running" = true ] && [ "$model_loaded" = true ]; then
        echo -e "\033[32m📂 LLM Service\033[0m \033[2m→\033[0m 🟢 \033[1m模型已就緒\033[0m"
        return 0
    fi

    # 情況 2: Service 運行，模型未載入，Menu Bar 運行
    if [ "$service_running" = true ] && [ "$menubar_running" = true ]; then
        echo -e "\033[33m📂 LLM Service\033[0m \033[2m→\033[0m 🔴 \033[1m待命中\033[0m \033[90m(點擊 Menu Bar 載入模型)\033[0m"
        return 0
    fi

    # 情況 3: Service 運行但 Menu Bar 未運行 → 啟動 Menu Bar
    if [ "$service_running" = true ] && [ "$menubar_running" = false ]; then
        echo -e "\033[34m📂 LLM Service\033[0m \033[2m→\033[0m 🔄 \033[1m啟動 Menu Bar App...\033[0m \033[90m(Service 已運行)\033[0m"
        start_menubar_app
        sleep 2
        if check_menubar_running; then
            if check_model_loaded; then
                echo -e "\033[32m📂 LLM Service\033[0m \033[2m→\033[0m 🟢 \033[1m模型已就緒\033[0m"
            else
                echo -e "\033[33m📂 LLM Service\033[0m \033[2m→\033[0m 🔴 \033[1m待命中\033[0m \033[90m(點擊 Menu Bar 載入模型)\033[0m"
            fi
        else
            echo -e "\033[33m📂 LLM Service\033[0m \033[2m→\033[0m 🔴 \033[1m待命中\033[0m \033[90m(Menu Bar 啟動失敗，Service 仍可用)\033[0m"
        fi
        return 0
    fi

    # 情況 4: Menu Bar 運行但 Service 未響應
    if [ "$menubar_running" = true ]; then
        echo -e "\033[33m📂 LLM Service\033[0m \033[2m→\033[0m 🟡 \033[1mMenu Bar App 運行中\033[0m \033[90m(Service 啟動中...)\033[0m"
        if wait_for_service; then
            echo -e "\033[32m📂 LLM Service\033[0m \033[2m→\033[0m 🔴 \033[1m已啟動\033[0m \033[90m(模型待載入)\033[0m"
        fi
        return 0
    fi

    # 情況 5: 都未運行，啟動 Menu Bar App
    echo -e "\033[34m📂 LLM Service\033[0m \033[2m→\033[0m 🔄 \033[1m啟動 Menu Bar App...\033[0m"

    start_menubar_app

    # 等待 Service 啟動
    if wait_for_service; then
        echo -e "\033[32m📂 LLM Service\033[0m \033[2m→\033[0m 🔴 \033[1m已啟動\033[0m \033[90m(Menu Bar 已就緒，模型待載入)\033[0m"
        return 0
    fi

    # 超時後再次檢查狀態
    if check_menubar_running; then
        echo -e "\033[33m📂 LLM Service\033[0m \033[2m→\033[0m 🟡 \033[1mMenu Bar App 已啟動\033[0m \033[90m(請從 Menu Bar 啟動 Service)\033[0m"
    else
        echo -e "\033[31m📂 LLM Service\033[0m \033[2m→\033[0m ❌ \033[1m啟動失敗\033[0m \033[90m(查看 $APP_LOG_FILE)\033[0m"
        return 1
    fi

    return 0
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面
# ═══════════════════════════════════════════════════════════════

case "${1:-status}" in
    status)
        main
        ;;
    start)
        if check_menubar_running; then
            echo "Menu Bar App 已在運行中"
        else
            start_menubar_app
            echo "Menu Bar App 啟動請求已發送"
        fi
        ;;
    stop)
        pid=$(get_menubar_pid)
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null
            echo "Menu Bar App 已停止 (PID: $pid)"
        else
            echo "Menu Bar App 未運行"
        fi
        ;;
    restart)
        pid=$(get_menubar_pid)
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null
            sleep 1
        fi
        start_menubar_app
        echo "Menu Bar App 重啟請求已發送"
        ;;
    warmup)
        if check_service_health; then
            echo "正在載入模型..."
            curl -s -X POST "${LLM_SERVICE_URL}/warmup"
            echo ""
        else
            echo "LLM Service 未運行，請先啟動"
            exit 1
        fi
        ;;
    *)
        echo "用法: $0 {status|start|stop|restart|warmup}"
        exit 1
        ;;
esac
