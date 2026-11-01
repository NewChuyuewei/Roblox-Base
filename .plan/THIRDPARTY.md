# 第三方依赖集成契约（Scribe · QuickZone）

> 决策：**把 Scribe 与 QuickZone 集成进框架**（用户 2026-10-25 决定，决策 D11）。
> **不计入 10 万行目标，也不计入 440 模块数**（见 §5）。
> 本文件是第三方依赖的**唯一权威**：集成方式、所有权划分、审计义务、不变量。

---

## 1. 实测事实（不是推测）

| | **Scribe** | **QuickZone** |
| --- | --- | --- |
| 位置 | `src/ReplicatedStorage/Scribe/` | `src/ReplicatedStorage/QuickZone/` |
| 规模 | **46 文件 / 42,077 行**（上游 `Scribe-main`） | 13 文件 / **6,534 行**（上游 `QuickZone-main`） |
| 版本 | **v2.6.1**（`Internal/Version.luau`，与 `wally.toml` 一致）+ 内容哈希 `3d797da3` | **v1.5.1**（头部 `--v1.5.1 • LDGerrits`）+ 内容哈希 `9babdda8` |
| LICENSE | **MIT**：`LICENSE`（+ `NOTICE`）留档于 `docs/thirdparty/Scribe/`；被 fork 的 ProfileStore 另有 `licenses/ProfileStore-Apache-2.0.txt` | **MIT**：`LICENSE.md` 留档于 `docs/thirdparty/QuickZone/` |
| 入口签名 | `require(Scribe) -> { Server, Client }`；**一个共享模块声明模板与选项** | 单例对象 + 方法：`configure/setEnabled/update/rebuild/setReference/setFrameBudget/getZonesAtPoint/iterZonesOfEntity/visualize` … |
| 自带子模块 | `Internal/{Log, Metrics, Health, Budget, Signal, Sched, Transport, Wire, Store/ProfileStore}` · `Server/{ServerStore, Persistence, Replication, Leaderboards, Monetization, Exchanges, Analytics, Commands, Timed}` | `Core/{PlayerTracker, Scheduler, State}` · `Utils/{Geometry, LinearBVH, Log}` · `Classes/{Zone, Zones, Group, Observer}` |
| 引擎触点 | 35× `game:GetService(` · 14× `DataStoreService` | `RunService` + 空间查询，无 DataStore |
| 后门面 | 无 `loadstring`、无数字 id `require` ✓ | 同 ✓ |
| 类型求解器要求 | 头部注明「typed accessor tree 需要新版 Luau 类型求解器；没有它也能运行（用 `.Raw` 逃逸）」 | 无 |

**规模认知（必须先接受这个事实）**：Scribe 一个库 ≈ **框架本体（5,486 行）的 7.7 倍**；两者合计 **48,611 行**。规格写「唯二例外」时显然不是这个量级。

## 2. 所有权划分（本文件最要紧的一张表）

Scribe 的能力范围**远超**规格原先设想的「PlayerData + Replica 封装」。不划清就会两边都造一遍。

| 能力 | **归谁** | 决策依据 |
| --- | --- | --- |
| 玩家数据持久化（模板/默认值/迁移/会话） | **Scribe** | 它已有 `Server/ServerStore` + `Persistence` + `Template` + `Conforms` |
| 客户端复制（自动、按需可见性） | **Scribe** | 已有 `Server/Replication` + `Internal/{Transport, Wire}` + `Visibility` 类型 |
| 经济（购买/兑换/货币/幂等） | **Scribe** | 已有 `Monetization/Exchanges/ExchangeLeg/ExchangeVerdict`；我们**不再自研** |
| 排行榜 | **Scribe** | 已有 `Leaderboards` + `LeaderboardEntry` |
| 分析上报 | **Scribe（Server/Analytics）** | 归它，但我们可加自己的 Sink |
| 玩家数据侧的日志/指标/健康 | **Scribe 内部**，不向外暴露 | `Internal/{Log,Metrics,Health}` 是**库内部**实现，不是框架级设施 |
| 空间查询（分区/区域/观察者） | **QuickZone** | 与规格原计划一致（`Dr.World.Spatial` 三件套） |
| 玩家位置追踪 | **QuickZone `Core/PlayerTracker`** + 我们的 `Dr.Runtime.Platform.InstanceTracker` | 职责划清：引擎实例生命周期归我们，空间位置归它 |
| 框架级日志/可观测 | **我们**（`Dr.Diagnostics.Logging`，已交付 5 文件） | 见 §4「不合并」 |
| 框架级 Signal / 调度 | **我们**（`Dr.Signal` / `Dr.Concurrency.Scheduling`） | 两库各自内部也有一份，属**库内部**，不共享、不替换 |
| 序列化 Codec | **我们**（I9 唯一 Codec）**+ 第三方内部实现豁免** | Scribe 的 `Wire/Transport` 是它自己的线上格式，我们不进去改 |
| 事务/WAL/崩溃恢复 | **我们**（TritiumSQL `Tri.Txn`/`Tri.Wal`） | Scribe 有 Budget/Health，**没有** WAL/事务语义 |
| ECS / 场景 / 对象管理 | **我们**（`Dr.ECS` / `Dr.World.Scene`） | 无重叠 |

