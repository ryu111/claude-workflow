/**
 * [函式描述]
 *
 * @param paramName - [參數描述]
 * @returns [返回值描述]
 * @throws {ErrorType} [何時拋出錯誤]
 *
 * @example
 * ```typescript
 * const result = functionName(param);
 * // result: expectedOutput
 * ```
 */
export function functionName(paramName: ParamType): ReturnType {
  // 1. 輸入驗證
  if (!paramName) {
    throw new ValidationError('paramName is required');
  }

  // 2. 主要邏輯
  // TODO: Implement

  // 3. 返回結果
  return result;
}
