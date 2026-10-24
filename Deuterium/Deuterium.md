# Deuterium — 六边形微内核 Roblox Framework（企业级规范 · VerySafe 全自研策略 v2）

> 定位：Massive Roleplay · 高并发 · 开发者友好的可扩展性
> 哲学：**易扩展，但零妥协** —— Registry + Middleware Hooks 实现业务易扩展；所有扩展依赖在 Init 阶段静态解析（拓扑排序），运行期热路径零动态查表。
> 地位：本游戏最底层架构系统。内部模块采用 `Dr.*` 分层命名空间（Dr = Deuterium 的缩写；RUNTIME · FOUNDATION · SERVICE · CROSS-CUTTING · TOOLING · APPLICATION），包名 Deuterium。
> 依赖策略：**能自研尽自研；唯二显式封装外部库：`PlayerState`（数据复制基底）与 `QuickZone`（空间查询）**，两者走 §1 审计内置通道。
> 状态：规划中（本文件即总纲）。系统完成后按 `AGENTS.md` 另写 `docs/dones/Deuterium.md`（功能 / API / 用法）。

---

## 0. 不变量（Invariants —— 任何阶段、任何模块都不得违反）

1. **静态胜于动态**：Init/Construct 期完成依赖解析、中间件编译、权限图加载；`[P0]` 热路径禁止字符串查表、匿名闭包分配、`table.insert` 扩容。
2. **服务器即权威**：客户端不可信；一切交互经服务器 RBAC + Schema + 物理校验三层裁决。
3. **隔离舱壁**：单扩展崩溃只影响自身（Bulkhead）；框架核心绝不因业务错误宕机。
4. **外部调用必有兜底**：DataStore / HTTP / 第三方服务一律经 `CircuitBreaker` 包裹，并有明确 Fallback。
5. **面向数据**：海量物件进 ECS 阵列（SparseSet/ChunkedStorage + System 线性扫）；OOP 只在扩展门面。
6. **可观测即正确性**：每个决策点经 Scribe/Dr.Diagnostics 可观察；黑盒代码视为未完成。
7. **VerySafe 供应链**：能自研均自研；例外仅限 PlayerState / QuickZone，且必须锁版本、全量审计、改造内置（详见 §2）。

---

## 1. 模块地图（源自 Dr.* 规范，全部纳入 Deuterium 管辖）

### RUNTIME —— 引擎抽象层（框架与 Roblox 引擎隔离带）
```
Dr.Runtime/
  Environment/  RunContext · EngineVersion · FeatureFlags
  Platform/     ServiceLocator · InstanceTracker · PhysicsProxy
                ServerRegistry（封装 Hoster） · ServerBrowser（封装 Hoster）
  Interop/      LegacyBridge · ExternalBridge · RuntimeTypes
```

### FOUNDATION —— 基础层
```
Dr.Core/
  Container/    Kernel · ServiceContainer · DependencyInjector · ServiceRegistry · ScopeContainer
  Lifecycle/    Lifecycle · ModuleLoader · Configuration · BootSequencer · HotReload · ShutdownManager
  Foundation/   ErrorHandler · Contract · CoreTypes · EventLoop · Context · Metadata
  Reflection/   Inspector · Proxy · Descriptor
Dr.Types/
  Primitives/   TypeChecker · TypeGuard · Enum · Branded · Opaque
  Validation/   Schema · Validator · SchemaBuilder · SchemaRegistry · Coercion
  Transform/    Serializer · Result · Option · Either · Codec
  Contract/     Interface · Precondition · Invariant
Dr.Concurrency/
  Async/        Promise · Deferred · AsyncIterator · AsyncQueue · AsyncPipeline · ConcurrencyTypes
  Sync/         Mutex · Semaphore · Channel · RWLock · Barrier · CondVar
  Scheduling/   Timer · TaskScheduler · TaskQueue · Throttle · CronJob · WorkerPool · TimeWheel
  Parallel/     Actor · ActorPool · SharedTable · ParallelJob
Dr.Memory/
  Pool/         ObjectPool · InstancePool · TablePool · BufferPool · StringPool
  Lifecycle/    Scope · ConnectionTracker · DisposableGroup · AutoCleanup
  Monitor/      WeakRef · MemoryBudget · LeakDetector · GCHint · MemorySnapshot
  Buffer/       ByteBuffer · BitBuffer · StreamBuffer
```

