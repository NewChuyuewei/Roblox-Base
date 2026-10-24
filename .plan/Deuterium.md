# Deuterium — 实施计划（Plan of Record）

> **规格基线**：`../Deuterium/Deuterium.md`（不重写，按本文档 §2 的修订清单打补丁）
> **地位**：本文件是排期与验收的唯一权威；与规格冲突时，以本文档为准，并回写规格。
> **本次改写的三件事**：① 按实际代码审计修正完成度；② 与 TritiumSQL 重划边界、裁掉重复波次；③ 新增 Phase 0 前置波次（工程骨架 + Foundation 前置件），它是当前唯一关键路径。

---

## 0. 环境审计结论（改写的依据）

| 项 | 实测 |
| --- | --- |
| 代码量 | 70 个 `.luau`，4894 行 |
| 覆盖 | `Deuterium.md` §8 的 Phase 1.1–1.7 全部 + Phase 2.2–2.4 + `Security/Crypto` 的 Hmac/Sha256 |
| 缺失 | Phase 0（本文档新增）、2.1、2.5–2.7、3、4、5、6 全部；`Core/Foundation` 缺 EventLoop/Context/Metadata |
| 工程 | **无** Rojo 工程文件、`.luaurc`、selene/stylua 配置、`AGENTS.md`、`MEMORY.md`、`Libraries/` |
| 依赖 | 18 个文件 `require(game:GetService("ReplicatedStorage"):WaitForChild("Debug"))`，而 **`Debug` 模块不存在** → 当前仓库无法加载 |
| CI | `.gitlab-ci.yml` 仅继承 GitLab 默认 SAST 模板，无构建/测试/静态检查 |
| 测试 | 全部 `SelfTest` 为 Studio 命令栏手工触发（`RunContext.IsStudio()` 断言），CI 不覆盖 |

**结论**：代码质量与设计意图一致（`--!strict`、`table.freeze` 导出、每模块配 SelfTest、Kernel 用 `xpcall` 做单 provider 隔离），但**当前状态是「不可运行」而非「可运行」，任何新波次动工前必须先补齐 Phase 0**。

---

## 1. 不变量增补（追加至规格 §0，编号续接）

| # | 增补 | 理由 |
| --- | --- | --- |
| I8 | **持久化不在框架内** | 一切落盘/查询/事务语义归 TritiumSQL；`Dr.Data` 只管会话态 + 编排，禁止实现页、索引、MVCC |
| I9 | **一份 Codec** | 序列化只在 `Dr.Types.Transform.Codec` 实现；`Dr.Net` 与 TritiumSQL 均调用它，禁止第三份 |
| I10 | **引擎 API 单一出入口** | 一切 Roblox 引擎 API 只出现在 `Dr.Runtime`；TritiumSQL 经 `Tri.Runtime.StorePort` 端口绑定，其 Standalone 绑定是**唯一**例外文件且必须单独标注 |
| I11 | **SQL 编译期化** | SQL 字符串只在 Init/Construct 期解析（PreparedStatement）；运行期热路径禁止解析 |
| I12 | **请求次数是验收指标** | 涉及 DataStore 的波次，验收必须含请求次数断言，结果正确不足以通过 |
| I13 | **薄入口** | 对外公共符号必须经 `API/Deuterium.luau` 门面收口（≤40 个），其余走 `Dr.*` 命名空间。对齐 Knit 的三概念体验，见 `SCALE.md` §3 |
| I14 | **集成方向单一出入口** | `Dr.*` 对 `Tri.*` 的调用只允许出现在 `Deuterium/Integration/`。见 `INTEGRATION.md` §0 |
| I15 | **锁顺序** | 先 `Dr.Concurrency.Sync.Mutex`（进程内短临界区）→ 后 `Tri.Txn.LockManager` 行锁（持久/跨服），禁止反向。见 `INTEGRATION.md` §0 |

---

## 2. 规格修订清单（回写 `Deuterium.md`）

