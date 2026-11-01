# 验证用例与结果 · CORETYPES

> **生成物 — 勿手改**。由 `lune run tests/cert/run.luau` 生成（认证线）。
> 与产品线严格分开：本文件不含 `SelfTest`/`TestKit` 的任何输出（`CERT.md` §9.2）。

- 环境：Lune `?` · loader `scripts/lune-loader.luau`（**无引擎桩**）
- 结果：**3/3 用例通过** · 断言 18 次
- 覆盖的需求：HLR-CORETYPES-001、HLR-CORETYPES-002、LLR-CORETYPES-001、LLR-CORETYPES-002

| 用例 | 类别 | 覆盖 | 结果 |
| --- | --- | --- | --- |
| `TC-CORETYPES-001` | 正常 | LLR-CORETYPES-001, HLR-CORETYPES-001 | PASS |
| `TC-CORETYPES-002` | 正常 | LLR-CORETYPES-002, HLR-CORETYPES-002 | PASS |
| `TC-CORETYPES-003` | 边界 | LLR-CORETYPES-001, LLR-CORETYPES-002, HLR-CORETYPES-001, HLR-CORETYPES-002 | PASS |