### SERVICE —— 服务层
```
Dr.Signal/
  Core/         Signal · Connection · AsyncSignal · PrioritySignal · ThrottledSignal
  Bus/          EventBus · EventEmitter · Subscription · TopicBus · ReplayBus
  Pipeline/     SignalPipeline · Combinator · Observable
  Pool/         Pool
Dr.Net/
  Core/         NetworkManager · Channel · UnreliableChannel · MultiChannel · ConnectionPool
  Bridge/       ClientBridge · ServerBridge · MockBridge · LocalBridge
  Processing/   Packet · Middleware · RateLimiter · Serializer · Compressor · BatchProcessor · PacketQueue · ProtocolBuffer
  Security/     RequestSigner · ReplayGuard · PacketValidator
Dr.Data/        ⚠️ PlayerData 底层使用 PlayerState 库；所有写操作强制走六段流程，不得绕过
  Core/         DataManager · DataTypes · DataPipeline · DataRegistry
  Store/        PlayerData（封装 PlayerState） · GlobalData · OrderedData · EphemeralData · ComputedData
  Reliability/  SessionLock · Transaction · Retry · Snapshot · WriteAheadLog · Checkpoint
  Processing/   Cache · Migrator · DataValidator · QueryEngine · Transformer
  Observe/      DataWatcher · ChangeLog · DiffEngine
Dr.State/       ⚠️ Replicator 底层使用 PlayerState 的 Replica 能力
  Core/         Store · Atom · StateTypes · StateGraph
  Reactive/     Computed · Observer · Selector · Reaction · Derivation
  Machine/      StateMachine · StateChart · Transition
  History/      UndoRedo · StateHistory · TimeTravelDebugger
  Sync/         Replicator（封装 PlayerState Replica） · Reconciler · StateMiddleware · SyncPolicy · ConflictResolver
Dr.ECS/
  Core/         World · Entity · Component · ECSTypes · WorldRegistry
  Query/        Archetype · Filter · Query · QueryCache · ReactiveQuery
  Execution/    System · Scheduler · CommandBuffer · ECSObserver · SystemGroup · DependencyGraph · ExecutionPipeline
  Storage/      SparseSet · ChunkedStorage · ComponentPool
  Prefab/       Prefab · PrefabRegistry · PrefabInstancer
```

### CROSS-CUTTING —— 横切层
```
Dr.Security/
  Access/       Permission · Guard · SecurityTypes · PolicyEngine · CapabilityToken
  Input/        Sanitizer · Validator · ContentFilter · SchemaEnforcer
  Crypto/       Hmac · TokenGenerator · Obfuscator
  Monitor/      AntiExploit · Fingerprint · AuditLog · ThreatDetector · BanManager · SecurityDashboard
  Compliance/   DataPrivacy · RateLimitPolicy · AbuseReporter
Dr.HA/
  Circuit/      CircuitBreaker · CircuitState · CircuitRegistry
  Recovery/     RetryPolicy · Fallback · Bulkhead · Hedging
  Resilience/   Timeout · LoadShedder · AdaptiveConcurrency
  Monitor/      Watchdog · RateLimiter · SLATracker
Dr.Collections/
  Linear/       LinkedList · Queue · Deque · Stack · RingBuffer
  Sorted/       PriorityQueue · SortedArray
  Map/          HashMap · OrderedMap · LRUCache
  Set/          Set · BitSet · BitFlag
  Spatial/      SpatialHash · QuadTree · Octree · BVH
  Advanced/     Trie · Graph · CollectionTypes
```

