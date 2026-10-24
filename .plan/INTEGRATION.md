# 集成契约（Deuterium ⇄ TritiumSQL）

> 目标：两个项目**真正互相配合**（不是「SQL 挂在框架旁边」）。
> 本文件是**互通接口与集成验收**的唯一出处。规模预算 → `SCALE.md` §2；不变量 I14/I15 → `README.md` §1；执行步骤 → `STEPS.md` 七点五。
> 验收 ID 为 `AC-G<n>`。

---

## 0. 双向配合，单向依赖

「互相配合」很容易退化成循环依赖，因此：

```
Deuterium  ⟶  TritiumSQL    消费：持久化 / 查询 / 变更流 / 索引
TritiumSQL ⟶  Deuterium     消费：生命周期 / 配置 / 并发原语 / HA / 可观测 / Codec
```

- **I14**：`Dr.*` 对 `Tri.*` 的一切调用只允许出现在 `Deuterium/Integration/`；其余位置出现即 CI 阻断。
- **I15**：跨两套锁体系固定加锁顺序 `Dr.Concurrency.Sync.Mutex`（进程内短临界区）→ `Tri.Txn.LockManager` 行锁（持久/跨服），禁止反向。理由：进程内协程锁与跨服持久锁之间没有统一死锁检测器。

---

## 1. 十条集成路径

| # | 路径 | 方向 | 承担模块 | Wave |
| --- | --- | --- | --- | --- |
| **G1** | 引导与生命周期 | Tri → Dr | `Dr.Integration.{Provider, Configuration, BootGate}` · `Tri.Integration.{DeuteriumProvider, Config, Capability}` | `D0.5` / `T0` |
| **G2** | 引擎端口与 HA 包裹 | Tri → Dr | `Tri.Integration.PortBindings` → `Dr.Runtime.Platform.DataStoreProxy` + `Dr.HA.*` | `D0.4`·`D3.1`·`D3.2` |
| **G3** | 会话态持久化与 Saga | Dr → Tri | `Dr.Integration.Persistence.*` ↔ `Tri.Txn` | `D4.1–4.3` / `T3` |
| **G4** | **DB 变更 → 客户端复制** | Tri → Dr | `Tri.Integration.{ChangeLog, ChangeStreamApi}` → `Dr.Integration.Replication.*` → `Dr.State.Sync.Replicator` | `T3`/`T8` / `D4.7` |
| **G5** | **行级安全（RLS）** | Dr → Tri | `Dr.Security.Access.PolicyEngine` → `Dr.Integration.Security.*` → `Tri.Integration.RowSecurity` | `D2.5` / `T4` |
| **G6** | 查询结果传输 | 双向 | `Tri.Integration.QueryApi.ResultSet` ↔ `Dr.Types.Transform.Codec` → `Dr.Net.Processing` | `D0.3`·`D2.3` / `T4` |
| **G7** | ECS 实体持久化 | Dr → Tri | `Dr.Integration.Ecs.WorldPersist` ↔ `Tri.NoSql` / 关系表 | `D5.5` / `T7` |
| **G8** | 可观测 | Tri → Dr | `Tri.Integration.Telemetry` + `Dr.Integration.Observe.*` → `Dr.Diagnostics.{Trace, Metrics, Logger}` | `D6.1`·`D6.2` / `T8` |
| **G9** | 并发原语与调度 | Tri → Dr | `Tri.Integration.{LockBridge, Scheduler}` → `Dr.Concurrency.{Mutex, TaskScheduler}` · `Dr.HA.Monitor.Watchdog` | `D0.3` / `T1`·`T8` |
| **G10** | 测试协同 | 双向 | `Dr.Testing.Integration.DataStoreSimulator` 即 `Tri.Testing.SimulatorPort` 的后端 | `D0.3` / `T1` |

集成层规模：**32 模块 / 14,100 行核心 + 8,000 行测试**（逐模块 LOC 见 §5；区域预算见 `SCALE.md` §2）。

---

## 2. 四个接缝（纵切时必须冻结）

### 2.1 Port（G2）

```lua
export type Port = {
	GetAsync:    (key: string) -> (any?, string?),
	SetAsync:    (key: string, value: any) -> (boolean, string?),
	UpdateAsync: (key: string, transform: (any?) -> any?) -> (any?, string?),
	RemoveAsync: (key: string) -> (boolean, string?),
	Stats:       () -> { requests: number, budget: number, queued: number },
	SetLimit:    (base: number, perPlayer: number) -> (),
}
```

- `Stats.queued` 存在是因为**排队 ≠ 失败**（`SCALE.md` §1.3）。
- `SetLimit` 封装 `SetRateLimitForRequestType`（T13）。
- 错误返回值必须是三态字符串：`"queued"` / `"throttled"` / `"failed:<code>"`（I12）。
- 三个绑定（Standalone / Deuterium / Simulator）必须跑同一份 `PortContract`，结果一致。

### 2.2 ChangeStream（G4）

