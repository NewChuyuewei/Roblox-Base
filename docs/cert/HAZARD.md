# 危害分析与 DAL 分配（C1 交付）

> 上游：`.plan/CERT.md`。本文档是 `docs/cert/` 的**第 0 号文件**，一切范围/需求/验证以此为准。
> 状态：**C1 完成**（2026-10-25）。`AC-C1` 自查表见 §7。
> 控制类别：CC1 —— 任何改动走变更控制（`CERT.md` §8 / `7.2.4`）。

---

## 1. 已决事项（`CERT.md` §10 的问题，由执行方裁定）

**问题**：目标定在「适航级合规」还是「航空级可靠性工程」？

**裁定：以「可审查的航空级可靠性工程」为交付目标，保留 DO-178C 的目标结构与升级路径。**

理由（三条，均可复核）：

1. **全合规产物无人可接受。** `CERT.md` §10 已记录三项永久偏差（组织独立性缺失、Luau 运行时与 Roblox 引擎不可鉴定、工具未鉴定）。没有当局、没有 DER、没有航空器 —— 无论如何都只能产出「PSAC 形状的工件集」，而其中关键论证（平台鉴定）在结构上不成立。
2. **项目真正缺的不是文书，是验证深度。** 12k 行核心（MVCC/WAL/崩溃恢复/B+ 树/查询引擎）目前**未被任何需求驱动的测试证明过**。把预算花在工具鉴定文书上，换来的是没人看的纸。
3. **升级是加法而非重写。** 本裁定保留：危害→DAL、HLR/LLR、双向追溯、statement 覆盖、范围切割、独立性纪律、变更控制、问题报告。若日后确有当局接口，**追加**工具鉴定包与缺失的生命周期数据项即可，不需要推翻工程。

**因此具体裁剪（相对 `CERT.md` 的原始配置）**：

| 项 | 原配置 | 裁定后 | 理由 |
| --- | --- | --- | --- |
| 工具鉴定 | 逐件判定 TQL | **只对「其输出作为验证信用」的工具做鉴定评估**；其余一律判为 TQL-5（无影响）并**记录判定与理由**，不做鉴定包 | 文书成本与证据价值不成比例；且「记录判定」本身就是 DO-330 的入口要求 |
| 生命周期数据 | 16 项 | **14 项**（去掉独立固化的 PSAC 副本与 ACCOMPLISHMENT） | `CERT.md` 即 PSAC-lite；ACCOMPLISHMENT 只在真正提交合规包时需要 |
| 覆盖与追溯范围 | 全部代码 | **只覆盖认证线（≤12k）** | 产品线不主张 DAL，强行覆盖只会稀释证据 |
| 目标数 | 全量 DAL C 的 62 个 | **62 个逐条标注**「关闭 / 不适用 / 偏差」，不追求全部"适用" | 部分目标（如目标码级验证）在本平台结构上不适用，**标注不适用比假装关闭更诚实** |

> 若目标应当改为全合规：把上表四行回滚，并先安排 §4.4 的工具鉴定工作 —— 那是一个独立项目级投入。

---

## 2. 被保护资产（先定资产，才谈 DAL）

| 资产 | 说明 | 丢失/损坏可恢复性 |
| --- | --- | --- |
| **A1 玩家进度数据** | 等级、物品、货币等持久化记录 | **不可恢复**（无 PITR、无物理复制，见 `CERT.md` §0 根因 2） |
| **A2 经济一致性** | 同一资源不重复发放、不凭空消失 | 不可回滚 |
| **A3 崩溃后状态正确性** | WAL Redo/Undo 的结果等于最后一次已提交状态 | 不可恢复（错误状态会被后续写入固化） |
| **A4 可观测的失败** | 失败必须可见，不得静默 | —— |

A1–A3 不可恢复这一条，正是把 H1/H2/H4 定为 **Major → DAL C** 的依据（若能恢复就只值 DAL D）。

---

## 3. 危害 → DAL → 模块（`AC-C1` 的核心表）