| 位置 | 现状 | 改为 |
| --- | --- | --- |
| §1 模块地图 `Dr.Data` | 含 Store/Reliability/Processing/Observe 四组，与 TritiumSQL 重叠 | 收窄为会话态：`Core` + `Store`（PlayerData/EphemeralData）+ `Reliability.Transaction`（跨存储 Saga 协调者）+ `Processing.Migrator`（会话态版本迁移）。其余标注「▶ 见 TritiumSQL」 |
| §1 `Dr.State.Sync.Replicator` | 底层 PlayerState Replica | 保留不变（复制不属于持久化） |
| §3 外部依赖 `PlayerState` | 「数据/复制基底」 | 改为「**复制**基底；持久化职责移交 TritiumSQL（决策 D2）」 |
| §4 目录落地 | `src/ReplicatedStorage/Deuterium/...` | 改为现树：`Deuterium/` → Rojo 映射 `ReplicatedStorage.Deuterium`（决策 D8） |
| §7 CI | 「后续加 TestKit 伪 headless」 | 明确为 Lune headless（决策 D4），且为本计划的 Phase 0.1 交付 |
| §8 Phase 4 | 4.3 / 4.4 大部分波次 | 删除并指向 `TritiumSQL.md`；Phase 4 只剩会话态 + 迁移 + 适配器 |
| §8 Phase 5 | 5.1–5.3 集合/内存/缓冲 | 提前到 Phase 0.3（TritiumSQL 硬依赖） |
| §8 Phase 6.1 | 日志/观测 | 提前到 Phase 0.1（`Debug` 模块与可观测门禁的依赖） |
| 全文 | 引用 `AGENTS.md`、`docs/dones/`、`MEMORY.md` 但均不存在 | Phase 0.1 创建 |

---

## 3. Phase 0 · 工程骨架与前置件（新增，阻塞全部）

> 目标：让仓库**可构建、可测试、可阻断**；并把 TritiumSQL 硬依赖的 Foundation 件从原 Phase 5 提前到此处。

### Wave 0.1 · 工具链与工程骨架

| 交付 | 说明 |
| --- | --- |
| `default.project.json` | Rojo 映射：`Deuterium/` → `ReplicatedStorage.Deuterium`、`TritiumSQL/` → `ReplicatedStorage.TritiumSQL`、`ServerScriptService/DeuteriumServer/`（新建，放强校验实现） |
| `src` 内的 `Debug` 模块 | 18 个文件已在 require 它。最小实现：Scribe 包装 + 无 Scribe 时降级到 `warn`/`print`，提供 `print/warn/err` |
| `dr.diagnostics.logging` 最小集 | `Logger` + `LogSink` + `StructuredLog`（规格 6.1 提前，`Debug` 建在其上） |
| `rokit.toml` | dev 工具锁定：`rojo` / `lune` / `selene` / `stylua` / `luau-lsp` |
| `.luaurc` | 严格模式 + 别名（`@Deuterium/...`） |
| `selene.toml` + `stylua.toml` | 含 P0 自定义规则（禁热路径 `table.insert`、禁匿名闭包分配的可疑点） |
| `.gitlab-ci.yml` 重写 | 四阶段：`lint`（stylua --check + selene）→ `types`（luau-lsp analyze + Roblox `globalTypes.d.luau`）→ `build`（rojo build）→ `test`（lune headless） |
| `AGENTS.md` / `MEMORY.md` | Agent 约定 + 依赖审计留档（规格 §2 第 5 步） |

**验收**：`rojo build` 通过；CI 四阶段全绿；`require(ReplicatedStorage.Deuterium.Core.Container.Kernel)` 在 Studio 与 headless 下均可加载；Scribe 审计结论写入 `MEMORY.md`（决策 D6）。

### Wave 0.2 · `Dr.Core.Foundation` 补件（Phase 1.5 缺口）

`EventLoop` · `Context` · `Metadata`。
**验收**：Metadata 反射与 `Dr.Core.Reflection.Descriptor` 互通；Context 在 Boot 链上可传递且不泄漏。

### Wave 0.3 · Foundation 前置抽取（原 Phase 5.1–5.3 + 2.1 最小集）

| 组 | 提前的模块 | 消费方 |
| --- | --- | --- |
| `Dr.Collections` | `Map.LRUCache` · `Sorted.PriorityQueue` · `Linear.RingBuffer` · `Linear.Queue` · `Set.Set` · `Map.HashMap` | TritiumSQL 页缓存 / 请求队列 / WAL 环形缓冲 |
| `Dr.Memory` | `Buffer.ByteBuffer` · `Pool.ObjectPool` · `Pool.TablePool` | 页编解码 / 热路径零 GC |
| `Dr.Concurrency` | `Sync.Mutex` · `Async.AsyncQueue` · `Scheduling.TaskScheduler` · `Async.Promise` | 协程化锁与调度（SQL 锁管理器依赖） |
| `Dr.Types` | `Primitives.*` · `Validation.Schema/Validator/SchemaBuilder/Coercion` · `Transform.Codec`（I9 唯一 Codec） | Schema 校验、页编解码、Net 打包 |
| `Dr.Testing.Integration` | `DataStoreSimulator` · `LoadTest` 骨架 | 无此件则 TritiumSQL Phase 1 无法测 |