### TOOLING —— 工具层
```
Dr.Util/
  Math/         MathUtil · NumberUtil · VectorUtil · CFrameUtil · ColorUtil · StatUtil · NoiseUtil
  String/       StringUtil · Encoding · Hash · Template · Lexer
  Data/         TableUtil · Functional · Iterator · Diff · Immutable · DeepEqual
  Time/         DateTimeUtil · UUID · Stopwatch
  Animation/    Easing · Interpolation · Spring
  Pattern/      Observable · Command · Pipeline · Builder
Dr.Plugin/
  Core/         PluginManager · PluginHost · Types
  Extension/    Hook · MiddlewarePipeline · Extension
Dr.Diagnostics/
  Logging/      Logger · LogSink · StructuredLog · LogAggregator
  Profiling/    Profiler · MemoryProfiler · NetworkProfiler · FrameProfiler · HotspotDetector
  Trace/        TraceContext · Span · TraceExporter
  Monitor/      Metrics · HealthCheck · Dashboard · Alerting · SLO
  Debug/        Inspector · Breakpoint · REPL
Dr.Testing/
  Runner/       TestRunner · TestSuite · Assert · TestContext
  Doubles/      Mock · Faker · Spy · Stub · Fixture
  Perf/         Benchmark · LoadTest · Regression
  Integration/  NetworkSimulator · DataStoreSimulator · PlayerSimulator
```

### APPLICATION —— 应用层
```
Dr.World/
  Scene/        SceneManager · SceneGraph · SceneTransition
  Spatial/      ZoneManager（封装 QuickZone） · EntityGroup（封装 QuickZone.Group） · RegionObserver（封装 QuickZone.Observer）
  Object/       ObjectManager · ObjectPool · TagSystem
```

---

## 2. 依赖策略与选型（VerySafe）

**总则**：全部自研；例外仅两个——**PlayerState**（数据/复制基底）与 **QuickZone**（空间查询）。两者必须：
`锁定 LTS 版本 → 全量源码人工审计 → 解耦改造后内置于 Libraries/`，并在 `MEMORY.md` 记录版本哈希 / LICENSE / 审计人 / 改动点。

| 需求 | 决策 | 落地方案 |
| --- | --- | --- |
| 微内核 / 容器 / 生命周期 | **自研** | `Dr.Core.Container` + `Dr.Core.Lifecycle` |
| ECS | **自研** | `Dr.ECS.*` 全套（SparseSet / Archetype / Query / CommandBuffer） |
| 网络层 | **自研** | `Dr.Net.*`（NetCodec = Schema→buffer，自研打包器，不学 Zap 工具链） |
| 数据 / 状态复制 | **内置 PlayerState** | `Dr.Data.Store.PlayerData`、`Dr.State.Sync.Replicator` 封装——**两横例外之一** |
| 空间查询 | **内置 QuickZone** | `Dr.World.Spatial.ZoneManager` 等三件套——**两个例外之二** |
| 日志/观测 | 沿用 **Scribe**（已内置，⚠️ 待审计） | `Dr.Diagnostics.Logging` 底层走 Scribe |
| 测试 | **自研** | `Dr.Testing.*` 全套（Runner/Assert/Mock/Benchmark/模拟器） |
| 安全 / HA / 集合 / 工具 | **自研** | Dr.Security / Dr.HA / Dr.Collections / Dr.Util 全自研 |

**审计纪律**（任何内置库必走）：
1. 锁版本（最新稳定 tag + commit hash）。
2. 全量审计，重点搜 `loadstring` / `HttpService` / `require(<id>)` 后门面。
3. 剥离用不到的模块。
4. 改造：加 `Overrides.luau`，不改上游文件本体。
5. 留档 MEMORY.md。

## 3. 外部依赖现状

| 依赖 | 位置/来源 | 角色 | VerySafe 状态 |
| --- | --- | --- | --- |
| **Scribe** | 已内置 `Libraries/Scribe` | 日志/观测 | ⚠️ 待审计 + 补 LICENSE 记录 |
| **PlayerState** | 待引入（上游仓库**待用户确认具体来源**） | `Dr.Data.PlayerData` 与 `Dr.State.Replicator` 底层 | ⛔ 未审计，不得用 |
| **QuickZone**（MIT, LDGerrits） | 计划内置 `ldgerrits/quickzone@^1.4.x` | `Dr.World.Spatial` 底层 | ⛔ 未审计，不得用 |
| jecs / Zap / Replica / prvd | 概念参考，不引入 | — | 无 |

