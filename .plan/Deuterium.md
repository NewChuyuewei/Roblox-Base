# Deuterium — 实施计划

> **规格基线**：`../Deuterium/Deuterium.md`（不重写，按本文档 §2 的清单打补丁）
> **权威划分**：不变量/门禁/决策/风险 → `README.md`；规模与预算 → `SCALE.md`；执行步骤 → `STEPS.md`；与 SQL 的互通 → `INTEGRATION.md`；**DAL 与认证约束 → `CERT.md`**。
> ⚠ 在 DO-178C 下，本项目的框架**只有纯底座进入认证范围**（`Core/Foundation` + `Types` + `Collections` + `Memory` + `Concurrency`，约 1,400 行）；`Runtime`/`Net`/`Security`/`Diagnostics`/`ECS`/`World` 全部是 **DAL E、出范围**且不得被认证核心 require（I16）。
> Wave ID 统一为 `D<phase>.<wave>`。

---

## 1. 环境审计（改写的依据）

| 项 | 实测 |
| --- | --- |
| 代码量 | **69 个 `.luau`，4,894 行**（`Core` 21/1,432 · `Net` 23/1,870 · `Runtime` 14/958 · `Security` 2/241 · `Testing` 5/304 · `Types` 3/47 · `Extensions` 1/42） |
| 覆盖 | `D1.1`–`D1.7` 全部 + `D2.2`–`D2.4` + `Dr.Security.Crypto` 的 Hmac/Sha256 |
| 缺失 | `D0.*`、`D2.0/2.1/2.5/2.6b/2.7`、`D3.x`、`D4.x`、`D5.x`、`D6.x`、`D7.x`、`D8`；`Core/Foundation` 缺 EventLoop/Context/Metadata |
| 工程 | **无** Rojo 工程文件、`.luaurc`、selene/stylua 配置、`AGENTS.md`、`MEMORY.md`、`Libraries/` |
| 依赖 | 18 个文件 `require(game:GetService("ReplicatedStorage"):WaitForChild("Debug"))`，而 **`Debug` 模块不存在** → 仓库当前无法加载 |
| CI | `.gitlab-ci.yml` 仅继承 GitLab 默认 SAST 模板；无构建/测试/静态检查 |
| 测试 | 全部 `SelfTest` 为 Studio 命令栏手工触发，CI 不覆盖 |

**结论**：代码质量与设计意图一致（`--!strict`、`table.freeze` 导出、每模块配 SelfTest、Kernel 用 `xpcall` 做单 provider 级故障隔离），但当前状态是「**不可运行**」而非「可运行」——任何新 Wave 动工前必须先补齐 `D0.1`（对应风险 R1）。

---

## 2. 规格修订清单（应用于 `Deuterium/Deuterium.md`）

| 位置 | 现状 | 改为 |
| --- | --- | --- |
| §0 不变量 | I1–I7 | 保留；追加一行指向本计划 `README.md` §1 的 I8–I15 |
| §1 `Dr.Data` | Store/Reliability/Processing/Observe 四组，与 TritiumSQL 重叠 | 收窄为会话态：`Core` + `Store`（PlayerData/EphemeralData）+ `Reliability.Transaction`（**跨存储 Saga 协调者**）+ `Processing.Migrator`。其余标注「▶ 见 TritiumSQL」（I8） |
| §1 `Dr.State.Sync.Replicator` | 底层 PlayerState Replica | 不变（复制 ≠ 持久化）；数据源增加 G4 的变更流 |
| §1 `Dr.Signal` | 排在 SERVICE 层 | **提前到 `D2.0`** —— Knit 把 Signal 当基础设施，没有它 I13 薄入口立不住 |
| §3 `PlayerState` | 「数据/复制基底」 | **取消**：Scribe 自带 `Internal/Store/ProfileStore` 且就是玩家数据/复制载体 → PlayerState 的存在理由消失（D2/D2-bis 结案） |
| §3 `Scribe` | 「日志/观测」 | ❌ **描述错了**。实测 Scribe 是**玩家数据/复制/经济/排行榜库**，并自带 `Log/Metrics/Health/Signal/Sched/Transport/Wire`。框架级日志仍是我们自己的 `Dr.Diagnostics`；两库内部的 Log 是**库内部实现**，不向外暴露 |
| §3 `QuickZone` | 「计划内置 `^1.4.x`」 | 实际已入库且为 **v1.5.1**；集成方式、所有权与适配器见 `THIRDPARTY.md` |
| §0 不变量 | I1–I15 | 追加 **I20**（第三方只经适配器）与 **I21**（不重复造）—— 定义在 `README.md` §1，理由在 `THIRDPARTY.md` |
| §3 外部依赖 | — | 增加 Scribe 审计留档要求 + 「TritiumSQL 存储层被 DataStore 封顶」声明（`SCALE.md` §1.2） |
| §4 目录落地 | `src/ReplicatedStorage/Deuterium/...` | 现树：`Deuterium/` → Rojo 映射 `ReplicatedStorage.Deuterium`（决策 D8） |
| §5.4 性能 | — | 增加一条：集成层（G 路径）的请求次数同样受 I12 约束 |
| §7 CI | 「后续加 TestKit 伪 headless」 | Lune headless（决策 D4），`D0.1` 交付 |
| §8 `D4.3`/`D4.4` | Reliability / Processing 大部分波次 | 删除，指向 `TritiumSQL.md`；`D4.x` 只剩会话态 + 迁移 + 适配器 |
| §8 `D5.1–5.3` | 集合/内存/缓冲 | 抽到 `D0.3`（TritiumSQL 硬依赖） |
| §8 `D6.1` | 日志/观测 | 最小集抽到 `D0.1`（`Debug` 与门禁 4 的依赖） |
| 全文 | 引用 `AGENTS.md`、`docs/dones/`、`MEMORY.md` 但均不存在 | `D0.1` 创建 |