**验收**：每件不少于 1 个单测覆盖正常 + 边界 + 失败；LRUCache 命中率与逐出顺序有断言；RingBuffer 背压行为有断言；`DataStoreSimulator` 支持故障注入（超时 / 配额超限 / 写失败）并统计请求次数。

### Wave 0.4 · `Dr.Runtime.Platform` 端口绑定（I10）

`DataStoreProxy` · `MemoryStoreProxy`：包装 `DataStoreService` / `MemoryStoreService`，提供请求计数、配额节流、故障注入钩子。
**验收**：Deuterium 其余层零引擎 API；proxy 可被 TritiumSQL 的 Deuterium 绑定直接使用；请求计数与实际调用一一对应。

### Wave 0.5 · 端到端纵切（`SCALE.md` §5）

`Kernel.Boot → SchemaStore（内存）→ TriSQL.Compile → IndexScan → B+树（内存）→ Page（内存）→ StorePort → 读回断言`。
允许占位与 `shortcut:` 标注，不做持久化/事务/优化器。唯一目标是让**架构接缝**暴露，产出 `.plan/SEAMS.md`。
**验收**：上述链路在 Studio 与 CI 各跑通一次；`SEAMS.md` 列出需正式化的接口与不成立的设想；耗时 ≤3 天。

---

## 4. 已完成波次（登记，不重做）

| Wave | 交付 | 文件 | 状态 |
| --- | --- | --- | --- |
| 1.1 | `Dr.Runtime.Environment`（RunContext/EngineVersion/FeatureFlags）+ `RuntimeTypes` | 4 + 1 | ✅ |
| 1.2 | `Dr.Runtime.Platform`（ServiceLocator/InstanceTracker/PhysicsProxy） | 6（含 SelfTest） | ✅ |
| 1.3 | `Dr.Runtime.Interop`（Legacy/ExternalBridge）+ `ServerRegistry`/`ServerBrowser` | 3 + 2 | ✅ |
| 1.4 | `Dr.Core.Container`（Kernel/ServiceContainer/DependencyInjector/ServiceRegistry/ScopeContainer/Types） | 7 | ✅ |
| 1.5 | `Dr.Core.Lifecycle`（Lifecycle/ModuleLoader/Configuration/BootSequencer/HotReload/ShutdownManager） | 7 | ✅（缺 `Dr.Core.Foundation` 三件 → Wave 0.2） |
| 1.6 | `Dr.Core.Reflection` + `Dr.Types.Contract` | 4 + 3 | ✅ |
| 1.7 | `Dr.Testing`（Runner/Suite/Assert/TestContext）+ `Extensions.Demo` | 5 + 1 | ✅ |
| 2.2 | `Dr.Net.Core` + `Dr.Net.Bridge` | 6 + 4 | ✅ |
| 2.3 | `Dr.Net.Processing` = NetCodec v1 | 8 | ✅（待 0.3 的 Codec 合并，见 I9） |
| 2.4 | `Dr.Net.Security` | 5 | ✅ |
| 2.6a | `Dr.Security.Crypto`（Hmac/Sha256） | 2 | ◐ 部分 |

---

## 5. 剩余波次

### Phase 2 · 网络与安全（续）

| Wave | 交付 | 验收 |
| --- | --- | --- |
| 2.1 → **已并入 0.3** | — | — |
| 2.5 | `Dr.Security.Access`（Permission/Guard/PolicyEngine/CapabilityToken）+ `Input`（Sanitizer/Validator/ContentFilter/SchemaEnforcer） | RBAC 图谱 Init 期编译；非法请求全部拒绝 |
| 2.6b | `Dr.Security.Crypto`（TokenGenerator/Obfuscator）+ `Monitor`（AntiExploit/Fingerprint/AuditLog/ThreatDetector/BanManager/SecurityDashboard） | 日志走 Scribe；禁令应用后重连被拒 |
| 2.7 | `Dr.Security.Compliance`（DataPrivacy/RateLimitPolicy/AbuseReporter）+ 全链联调 | 作弊样本集 0 误放行；AuditLog 完整 |