| # | 危害 | 后果 | 严重度 | DAL | 资产 | 对应模块 | 验证手段 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **H1** | 玩家进度永久丢失或损坏 | 不可恢复的玩家资产损失 | Major | **C** | A1 | `Tri.Storage.*` · `Tri.Wal.*` · `Tri.Catalog.SchemaStore` | 需求测试 + 故障注入 + 100% statement |
| **H2** | 复制/重复扣加导致经济不一致 | 经济被破坏 | Major | **C** | A2 | `Tri.Txn.LockManager` · `Tri.Txn.Mvcc` · `Tri.Index.UniqueGuard` | 并发用例（两协程抢同一唯一键等）+ 死锁图用例 |
| **H3** | 跨服并发写导致同记录互相覆盖 | 部分丢失，可检测 | Minor | **D** | A1/A2 | `Tri.Txn.TransactionManager` · `Tri.Catalog.Partitioner` | 隔离级别矩阵 |
| **H4** | 崩溃后恢复出错误状态 | A3 失效，是 H1/H2 的成因 | Major | **C** | A3 | `Tri.Wal.{WalWriter,Recovery,Checkpoint}` | **崩溃点注入**：任意 WAL 边界恢复 == 最后一次 COMMIT |
| **H5** | 节流/超时未处理导致写入静默失败 | 数据丢失且无人知晓 | Major | **C** | A1/A4 | `Tri.Request.{RequestBudget,RequestQueue,TokenBucket}` | 三态语义（排队/键级节流/真失败）用例 + 预算断言 |
| **H6** | 查询结果错误（读错行/漏行） | 业务误判 | Minor | **D** | A1 | `Tri.Query.*` · `Tri.Index.IndexScan` | 负例集 + 索引/全扫一致性对拍 |
| **H7** | 日志/面板/示例/工具错误 | 无数据影响 | No Safety Effect | **E** | — | `Dr.Diagnostics` · 示例 · 工具脚本 | 出范围 |
| **H8** | 确定性随机的序列或状态持久化出错（`Platinum`） | 回放误判；发放重复/遗漏 | Major | **C**（仅候选模块） | A2/A4/A1 | `Pt.Rng.Generator`（**候选**） | 见 `HAZARD-L0.md` §1 |
| **H9** | 编解码写坏/读错且下游不可察觉（`Tin`） | 存档永久损坏 | Major | **C**（仅候选模块） | A1/A4 | `Tn.Binary.Varint`（**候选**） | 见 `HAZARD-L0.md` §2 |
| **H10** | 完整性检测假通过（`Krypton`）——掩盖 H1/H4 | 坏页被当好数据固化 | Major | **C**（仅候选模块） | A3/A1 | `Kr.Checksum.Crc32` · `Kr.Hash.Sha256`（**候选**） | 见 `HAZARD-L0.md` §3 |

**DAL 分布（核心线）**：C × 4（H1/H2/H4/H5）· D × 2（H3/H6）· E × 1（H7）
**L0 扩展（2026-11-15，P1.W5）**：H8–H10 为计划期分析，三条各定 C 但**只作用于候选模块**；组件本体仍 DAL E；候选未入 `scope.txt`，入册手续与 12k 加减见 `HAZARD-L0.md` 文末。
**没有任何 A/B**：见 `CERT.md` §0。这一条不得被后续文档悄悄抬高。

---

## 4. 认证范围（DAL C/D）—— 逐模块

机器可读版本：`docs/cert/scope.txt`（门禁 10 读它）。**新增文件必须显式加进去**（CC1 变更控制，I18）。

