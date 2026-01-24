#!/bin/bash
# detect-framework.sh - 自動偵測專案使用的測試框架
# 用法: ./detect-framework.sh [project-path]

PROJECT_PATH="${1:-.}"

detect_framework() {
    local path="$1"

    # JavaScript/TypeScript
    if [ -f "$path/package.json" ]; then
        if grep -q '"jest"' "$path/package.json" 2>/dev/null; then
            echo "jest"
            return
        fi
        if grep -q '"vitest"' "$path/package.json" 2>/dev/null; then
            echo "vitest"
            return
        fi
        if grep -q '"mocha"' "$path/package.json" 2>/dev/null; then
            echo "mocha"
            return
        fi
    fi

    # Python
    if [ -f "$path/pytest.ini" ] || [ -f "$path/pyproject.toml" ]; then
        if grep -q 'pytest' "$path/pyproject.toml" 2>/dev/null; then
            echo "pytest"
            return
        fi
    fi
    if [ -f "$path/setup.py" ] || [ -d "$path/tests" ]; then
        echo "pytest"  # 預設 Python 測試框架
        return
    fi

    # Go
    if [ -f "$path/go.mod" ]; then
        echo "go-test"
        return
    fi

    # Rust
    if [ -f "$path/Cargo.toml" ]; then
        echo "cargo-test"
        return
    fi

    echo "unknown"
}

FRAMEWORK=$(detect_framework "$PROJECT_PATH")

echo "Detected framework: $FRAMEWORK"

# 輸出對應的測試命令
case "$FRAMEWORK" in
    jest)
        echo "Run: npm test"
        echo "Run specific: npm test -- --testPathPattern=\"pattern\""
        echo "Coverage: npm test -- --coverage"
        ;;
    vitest)
        echo "Run: npm test"
        echo "Run specific: npm test -- pattern"
        echo "Coverage: npm test -- --coverage"
        ;;
    pytest)
        echo "Run: pytest"
        echo "Run specific: pytest tests/test_file.py::test_name"
        echo "Coverage: pytest --cov=src"
        ;;
    go-test)
        echo "Run: go test ./..."
        echo "Run specific: go test ./pkg/name"
        echo "Coverage: go test -cover ./..."
        ;;
    cargo-test)
        echo "Run: cargo test"
        echo "Run specific: cargo test test_name"
        echo "Coverage: cargo tarpaulin"
        ;;
    *)
        echo "No test framework detected"
        ;;
esac