---

## 3. Wave 计划

> 每个 Wave 的验收 ID 为 `AC-D<wave>`；完成判据的可执行版本在 `STEPS.md`。
> 区域 LOC 预算见 `SCALE.md` §2（本体 26,000 核心 + 9,000 测试）；本体完整模块清单仍在规格 §1。

### D0 · 工程骨架与前置件（阻塞全部）

| Wave | 交付 | AC |
| --- | --- | --- |
| **`D0.1`** | 工具链与工程骨架：`default.project.json`（Rojo 映射）· `Debug` + `Logger`/`LogSink`/`StructuredLog`（`D6.1` 最小集）· `.luaurc` · `stylua.toml` · `selene.toml` · `scripts/p0-check.sh` · `.gitlab-ci.yml` 四阶段 · `AGENTS.md` · `MEMORY.md`（Scribe 审计） | `AC-D0.1`：CI 四阶段全绿；`require(ReplicatedStorage.Debug)` 可用；Scribe 审计结论留档（决策 D6 关闭） |
| **`D0.2`** | `Dr.Core.Foundation` 补件：`Metadata` · `Context` · `EventLoop` | `AC-D0.2`：Metadata ↔ Reflection 互通；`Context.With` 不改父袋（父袋键数不变） |
| **`D0.3`** | Foundation 前置件（14 件，逐件实现+单测）：`HashMap` `LRUCache` `PriorityQueue` `RingBuffer` `Queue` `Set` · `ByteBuffer` · `ObjectPool` `TablePool` · `Mutex` `AsyncQueue` `TaskScheduler` `Promise` · `Primitives` `Validation` · **`Transform.Codec`（I9 唯一 Codec）** · `Dr.Testing.Integration`：`DataStoreSimulator` + `RequestAssert` | `AC-D0.3`：每件至少正常/边界/失败三例；LRU 逐出顺序有断言；RingBuffer 背压有断言；Simulator 支持故障注入并统计请求次数；Codec round-trip 稳定，`Dr.Net` 改为调用它后 Net SelfTest 仍绿 |
| **`D0.4`** | `Dr.Runtime.Platform` 端口：`DataStoreProxy` · `MemoryStoreProxy`（请求计数 / 配额节流 / 故障注入），签名与 Simulator 一致 | `AC-D0.4`：`grep DataStoreService Deuterium` 只命中这两个文件；代理与模拟器互换后上层测试无需改动 |
| **`D0.5`** | **端到端纵切**（`SCALE.md` §6）：内存版全链，允许脏 | `AC-D0.5`：链路在 Studio 与 CI 各跑通一次；产出 `.plan/SEAMS.md`；耗时 ≤3 天。**这是横铺（Step 14 起）的准入条件** |

### D1 · 运行时与微内核（已完成，登记不重做）

