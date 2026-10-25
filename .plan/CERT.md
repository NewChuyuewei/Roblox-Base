# DO-178C 适配（本项目的 PSAC-lite）

> 需求来源：用户要求本项目满足 **DO-178C**。本文件是合规层的唯一权威，并**修改**其余计划的排期与范围。
> 先读 §0 与 §9：它们改的是**能不能做、做什么范围、先做什么**，其余章节是做法。
> 本文件把 DO-178C 的**目标**当作工程标准采用；**只有适航当局能"认证"**，本仓库不宣称认证。

---

## 0. 结论先行（不粉饰）

| 问题 | 答案 |
| --- | --- |
| 能否让整个 440 模块 / 100k 行计划达到 DO-178C？ | **不能。** 认证成本随目标数与独立性要求增长，且下述三个根因无法用工作量解决 |
| 能否在一个**有界子集**上按 DO-178C 目标做工程？ | **能。** 目标 **DAL C**，认证子集 ≤ **12k 行核心**（见 §3） |
| 为什么不是 DAL A/B？ | ① 覆盖工具（MC/DC）在本生态不存在且需自研+鉴定；② DAL A/B 要求**组织独立性**，单人/单 agent 项目结构上不可能；③ 见下方"三个根因" |
| 已写的 ~5k 行怎么办？ | 其中约 1.5k 行落在认证范围内，必须**反向补需求并重新验证**（§9.2）；其余冻结为非认证范围 |

### 三个不可用工作量解决的根因

1. **Luau 解释器不在我们手里。** Roblox 引擎闭源、服务端远程更新、无法固定版本、无法审计。DO-178C 语境下 Luau 引擎本身是 flight software —— DLR 的《Scripting Engine Design Approach for Avionics Systems》正是这么处理的（"the Lua scripting engine has to be considered as flight software"）。我们既不能鉴定它，也不能冻结它。
2. **`DataStoreService` 不满足可验证性。** 它是带节流、键级节流、最终一致性、网络故障的远程服务 —— 非确定性、不可控行为。DO-178C 要求行为可确定、可验证。
3. **动态类型与隐式转换。** DO-178C §6.7/6.7.1 要求**一致地使用类型**并**说明类型转换意图**（DLR 论文明确指出这一点）。Luau 的隐式转换必须有显式规约才能谈合规（§7.4）。

### 因此本项目采用的立场

> **已验证的纯逻辑核心 + 不可鉴定的引擎作为有界 COTS 边界。**
> 认证信用只挂在**确定性、可复现、可在受控底座上运行的纯 Luau 模块**上；Roblox 引擎与 DataStore 按 §12（Additional Considerations）+ COTS/PDS 处理，用**设计隔离**而非"证明"来防护（§4）。
>
> 这不是绕过标准，而是标准里对 COTS 的正规处理方式：CASA 的指引明确说闭源 COTS "makes traceability difficult"，FAA AC 20-115C 要求对复用/遗留软件**评估使用历史与已知缺陷**后再复用。我们就是在做这件事，并把边界写出来。

---

## 1. 标准事实基线（均带出处，不凭记忆）