---

## 4. 架构总览（Hexagonal Microkernel + 分层）

```
APPLICATION  Dr.World（封装 QuickZone · 场景/对象管理）
SERVICE      Dr.Signal · Dr.Net · Dr.Data · Dr.State · Dr.ECS
FOUNDATION   Dr.Core（Kernel/DI/Lifecycle）· Dr.Types · Dr.Concurrency · Dr.Memory
CROSS-CUTTING Dr.Security · Dr.HA · Dr.Collections
TOOLING      Dr.Util · Dr.Plugin · Dr.Diagnostics · Dr.Testing
RUNTIME      Dr.Runtime（引擎抽象层——Roblox API 的唯一接触带）
```

规则：
- 上层只允许向下依赖；**反向依赖 = 架构违反**（CI 静态护卫）。
- 所有 Roblox 引擎 API 的调用点集中在 `Dr.Runtime`；其余层只碰抽象类型。
- 目录落地：`src/ReplicatedStorage/Deuterium/...`；机密/强校验实现放 `src/ServerScriptService/DeuteriumServer/`。

---

## 5. 四支柱 → 落地映射

### 5.1 安全
| # | 控制点 | 实现 |
| --- | --- | --- |
| ① | RateLimit + 包大小上限（默认 10 req/s · 512B，超限丢弃） | `Dr.Net.Processing.RateLimiter` + `Dr.Net.Security` |
| ② | Distance 阈值 + Raycast 防穿墙；QuickZone 预筛 | `Dr.World.Spatial` + `Dr.Runtime.PhysicsProxy` |
| ③ | RBAC（Team/Role/卡级别）强制 Middleware 前置钩子 | `Dr.Security.Access.PolicyEngine` |
| ④ | Schema 形状断言 + Sanitizer 白名单洗脱 | `Dr.Types.Validation` + `Dr.Security.Input` |

### 5.2 可用性
| # | 机制 | 落点 |
| --- | --- | --- |
| ① | CircuitBreaker（闭/半开/开 + Fallback） | `Dr.HA.Circuit` |
| ② | Bulkhead：扩展崩溃隔离单元，失败即 Stop | `Dr.Core.Container.ScopeContainer` + `Dr.HA.Recovery` |
| ③ | RetryPolicy 指数退避 + Watchdog 自愈 | `Dr.HA.Recovery.RetryPolicy` + `Dr.HA.Monitor.Watchdog` |

### 5.3 完整性
| # | 机制 | 落点 |
| --- | --- | --- |
| ① | Transaction（Saga do/undo） | `Dr.Data.Reliability.Transaction` |
| ② | StateSync + ConflictResolver（server-wins + 逻辑时钟） | `Dr.State.Sync.*`（底层 PlayerState Replica） |
| ③ | IdempotencyLock（playerId:resourceId:opId） | `Dr.Data.Reliability.SessionLock` 旁路 |

### 5.4 性能
| # | 约束 | 落点 |
| --- | --- | --- |
| ① | `[P0]` 禁 table.insert/匿名闭包/实例化 | 规约 + CI 静态巡检（后续 Selene） |
| ② | 自研 ECS（SparseSet/ChunkedStorage SoA） | `Dr.ECS.Storage` + `Execution` |
| ③ | NetCodec（Schema→buffer）关键链路带宽降 ≥60% | `Dr.Net.Processing.Serializer` + `PacketQueue` |
| ④ | 空间查询 QuickZone LBVH（大运尽） | `Dr.World.Spatial.ZoneManager` |

---

## 6. 生命周期与扩展契约

```lua
-- src/ReplicatedStorage/Deuterium/Core/Types/Contract.luau（契约预览）
export type Provider = {
	Name: string,
	Dependencies: { string }?,
	Init:  (self: any, ctx: KernelContext) -> (),
	Start: (self: any) -> ()?,
	Stop:  (self: any) -> ()?,
}
```