| Wave | 交付 | 文件 | 状态 |
| --- | --- | --- | --- |
| `D1.1` | `Dr.Runtime.Environment`（RunContext/EngineVersion/FeatureFlags）+ `RuntimeTypes` | 4 + 1 | ✅ 未验证 |
| `D1.2` | `Dr.Runtime.Platform`（ServiceLocator/InstanceTracker/PhysicsProxy） | 6 | ✅ 未验证 |
| `D1.3` | `Dr.Runtime.Interop`（Legacy/ExternalBridge）+ `ServerRegistry`/`ServerBrowser` | 3 + 2 | ✅ 未验证 |
| `D1.4` | `Dr.Core.Container`（Kernel/ServiceContainer/DependencyInjector/ServiceRegistry/ScopeContainer/Types） | 7 | ✅ 未验证 |
| `D1.5` | `Dr.Core.Lifecycle`（Lifecycle/ModuleLoader/Configuration/BootSequencer/HotReload/ShutdownManager） | 7 | ✅ 未验证（缺 `Dr.Core.Foundation` 三件 → `D0.2`） |
| `D1.6` | `Dr.Core.Reflection` + `Dr.Types.Contract` | 4 + 3 | ✅ 未验证 |
| `D1.7` | `Dr.Testing`（Runner/Suite/Assert/TestContext）+ `Extensions.Demo` | 5 + 1 | ✅ 未验证 |

**DAL 归属（`CERT.md` §3）**：`D1.*`/`D2.2–2.4` 已完成的全部内容均为 **DAL E、认证范围外**，冻结；它们**不得被认证核心 require**（I16 守卫）。`Core/Foundation` 与 `Types` 被核心依赖，因此必须以 **PDS 式反补 HLR/LLR** 后纳入范围（`CERT.md` §9.2，约 0.5k 行）—— 这是晚开工的诚实成本。

> 「未验证」= 文件与 SelfTest 齐备，但未在任何环境跑通。`STEPS.md` Step 10 之后本列全部转 ✅。

### D2 · 网络与安全

| Wave | 交付 | AC |
| --- | --- | --- |
| `D2.0` | `Dr.Signal`（Signal/Connection/AsyncSignal/PrioritySignal/ThrottledSignal + EventBus/EventEmitter/Subscription/TopicBus）：从 SERVICE 层提前 | `AC-D2.0`：优先级顺序稳定；断连后无泄漏（连接数归零断言） |
| `D2.2` | `Dr.Net.Core` + `Dr.Net.Bridge` | ✅ 未验证 |
| `D2.3` | `Dr.Net.Processing` = NetCodec v1 | ✅ 未验证（待 `D0.3` 的 Codec 合并，I9） |
| `D2.4` | `Dr.Net.Security` | ✅ 未验证 |
| `D2.5` | `Dr.Security.Access`（Permission/Guard/PolicyEngine/CapabilityToken）+ `Input`（Sanitizer/Validator/ContentFilter/SchemaEnforcer） | `AC-D2.5`：RBAC 图谱 Init 期编译（运行期零解析）；非法请求 100% 拒绝且原因结构化 |
| `D2.6b` | `Dr.Security.Crypto`（TokenGenerator/Obfuscator）+ `Monitor`（AntiExploit/Fingerprint/AuditLog/ThreatDetector/BanManager/SecurityDashboard） | `AC-D2.6b`：日志经 Scribe；禁令生效后重连被拒 |
| `D2.7` | `Dr.Security.Compliance`（DataPrivacy/RateLimitPolicy/AbuseReporter）+ 全链联调 | `AC-D2.7`：作弊样本集 0 误放行；AuditLog 字段完整 |

> `D2.1`（`Dr.Types.Primitives`/`Validation`）已并入 `D0.3`。

### D3 · 弹性（HA）— 分两批

| Wave | 交付 | AC | 批次 |
| --- | --- | --- | --- |
| `D3.1` | `Dr.HA.Circuit`（CircuitBreaker/CircuitState/CircuitRegistry） | `AC-D3.1`：关→半开→开状态机 + 锯齿边界用例过 | **先做**（TritiumSQL 依赖） |
| `D3.2` | `Dr.HA.Recovery`（RetryPolicy/Timeout/Fallback/Bulkhead/Hedging） | `AC-D3.2`：重试曲线含 ±10% 抖动；Hedging 下副作用只发生一次（计数器断言） | **先做**（TritiumSQL 依赖） |
| `D3.3` | `Dr.HA.Resilience`（Timeout/LoadShedder/AdaptiveConcurrency） | `AC-D3.3`：看门狗压测下内存与吞吐不下滑 | 后做 |
| `D3.4` | `Dr.HA.Monitor`（Watchdog/RateLimiter/SLATracker）+ ProfileStore 适配 | `AC-D3.4`：人为断网 60s 不雪崩；重连 30s 内自愈 | 后做 |

