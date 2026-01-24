# 禁止硬編碼規則

## TypeScript/JavaScript

```typescript
// ❌ 禁止
if (status === "pending") { ... }
const result = { status: "pending", code: 200 };

// ✅ 正確
enum Status { PENDING = "pending", APPROVED = "approved" }
const HttpCode = { OK: 200, NOT_FOUND: 404 } as const;

if (status === Status.PENDING) { ... }
const result = { status: Status.PENDING, code: HttpCode.OK };
```

## Python

```python
# ❌ 禁止
if status == "pending":
    ...

# ✅ 正確
from enum import Enum

class Status(Enum):
    PENDING = "pending"
    APPROVED = "approved"

if status == Status.PENDING:
    ...
```

## Go

```go
// ❌ 禁止
if status == "pending" { ... }

// ✅ 正確
const (
    StatusPending  = "pending"
    StatusApproved = "approved"
)

if status == StatusPending { ... }
```

## Rust

```rust
// ❌ 禁止
if status == "pending" { ... }

// ✅ 正確
enum Status {
    Pending,
    Approved,
}

if status == Status::Pending { ... }
```

## 例外情況

以下情況可以接受字串字面值：
- 日誌訊息（純顯示用途）
- 測試中的測試資料
- 一次性腳本

但業務邏輯中的狀態、錯誤碼、配置值必須使用常數定義。
