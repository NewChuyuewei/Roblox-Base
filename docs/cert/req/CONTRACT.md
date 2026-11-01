# 需求基线 · `Dr.Core.Foundation.Contract`

> CC1。模块：`src/ReplicatedStorage/Deuterium/Core/Foundation/Contract.luau`（DAL C，危害＝基础）。
> 依据：`REQ-STD.md` §2/§3 · `HAZARD.md` §4。**C3（Step 72）反向补需求**产出。
> 机器锚点：`-- LLR-CONTRACT-nnn` 注解 + `tests/cert/cases/Contract.luau` 的 `-- covers:`。

---

## HLR

### HLR-CONTRACT-001

- **需求**：当调用点声明的契约条件不成立时，框架必须以一个结构化错误**终止**该调用，不得继续执行到未定义状态。
- **激励**：`Contract.Precondition` / `Contract.Invariant` / `Contract.IsA` 在条件为假时被调用。
- **响应**：抛出 `DrError`（经 `ErrorHandler.Raise`），其 `code` 非空；控制流不返回调用点。
- **前置条件**：无。
- **后置条件**：条件为真时不产生任何副作用（不改状态、不抛错、返回值）。
- **危害追溯**：基础 —— 契约不拦会造成「继续跑在坏状态上」，是 H1–H7 的**共同成因**。
- **验证方法**：测试（`TC-CONTRACT-001`、`TC-CONTRACT-003`）+ 评审。
- **可判定性**：`pcall` 是否失败 + `code` 的前缀断言可判定。

### HLR-CONTRACT-002

- **需求**：契约错误的 `code` 必须能区分**调用方违反前置条件**与**我方不变量被破坏**两类责任方。
- **激励**：任一契约失败。
- **响应**：前置条件失败的 `code` 以 `DR.CONTRACT.PRECONDITION.` 开头；不变量失败以 `DR.CONTRACT.INVARIANT.` 开头；形状断言失败以 `DR.CONTRACT.TYPE.` 开头。
- **前置条件**：无。
- **后置条件**：前缀集合在 1.x 内不变（变更属 CC1）。
- **危害追溯**：基础 —— 责任方不可辨会把排查引向错误方向，掩盖真实成因。
- **验证方法**：测试（`TC-CONTRACT-001`、`TC-CONTRACT-002`）。
- **可判定性**：`string.sub(code, 1, n)` 相等断言可判定。

### HLR-CONTRACT-003

- **需求**：`Contract.IsA` 的形状断言必须在**有引擎**与 **headless** 两种环境下给出同一判定：`"Instance"` 这一伪类名对引擎实例成立，对其它类型不成立。
- **激励**：`Contract.IsA(value, "Instance", ...)`。
- **响应**：value 为引擎实例（或 headless 下带 `ClassName` 的表 / `userdata`）时通过；否则抛 `DR.CONTRACT.TYPE.` 错误，消息里同时给出期望与实际种类。
- **前置条件**：`kind` 为调用方给定的种类名，其解析规则来自 `typeof`（非 `type`）。
- **后置条件**：不做隐式转换；不修改 value。
- **危害追溯**：基础 —— 判定在两种环境下不一致会让 headless 测试**假绿**（R28）。
- **验证方法**：测试（`TC-CONTRACT-003`、`TC-CONTRACT-004`）。
- **可判定性**：通过/抛错的二值结果 + 消息中的 `expected/got` 子串可判定。

---

## LLR

### LLR-CONTRACT-001

- **需求**：`Precondition(cond, code, message)`：`cond` 为 `true` 时立即返回且无副作用；为 `false` 时抛 `DrError`，其 `code = "DR.CONTRACT.PRECONDITION." .. code`，`message` 原样透传。
- **实现位置**：`Deuterium/Core/Foundation/Contract.luau` → `Contract.Precondition`
- **分支/边界**：两个分支（真/假）都必须有测试；`code` 为空串时前缀仍然成立（不做额外校验）。
- **验证方法**：测试（`TC-CONTRACT-001` 正常、`TC-CONTRACT-002` 错误）
- **上级需求**：`HLR-CONTRACT-001`、`HLR-CONTRACT-002`

### LLR-CONTRACT-002

- **需求**：`Invariant(cond, code, message)`：与 `Precondition` 同构，但 `code = "DR.CONTRACT.INVARIANT." .. code`。
- **实现位置**：`Deuterium/Core/Foundation/Contract.luau` → `Contract.Invariant`
- **分支/边界**：同 `LLR-CONTRACT-001`；关键边界是**前缀必须不同**（否则 `HLR-CONTRACT-002` 失效）。
- **验证方法**：测试（`TC-CONTRACT-002`）
- **上级需求**：`HLR-CONTRACT-001`、`HLR-CONTRACT-002`

### LLR-CONTRACT-003

- **需求**：`IsA(value, kind, code, message?)`：取 `actualKind = typeof(value)`；当 `kind == "Instance"` 时，若 `typeof(value) ~= "nil"` 且（`type(value) == "userdata"` 或 value 是带 `ClassName` 的表）则 `actualKind = "Instance"`；最后若 `actualKind ~= kind` 则抛 `code = "DR.CONTRACT.TYPE." .. code`、消息为 `(message or "type mismatch") .. " (expected {kind}, got {actualKind})"`。
- **实现位置**：`Deuterium/Core/Foundation/Contract.luau` → `Contract.IsA`
- **分支/边界**：四条分支：①`kind ~= "Instance"` 直接比较；②`nil` 必须**不**被判成 Instance（`typeof(nil) == "nil"`）；③`userdata` 在 headless 下无 `ClassName` 也算 Instance（桩保真度所致，见 R28）；④表带 `ClassName` 算 Instance。
- **验证方法**：测试（`TC-CONTRACT-003` 正常/边界、`TC-CONTRACT-004` 错误）
- **上级需求**：`HLR-CONTRACT-003`

---

未读/未验证：`Contract.IsA` 对**真实引擎实例**的判定只在 Studio 桩下验证过（`typeof` 桩返回 `"Instance"` 系），未在真引擎里跑；`HLR-CONTRACT-002` 的「前缀集合不变」由评审保证，机器只检查存在性。
