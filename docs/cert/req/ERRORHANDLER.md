# 需求基线 · `Dr.Core.Foundation.ErrorHandler`

> CC1。模块：`src/ReplicatedStorage/Deuterium/Core/Foundation/ErrorHandler.luau`（DAL C，危害＝基础）。
> 依据：`REQ-STD.md` §2/§3 · `HAZARD.md` §4/§5.1。**C3（Step 72）反向补需求**产出。
> 机器锚点：`-- LLR-ERRORHANDLER-nnn` 注解 + `tests/cert/cases/ErrorHandler.luau` 的 `-- covers:`。

---

## HLR

### HLR-ERRORHANDLER-001

- **需求**：一个失败值无论来自我方还是外部，经过本模块后必须能以 `DrError` 形状被消费：`IsDrError` 对 `Normalize` 的返回值恒为真，且 `code` 非空。
- **激励**：`Normalize(err, fallbackCode, source?)` 被调用（`Try` 内部也走它）。
- **响应**：已是 `DrError` 的原值返回；否则返回新建的 `DrError`，其 `code = fallbackCode`、`message = tostring(err)`，原始信息不丢失（在 message 里）。
- **前置条件**：`fallbackCode` 为非空 string（由调用方负责；本函数不校验）。
- **后置条件**：返回值为冻结表；不改动入参。
- **危害追溯**：基础 —— 异构失败无法归一化会让 H5（写入静默失败）被当作正常路径。
- **验证方法**：测试（`TC-ERRORHANDLER-001`、`TC-ERRORHANDLER-004`）+ 评审。
- **可判定性**：`IsDrError(result)` 与字段级断言可判定。

### HLR-ERRORHANDLER-002

- **需求**：任一失败值必须能渲染成**单行、可 grep** 的字符串，且 `DrError` 的渲染结果必须包含其 `code`。
- **激励**：`Render(err)` 被调用（测试程序与日志层用）。
- **响应**：string 原样返回；`DrError` 返回 `` `[{code}] {message} @ {source or "?"}` ``；其它值返回 `tostring(err)`；**任何输入都不得抛错**。
- **前置条件**：无（必须容忍任意输入，包括 `nil`）。
- **后置条件**：返回值不含换行。
- **危害追溯**：基础 —— 失败不可读会拖长故障定位（H1–H7 的处置时长）。
- **验证方法**：测试（`TC-ERRORHANDLER-002`）。
- **可判定性**：返回串包含 `code` 子串、不含 `\n`，可判定。

### HLR-ERRORHANDLER-003

- **需求**：`Try(fn, code, source?)` 必须**不向外抛**：`fn` 抛出的任何值都被捕获并转成 `Result`。
- **激励**：`Try` 被调用，`fn` 内部抛错。
- **响应**：`fn` 正常结束 → `{ ok = true, err = nil }`；抛错 → `{ ok = false, err = DrError }`，且该 `err` 满足 `IsDrError`。
- **前置条件**：无。
- **后置条件**：返回的 `Result` 为冻结表；满足 `HLR-CORETYPES-002` 的组合约束（`ok = true` 时 `err` 必为 `nil`）。
- **危害追溯**：基础 —— 抛穿会让调用方的清理逻辑被跳过。
- **验证方法**：测试（`TC-ERRORHANDLER-003` 正常、`TC-ERRORHANDLER-004` 错误）。
- **可判定性**：`ok`/`err` 断言可判定；「不向外抛」由 `pcall` 包裹调用可判定。

### HLR-ERRORHANDLER-004

- **需求**：本模块的全部导出函数必须在**无引擎**环境下可运行（纯函数、零引擎依赖），以满足 I16。
- **激励**：在 headless 环境 require 本模块并调用全部导出。
- **响应**：require 不触碰 `game`/网络；全部导出可调用并给出上述行为。
- **前置条件**：无。
- **后置条件**：模块的依赖闭包只含 `CoreTypes`（`HAZARD.md` §5.1 的净化结论）。
- **危害追溯**：基础 —— 认证范围触碰引擎会让 I16 失效，并把认证证据绑到不可控环境上。
- **验证方法**：测试（`TC-ERRORHANDLER-005`，门禁 10 的依赖闭包检查）+ 评审。
- **可判定性**：headless 装载成功/失败 + 门禁 10 的违规计数可判定。

---

## LLR

### LLR-ERRORHANDLER-001