| 模块 / 文件 | DAL | 危害 | 现状 | 预算 LOC |
| --- | --- | --- | --- | --- |
| `Tri.Catalog.NamespaceCodec` | C | H1 | 计划 | 250 |
| `Tri.Catalog.SchemaStore` | C | H1/H6 | 计划 | 300 |
| `Tri.Catalog.TableRegistry` | D | H6 | 计划 | 250 |
| `Tri.Types.*` | C | H1 | 计划 | 800 |
| `Tri.Storage.Page` · `HeapLayout` | C | H1 | 计划 | 700 |
| `Tri.Storage.PageManager` | C | H1/H4 | 计划 | 800 |
| `Tri.Storage.PageCache` | C | H1 | 计划 | 400 |
| `Tri.Storage.RowStore` | C | H1/H6 | 计划 | 500 |
| `Tri.Storage.Vacuum` | C | H1 | 计划 | 300 |
| `Tri.Index.NodeCodec` · `BPlusTree` | C | H6/H1 | 计划 | 800 |
| `Tri.Index.IndexScan` | D | H6 | 计划 | 350 |
| `Tri.Index.UniqueGuard` | C | H2 | 计划 | 250 |
| `Tri.Txn.TransactionManager` | D | H3 | 计划 | 450 |
| `Tri.Txn.Mvcc` | C | H2/H3 | 计划 | 600 |
| `Tri.Txn.LockManager` | C | H2 | 计划 | 600 |
| `Tri.Txn.WaitForGraph` | C | H2 | 计划 | 400 |
| `Tri.Txn.UndoLog` · `Isolation` · `Savepoint` | C | H4 | 计划 | 550 |
| `Tri.Wal.WalWriter` · `WalReader` | C | H4 | 计划 | 700 |
| `Tri.Wal.Checkpoint` · `Recovery` | C | H4 | 计划 | 800 |
| `Tri.Query.{Lexer,Parser,Ast,Analyzer}` | D | H6 | 计划 | 900 |
| `Tri.Query.{LogicalPlan,Optimizer,PhysicalPlan,Executor,PlanCache}` | D | H6 | 计划 | 900 |
| `Tri.Request.{RequestBudget,RequestQueue,TokenBucket}` | C | H5 | 计划 | 800 |
| `Dr.Core.Foundation.CoreTypes` | C | 基础 | **现存** | 20 |
| `Dr.Core.Foundation.Contract` | C | 基础 | **现存** | 15 |
| `Dr.Core.Foundation.ErrorHandler` ⚠ **需拆分，见 §5.1** | C | 基础 | **现存（违规）** | 60 |
| `Dr.Core.Foundation.Metadata` · `Context` | C | 基础 | 计划 | 250 |
| `Dr.Types.Contract.Interface` | C | 基础 | **现存** | 30 |
| `Dr.Collections.{Map,Linear,Sorted,Set}` | C | 基础 | 计划 | 600 |
| `Dr.Memory.{Buffer.ByteBuffer,Pool.ObjectPool,Pool.TablePool}` | C | H1 | 计划 | 400 |
| `Dr.Concurrency.{Sync.Mutex,Async.AsyncQueue,Scheduling.TaskScheduler}` | C | H2 | 计划 | 400 |
| `Tri.Testing.SimulatorPort` | **（验证用模型）** | 全部 | 计划 | 300 |

**合计预算：11,200 行 + 800 行余量（7%）= 12,000 行上限。**
**L0 T1 候选（`HAZARD-L0.md`）合计 730 行尚未入册；若入册则为 11,930——余量只剩 70，此后任何扩线都必须走换入换出。**

> 预算已重切。原 `CERT.md` §3.1 的表算出 **12,400 行 → 超帽子 400 行（103.3%）**，即范围表自身违反自己的硬上限。本次把 Txn+Wal 3000→2800、Storage 2600→2400、Index 1600→1400、Query 2000→1800、Catalog+Types 900→800、Dr 底座 1400→1200，得 11,200，**并留 800 行余量**（无余量的上限不是上限，是迟早要破的承诺）。

**现状**（2026-10-25 实测）：范围内现存 **6 文件 / 175 行**（占上限 1.5%）。TritiumSQL 侧全为 0 —— 即**认证线尚未开工**。

---

## 5. C1 发现的两处必须先修的问题

### 5.1 `ErrorHandler` 违反 I16（认证范围内的既有违规）

**实测**：`Deuterium/Core/Foundation/ErrorHandler.luau` 里 `require(game:GetService("ReplicatedStorage"):WaitForChild("Debug"))` → 触碰 `game` + 依赖 `Dr.Diagnostics`（DAL E）。

**后果**：按 I16 它不能留在认证范围；但认证核心又确实需要结构化错误（`DrError` 是核心的公共错误类型）。

**必须的修法（在 C3 之前完成）**——把纯与不纯切开：

| 部分 | 处置 | 理由 |
| --- | --- | --- |
| `New` · `IsDrError` · `Normalize` · `Render` · `Raise` | **留在认证范围**（移入纯模块，或拆为 `ErrorHandler.Pure`） | 全是纯函数，无 `game`，是核心需要的 |
| `Report`（内部 `Debug.warn`） | **移出**认证范围 → 由非认证层的适配器/Logger 承担 | 它是 I/O，属 DAL E |

调用方影响：`ErrorHandler.Report` 的调用者需改为持有 Logger（构造器注入）。这与 `.plan/STEPS.md` Step 7 已记录的结论一致 —— *「A 档核心逻辑应构造器注入依赖，而不是 `script.Parent` 硬接」*。