- `Kernel.Register` → 重名报错。
- `Kernel.Construct` → 拓扑排序 + 循环检测；失败带依赖路径。
- `Kernel.Init` → 按序 Init + Bulkhead；Middleware 在此编译为扁平数组。
- `Kernel.Start` → 按序 Start；Watchdog 巡检 Failed|Recoverable。
- 任意阶段抛错 → Log.tag("[Bulkhead]") + Failed 标记，其余照常。

---

## 7. 测试与质量门槛（Deuterium 专属）

- `Dr.Testing` 自研：`Runner/Assert/Mock/Benchmark/...`；服务器侧跑 headless。
- 每个 Core 模块覆盖：正常 / 循环依赖报错 / 重复注册报错 / Bulkhead 隔离。
- 每个 Adapter 做故障注入验收（DataStore 掉线 / 射线失败 / 超时）。
- CI：`luau-lint`（现有 advisory）→ 后续加 TestKit 伪 headless + 类型统计门槛。
- 系统完成时写 `docs/dones/Deuterium.md`。

---

## 8. 里程碑（Phase × Wave）

原则：每个 **Wave 独立可 Build + TestKit 验收**；Wave 内禁止跨 Phase 写码；Phase 末盘点依赖（只允许 Scribe + PlayerState + QuickZone 至多三项）。

### Phase 1 · 运行时与微内核（地基）

| Wave | 交付 | 验收 |
| --- | --- | --- |
| 1.1 | `Dr.Runtime.Environment`（RunContext/EngineVersion/FeatureFlags）+ `RuntimeTypes` | 环境探测单测过；FeatureFlags 读取无副作用 |
| 1.2 | `Dr.Runtime.Platform`（ServiceLocator/InstanceTracker/PhysicsProxy）| 不触引擎 API 其余层；InstanceTracker 观察/释放单测 |
| 1.3 | `Dr.Runtime.Interop`（LegacyBridge/ExternalBridge）+ `ServerRegistry/ServerBrowser` 接口 | 遗留系统接入 Demo 过；接口只读类型单测 |
| 1.4 | `Dr.Core.Container`（Kernel/ServiceContainer/DependencyInjector/ServiceRegistry/ScopeContainer）| 拓扑排序/环检测/重复注册报错三类单测 |
| 1.5 | `Dr.Core.Lifecycle`（Lifecycle/ModuleLoader/BootSequencer/ShutdownManager/HotReload）+ `Dr.Core.Foundation`（ErrorHandler/Contract/CoreTypes）| Boot 顺序日志链完整；双盖复启入状态机 |
| 1.6 | `Dr.Core.Reflection`（Inspector/Proxy/Descriptor）+ `Dr.Types.Contract`（Interface/Precondition/Invariant）| 契约违背在 Init 期失败；错误报告含路径 |
| 1.7 | `Dr.Testing.Runner`（TestRunner/TestSuite/Assert/TestContext）+ `Toolbox`（Benchmark 骨架）+ Demo 扩展端到端 | TestKit 自跑 + Demo 扩展 Fabric 注入崩溃，Bulkhead 拦截 |

### Phase 2 · 网络与安全

