# 验证用例与结果 · INTERFACE

> **生成物 — 勿手改**。由 `lune run tests/cert/run.luau` 生成（认证线）。
> 与产品线严格分开：本文件不含 `SelfTest`/`TestKit` 的任何输出（`CERT.md` §9.2）。

- 环境：Lune `?` · loader `scripts/lune-loader.luau`（**无引擎桩**）
- 结果：**3/3 用例通过** · 断言 14 次
- 覆盖的需求：HLR-INTERFACE-001、LLR-INTERFACE-001

| 用例 | 类别 | 覆盖 | 结果 |
| --- | --- | --- | --- |
| `TC-INTERFACE-001` | 正常 | LLR-INTERFACE-001, HLR-INTERFACE-001 | PASS |
| `TC-INTERFACE-002` | 边界 | LLR-INTERFACE-001, HLR-INTERFACE-001 | PASS |
| `TC-INTERFACE-003` | 错误 | LLR-INTERFACE-001, HLR-INTERFACE-001 | PASS |
