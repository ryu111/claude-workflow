# 功能實作範例

## 場景

實作一個「商品收藏」功能，允許用戶收藏喜歡的商品。

## OpenSpec 規格

```markdown
## Task 2.3 - 實作收藏功能

**Agent**: DEVELOPER
**Files**: src/services/favorite.ts, src/models/favorite.ts
**依賴**: Task 2.1 (UserService), Task 2.2 (ProductService)

### 功能需求
- 用戶可以收藏商品
- 用戶可以取消收藏
- 用戶可以查看收藏清單
- 同一商品不能重複收藏

### 技術要求
- 使用 Repository 模式
- 實作適當的錯誤處理
- 遵循專案命名規範
```

---

## 實作過程

### Step 1: 定義資料模型

```typescript
// src/models/favorite.ts

export interface Favorite {
  id: string;
  userId: string;
  productId: string;
  createdAt: Date;
}

export interface CreateFavoriteInput {
  userId: string;
  productId: string;
}
```

**設計決策**:
- 使用簡單的複合關係表
- `createdAt` 用於排序收藏清單
- 不需要 `updatedAt`，因為收藏沒有更新邏輯

---

### Step 2: 定義 Repository 介面

```typescript
// src/repositories/favorite.repository.ts

import { Favorite, CreateFavoriteInput } from '../models/favorite';

export interface FavoriteRepository {
  create(input: CreateFavoriteInput): Promise<Favorite>;
  delete(userId: string, productId: string): Promise<void>;
  findByUserId(userId: string): Promise<Favorite[]>;
  findByUserAndProduct(userId: string, productId: string): Promise<Favorite | null>;
}
```

**設計決策**:
- 介面優於實作，方便測試時 mock
- `findByUserAndProduct` 用於檢查是否已收藏

---

### Step 3: 實作 Service

```typescript
// src/services/favorite.ts

import { FavoriteRepository } from '../repositories/favorite.repository';
import { ProductService } from './product';
import { Favorite } from '../models/favorite';

export class FavoriteService {
  constructor(
    private readonly favoriteRepo: FavoriteRepository,
    private readonly productService: ProductService
  ) {}

  /**
   * 收藏商品
   * @throws {Error} 商品不存在
   * @throws {Error} 已經收藏過
   */
  async addFavorite(userId: string, productId: string): Promise<Favorite> {
    // 1. 驗證商品存在
    const product = await this.productService.getById(productId);
    if (!product) {
      throw new Error('Product not found');
    }

    // 2. 檢查是否已收藏
    const existing = await this.favoriteRepo.findByUserAndProduct(userId, productId);
    if (existing) {
      throw new Error('Product already favorited');
    }

    // 3. 建立收藏
    return this.favoriteRepo.create({ userId, productId });
  }

  /**
   * 取消收藏
   * @throws {Error} 收藏不存在
   */
  async removeFavorite(userId: string, productId: string): Promise<void> {
    // 檢查收藏是否存在
    const existing = await this.favoriteRepo.findByUserAndProduct(userId, productId);
    if (!existing) {
      throw new Error('Favorite not found');
    }

    await this.favoriteRepo.delete(userId, productId);
  }

  /**
   * 取得用戶的收藏清單
   */
  async getFavorites(userId: string): Promise<Favorite[]> {
    return this.favoriteRepo.findByUserId(userId);
  }

  /**
   * 檢查商品是否已被收藏
   */
  async isFavorited(userId: string, productId: string): Promise<boolean> {
    const existing = await this.favoriteRepo.findByUserAndProduct(userId, productId);
    return existing !== null;
  }
}
```

---

### Step 4: 實作 Repository（Prisma 範例）

```typescript
// src/repositories/prisma/favorite.prisma.repository.ts

import { PrismaClient } from '@prisma/client';
import { FavoriteRepository } from '../favorite.repository';
import { Favorite, CreateFavoriteInput } from '../../models/favorite';

export class PrismaFavoriteRepository implements FavoriteRepository {
  constructor(private readonly prisma: PrismaClient) {}

  async create(input: CreateFavoriteInput): Promise<Favorite> {
    return this.prisma.favorite.create({
      data: {
        userId: input.userId,
        productId: input.productId,
      },
    });
  }

  async delete(userId: string, productId: string): Promise<void> {
    await this.prisma.favorite.delete({
      where: {
        userId_productId: { userId, productId },
      },
    });
  }

  async findByUserId(userId: string): Promise<Favorite[]> {
    return this.prisma.favorite.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findByUserAndProduct(
    userId: string,
    productId: string
  ): Promise<Favorite | null> {
    return this.prisma.favorite.findUnique({
      where: {
        userId_productId: { userId, productId },
      },
    });
  }
}
```

---

## 程式碼品質檢查

### ✅ 命名規則
- 類別名稱：大駝峰 (`FavoriteService`)
- 方法名稱：動詞開頭 (`addFavorite`, `removeFavorite`)
- 變數名稱：描述用途 (`existing`, `product`)

### ✅ 函式設計
- 單一職責：每個方法只做一件事
- 提早返回：錯誤情況優先處理
- 適當長度：沒有過長的方法

### ✅ 錯誤處理
- 所有可能失敗的操作都有錯誤處理
- 錯誤訊息具描述性

### ✅ 依賴注入
- 依賴通過 constructor 注入
- 使用介面而非具體實作

---

## 輸出摘要

```markdown
## 💻 DEVELOPER 完成報告

### 完成項目
- ✅ 建立 Favorite 資料模型
- ✅ 定義 FavoriteRepository 介面
- ✅ 實作 FavoriteService（含 4 個方法）
- ✅ 實作 PrismaFavoriteRepository

### 新增/修改檔案
- `src/models/favorite.ts` (新增)
- `src/repositories/favorite.repository.ts` (新增)
- `src/services/favorite.ts` (新增)
- `src/repositories/prisma/favorite.prisma.repository.ts` (新增)

### 測試建議
1. 收藏成功的情況
2. 收藏不存在的商品
3. 重複收藏同一商品
4. 取消不存在的收藏
5. 空的收藏清單

### 下一步
→ REVIEWER 審查
```