### D4 · 会话态与状态（已按 I8 收窄）

| Wave | 交付 | AC |
| --- | --- | --- |
| `D4.1` | PlayerState 审计 + 内置 → `Dr.Data.Core`（DataManager/DataTypes/DataPipeline/DataRegistry） | `AC-D4.1`：走规格 §2 五步流程；CRUD 单测过 |
| `D4.2` | `Dr.Data.Store`（PlayerData/EphemeralData/ComputedData） | `AC-D4.2`：写入强制走六段流水；旁路代码静态不可调通 |
| `D4.3` | `Dr.Data.Reliability.Transaction`（**仅 Saga 协调者**）+ `SessionLock` | `AC-D4.3`：跨存储（会话态 ↔ TritiumSQL）任一步中断逆序回滚、成果归属明确 |
| `D4.4` | `Dr.Data.Processing.Migrator`（会话态版本迁移）+ `Observe.Changelog` | `AC-D4.4`：多轮 v0→v3 各自走通 |
| `D4.5` | `Dr.State.Core`（Store/Atom/StateGraph）+ `Reactive`（Computed/Observer/Selector/Reaction） | `AC-D4.5`：反应链表达树去重，不重复求值 |
| `D4.6` | `Dr.State.Machine`（StateMachine/StateChart/Transition）+ `History`（UndoRedo/StateHistory） | `AC-D4.6`：状态机切换可倒序回溯出中间值 |
| `D4.7` | `Dr.State.Sync`（Replicator/Reconciler/SyncPolicy/ConflictResolver）；数据源接 G4 变更流 | `AC-D4.7`：多端同改同字段结果一致；server-wins 默认走通 |

> ⚠ **第三方集成后 `D4.x` 大幅收缩（`THIRDPARTY.md` §2/§6）**：
> - `D4.1`（PlayerState 审计 + 内置）**取消** → 改为 Scribe 审计与适配
> - `D4.2`（`Dr.Data.Store.PlayerData` 自研）**取消** → 由 `Dr.Data.Adapter.ScribeAdapter` 承担
> - `D4.7`（`Dr.State.Sync.Replicator` 自研）**取消** → 由 `Dr.State.Adapter.ScribeReplica` 承担
> - `D4.3`（Saga 协调）**保留并扩展**为「Scribe 会话态 ↔ TritiumSQL 持久表」的桥
> - `D4.5`/`D4.6`（响应式 Store / 状态机 / 历史）**保留** —— Scribe 无此能力，属我们
>
> ⚠ `D6.6` 的 `Dr.World.Spatial` 三件套改为 **QuickZone 适配器**（规格原意）；`Dr.World.Scene` 仍自研。
>
> **新增 `D0.6` · 第三方集成准备**（在 D0.3 之前或并行）：
> ① 审计五步（顺序：**先剥离再审计**） ② 5 个适配器骨架（`THIRDPARTY.md` §3） ③ `scripts/thirdparty-check.luau` 门禁（I20）。
>
> `D4.8`（TritiumAdapter）已升级为完整集成层 `Dr.Integration`（18 模块），见 `INTEGRATION.md` §5.1 与 `STEPS.md` Step 50–57。
> ▶ 原 `D4.3`（MVCC/WAL/Checkpoint）与 `D4.4`（QueryEngine/Cache/DataValidator）→ `TritiumSQL.md` 的 `T3`。

### D5 · 性能（余量）