| 事实 | 值 | 出处 |
| --- | --- | --- |
| DAL 与失效后果 | A Catastrophic · B Hazardous · C Major · D Minor · E No Safety Effect | Rapita；do178.org |
| 目标数 | A **71** · B **69** · C **62** · D **26** · E 0 | RTI；spilma；do178.org（三源一致） |
| 其中要求独立性的目标数 | A **30** · B **18** · C **5** · D **2** | RTI；spilma |
| 结构覆盖 | A：MC/DC + decision + statement · B：decision + statement · **C：statement** · D：无 | spilma 表；Adacore（"Statement coverage for Level C"） |
| MC/DC 用例下界 | n 个条件最少 **n+1** 组（对比 2ⁿ） | LDRA |
| 结构覆盖的位置 | §6.4.4 + Table A-7 row 5 | LDRA；Adacore |
| DO-330 工具鉴定 | 3 条准则 × 软件 DAL → **TQL-1..5**。准则 1（工具输出构成机载软件的一部分、可能引入错误）：A→**TQL-1**、B→**TQL-2**、C→**TQL-3**、D→**TQL-4** | Rapita DO-330 表 |
| 准则 2/3 的 TQL 映射 | ⚠️ **未核实**（本次检索只拿到准则 1 的行）。动工前须查 DO-330 原表 | — |
| §12 | Additional Considerations；12.1.3 = Change of Application or Development Environment | Vector/DO-178C 摘要 |
| COTS / PDS | COTS = 非以 DO-178C 合规为目标开发的商用件；PDS = 之前按 DO-178C 开发并复用的软件。二者都缺完整生命周期数据 | ee-aero；CASA |
| CC1 / CC2 | CC2 ⊂ CC1。Design Description 在 A/B 为 CC1，在 **C/D 为 CC2** | Adacore |
| SCM 活动 | 7.2.1 配置标识 · 7.2.2 基线与追溯 · 7.2.3 问题报告/纠正 · 7.2.4 变更控制 · 7.2.5 变更评审 · 7.2.6 状态记帐 · 7.2.7 归档/检索/发布 · 7.3 数据控制类别 | FAA DO-178B/C Differences Tool |
| 动态语言先例 | 存在 DLR/IEEE DASC 关于 Lua 与 Python 用于 DO-178C 的研究；结论是**引擎自身须按飞行软件开发** | DLR elib；IEEE DASC 2024/2025；Journal of Computer Languages |

---

## 2. 危害分析与 DAL 分配（游戏语境）

DO-178C 的 DAL 来自系统安全评估。游戏没有机上安全后果，所以**必须先把"被保护资产"定义清楚**，否则 DAL 无从谈起。本项目的资产与危害：

| # | 危害（Hazard） | 后果 | 严重度借用 | DAL |
| --- | --- | --- | --- | --- |
| H1 | 玩家进度数据**永久丢失或损坏** | 不可恢复的玩家资产损失；无法用运维手段修复 | Major | **C** |
| H2 | **复制/重复扣加**导致经济数据不一致（刷物品、刷货币） | 经济被破坏，不可回滚 | Major | **C** |
| H3 | 跨服并发写入导致**同一记录互相覆盖** | 部分数据丢失，通常可检测可补偿 | Minor | **D** |
| H4 | 崩溃后**恢复出错误状态**（Redo/Undo 不对） | H1/H2 的前置失效，属 H1 的成因 | Major | **C** |
| H5 | 节流/超时未处理导致**写入静默失败** | 数据丢失且无人知晓 → 归入 H1 | Major | **C** |
| H6 | 查询结果错误（读错行/漏行） | 业务误判，一般不损坏持久数据 | Minor | **D** |
| H7 | 日志/面板/示例/工具错误 | 无数据影响 | No Safety Effect | **E** |

**判定结果：被认证的等级是 DAL C。** 巧合但重要的一点：**DAL C 恰好要求 statement coverage，而 statement coverage 恰好是本生态唯一可实现的覆盖级别**（§7.2）。所以 DAL C 不是妥协，是**与可达成能力对齐的正确目标**。

DAL A/B **不主张**，理由见 §0。任何把等级往上抬的尝试都必须先解决 MC/DC 工具与组织独立性，否则是自欺。

---

## 3. 范围切割（本次优化最重要的改动）

### 3.1 认证范围（Certified Scope, DAL C）

| 归属 | 模块 | 估算核心行 |
| --- | --- | --- |
| 事务与恢复（H2/H4） | `Tri.Txn.*` · `Tri.Wal.*` | 3,000 |
| 存储与页面（H1/H4） | `Tri.Storage.{Page,HeapLayout,PageManager,PageCache,RowStore,Vacuum}` | 2,600 |
| 索引（H6/D 级输入给 C 级） | `Tri.Index.*` | 1,600 |
| 查询（H6） | `Tri.Query.{Lexer,Parser,Ast,Analyzer,LogicalPlan,Optimizer,PhysicalPlan,Executor}` · `Operators/*` | 2,000 |
| 请求与节流（H5） | `Tri.Request.{RequestBudget,RequestQueue,TokenBucket}` | 900 |
| 目录与类型（基础） | `Tri.Catalog.{NamespaceCodec,SchemaStore,TableRegistry}` · `Tri.Types.*` | 900 |
| 框架纯底座 | `Dr.Core.Foundation.{ErrorHandler,CoreTypes,Contract,Metadata,Context}` · `Dr.Types.*` · `Dr.Collections.*` · `Dr.Memory.{Buffer,Pool}` · `Dr.Concurrency.{Sync,Async}` | 1,400 |
| **合计** | **≤ 40 模块** | **≈ 12,400** |