- **需求**：`New(code, message, source?)`：断言 `code` 为非空 string、`message` 为非空 string（违反即 `assert` 失败）；返回冻结的 `{ code, message, source }`。
- **实现位置**：`Deuterium/Core/Foundation/ErrorHandler.luau` → `ErrorHandler.New`
- **分支/边界**：两个断言分支（空 `code`、空 `message`）+ 正常路径；`source` 允许 `nil`（`source` 为 nil 时字段仍存在且值为 nil）。
- **验证方法**：测试（`TC-ERRORHANDLER-001` 正常、`TC-ERRORHANDLER-001b` 边界）
- **上级需求**：`HLR-ERRORHANDLER-001`、`HLR-CORETYPES-001`

### LLR-ERRORHANDLER-002

- **需求**：`IsDrError(value)`：当且仅当 `value` 是表、`value.code` 是 string、`value.message` 是 string 时返回 `true`。
- **实现位置**：`Deuterium/Core/Foundation/ErrorHandler.luau` → `ErrorHandler.IsDrError`
- **分支/边界**：非表（`nil`/string/number）、缺 `code`、缺 `message`、两字段类型错 —— 全部必须 `false`；表带额外字段仍为 `true`。
- **验证方法**：测试（`TC-ERRORHANDLER-001b`、`TC-ERRORHANDLER-002`）
- **上级需求**：`HLR-ERRORHANDLER-001`

### LLR-ERRORHANDLER-003

- **需求**：`Normalize(err, fallbackCode, source?)`：`IsDrError(err)` 为真时**原样返回该值**（同一引用）；否则返回 `New(fallbackCode, tostring(err), source)`。
- **实现位置**：`Deuterium/Core/Foundation/ErrorHandler.luau` → `ErrorHandler.Normalize`
- **分支/边界**：两条分支；边界：`err` 为 `nil` 时 `tostring(nil) == "nil"`（非空，满足 `New` 的断言）；`err` 为字符串时原样进 message。
- **验证方法**：测试（`TC-ERRORHANDLER-004`）
- **上级需求**：`HLR-ERRORHANDLER-001`

### LLR-ERRORHANDLER-004

- **需求**：`Render(err)`：string 直通；`DrError` → `` `[{code}] {message} @ {source or "?"}` ``；其它 → `tostring(err)`；三种情况都不抛。
- **实现位置**：`Deuterium/Core/Foundation/ErrorHandler.luau` → `ErrorHandler.Render`
- **分支/边界**：三条分支；边界：`source = nil` 时必须渲染出 `?`；`nil` 输入渲染成 `"nil"`。
- **验证方法**：测试（`TC-ERRORHANDLER-002`）
- **上级需求**：`HLR-ERRORHANDLER-002`

### LLR-ERRORHANDLER-005

- **需求**：`Raise(code, message, source?)`：以 `error(DrError, 2)` 抛出，level 为 2（错误位置指向**调用方**而不是本模块内部）。
- **实现位置**：`Deuterium/Core/Foundation/ErrorHandler.luau` → `ErrorHandler.Raise`
- **分支/边界**：无分支。边界：抛出的值不是字符串而是表（这是刻意的：调用方可用 `IsDrError` 判别）。
- **验证方法**：测试（`TC-ERRORHANDLER-003`）
- **上级需求**：`HLR-ERRORHANDLER-001`

### LLR-ERRORHANDLER-006

- **需求**：`Try(fn, code, source?)`：以 `xpcall` 执行 `fn`，处理器把非 `DrError` 的抛出值经 `Normalize(e, code, source)` 归一；成功 → 冻结的 `{ ok = true, err = nil }`；失败 → 冻结的 `{ ok = false, err = <DrError> }`。
- **实现位置**：`Deuterium/Core/Foundation/ErrorHandler.luau` → `ErrorHandler.Try`
- **分支/边界**：三条分支（成功 / 抛出 `DrError` / 抛出外来值）；边界：`fn` 返回多个值时被丢弃（签名声明 `() -> ()`）；`fn` 抛 `nil` 时 `Normalize` 仍给出合法 `DrError`。
- **验证方法**：测试（`TC-ERRORHANDLER-003`、`TC-ERRORHANDLER-004`）
- **上级需求**：`HLR-ERRORHANDLER-003`、`HLR-CORETYPES-002`

---

未读/未验证：`Raise` 的 `level = 2` 只验证了「抛出的值是 DrError」，**未验证**调用方行号在栈里的实际位置（需要读 `debug.info`，headless 下未做）；`HLR-ERRORHANDLER-004` 的「零引擎依赖」由门禁 10 的闭包检查覆盖，不由本模块测试覆盖。