**结论：`Dr.Data` 与 `Dr.State` 从「自研实现」收缩为「适配 + 迁移 + 与 TritiumSQL 的桥」。** 原计划里 `Dr.Data.Store`/`Dr.Data.Processing`/`Dr.State.Sync` 的大部分波次**取消或大幅收缩**（见 §6）。这一条省下的工作量很大，也消掉了「同一件事做两遍」的风险。

## 3. 集成方式：适配器，不是直接调用

**新增不变量 I20（第三方只经适配器）**：`src/ReplicatedStorage/Deuterium/**` 内**除下列目录外**，不得 `require` 到 `Scribe`/`QuickZone`。由门禁强制（`scripts/thirdparty-check.luau`，随本文件交付）。

| 适配器（我们写的，计入我们的行数） | 包住什么 |
| --- | --- |
| `Dr.Data.Adapter.ScribeAdapter` | Scribe 的 `Server` 入口：模板声明、会话开/关、读写、迁移钩子 |
| `Dr.State.Adapter.ScribeReplica` | Scribe 的 `Client` 入口：把复制出来的数据接到我们的响应式 Store/Atom |
| `Dr.Data.Adapter.TritiumPersistenceBridge` | Scribe（会话态）↔ TritiumSQL（持久关系表）的桥；Saga 协调在 `Dr.Data.Reliability.Transaction` |
| `Dr.World.Adapter.QuickZoneAdapter` | QuickZone 单例：初始化、重建、帧预算、观察者/区域到我们的 World/ECS 实体映射 |
| `Dr.Runtime.Adapter.ThirdPartyLifecycle` | 两库的启动/关闭顺序、失败隔离（Bulkhead）、健康上报接入我们的 `Dr.Diagnostics` |

**三条硬规则**：
1. 适配器里**只做翻译**：不得把 Scribe/QuickZone 的类型泄漏到框架公共 API（对外只暴露我们自己的类型）。
2. 引擎触点集中：两个库各自的 `game:GetService` 是**已登记的 I10 例外**（§4），我们**不新增**对引擎的直接调用。
3. 版本升级 = 换上游目录 + 重跑适配器契约测试；适配器不得依赖上游内部路径（只用公开入口）。

## 4. 对既有不变量的影响（必须显式登记，否则不变量就成空话）

| 不变量 | 影响 | 处置 |
| --- | --- | --- |
| **I9 一份 Codec** | Scribe 自带 `Internal/Wire`/`Transport` | **豁免声明**：库内部的线上格式不属我们的 Codec；**但我们的代码（含适配器）不得再引入第二个 Codec** —— TritiumSQL 仍只用 `Dr.Types.Transform.Codec` |
| **I10 引擎 API 单一出入口** | 两库合计 35+ 处 `game:GetService` | **登记为例外**：例外清单从「TritiumSQL Standalone 绑定」扩展为「+ `Scribe/**`、`QuickZone/**`」。规则不变：**我们自己写的代码**不得新增引擎调用点 |
| **I16 认证核心不依赖非认证代码** | 两库是无可鉴定的 COTS/PDS | **强化**：认证核心不得 require 它们；门禁 10 的 B 段（依赖闭包）已能拦。适配器也在认证范围外 |
| I14（Dr→Tri 只在 `Dr.Integration`） | 不受影响 | 保持 |
| **新增 I20** | 第三方只经适配器 | 门禁强制 |
| **新增 I21** | **不重复造**：Scribe 已有的能力（玩家数据/复制/经济/排行榜）不在 `Dr.Data`/`Dr.State` 里重实现 | 评审 + §2 所有权表 |

## 5. 与 10 万行目标的关系（用户明确要求）

**Scribe 与 QuickZone 不计入 100,000 行，也不计入 440 模块数。**

| 项 | 计入 100k？ | 理由 |
| --- | --- | --- |
| `Scribe/**`（42,077 行）· `QuickZone/**`（6,534 行） | **否** | 不是我们的产出；其维护成本不随我们的预算增长；且它们有独立的上游生命周期 |
| **适配器**（§3 的 5 个模块） | **是** | 我们写的、要维护、要测 |
| `Overrides/` 补丁层（若将来需要） | **是** | 同上 |
| 第三方侧的**测试**（契约测试） | **是** | 我们写的，且是接入的质量保证 |

因此 `SCALE.md` §2 的预算表新增一行「第三方（不计入）」，`scripts/loc-budget.luau`（待建）按路径排除 `src/ReplicatedStorage/{Scribe,QuickZone}/**`，并在报告里**单独显示**其行数以免被当成"进度"。

**副作用（必须承认）**：仓库从 ~5.5k 行变成 ~50k 行，且其中 **90% 不是我们写的**。`git log`、评审、`grep` 的噪声都会变大。缓解：门禁范围已排除两棵树（`stylua`/`analyze` 只跑我们的目录）。

## 6. 对现有计划的改动

