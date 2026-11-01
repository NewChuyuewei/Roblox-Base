# 验证用例与结果 · CONTRACT

> **生成物 — 勿手改**。由 `lune run tests/cert/run.luau` 生成（认证线）。
> 与产品线严格分开：本文件不含 `SelfTest`/`TestKit` 的任何输出（`CERT.md` §9.2）。

- 环境：Lune `?` · loader `scripts/lune-loader.luau`（**无引擎桩**）
- 结果：**5/5 用例通过** · 断言 15 次
- 覆盖的需求：HLR-CONTRACT-001、HLR-CONTRACT-002、HLR-CONTRACT-003、LLR-CONTRACT-001、LLR-CONTRACT-002、LLR-CONTRACT-003

| 用例 | 类别 | 覆盖 | 结果 |
| --- | --- | --- | --- |
| `TC-CONTRACT-001` | 正常 | LLR-CONTRACT-001, HLR-CONTRACT-001, HLR-CONTRACT-002 | PASS |
| `TC-CONTRACT-001b` | 边界 | LLR-CONTRACT-001, LLR-CONTRACT-002, HLR-CONTRACT-001 | PASS |
| `TC-CONTRACT-002` | 错误 | LLR-CONTRACT-001, LLR-CONTRACT-002, HLR-CONTRACT-001, HLR-CONTRACT-002 | PASS |
| `TC-CONTRACT-003` | 正常 | LLR-CONTRACT-003, HLR-CONTRACT-003 | PASS |
| `TC-CONTRACT-004` | 错误 | LLR-CONTRACT-003, HLR-CONTRACT-001, HLR-CONTRACT-003 | PASS |
