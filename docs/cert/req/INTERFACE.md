# 需求基线 · `Dr.Types.Contract.Interface`

> CC1。模块：`src/ReplicatedStorage/Deuterium/Types/Contract/Interface.luau`（DAL C，危害＝基础）。
> 依据：`REQ-STD.md` §2/§3 · `HAZARD.md` §4。**C3（Step 72）反向补需求**产出。
> 机器锚点：`-- LLR-INTERFACE-nnn` 注解 + `tests/cert/cases/Interface.luau` 的 `-- covers:`。

---

## HLR

### HLR-INTERFACE-001

- **需求**：边界处（provider 注册、配置加载、适配器入口）的结构契约必须可断言：调用方给出 `{ 字段名 = 期望种类 }` 的 spec，`Conform` 在 `value` 的对应字段种类不符时以结构化错误拒绝。
- **激励**：`Conform(label, value, spec)` 被调用。
- **响应**：spec 中**每一个**列出的字段都满足 `typeof(value[field]) == expectedKind` 时返回 `true`；否则抛 `DrError`（`code = "DR.CONTRACT.INTERFACE.FIELD"`），消息含 `label.field` 与期望/实际种类。
- **前置条件**：`label` 为非空 string；`value` 为 table。
- **后置条件**：不修改 `value`；不新增字段。
- **危害追溯**：基础 —— 边界不设防会让错误形状的数据进入内核（H1/H6 的上游成因）。
- **验证方法**：测试（`TC-INTERFACE-001` 正常、`TC-INTERFACE-002` 边界、`TC-INTERFACE-003` 错误）+ 评审。
- **可判定性**：返回 `true` / 抛错 + 消息子串可判定。

---

## LLR

### LLR-INTERFACE-001

- **需求**：`Conform(label, value, spec)`：断言 `label` 为非空 string；断言 `value` 是 table（否则抛 `` `[Dr.Interface] {label}: value must be a table` ``）；遍历 `spec`，对每个键做 `typeof(value[field]) ~= expectedKind` 判定，不符即经 `ErrorHandler.Raise("DR.CONTRACT.INTERFACE.FIELD", "{label}.{field} expected {expectedKind}, got {actualKind}", label)` 抛出；全部通过返回 `true`。
- **实现位置**：`Deuterium/Types/Contract/Interface.luau` → `Interface.Conform`
- **分支/边界**：四条分支：①`label` 为空 → assert 失败；②`value` 非表 → assert 失败；③某字段种类不符 → 抛 `DrError`；④全部相符 → `true`。边界：**空 spec 恒真**；**spec 未列出的字段一律不检查**（多余字段不拒——这是已断言的已知行为，勿当成漏检）；字段缺失时 `typeof(nil) == "nil"`，所以 spec 写 `"nil"` 即通过。
- **验证方法**：测试（`TC-INTERFACE-001` 正常、`TC-INTERFACE-002` 边界、`TC-INTERFACE-003` 错误）
- **上级需求**：`HLR-INTERFACE-001`

---

未读/未验证：`Conform` 的**遍历顺序**不保证（`for field, expectedKind in spec do` 的哈希序）→ 多字段同时不符时，报出**哪一个**不确定；测试因此只断言「至少一个是这个字段」。嵌套结构（spec 里写 `"table"` 后不再深入）不在范围内。
