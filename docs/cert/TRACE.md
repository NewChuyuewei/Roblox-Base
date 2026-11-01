# 追溯矩阵（生成物 — 勿手改）

> 由 `lune run scripts/cert-trace-check.luau` 生成（门禁 11）。权威规则：`docs/cert/REQ-STD.md` §5。
> 需求文本：`docs/cert/req/` · 用例：`tests/cert/cases/` · 用例结果：`docs/cert/verify/`。

规模：**10 条 HLR · 12 条 LLR** · 违规 **0** 处

## 1. 需求 → 代码 → 用例

| LLR | 上级 HLR | 实现位置 | 覆盖用例 |
| --- | --- | --- | --- |
| `LLR-CONTRACT-001` | HLR-CONTRACT-001 | src/ReplicatedStorage/Deuterium/Core/Foundation/Contract.luau | TC-CONTRACT-001、TC-CONTRACT-002 |
| `LLR-CONTRACT-002` | HLR-CONTRACT-001 | src/ReplicatedStorage/Deuterium/Core/Foundation/Contract.luau | TC-CONTRACT-001、TC-CONTRACT-002 |
| `LLR-CONTRACT-003` | HLR-CONTRACT-003 | src/ReplicatedStorage/Deuterium/Core/Foundation/Contract.luau | TC-CONTRACT-003、TC-CONTRACT-004 |
| `LLR-CORETYPES-001` | HLR-CORETYPES-001 | src/ReplicatedStorage/Deuterium/Core/Foundation/CoreTypes.luau | TC-CORETYPES-001、TC-CORETYPES-003 |
| `LLR-CORETYPES-002` | HLR-CORETYPES-002 | src/ReplicatedStorage/Deuterium/Core/Foundation/CoreTypes.luau | TC-CORETYPES-002、TC-CORETYPES-003 |
| `LLR-ERRORHANDLER-001` | HLR-ERRORHANDLER-001 | src/ReplicatedStorage/Deuterium/Core/Foundation/ErrorHandler.luau | TC-ERRORHANDLER-001 |
| `LLR-ERRORHANDLER-002` | HLR-ERRORHANDLER-001 | src/ReplicatedStorage/Deuterium/Core/Foundation/ErrorHandler.luau | TC-ERRORHANDLER-001、TC-ERRORHANDLER-002 |
| `LLR-ERRORHANDLER-003` | HLR-ERRORHANDLER-001 | src/ReplicatedStorage/Deuterium/Core/Foundation/ErrorHandler.luau | TC-ERRORHANDLER-004 |
| `LLR-ERRORHANDLER-004` | HLR-ERRORHANDLER-002 | src/ReplicatedStorage/Deuterium/Core/Foundation/ErrorHandler.luau | TC-ERRORHANDLER-002 |
| `LLR-ERRORHANDLER-005` | HLR-ERRORHANDLER-001 | src/ReplicatedStorage/Deuterium/Core/Foundation/ErrorHandler.luau | TC-ERRORHANDLER-003 |
| `LLR-ERRORHANDLER-006` | HLR-ERRORHANDLER-003 | src/ReplicatedStorage/Deuterium/Core/Foundation/ErrorHandler.luau | TC-ERRORHANDLER-003、TC-ERRORHANDLER-004 |
| `LLR-INTERFACE-001` | HLR-INTERFACE-001 | src/ReplicatedStorage/Deuterium/Types/Contract/Interface.luau | TC-INTERFACE-001、TC-INTERFACE-002、TC-INTERFACE-003 |

## 2. HLR → 用例