**硬上限 12,000 行核心**（超出必须走 §8 的范围变更，不允许悄悄长大）。

### 3.2 非认证范围（Uncertified, DAL E）

- 一切触碰 `game` 的代码：`Dr.Runtime.*`、`Tri.Runtime.Bindings.{Standalone,Deuterium}`、`Dr.Net`、`Dr.Security`、`Dr.Diagnostics`、`Dr.ECS`、`Dr.World`、`Dr.Plugin`、`Dr.Testing`、示例与工具。
- **第三方树**：`src/ReplicatedStorage/{Scribe,QuickZone}/**` 及其**适配器**（`*/Adapter/*`）—— 见上面的条目。
- **`Tri.Testing.SimulatorPort` 例外且必须在范围内**：它是认证信用所依赖的确定性底座（§4.3），是"验证用模型"，不是被测软件。
- **Scribe（38,717 行）与 QuickZone（6,534 行）**：无可鉴定的 **COTS/PDS**（各自直调 `game`/DataStore；无生命周期数据、无版本锁定、无 LICENSE、未审计）→ **永久出范围**；它们的**适配器**也属产品线。I16 禁止认证核心 require 它们，门禁 10 的 B 段（依赖闭包）已能静态拦住越界。详见 `THIRDPARTY.md`。
- 非认证代码**不得**被认证核心 require（CI 阻断，见 §9.3 的 I16 守卫）。

### 3.3 与 100k 行目标的冲突（必须明说）

`SCALE.md` 的目标是 440 模块 / 100k 行。**DO-178C 的目标数与成本不可摊薄**：DAL C 有 62 个目标（其中 5 个要求独立性），每个目标都要证据；12k 行 DAL C 往往需要 ≥1.5× 行数的验证资产与全套生命周期数据。

**处理方式：把 100k 拆成三条独立的线，互不借用信用。**

| 线 | 范围 | 目标 | 依据 |
| --- | --- | --- | --- |
| **认证线** | §3.1，≤12k 行 | DAL C，62 目标逐条关闭 | 本文件 |
| **产品线** | 其余功能（网络/安全/ECS/世界/工具…） | 现有 `SCALE.md` 的质量分档 A/B/C，**不主张任何 DAL** | `SCALE.md` |
| **工具线** | 构建/测试/覆盖工具 | 按 DO-330 登记（§4.4） | 本文件 |

**禁止**：用产品线的测试去填认证线的覆盖，或反之。两条线的证据必须可区分（`docs/cert/` 与普通 CI 报告分开存放）。

---

## 4. 平台与工具鉴定（DO-330 + §12）

### 4.1 平台处理（这是最关键的一条）

| 平台 | 处理 | 理由 |
| --- | --- | --- |
| **官方 Luau（开源仓库）** | **受控底座**：编译并固定 commit hash，作为认证核心的**语义参考实现与测试宿主** | 开源、可复现、可审计、可 hash 固定 |
| **Roblox 引擎 / Luau 运行时** | **目标环境（target），COTS，未鉴定** | 闭源、远程更新、无法冻结 |
| **`DataStoreService`** | 边界之外（通过 Port 隔离） | 非确定性远程服务（§0 根因 2） |

**论证形式（§12.1.3 类）**：认证核心的语义在**受控底座**上定义并验证；Roblox 引擎只作为安装目标。真实适航项目里这一条必须由当局/DER 认可；本仓库把它**写清楚并留证**，不假装它已被认可。

### 4.2 边界纪律（替代"证明引擎正确"）

认证核心与不信世界之间只有三个接口：`Tri.Runtime.RuntimeTypes.Port`、`Tri.Query.ResultSet`、`Dr.Types.Transform.Codec`。
**规则**：认证核心对**所有**边界输入做防御性校验并在失败时给出结构化错误（不信任上游），这是"用设计隔离代替鉴定"的具体含义，也是可被审查的证据。

### 4.3 确定性底座