| 位置 | 改动 |
| --- | --- |
| **`Deuterium.md` 规格 §2/§3** | ① Scribe 的角色描述**错了**：它不是「日志/观测」，而是玩家数据/复制/经济/排行榜库；② `PlayerState` **取消**（Scribe 自带 ProfileStore，已覆盖其职责）→ 决策 D2/D2-bis 结案；③ 例外清单从「Scribe + PlayerState + QuickZone」改为「**Scribe + QuickZone**」 |
| `D4.x` 会话态与状态 | **大幅收缩**：`D4.1`（PlayerState 审计+内置）**取消** → 改为「Scribe 适配」；`D4.2`/`D4.7`（PlayerData / Replicator 自研）**取消** → 改为适配器；`D4.5`/`D4.6`（State 响应式/状态机）**保留**（Scribe 无此能力）；`D4.3`（Saga 协调）保留并扩展为「Scribe ↔ TritiumSQL」桥 |
| `D6.6` 世界层 | `Dr.World.Spatial` 三件套改为 **QuickZone 适配器**（规格原意）；`Dr.World.Scene` 仍自研 |
| 设备/波次 | **D0.6 第三方集成准备（2026-10-26 部分完成）**：① 审计五步已机器化关闭 ✅（`scripts/thirdparty-audit.luau` + `docs/thirdparty/AUDIT.md`/`LOCK.txt`）② 审计器同时就是 ③ 里的 `thirdparty-check`/I20 门禁 ✅（已进 CI）→ **剩余：5 个适配器骨架**（随 D4.x/D6.6 落地） |
| 认证线 | 两棵树**明确列为范围外 COTS**；适配器也在范围外。`scope.txt` 不加任何 Scribe/QuickZone 文件 |

## 7. 审计义务（D11 的剩余部分）—— **审计已机器化关闭（2026-10-26）**

规格 §2 的五步（锁版本 → 全量审计 → 剥离 → Overrides → 留档）已交付**可复现的工具链**，不再是纸质承诺：

| 步 | 状态 | 证据 / 关闭动作 |
| --- | --- | --- |
| 1 锁版本 | ✅ **已关闭** | Scribe `2.6.1`（`Internal/Version.luau`）+ QuickZone `1.5.1`；各自的**内容哈希**与文件/LOC/字节数写入 `docs/thirdparty/LOCK.txt`（升级后跑 `--write-lock` 重建） |
| 2 全量审计（找后门面） | ✅ **已关闭（按可达闭包）** | 机器扫描：`loadstring`/`getfenv`/`setfenv`/`getgenv`/`debug.getinfo`/`debug.setupvalue`/数字 `require`/`_G.`/**网络出口**（`HttpService:{Get,Post,Request}Async`）→ **0 违规**。`HttpService` 其余用法（`JSONEncode`/`GenerateGUID`）已核为良性。**1 处动态 require 经审阅登记为接受**（`Server/Persistence.luau` 的 `require(injected)`，注入点由我们的适配器控制） |
| 3 剥离 | ◐ **按需收敛** | **不改上游文件**（否则升级要手工合并）→ 改为**按入口收敛审计面**：`init.luau` 46/46 文件、`Server/init.luau` 43 文件、`Client/init.luau` 22 文件（数字见 `docs/thirdparty/AUDIT.md` §3）。真删文件等适配器定下入口集 |
| 4 Overrides 层 | ✅ **约定已立** | 适配器优先、**不改上游**；必须改时放 `Overrides.luau`（我们写的，计入预算）。`LOCK.txt` 会拦下任何未登记的改动 |
| 5 留档 | ✅ **已关闭** | `docs/thirdparty/{Scribe/{LICENSE,NOTICE,licenses,wally.toml},QuickZone/{LICENSE.md,wally.toml}}` + `AUDIT.md`（生成物）+ `LOCK.txt` + 本节 |

**审计的规模要说清**：Scribe 42,077 行做「全量人工审计」不现实。本项目的做法是**机器化的入口收敛审计**：`scripts/thirdparty-audit.luau` 先算 require 可达闭包（**形状不认识就报错，不静默跳过** —— 漏边会让闭包假小），再对闭包内文本做后门面扫描。它同时是 I20 门禁，进出 CI。

**升级上游的流程（runbook）**：① 取上游新副本 → ② `cp -r <上游>/src/. src/ReplicatedStorage/<Lib>/` → ③ `lune run scripts/thirdparty-audit.luau`（看违规与闭包变化）→ ④ 人工复核 §2 的引擎触点清单变化 → ⑤ `--write-lock` 重建锁 → ⑥ 重跑适配器契约测试。**任何一步跳过都会让锁与审计失真。**

---

未读/未验证：闭包口径是 **require 静态可达**（不含运行期才访问的路径，如通过 Scribe 自身的 DI 逃逸口加载的模块）；`game:GetService` 的**调用时序**未验证；上游 **commit/tag 未在本地核对**（无网络），锁定依据是内容哈希；Scribe 的 33 个导出类型未逐个理解语义；QuickZone 的 `configure` 参数与帧预算语义未读。**headless 实测**见 `MEMORY.md` §1.1.1：Scribe 三入口可装载、QuickZone 因桩缺 `:Connect` 面不可装载。