| Wave | 交付 | 验收 |
| --- | --- | --- |
| 2.1 | `Dr.Types.Primitives` + `Dr.Types.Validation`（Schema/Validator/SchemaBuilder/SchemaRegistry/Coercion）| Schema 负例样例集 100% 拒绝 |
| 2.2 | `Dr.Net.Core`（NetworkManager/Channel/UnreliableChannel/MultiChannel/ConnectionPool）+ `Bridge`（Client/Server/Local/Mock）| 本地桥 + MockBridge 内存回环过；多通道单向隔离过 |
| 2.3 | `Dr.Net.Processing`（Packet/Middleware/Serializer/Compressor/BatchProcessor/PacketQueue/ProtocolBuffer）= NetCodec v1 | Schema→buffer 双端一致性单测；无效侧包入内存绝不崩 |
| 2.4 | `Dr.Net.Security`（RequestSigner/ReplayGuard/PacketValidator/RateLimiter） | 超限丢弃率 100%；重放包拒绝 100% |
| 2.5 | `Dr.Security.Access`（Permission/Guard/PolicyEngine/CapabilityToken）+ `Input`（Sanitizer/Validator/ContentFilter/SchemaEnforcer） | RBAC 图谱 Init 编译；非法请求全部拒绝 |
| 2.6 | `Dr.Security.Crypto`（Hmac/TokenGenerator/Obfuscator）+ `Monitor`（AntiExploit/Fingerprint/AuditLog/ThreatDetector/BanManager/SecurityDashboard） | 日志走 Scribe；禁令应用后重连被拒绝 |
| 2.7 | `Dr.Security.Compliance`（DataPrivacy/RateLimitPolicy/AbuseReporter）+ 全链联调 | 注入作弊样本集 0 误放行；AuditLog 记录完整 |

### Phase 3 · 弹性（HA）

| Wave | 交付 | 验收 |
| --- | --- | --- |
| 3.1 | `Dr.HA.Circuit`（CircuitBreaker/CircuitState/CircuitRegistry）| 状态机单测：关→半开→开 → 锯齿边界用例过 |
| 3.2 | `Dr.HA.Recovery`（RetryPolicy/Fallback/Bulkhead/Hedging）| 重试曲线含 ±10% 抖动；Hedging 无任何重复副作用 |
| 3.3 | `Dr.HA.Resilience`（Timeout/LoadShedder/AdaptiveConcurrency）| 看门狗压测下内存与处理效率不下滑 |
| 3.4 | `Dr.HA.Monitor`（Watchdog/RateLimiter/SLATracker）+ ProfileStore 适配 | 人为断网 60s 不雪崩；重连后 30s 内自愈 |

### Phase 4 · 数据与状态

| Wave | 交付 | 验收 |
| --- | --- | --- |
| 4.1 | PlayerState 审计+内置 → `Dr.Data.Core`（DataManager/DataTypes/DataPipeline/DataRegistry）| 审计走 §2 五步流程；DataManager CRUD 单测过 |
| 4.2 | `Dr.Data.Store`（PlayerData/GlobalData/OrderedData/EphemeralData/ComputedData）| 写在六段流水内强制走 DataPipeline；旁路代码静态不能调通 |
| 4.3 | `Dr.Data.Reliability`（SessionLock/Transaction/Retry/Snapshot/WriteAheadLog/Checkpoint）| Saga 任一步中断逆序回滚、成果归属明确 |
| 4.4 | `Dr.Data.Processing`（Cache/Migrator/DataValidator/QueryEngine/Transformer）+ `Observe`（DataWatcher/ChangeLog/DiffEngine）| Migrator 不止可用，明明多轮 v0→v3 各自走通 |
| 4.5 | `Dr.State.Core`（Store/Atom/StateTypes/StateGraph）+ `Reactive`（Computed/Observer/Selector/Reaction/Derivation）| 反应链 表达棵树未去重不重复刷付价 |
| 4.6 | `Dr.State.Machine`（StateMachine/StateChart/Transition）+ `History`（UndoRedo/StateHistory/TimeTravelDebugger）| 状态机切换可倒置回溯出中阅读愿值 |
| 4.7 | `Dr.State.Sync`（Replicator=PlayerState.Replica封装/Reconciler/StateMiddleware/SyncPolicy/ConflictResolver） | 多端同改同字段结果互同；server-wins 默认走通 |

### Phase 5 · 性能（ECS + 集合 + 内存）