**认证信用的唯一宿主是 `SimulatorPort` + 受控 Luau**：
- 全部 DAL C 验证测试跑在 `SimulatorPort` 上 → 确定性、可复现、不依赖网络。
- `StandaloneBinding`/`DeuteriumBinding` 的测试属**产品线**，不计入认证信用。
- 故障注入（超时/配额/写失败/崩溃点）是**需求的一部分**，不是附加测试。

### 4.4 工具鉴定登记表（初版，动工前须逐条关闭）

| 工具 | 在流程中的作用 | 若作为验证信用的准则/DAL→TQL | 处置 |
| --- | --- | --- | --- |
| `luau`（官方，pin hash） | 编译/运行认证核心 | 准则 1，DAL C → **TQL-3** | **倾向鉴定**（自研测试宿主 + 记录 hash）；否则须逐项人工复核其输出。⚠ 实测：Lune 0.11.1 **无 `debug.sethook`、无 `luau` 库**（`docs/headless.md` §2） |
| Roblox 引擎 | 目标环境 | 不可鉴定 | 出范围（§4.1） |
| `rojo` | 生成实例树（生命周期数据） | 准则 1，DAL C → TQL-3 | 不用于认证信用；实例树结构由 `rojo sourcemap` **人工评审**并留证 |
| `stylua` | 改写源码（源码是受控数据！） | 准则 1，DAL C → TQL-3 | **只在 CI 跑 `--check`（改为只读）**，不用于改写认证范围内文件；另加 **AST 等价性检查**证明格式化不改语义 |
| `luau-lsp analyze` | 静态分析 | 准则 2 类（探测错误） | 仅作**咨询**，不作为目标关闭证据；其发现进入问题报告流程 |
| 自研覆盖工具 | 产出 statement coverage 证据 | 准则 1，DAL C → TQL-3 | 需自研 + 鉴定计划（§7.3）；若鉴定不可行 → 覆盖率不得作为目标关闭证据 |
| `scripts/p0-check.sh` · `loc-budget` | 约束守卫 | 准则 3（无影响） | TQL-5，无需鉴定；仅作流程守卫 |
| 子代理 / LLM | 生成代码与文档 | **不在 DO-330 的"工具"范畴内，等同人** | 见 §7.5 的独立性诚实声明 |

---

## 5. 生命周期数据 → 落盘位置

`docs/cert/`（新建，认证线的生命周期数据，与产品线分开）：

| # | 数据项 | 文件 | 控制类别 |
| --- | --- | --- | --- |
| 1 | 计划（PSAC-lite） | `docs/cert/PSAC.md`（= 本文件的固化版 + 当局接口约定） | CC1 |
| 2 | 软件开发计划 | `docs/cert/SDP.md` | CC1 |
| 3 | 软件验证计划 | `docs/cert/SVP.md` | CC1 |
| 4 | 配置管理计划 | `docs/cert/SCMP.md` | CC1 |
| 5 | 软件质量保证计划 | `docs/cert/SQAP.md` | CC1 |
| 6 | 需求标准 | `docs/cert/REQ-STD.md`（HLR/LLR 写法、可验证性判据） | CC1 |
| 7 | 高层需求 HLR | `docs/cert/req/HLR-<module>.md` | CC1 |
| 8 | 低层需求 LLR | `docs/cert/req/LLR-<module>.md` | CC1 |
| 9 | 设计描述 | `docs/cert/design/<module>.md` | **CC2**（DAL C） |
| 10 | 需求→代码→测试 追溯矩阵 | `docs/cert/TRACE.md`（CI 生成） | CC1 |
| 11 | 验证用例与结果 | `docs/cert/verify/<module>.md` + CI 产物 | CC1 |
| 12 | 结构覆盖报告 | `docs/cert/coverage/<module>.json` | CC1 |
| 13 | 问题报告 | `docs/cert/PROBLEMS.md` | CC1 |
| 14 | 配置索引 / 基线记录 | `docs/cert/BASELINE.md` | CC1 |
| 15 | 工具鉴定材料 | `docs/cert/tool-qual/TQ-<tool>.md` | CC1 |
| 16 | 完成摘要 | `docs/cert/ACCOMPLISHMENT.md` | CC1 |

**规则**：`docs/cert/` 下的内容任何变更都是 CC1 → 必须走变更控制（§8），不是"顺手改一下"。

---

## 6. 需求基线（先于代码）

### 6.1 两级需求