```lua
export type Change = {
	lsn: number, table: string, op: "INSERT" | "UPDATE" | "DELETE",
	rowId: string, before: any?, after: any?, txnId: number, ts: number,
}

export type ChangeStream = {
	Subscribe: (table: string, opts: { since: number? }) -> Subscription,
	Poll:      (sub: Subscription, max: number) -> { Change },
	Ack:       (sub: Subscription, lsn: number) -> (),
	Watermark: (table: string) -> number,
}
```

契约要点：
- 变更由 `Tri.Wal` 的**提交路径顺带发射**（T12），不额外扫表 → **未提交事务天然不可见**。
- `lsn` 全序单调；重连一律 `since = lastAck`；重复投递必须被消费方幂等吸收（`rowId + lsn` 去重）。
- 背压：`Watermark` 与 `Ack` 之差即积压量；**没有背压能力的订阅者不允许上线**（否则内存无界增长）。

### 2.3 RowPredicate（G5）— 安全关键

```lua
export type RowPredicate = {
	table: string,
	expr: Expr,          -- 已解析的表达式树（I11：不是字符串）
	trusted: boolean,    -- false = 禁止优化器下推/折叠
	principal: string,   -- 判定主体，写审计日志
}
```

契约要点（真实陷阱，非形式）：
- 行谓词必须在 **Analyzer 之后、Optimizer 之前**注入。
- `trusted = false` 时禁止三件事：**常量折叠**、**谓词下推到 Scan 之下**、**参与索引选择**。否则优化器会把「只能返回自己的行」折叠成常量真值或绕过谓词直接走索引 → 越权读取。
- 每次注入都发审计事件（`principal` + 谓词摘要 + 表名）。

### 2.4 ResultSet / Codec（G6）

```lua
export type ResultSet = {
	columns: { string }, rows: { { any } },
	affected: number, schemaVersion: number,
}
```

编解码走 `Dr.Types.Transform.Codec`（I9）。跨服/跨端传行必须携带 `schemaVersion`；版本不一致时**拒绝解码并回报**，绝不「尽力解析」——静默半对的数据比报错危险。

---

## 3. 启动时序（G1）

```
Kernel.Register(Tri.Integration.DeuteriumProvider)
   │  Construct: 拓扑解析（Tri 依赖 Dr.Runtime/FOUNDATION/TOOLING）
   ▼
Init:  RunContext
    → Configuration（读 `TritiumSQL` 段：db / 分区策略 / 限额 base & perPlayer / 是否启用 WAL）
    → HA（CircuitBreaker + RetryPolicy + Timeout 包裹 Port）
    → Tri.Runtime（端口绑定 + SetLimit）
    → Tri.Catalog（Schema 载入 → BootMigrator 跑未完成迁移）
    → Dr.Data（TritiumAdapter 就绪，六段流水最后一段接管）
    → Dr.State（ChangeStream 以 since = Watermark 订阅需要复制的表）
    → Dr.ECS（WorldPersist 注册持久化字段）
    ▼
Start: PageCache 预热 → ChangeStream 开始消费 → Watchdog 接管 VACUUM / CHECKPOINT 周期
    ▼
客户端首帧: Replicator 用 since = lastAck 补齐断线期间变更
```

硬约束（`BootGate` 显式断言，不依赖拓扑排序「碰巧」正确）：**`Tri.Catalog` 必须早于 `Dr.Data` Init**（否则适配器无表可写）；**`Dr.State` 必须晚于 `Tri.Wal`**（否则变更流无游标）。

---

## 4. 集成层模块清单（逐模块 LOC，唯一出处）

### 4.1 `Deuterium/Integration/` — 18 模块 / 8,400 行核心（Step 50–57）

| Step | 模块 | 行 | 职责 |
| --- | --- | --- | --- |
| 50 | `Types.luau` | 150 | 四个接缝的类型（§2） |
| 50 | `Capability.luau` | 250 | 能力探测：Tri 缺失/版本不符时降级（框架必须能无 DB 启动） |
| 51 | `Provider.luau` | 200 | 把 `Tri.Integration.DeuteriumProvider` 注册进 Kernel |
| 51 | `Configuration.luau` | 150 | `TritiumSQL` 配置段读取与校验 |
| 51 | `BootGate.luau` | 250 | §3 的两条硬顺序断言 + 迁移触发 |
| 52 | `Persistence/TritiumAdapter.luau` | 700 | 六段流水最后一段落到关系表 |
| 52 | `Persistence/SessionStore.luau` | 600 | 会话态 ↔ 表 + 列的映射 |
| 53 | `Persistence/SagaBridge.luau` | 900 | `Dr.Data.Reliability.Transaction` ↔ `Tri.Txn` 协调与逆序回滚 |
| 54 | `Replication/ChangeStream.luau` | 800 | ChangeStream 客户端（订阅/游标/背压/重连） |
| 54 | `Replication/ReplicaBridge.luau` | 600 | Change → `Dr.State.Sync.Replicator` |
| 54 | `Replication/ConvergenceGuard.luau` | 500 | 乱序/重复检测、幂等吸收、`lastAck` 持久化 |
| 55 | `Security/RowPredicate.luau` | 700 | `PolicyEngine` → 行谓词编译（Expr 树） |
| 55 | `Security/PredicateInjector.luau` | 500 | 注入点 + 三种优化禁用 + 审计 |
| 56 | `Net/ResultCodec.luau` | 450 | ResultSet ↔ Net 包（带 `schemaVersion`） |
| 56 | `Net/QueryService.luau` | 400 | 客户端可安全调用的查询门面（白名单 + RBAC） |
| 57 | `Ecs/WorldPersist.luau` | 600 | World 快照 ↔ Tri（批量 upsert 经 `BatchExecutor`） |
| 57 | `Observe/QuerySpan.luau` | 350 | 算子级 span |
| 57 | `Observe/SqlMetrics.luau` | 300 | `Tri.Stat` → Metrics |
| — | `TestKit/E2E.luau` | 400 | 端到端场景骨架（计入集成测试） |
| **合计** | **18** | **8,400** | |