| Wave | 交付 | AC |
| --- | --- | --- |
| `D5.2` | `Dr.Collections.Spatial`（SpatialHash/QuadTree/Octree/BVH）+ `Advanced`（Trie/Graph） | `AC-D5.2`：1e4 区域预筛 @60fps |
| `D5.3b` | `Dr.Memory` 剩余（Instance/Buffer/StringPool）+ `Lifecycle`/`Monitor` | `AC-D5.3b`：玩家下场后句柄零遗留 |
| `D5.5` | `Dr.ECS.Core`（World/Entity/Component/WorldRegistry）+ `Storage`（SparseSet/ChunkedStorage/ComponentPool） | `AC-D5.5`：5000 实体更新 < 1ms/帧 |
| `D5.6` | `Dr.ECS.Query` + `Execution`（System/Scheduler/CommandBuffer/SystemGroup/ExecutionPipeline） | `AC-D5.6`：CommandBuffer 延迟到下一帧才生效 |
| `D5.7` | `Dr.ECS.Prefab` + NetCodec 带宽基准（合并 `D0.3` 的 Codec 后复测） | `AC-D5.7`：关键链路带宽降 ≥60%（含数字报告） |

> `D5.1`（集合）与 `D5.3a`（池/缓冲）已抽到 `D0.3`。

### D6 · 工具 / 世界层

| Wave | 交付 | AC |
| --- | --- | --- |
| `D6.1b` | `Dr.Diagnostics.Logging` 完整（LogAggregator/采样/标签约束） | `AC-D6.1b`：标签约束生效；可采样定性 |
| `D6.2` | `Profiling`（Profiler/MemoryProfiler/NetworkProfiler/FrameProfiler/HotspotDetector）+ `Trace`（TraceContext/Span/TraceExporter） | `AC-D6.2`：每决策点有 Trace；热点报告可产出 |
| `D6.3` | `Monitor`（Metrics/HealthCheck/Dashboard/Alerting/SLO）+ `Debug`（Inspector/Breakpoint/REPL） | `AC-D6.3`：SLO 可人工调用；REPL 沙箱隔离 |
| `D6.4` | `Dr.Util`（Math/String/Data/Time/Animation/Pattern） | `AC-D6.4`：全部按 P0 规则写就（`p0-check.sh` 不上升） |
| `D6.5` | `Dr.Plugin`（PluginManager/PluginHost/Hook/MiddlewarePipeline/Extension） | `AC-D6.5`：动态增删插件不重启 |
| `D6.6` | `Dr.World`（SceneManager/SceneGraph/SceneTransition；Spatial = QuickZone 审计内置后接入） | `AC-D6.6`：QuickZone 过审计，Overrides 不改上游本体 |

> `D6.1` 最小集已抽到 `D0.1`。

### D7 · 发布与生态（「堪比 Knit」的落地）

| Wave | 交付 | AC |
| --- | --- | --- |
| `D7.1` | 薄入口门面 `API/Deuterium.luau`（I13） | `AC-D7.1`：公共导出 ≤40 符号；三个概念、五行代码可跑 |
| `D7.2` | `Component` 语义补件（补齐 Knit 三分的第三分） | `AC-D7.2`：组件挂载/卸载生命周期单测 |
| `D7.3` | 文档站（moonwave 或 MkDocs）+ API 参考 | `AC-D7.3`：全部公共符号有页；构建进 CI |
| `D7.4` | `examples/`：最小 · 带持久化（走 TritiumSQL）· 带客户端复制 | `AC-D7.4`：三个示例均可直接运行 |
| `D7.5` | `docs/migration-knit.md` | `AC-D7.5`：一个 Knit 项目按指南迁移成功 |
| `D7.6` | CHANGELOG + SemVer + `.rbxm` + Wally 发布 `vospek/deuterium` | `AC-D7.6`：从 Wally 安装即可用 |
| `D7.7` | 基准报告（带宽 ≥60% 下降等宣称全部有数字） | `AC-D7.7`：报告可复现，脚本入库 |

### D8 · Studio 插件（可选，不阻塞 v1）

代码生成 / 类型导出，对标 Knit 的插件体验。

---

## 4. 项目专属风险

R1（跳过 `D0.1`）、R4（广度压倒深度）、R10（失速）、R12（边界被打破）的完整条目在 `README.md` §6。框架侧补充两条：

| 风险 | 触发条件 | 对策 |
| --- | --- | --- |
| PlayerState 上游未定，`D4.1` 阻塞 | 决策 D1 仍为 OPEN | `D4.5`–`D4.7` 先用 `MockPlayerState` 先行；`D4.1` 前必须关闭 D1 |
| Studio-only 测试导致回归不可见 | 只有 `SelfTest` 无 CI 用例 | `D0.1` 落地 Lune headless；Step 7 探针决定覆盖范围 |