- **HLR**：模块对外可观察行为，不含实现。写法：`HLR-<MOD>-nnn` + 一句话 + 激励/响应 + 可判定条件 + 追溯（危害 ID）。
- **LLR**：实现级需求，覆盖每个分支/循环/错误路径。写法：`LLR-<MOD>-nnn`，必须能一对一映射到代码结构。
- 每条需求必须**可验证**：有客观判据，禁止"正确处理"这类不可判定的表述。

### 6.2 追溯是双向的

`HLR ↔ LLR ↔ 代码 ↔ 测试 ↔ 覆盖`。CI 检查：
- 无测试的 HLR/LLR → 失败（"孤儿需求"）
- 无需求的代码（未被任何 LLR 覆盖的可执行语句）→ 失败（"意外功能"，DO-178C 明确要查的东西）
- 追溯矩阵由脚本生成，禁止手写（手写会漂移）

### 6.3 类型规约（对应 §1 对动态语言的要求）

`docs/cert/req/TYPES.md`：为认证范围内每个数据项声明**唯一类型**与**显式转换规则**，禁止依赖隐式转换；数值边界（Luau number 的整数精度 2^53、`INT`/`BIGINT` 的实际范围）必须写成需求并测试边界值。

---

## 7. 验证改革（现状做法完全不够）

现有 `SelfTest.luau` 是**开发者自测**，不是认证验证：无需求追溯、无覆盖度量、无独立性、无结果归档。

| # | 目标（DAL C） | 本项目的做法 | 工具 |
| --- | --- | --- | --- |
| 7.1 | 需求驱动测试：每条 HLR/LLR 有 ≥1 个用例 | `docs/cert/verify/*` + 用例 ID 与需求 ID 绑定；正常/边界/错误三类 | 自研 runner（`Dr.Testing` 需改造为可归档） |
| 7.2 | 100% statement coverage + 覆盖未达标的合理解释 | **可行，但机制已改**：`debug.sethook` 在 Lune 0.11.1 **不存在**（Step 7 实测）→ 改为**源码插桩 + `loadstring` + `setfenv`**，已端到端跑通（`docs/headless.md` §3） | 自研插桩器（§7.3） |
| 7.3 | 覆盖工具的产出可信 | 自研 statement 插桩器 + 对其做 DO-330 评估；**插桩器必须有自己的测试**（误插会高估→假绿），且其统计的可执行行须与 `debug.info` 的函数范围交叉校验（风险 R21）；**若鉴定不可行，覆盖率不得作为目标关闭的唯一证据**，需辅以人工复核 | `scripts/coverage.luau` |
| 7.4 | 类型与转换一致性（§6.7/6.7.1） | 见 §6.3：显式规约 + 边界测试 | `luau-lsp`（咨询） |
| 7.5 | **独立性**（DAL C 有 5 个目标要求独立） | ⚠️ **只能做到流程独立性，做不到组织独立性**：验证由**不共享上下文的另一个 agent 会话**执行并留证（本仓库已有先例：Step 3 的独立复审子代理）。真实 DER 不会接受这等同于组织独立性 —— **明确记录为偏差（deviation）**，不做虚假声明 | 子代理 + 证据归档 |

**明确不做**：MC/DC、目标码级验证、硬件/软件集成验证、面向 DAL A/B 的独立性。理由见 §0。

---

## 8. 配置管理与 SQA

| 活动（§1 来源的 7.2.x） | 落地 |
| 7.2.1 配置标识 | 认证范围模块在 `docs/cert/BASELINE.md` 逐文件登记 `路径 + sha256 + DAL + 需求 ID 范围` |
| 7.2.2 基线与追溯 | 每个 C-Phase 结束打 tag，生成基线记录；追溯矩阵随基线冻结 |
| 7.2.3 问题报告 | `docs/cert/PROBLEMS.md`：`PR-nnn` / 严重度 / 关联需求 / 处置 / 关闭证据 |
| 7.2.4 变更控制 | 认证范围文件的改动必须：PR + 影响分析（受影响需求/测试/覆盖）+ 评审记录。**已有的 `main` 提交守卫是这套机制的原始形态，继续用** |
| 7.2.5 变更评审 | 独立会话评审（§7.5 的偏差在此记录） |
| 7.2.6 状态记帐 | CI 产出 `docs/cert/STATUS.md`（目标关闭表：62 个目标 × 状态 × 证据链接） |
| 7.2.7 归档/检索/发布 | tag + 发布产物 hash；`docs/cert/ACCOMPLISHMENT.md` 汇总 |
| SQA | 独立的 SQA 检查单会话，**有权阻断合并**（对应门禁，见 `README.md`） |