### Phase 3 · 弹性（HA）— 分两批

| Wave | 交付 | 验收 | 批次 |
| --- | --- | --- | --- |
| 3.1 | `Dr.HA.Circuit`（CircuitBreaker/CircuitState/CircuitRegistry） | 状态机单测：关→半开→开，锯齿边界用例过 | **先做**（TritiumSQL 依赖） |
| 3.2 | `Dr.HA.Recovery`（RetryPolicy/Fallback/Bulkhead/Hedging） | 重试曲线含 ±10% 抖动；Hedging 无重复副作用 | **先做**（TritiumSQL 依赖） |
| 3.3 | `Dr.HA.Resilience`（Timeout/LoadShedder/AdaptiveConcurrency） | 看门狗压测下内存与吞吐不下滑 | 后做 |
| 3.4 | `Dr.HA.Monitor`（Watchdog/RateLimiter/SLATracker）+ ProfileStore 适配 | 人为断网 60s 不雪崩；重连 30s 内自愈 | 后做 |

### Phase 4 · 会话态与状态（重写：删除与 TritiumSQL 重复的波次）

| Wave | 交付 | 验收 |
| --- | --- | --- |
| 4.1 | PlayerState 审计 + 内置 → `Dr.Data.Core`（DataManager/DataTypes/DataPipeline/DataRegistry） | 走规格 §2 五步流程；CRUD 单测过 |
| 4.2 | `Dr.Data.Store`（PlayerData/EphemeralData/ComputedData） | 写入强制走六段流水；旁路代码静态不可调通 |
| 4.3 | `Dr.Data.Reliability.Transaction`（**仅 Saga 协调者**）+ `SessionLock` | 跨存储（会话态 ↔ TritiumSQL）任一步中断逆序回滚、成果归属明确 |
| 4.4 | `Dr.Data.Processing.Migrator`（会话态版本迁移）+ `Observe.Changelog` | 多轮 v0→v3 各自走通 |
| 4.5 | `Dr.State.Core`（Store/Atom/StateGraph）+ `Reactive`（Computed/Observer/Selector/Reaction） | 反应链表达树去重，不重复求值 |
| 4.6 | `Dr.State.Machine`（StateMachine/StateChart/Transition）+ `History`（UndoRedo/StateHistory） | 状态机切换可倒序回溯出中间值 |
| 4.7 | `Dr.State.Sync`（Replicator=PlayerState.Replica 封装/Reconciler/SyncPolicy/ConflictResolver） | 多端同改同字段结果一致；server-wins 默认走通 |
| 4.8 | `Dr.Data.Adapter.TritiumAdapter`（新增） | `TritiumSQL` 缺失时框架仍可启动（降级）；存在时可把会话态写入关系表并由 TriSQL 查回 |

> ▶ 原 4.3（MVCC/WAL/Checkpoint）、原 4.4（QueryEngine/Cache/DataValidator）→ `TritiumSQL.md` Phase 1–3。
> ▶ 4.8 只建**适配器**；与 TritiumSQL 的全部互通（持久化 / 变更流复制 / 行级安全 / 结果传输 / ECS 持久化）在 `INTEGRATION.md` 的 G1–G10 与 `Deuterium/Integration/`（18 模块）内实现，Step 50–57。

### Phase 5 · 性能（余量）

| Wave | 交付 | 验收 |
| --- | --- | --- |
| 5.1 → 已并入 0.3 | — | — |
| 5.2 | `Dr.Collections.Spatial`（SpatialHash/QuadTree/Octree/BVH）+ `Advanced`（Trie/Graph） | 1e4 区域预筛 @60fps |
| 5.3b | `Dr.Memory.Pool` 剩余（Instance/Buffer/StringPool）+ `Memory.Lifecycle/Monitor` | 玩家下场后句柄零遗留 |
| 5.5 | `Dr.ECS.Core`（World/Entity/Component/WorldRegistry）+ `Storage`（SparseSet/ChunkedStorage/ComponentPool） | 5000 实体更新 < 1ms/帧 |
| 5.6 | `Dr.ECS.Query` + `Execution`（System/Scheduler/CommandBuffer/SystemGroup/ExecutionPipeline） | CommandBuffer 延迟到下一帧才生效 |
| 5.7 | `Dr.ECS.Prefab` + NetCodec 带宽基准（合并 0.3 的 Codec 后复测） | 关键链路带宽降 ≥60% |