**✅ 已修复（2026-10-25）**：`ErrorHandler.Report` **零调用方**（全仓 grep 实测），故直接删除而不是搬家 —— 按“删优于加”，也避免留下一个没人用的适配层。`ErrorHandler.luau` 现在**零 require 之外无任何外部依赖**（79 行，纯函数），与 `StructuredLog` 一样可 headless 运行。回报职责交给非认证层：

```lua
local Logger = require(...Diagnostics.Logging.Logger)
Logger.New("Dr.<Tag>"):warn(ErrorHandler.Render(err))
```

副产品：`scripts/p0-check.sh` 的 `game:GetService(` 棘轮从 48 降到 **47**（已收紧基线）。

### 5.3 门禁 10 已交付并**自带自检**（本应更早发现的问题）

`scripts/cert-scope-check.luau`（Lune 单进程；先写的 bash 版在 Windows 上 57 个条目要跑 4 分钟，已删）。它做两件事：

| 阶段 | 检查 | 为什么必需 |
| --- | --- | --- |
| **A 字面** | `GetService(` / `game:` / `ReplicatedStorage` / 非认证层名 / `loadstring(` | 直接触碰引擎与网络 |
| **B 依赖闭包** | 认证文件里**每个** require 必须解析到范围内 | A 段只抓字面：`require(script.Parent.Parent.Parent.Diagnostics.Logging.Logger)` 在 A 段下**全绿**，但 I16 已被静默穿透 |

**B 段暴露的一个真实语义细节**：`script` 是**本文件**，所以 `script.Parent` = 所在目录 = `dirname(file)`，**N 个 `Parent` 只向上 N−1 层**。我第一版实现按 N 层处理，把 5 个合法依赖误报成违规 —— 这个错误如果没被自检抓住，会在 CI 里变成一个“看起来合理”的红灯。

**自检（`--selftest`，9 条断言）**：门禁必须**先证明自己会失败**。它走的是与正式校验**同一条 `audit` 路径**（不是重写一遍循环——重写等于什么都没测），覆盖：路径语义 5 例 · A 段反例 · B 段反例 + 不误报例 · 整行注释不得误报。

> 教训（已写进 STEPS DoD）：**一个会误报文档的门禁，最终结局是被人加豁免关掉 —— 那比没有门禁更糟。** 同理：一个不会失败的门禁等于不存在，所以自检是交付物的一部分，不是可选赠品。

### 5.2 预算超帽子

已按 §4 重切（12,400 → 11,200 + 800 余量）。

---

## 6. 边界与验证底座（I17/I19）

认证核心与不信世界之间**只有三个接口**：`Tri.Runtime.RuntimeTypes.Port`、`Tri.Query.ResultSet`、`Dr.Types.Transform.Codec`。三者入参在核心内**先验后用**（I17）。

| 底座 | 是否产生认证信用 | 说明 |
| --- | --- | --- |
| `SimulatorPort` + 受控 Luau | **是**（唯一） | 确定性、可复现、不依赖网络（I19） |
| `Standalone`/`Deuterium` 绑定 · 真实 DataStore · Roblox 引擎 | 否 | 属产品线，其测试不计入认证覆盖 |

---

## 7. `AC-C1` 自查表

| 判据 | 状态 | 证据 |
| --- | --- | --- |
| H1–H7 每条有 DAL + 失效后果 + 被保护资产 | ✅ | §3 |
| 每条危害可追溯到模块 | ✅ | §3「对应模块」列，逐条有模块 |
| 范围表逐模块（文件级）勾选 | ✅ | §4 + `scope.txt` |
| 12k 上限有加减核对 | ✅ | §4 尾注：11,200 + 800 = 12,000（并记录了原表的 −400 缺口） |
| 范围外清单明确 | ✅ | `CERT.md` §3.2；本文 §6 边界表 |
| 已知违规暴露而非掩盖 | ✅ | §5.1（`ErrorHandler`）· §5.2（预算） |

---

未读/未验证：§4 的**逐模块 LOC 预算是估算**，非实测（仅有 175 行是实测）；`Tri.NoSql`/`Tri.Ddl`/`Tri.Stat` 未列首批范围，若纳需走范围变更；H3/H6 的 DAL 定 D 的依据是"可检测可补偿"，若日后发现不可补偿则须上调为 C（并按 C 重做验证）。