---

## 9. 对现有计划的改动

### 9.1 新增 C-Phase（插在**继续写功能代码之前**）

**排期硬规则：C1–C3 未完成前，不得开始任何新的功能 Wave（D2.5 起、T0 起）。** 这是本次优化最重要的结论 —— DO-178C 要求**计划先于代码**，而我们已经写了 5k 行。

| Wave | 交付 | AC |
| --- | --- | --- |
| **C1** | 危害分析 + DAL 分配固化（§2）→ `docs/cert/HAZARD.md`。**已用 `p0-check`/`STEP` 流程证明可执行** | `AC-C1`：H1–H7 每条有 DAL、失效后果、被保护资产、对应模块；范围表（§3.1/3.2）逐模块勾选 |
| **C2** | 五份计划（PSAC-lite/SDP/SVP/SCMP/SQAP）+ 需求标准 | `AC-C2`：五份文件齐备且互不矛盾；62 个 DAL C 目标逐条标注"本项目如何关闭 / 为何不适用 / 偏差" |
| **C3** | 认证范围 HLR + `TRACE.md` 生成器 + CI 追溯检查 | `AC-C3`：追溯检查能**故意**报出孤儿需求与无需求代码；**含 1.5k 行既有代码的反向补需求**（§9.2） |
| **C4** | statement 覆盖工具 + 覆盖报告入库 | `AC-C4`：任意被测模块报告行覆盖率；未覆盖行必须落进问题报告或得到解释 |
| **C5** | 工具鉴定登记（§4.4）逐条关闭 + `stylua` 只读化 + AST 等价检查 | `AC-C5`：每件工具有 TQL 判定与理由；无一件"默认免鉴定" |
| **C6** | 配置管理机制化（基线/问题报告/状态记帐自动产出） | `AC-C6`：`BASELINE.md`/`PROBLEMS.md`/`STATUS.md` 由 CI 生成；故意改一个认证范围文件能触发变更控制流程 |

### 9.2 已写代码的处理（PDS 式评估）

| 既有内容 | 处理 |
| --- | --- |
| `Core/Foundation`（ErrorHandler/CoreTypes/Contract）· `Types/Contract` · `Diagnostics/Logging` | **落在认证范围外**（Logging 触碰 `game`/I/O）→ 冻结，标 DAL E；其中 `ErrorHandler`/`CoreTypes` 被核心依赖，故**反向补 HLR/LLR 并纳入范围**（约 0.5k 行）——这是晚开工的诚实成本 |
| `Runtime`（RunContext/FeatureFlags/…）· `Net` · `Security` · `Testing` · `Extensions` | 出范围，冻结，标 DAL E。允许继续演进，但**不得被认证核心 require**（I16 守卫） |
| 既有 `SelfTest`（10 个） | 保留为**开发者自测**；不得计入认证验证证据（CI 报告分开存放） |

### 9.3 新增不变量（并入 `README.md` §1）

| # | 不变量 |
| --- | --- |
| **I16** | **认证核心不得依赖非认证代码**（含 `game`、`Dr.Runtime`、`Dr.Net`、`Dr.Security`、`Dr.Diagnostics`、`Dr.Testing`）。CI 静态守卫，与 I14 同一机制 |
| **I17** | **边界输入一律防御性校验**：`Port` / `ResultSet` / `Codec` 三个接口的入参在核心内先验后用（§4.2） |
| **I18** | **需求先于代码**：认证范围内任何新代码必须先有 LLR；CI 检查"无 LLR 的新增认证范围文件" |
| **I19** | **确定性底座**：认证信用的测试只能跑在 `SimulatorPort` + 受控 Luau 上；碰网络/引擎的测试属产品线 |

### 9.4 其他文档的改动