| HLR | 危害追溯 | 覆盖用例 |
| --- | --- | --- |
| `HLR-CONTRACT-001` | ��基础 —— 契约不拦会造成「继续跑在坏状态上」，是 H1–H7 的**共同成因**。 | TC-CONTRACT-001、TC-CONTRACT-002、TC-CONTRACT-004 |
| `HLR-CONTRACT-002` | ��基础 —— 责任方不可辨会把排查引向错误方向，掩盖真实成因。 | TC-CONTRACT-001、TC-CONTRACT-002 |
| `HLR-CONTRACT-003` | ��基础 —— 判定在两种环境下不一致会让 headless 测试**假绿**（R28）。 | TC-CONTRACT-003、TC-CONTRACT-004 |
| `HLR-CORETYPES-001` | ��基础（`HAZARD.md` §4 的 Dr 纯底座行）—— 错误形状是 H1–H7 全部检测机制的前提：形状不成立则危害无法被识别。 | TC-CORETYPES-001、TC-CORETYPES-003 |
| `HLR-CORETYPES-002` | ��基础 —— 失败若无 `err`，则 H5（静默失败）不可检测。 | TC-CORETYPES-002、TC-CORETYPES-003 |
| `HLR-ERRORHANDLER-001` | ��基础 —— 异构失败无法归一化会让 H5（写入静默失败）被当作正常路径。 | TC-ERRORHANDLER-001、TC-ERRORHANDLER-004 |
| `HLR-ERRORHANDLER-002` | ��基础 —— 失败不可读会拖长故障定位（H1–H7 的处置时长）。 | TC-ERRORHANDLER-002 |
| `HLR-ERRORHANDLER-003` | ��基础 —— 抛穿会让调用方的清理逻辑被跳过。 | TC-ERRORHANDLER-003、TC-ERRORHANDLER-004 |
| `HLR-ERRORHANDLER-004` | ��基础 —— 认证范围触碰引擎会让 I16 失效，并把认证证据绑到不可控环境上。 | TC-ERRORHANDLER-005 |
| `HLR-INTERFACE-001` | ��基础 —— 边界不设防会让错误形状的数据进入内核（H1/H6 的上游成因）。 | TC-INTERFACE-001、TC-INTERFACE-002、TC-INTERFACE-003 |

## 3. 认证源码的注解覆盖（② 代码 → 需求）

| 文件 | 导出声明 | 注解 |
| --- | --- | --- |
| `src/ReplicatedStorage/Deuterium/Core/Foundation/CoreTypes.luau` | 2 | 2 |
| `src/ReplicatedStorage/Deuterium/Core/Foundation/Contract.luau` | 3 | 3 |
| `src/ReplicatedStorage/Deuterium/Core/Foundation/ErrorHandler.luau` | 6 | 6 |
| `src/ReplicatedStorage/Deuterium/Types/Contract/Interface.luau` | 1 | 1 |

## 4. 用例文件（③ 需求 → 测试）

| 文件 | 用例数 |
| --- | --- |
| `tests/cert/cases/Contract.luau` | 4 |
| `tests/cert/cases/CoreTypes.luau` | 3 |
| `tests/cert/cases/ErrorHandler.luau` | 5 |
| `tests/cert/cases/Interface.luau` | 3 |

## 5. 违规

**0 处** —— 四向闭环成立（方向 ④ 见下）。

## 6. 方向 ④（需求 → 覆盖）—— 由覆盖工具负责

本节**不提供**行级覆盖数字：那属于 `scripts/coverage.luau`（**门禁 12**，C4 已交付）。
它按 statement 口径统计认证范围的可执行行，报告在 `docs/cert/coverage/<MOD>.json`，
未覆盖行必须逐条登记在 `docs/cert/coverage/UNCOVERED.md`。

**关系要说清**：本文件证明「需求 ↔ 代码 ↔ 用例」的**映射链完整**；覆盖工具证明「映射到的代码真的被执行过」。
两者都绿才算方向 ④ 成立 —— 本文件单独绿**不等于**覆盖达标。
---

未读/未验证：本地图是**静态**可导出的关系；`ILLR→代码` 的映射靠注解声明，
而不是靠解析 AST —— 注解可以被放在错误的位置（有人为错误的空间），
这一残留风险由评审（`REQ-STD.md` §6）承担，不由本脚本消除。