### 4.2 `TritiumSQL/Tri/Integration/` — 14 模块 / 5,700 行核心（Step 60–65）

| Step | 模块 | 行 | 职责 |
| --- | --- | --- | --- |
| 60 | `Types.luau` | 150 | 反向接缝类型 |
| 60 | `DeuteriumProvider.luau` | 250 | 可选：把自己注册为 Dr Provider |
| 60 | `Config.luau` | 150 | 配置解析入口 |
| 60 | `Capability.luau` | 300 | 探测 Dr 提供的端口/HA/Codec 是否存在 |
| 61 | `Preload.luau` | 200 | 注入 I9 的 Codec（唯一序列化来源） |
| 61 | `PortBindings.luau` | 450 | 绑定 Dr proxy + HA 包裹 |
| 62 | `ChangeLog.luau` | 700 | 提交路径顺带发射变更（不额外扫表） |
| 62 | `ChangeStreamApi.luau` | 600 | 订阅/游标/背压/水位 |
| 63 | `RowSecurity.luau` | 550 | 谓词接收点 + 优化禁用标记 |
| 63 | `LockBridge.luau` | 400 | I15 的加锁顺序强制 |
| 64 | `Scheduler.luau` | 400 | VACUUM / CHECKPOINT 周期注册 |
| 64 | `Telemetry.luau` | 500 | span / metric 发射 |
| 65 | `QueryApi.luau` | 600 | 给 Dr 的稳定查询门面 |
| 65 | `Migration/BootMigrator.luau` | 450 | 启动期渐进迁移 |
| **合计** | **14** | **5,700** | |

---

## 5. 集成验收

| # | 验收（AC-G<n>） | 路径 |
| --- | --- | --- |
| G1 | ① 框架在 `TritiumSQL` 缺失时仍能完整启动并给出明确降级日志（不崩）② `BootGate` 两条顺序断言在人为打乱时**必须失败**（负例测试） | G1 |
| G2 | 断网 60s 内不雪崩：Circuit 打开 → 请求排队 → 恢复后 30s 内自愈；三绑定 `PortContract` 一致 | G2 |
| G3 | Saga 任一步中断逆序回滚，会话态与关系表**双双回到起点**（两次快照比对） | G3 |
| G4 | ① 写入 100 行 → 客户端严格按 `lsn` 收到 100 个变更且幂等（无重复效果）② 断线 30s 期间写入 50 行 → 重连用 `lastAck` 补齐，逐行比对最终一致 ③ 订阅者不 `Ack` 时积压有上界（背压生效），内存不无界增长 | G4 |
| G5 | ① **越权负例 ≥10 个**（索引选择 / 常量折叠 / 下推 三类绕过手法）全部被拦 ② 每次注入都有审计记录（主体 + 摘要 + 表） | G5 |
| G6 | `schemaVersion` 不一致时拒绝解码并回报，不产生半对数据 | G6 |
| G7 | 1e3 实体的 World 快照往返一致；批量写请求数满足预算 | G7 |
| G8 | 每个算子在 Trace 树里有 span；慢查询进日志 | G8 |
| G9 | I15 的加锁顺序被 `LockBridge` 强制执行，反序调用直接报错（负例测试） | G9 |
| G10 | 同一套端到端场景在 `SimulatorPort` 与真实 DataStore 上**结果一致** | G10 |

---

## 6. 风险与不可压缩项

R2（从未合练）、R3（RLS 被绕过）、R5（复制乱序/丢变更）、R6（双锁死锁）、R7（启动顺序耦合）、R14（集成层垃圾场）的完整条目在 `README.md` §6。

**不可压缩**：G4 + G5 合计 **4,950 行核心**（G4：`ChangeLog` 700 + `ChangeStreamApi` 600 + `ChangeStream` 800 + `ReplicaBridge` 600 + `ConvergenceGuard` 500 = 3,200；G5：`RowPredicate` 700 + `PredicateInjector` 500 + `RowSecurity` 550 = 1,750）——它们是全计划里唯一**同时压安全与一致性**的部分。排期吃紧时砍 **G7（ECS 持久化，600 行）**，不砍这两个。

**目录纪律**：集成层模块必须映射到 §1 的某条 G 路径，否则不进目录（R14）。