| 文档 | 改动 |
| --- | --- |
| `README.md` | 文件地图加 `CERT.md`；新增门禁 10–12（追溯/覆盖/范围）；不变量 I16–I19；关键路径插入 C1–C6；风险登记加合规类 |
| `SCALE.md` | §2 预算表加"认证线/产品线/工具线"三分与 12k 硬上限；质量分档 A/B/C 改为"产品线分档"，与 DAL 解耦；§2.1 工作量按验证资产 ≥1.5× 重估 |
| `STEPS.md` | 插入 C1–C6 步骤并声明"功能 Wave 冻结"；DoD 增加"需求 ID / 覆盖 / 追溯"三项 |
| `TritiumSQL.md` | 每个模块标注 DAL；`Tri.Testing.SimulatorPort` 升级为**范围内的验证用模型**；绑定类明确出范围 |
| `Deuterium.md` | 明确只有纯底座在范围内；`D1.*`/`D2.*` 已完成波次标 DAL E |

---

## 10. 诚实的边界声明（写进发布说明）

1. 本仓库**没有、也不能获得 DO-178C 认证** —— 没有航空器、没有当局、没有 DER。它做的是**按 DO-178C 目标组织的工程与证据**。
2. 认证范围是**子集**（≤12k 行 / ≤40 模块）；范围外代码不主张任何 DAL。
3. 三项**已知偏差**，永久记录、不隐瞒：
   - **组织独立性缺失**（§7.5）—— 只能做到流程独立性。
   - **Luau 运行时与 Roblox 引擎不可鉴定**（§4.1）—— 用受控底座 + 边界隔离代替，形式上是 §12.1.3 类论证，未被当局认可。
   - **`stylua`/`rojo` 等工具未鉴定**（§4.4）—— 靠"不改写认证文件 + 人工评审 + AST 等价检查"回避对鉴定的依赖。
4. **如果目标其实是"可靠性工程"而不是"适航合规"**：本计划 90% 的工作（需求、追溯、覆盖、变更控制、问题报告）仍然值得做；但 §4 的工具鉴定与 §5 的 16 项生命周期数据成本可以减半。**建议先确认目标，再决定是否全量执行。** 这个问题必须在 C1 之前回答。

---

## 11. 出处

| 用途 | 来源 |
| --- | --- |
| DAL 目标数/独立性 | https://www.rti.com/blog/rtca-do178c-certification ；https://www.spilma.com/en/guides/do-178c-do-254-avionics ；https://www.do178.org/do178_introduction.html |
| 结构覆盖分级 | https://learn-latest.adacore.com/booklets/adacore-technologies-for-airborne-software/chapters/analysis.html ；https://ldra.com/ldra-blog/do-178c-structural-coverage-analysis/ |
| MC/DC n+1 | https://ldra.com/capabilities/mc-dc/ |
| DAL 与失效后果 | https://www.rapitasystems.com/blog/whats-difference-between-sil-and-dal-how-does-it-affect-my-code-coverage |
| DO-330 TQL 表 | https://www.rapitasystems.com/do-330 |
| §12 / 12.1.3 | https://cdn.vector.com/cms/content/know-how/aerospace/Documents/Complete_Verification_and_Validation_for_DO-178C.pdf |
| COTS / PDS | https://ee-aero.com/glossary/cots-reused-software/ ；https://www.casa.gov.au/approval-software-and-electronic-hardware-parts |
| SCM 7.2.x / CC1·CC2 | https://www.faa.gov/sites/faa.gov/files/aircraft/air_cert/design_approvals/air_software/differences_tool.pdf ；https://www.adacore.com/uploads/books/DO178C-ED12C-Changes_and_Improvements-Sep2012.pdf |
| 遗留/复用软件评估 | https://www.faa.gov/documentlibrary/media/advisory_circular/ac_20-115c.pdf |
| Lua/动态语言先例 | https://elib.dlr.de/216695/1/2_design_approach_final.pdf ；https://doi.org/10.1109/dasc62030.2024.10748678 ；https://doi.org/10.1016/j.cola.2025.101383 |

---

未读/未验证：DO-330 准则 2、3 的 TQL 映射（只核实到准则 1）；DO-178C 原文的 Table A-1…A-10 目标编号（本文件按公开二级资料的目标**数量**与**覆盖率要求**编写，未逐条核对标准原文）；`debug.sethook` 在 Lune 0.11.1 中是否可用于行级覆盖（**这是 C4 的第一步，必须先做成功性探针**——若不可用，DAL C 的 7.2 目标无法关闭，DAL C 本身也要重新评估）。