| Wave | 交付 | 验收 |
| --- | --- | --- |
| 5.1 | `Dr.Collections.Linear/Sorted/Map/Set`（开放定址冲目标品调优） | 点查 O(1)；RingBuffer 背压行为过 |
| 5.2 | `Dr.Collections.Spatial`（SpatialHash/QuadTree/Octree/BVH）+ `Advanced`（Trie/Graph）| 1e4 区域预筛 @60fps；QuickZone 泊诺仅落不了 5.6 则启用 |
| 5.3 | `Dr.Memory.Pool`（Object/Instance/Table/Buffer/StringPool）+ `Buffer`（Byte/Bit/Stream） | 热路径零阿里云 GC；内存以预算可能是下限 |
| 5.4 | `Dr.Memory.Lifecycle/Monitor`（Scope/ConnectionTracker/DisposableGroup/AutoCleanup/WeakRef/MemoryBudget/LeakDetector/GCHint/MemorySnapshot） | 玩样下场后句柄令人怀念零遗留 |
| 5.5 | `Dr.ECS.Core`（World/Entity/Component/WorldRegistry）+ `Storage`（SparseSet/ChunkedStorage/ComponentPool）| SparseSet 并发支撑 5000 实体更新 <1ms/帧 |
| 5.6 | `Dr.ECS.Query`（Archetype/Filter/Query/QueryCache/ReactiveQuery）+ `Execution`（System/Scheduler/CommandBuffer/ECSObserver/SystemGroup/DependencyGraph/ExecutionPipeline）| CommandBuffer 后悔顺崖测定表最后一个活跃变化到下一帧才生效 |
| 5.7 | `Dr.ECS.Prefab`（Prefab/PrefabRegistry/PrefabInstancer）+ NetCodec 带宽基准 | 关键链路带宽降 ≥60%（有效位包等级） |

### Phase 6 · 工具 / 治理 / 世界层

| Wave | 交付 | 验收 |
| --- | --- | --- |
| 6.1 | `Dr.Diagnostics.Logging`（Logger/LogSink/StructuredLog/LogAggregator，底层 Scribe） | 日志色带 标签约束；log sample 能被拍定 |
| 6.2 | `Dr.Diagnostics.Profiling`（Profiler/MemoryProfiler/NetworkProfiler/FrameProfiler/HotspotDetector）+ `Trace`（TraceContext/Span/TraceExporter） | 框架内每决策点有 Trace；热点报告能产出 |
| 6.3 | `Dr.Diagnostics.Monitor`（Metrics/HealthCheck/Dashboard/Alerting/SLO）+ `Debug`（Inspector/Breakpoint/REPL） | SLO 刀手榜可人工调用；REPL 沙箱隔离 |
| 6.4 | `Dr.Util`（Math/String/Data/Time/Animation/Pattern） | 所有之一方按 P0 规则写就（热路径洪性） |
| 6.5 | `Dr.Plugin`（PluginManager/PluginHost/Hook/MiddlewarePipeline/Extension） | 动态增删插件不重启不退机 |
| 6.6 | `Dr.World`（SceneManager/SceneGraph/SceneTransition，Spatial=QuickZone三件套 审计内置后接入） | QuickZone 过审计，补丁层 Overrides 不改上游本体 |
| 6.7 | 治理：SemVer 发布 + `docs/dones/Deuterium.md` + 扩展作者指南 + ADR-001 | 文档手绘验收过；一个新 Human 能 30 分钟内写完一个玩具扩展 |

---

## 9. 风险与对策

| 风险 | 对策 |
| --- | --- |
| 模块太多（60+ 个子模块）导致开局烂尾 | 里程碑按期走；每期交付可运行闭环，不是烂尾脚手架 |
| VerySafe 自研工作量大 | 默认自研但对齐极小子集；压力测试不达标才开审计通道 |
| PlayerState / QuickZone 上游变更 | 锁版本；更新 = 重新审计 + Overrides 层 |
| Scribe 未审计遗留风险 | Phase 1 验收前 ≈30 分钟人工审计并留档 |
| 与社区系统共存 | 只增不改；Deuterium 是新总线，逐步接管 |
| 分层命名冲突 | 模块前缀统一 `Dr.<Layer>`；`Deuterium.*` 为对外公共区域 |

---

## 10. 先例参考（只读，不引入）
- prvd 'M Wrong（生命周期语义参考）
- ReplicaService / Replica（选择性复制语义）
- jecs / Zap / QuickZone（作为设计参考；后两者仅内置通道候选）