### Phase 6 · 工具 / 治理 / 世界层

| Wave | 交付 | 验收 |
| --- | --- | --- |
| 6.1 → 已并入 0.1（最小集） | — | — |
| 6.1b | `Dr.Diagnostics.Logging` 完整（LogAggregator/采样/标签约束） | 日志标签约束生效；可采样定性 |
| 6.2 | `Profiling`（Profiler/MemoryProfiler/NetworkProfiler/FrameProfiler/HotspotDetector）+ `Trace` | 每决策点有 Trace；热点报告可产出 |
| 6.3 | `Monitor`（Metrics/HealthCheck/Dashboard/Alerting/SLO）+ `Debug`（Inspector/Breakpoint/REPL） | SLO 可人工调用；REPL 沙箱隔离 |
| 6.4 | `Dr.Util`（Math/String/Data/Time/Animation/Pattern） | 全部按 P0 规则写就 |
| 6.5 | `Dr.Plugin`（PluginManager/PluginHost/Hook/MiddlewarePipeline/Extension） | 动态增删插件不重启 |
| 6.6 | `Dr.World`（SceneManager/SceneGraph/SceneTransition；Spatial=QuickZone 审计内置后接入） | QuickZone 过审计，Overrides 不改上游本体 |
| 6.7 | 治理：`docs/dones/Deuterium.md` + 扩展作者指南 + ADR | 新人 30 分钟能写完一个玩具扩展 |

### Phase 7 · 发布与生态（新增，`SCALE.md` §3 · §6.1）

> 「堪比 Knit」在本项目是**可用性**目标而非规模目标；本 Phase 就是补齐 Knit 有而我们缺的四样。

| Wave | 交付 | 验收 |
| --- | --- | --- |
| 7.1 | 薄入口门面 `API/Deuterium.luau`（I13） | 公共导出 ≤40 个符号；三个概念、五行代码可跑 |
| 7.2 | `Component` 语义补件（对齐 Knit 三分的第三分） | 组件挂载/卸载生命周期单测 |
| 7.3 | 文档站（moonwave 或 MkDocs）+ API 参考 | 全部公共符号有页；构建进 CI |
| 7.4 | `examples/`：最小示例 · 带持久化（走 TritiumSQL）· 带客户端复制 | 三个示例均可直接运行 |
| 7.5 | `docs/migration-knit.md` | 一个 Knit 项目按指南迁移成功 |
| 7.6 | CHANGELOG + SemVer + `.rbxm` + Wally 发布 `vospek/deuterium` | 从 Wally 安装即可用 |
| 7.7 | 基准报告（带宽 ≥60% 下降等宣称全部有数字） | 报告可复现，脚本入库 |

### Phase 8 · Studio 插件（可选，不阻塞 v1）

代码生成 / 类型导出，对标 Knit 的插件体验。

---

## 6. 风险

| 风险 | 等级 | 对策 |
| --- | --- | --- |
| **Phase 0 被跳过，直接在不可运行仓库上叠新模块** | 高 | Phase 0 验收是唯一硬门禁；0.1 未绿不得开任何其他波次 |
| 模块总数（60+）导致烂尾 | 高 | 每 Wave 独立可构建可验收；Wave 不交叉写码 |
| 与 TritiumSQL 边界执行不严，重复实现页/事务 | 中 | I8 + 边界铁律表；Code Review 检查 `Dr.Data` 是否出现页/索引/MVCC 概念 |
| PlayerState 上游未定，Phase 4 阻塞 | 中 | 决策 D1；在 4.1 前用 `MockPlayerState` 保持 4.5–4.7 可先行 |
| Scribe 未审计 | 中 | 0.1 内 30 分钟人工审计并留档 |
| Studio-only 测试导致回归不可见 | 中 | 0.1 落地 Lune headless + CI 阻断 |

未读：Phase 1/2 已完成模块的内部实现逻辑（只抽样了 Kernel/Testing/Container，未逐行审查 70 个文件），因此「已完成」= 文件与 SelfTest 齐备，**不等于**功能经独立验证。风险：上述完成度结论基于目录与抽样，可能存在实现与规格不一致之处，需在 Phase 0.1 的 CI 跑通后重估。
