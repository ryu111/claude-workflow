/**
 * [Service 描述]
 *
 * @example
 * ```typescript
 * const service = new ServiceName(dependencies);
 * const result = await service.method(params);
 * ```
 */
export class ServiceName {
  constructor(
    private readonly dependency1: Dependency1Type,
    private readonly dependency2: Dependency2Type
  ) {}

  /**
   * [方法描述]
   */
  async methodName(params: ParamsType): Promise<ResultType> {
    // 1. 輸入驗證
    this.validateParams(params);

    // 2. 執行業務邏輯
    try {
      const result = await this.executeLogic(params);
      return result;
    } catch (error) {
      // 3. 錯誤處理
      if (error instanceof KnownError) {
        throw new ServiceError(error.message);
      }
      throw error;
    }
  }

  private validateParams(params: ParamsType): void {
    // 驗證邏輯
  }

  private async executeLogic(params: ParamsType): Promise<ResultType> {
    // 核心邏輯
  }
}
