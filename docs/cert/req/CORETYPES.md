# 需求基线 · `Dr.Core.Foundation.CoreTypes`

> CC1。模块：`src/ReplicatedStorage/Deuterium/Core/Foundation/CoreTypes.luau`（DAL C，危害＝基础）。
> 依据：`REQ-STD.md` §2/§3 模板 · `HAZARD.md` §4（Dr 纯底座，危害列＝`基础`）。
> 本文件由 **C3（Step 72）反向补需求**产出：代码先存在（约 5k 行历史），需求在此追认。
> 机器锚点：源码里 `-- LLR-CORETYPES-nnn` 注解 + `tests/cert/cases/CoreTypes.luau` 的 `-- covers:`。

---

## HLR

### HLR-CORETYPES-001

- **需求**：任一 Deuterium 模块发生跨模块失败时，暴露给外部的失败值必须满足 `DrError` 形状：`code` 为非空 string、`message` 为非空 string、`source` 为 string 或 nil。
- **激励**：框架内任一模块向上层返回失败。
- **响应**：失败值可通过 `code` 稳定匹配（同一失败原因在任意运行中给出同一 `code`）。
- **前置条件**：无（本需求约束的是形状本身，不约束产生者）。
- **后置条件**：该形状在 1.x 生命周期内不变；变更属 CC1。
- **危害追溯**：基础（`HAZARD.md` §4 的 Dr 纯底座行）—— 错误形状是 H1–H7 全部检测机制的前提：形状不成立则危害无法被识别。
- **验证方法**：测试（`TC-CORETYPES-001`、`TC-CORETYPES-003`）+ 评审。
- **可判定性**：`code`/`message`/`source` 的 `typeof` 与 `#code > 0` 断言可逐条判定。

### HLR-CORETYPES-002

- **需求**：`Result` 形状必须能无损表达「成功」与「失败」两种结局：成功的 `ok` 为 `true` 且 `err` 为 `nil`；失败的 `ok` 为 `false` 且 `err` 为一个 `DrError`。
- **激励**：调用方使用不抛异常的错误处理（`ErrorHandler.Try` 等）。
- **响应**：调用方仅凭 `ok` 即可分支，仅凭 `err` 即可取得 `code`，无需再判空。
- **前置条件**：`Result` 由本框架的模块产生。
- **后置条件**：不出现 `ok = true` 且 `err ~= nil` 的组合。
- **危害追溯**：基础 —— 失败若无 `err`，则 H5（静默失败）不可检测。
- **验证方法**：测试（`TC-CORETYPES-002`、`TC-CORETYPES-003`）+ 评审。
- **可判定性**：`ok` 与 `err` 的布尔/形状断言可判定。

---

## LLR

### LLR-CORETYPES-001

- **需求**：`DrError` 定义为 `{ code: string, message: string, source: string? }`；三个字段均存在于类型声明，`source` 允许 `nil`。
- **实现位置**：`Deuterium/Core/Foundation/CoreTypes.luau` → `export type DrError`
- **分支/边界**：无分支（类型声明）。边界：`source` 可为 `nil`，`code`/`message` 不得为空串 —— 空串约束由产生侧（`ErrorHandler.New`）执行，见 `LLR-ERRORHANDLER-001`。
- **验证方法**：测试（`TC-CORETYPES-001`）
- **上级需求**：`HLR-CORETYPES-001`

### LLR-CORETYPES-002

- **需求**：`Result` 定义为 `{ ok: boolean, err: DrError? }`；`err` 为可选字段，不出现 `ok = true` 且 `err ~= nil` 的实例。
- **实现位置**：`Deuterium/Core/Foundation/CoreTypes.luau` → `export type Result`
- **分支/边界**：无分支（类型声明）。边界：`ok = true` 时 `err` 必须为 `nil` —— 该不变式由构造侧执行（`ErrorHandler.Try`，见 `LLR-ERRORHANDLER-006`）。
- **验证方法**：测试（`TC-CORETYPES-002`、`TC-CORETYPES-003`）
- **上级需求**：`HLR-CORETYPES-002`

---

未读/未验证：本模块的 `return table.freeze({})` 是空表（纯类型模块），**没有可执行语句**，因此「代码 → 需求」方向对它只有类型声明可查；`TRACE.md` 生成器按此实现。
