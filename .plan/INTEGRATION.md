# 集成契约（Deuterium ⇄ TritiumSQL）

> 目标：两个项目**真正互相配合**（不是「SQL 挂在框架旁边」），并把两者合计做到 **100,000 行**的量级。
> 本文档是集成的唯一权威；`.plan/SCALE.md` §2.2 的 LOC 预算被本文档 §4 取代。

---

## 0. 配合的前提：双向配合，单向依赖

「互相配合」很容易退化成循环依赖。规则：

```
Deuterium  ⟶  TritiumSQL    消费：持久化 / 查询 / 变更流 / 索引        ← 只允许出现在 Dr.Integration/
TritiumSQL ⟶  Deuterium     消费：生命周期 / 配置 / 并发原语 / HA / 可观测 / Codec
```

**I14（新增不变量）**：`Deuterium` 对 `TritiumSQL` 的一切调用只允许出现在 `Deuterium/Integration/` 一个目录内。其他任何 `Dr.*` 模块 require `Tri.*` 视为架构违反，CI 阻断。

**I15（新增不变量）**：跨两套锁体系的加锁顺序固定为 **先 `Dr.Concurrency.Sync.Mutex`（进程内、短临界区）→ 后 `Tri.Txn.LockManager` 行锁（持久、跨服）**；禁止反向。理由：进程内协程锁与跨服持久锁之间没有统一的死锁检测器，唯一可行的保证是固定顺序。

---

## 1. 十条集成路径

| # | 路径 | 方向 | 承担方 | 对应 Phase | 核心 LOC |
| --- | --- | --- | --- | --- | --- |
| **G1** | 引导与生命周期 | Tri → Dr | `Dr.Integration.Provider` · `Tri.Integration.DeuteriumProvider` | Dr 0.5 / Tri 0 | 1,100 |
| **G2** | 引擎端口与 HA 包裹 | Tri → Dr | `Tri.Integration.PortBindings` → `Dr.Runtime.Platform.DataStoreProxy` | Dr 0.4 · 3.1 · 3.2 | 1,300 |
| **G3** | 会话态持久化与 Saga | Dr → Tri | `Dr.Integration.Persistence.*` | Dr 4.1–4.3 / Tri 3 | 2,600 |
| **G4** | **DB 变更 → 客户端复制** | Tri → Dr | `Tri.Integration.ChangeLog` → `Dr.Integration.Replication.*` → `Dr.State.Sync.Replicator` | Tri 3/8 / Dr 4.7 | 3,000 |
| **G5** | **行级安全（RLS）** | Dr → Tri | `Dr.Security.Access.PolicyEngine` → `Dr.Integration.Security.*` → `Tri.Integration.RowSecurity` | Dr 2.5 / Tri 4 | 2,400 |
| **G6** | 查询结果传输 | 双向 | `Tri.Integration.QueryApi.ResultSet` ↔ `Dr.Types.Transform.Codec` → `Dr.Net.Processing` | Dr 2.3 · 0.3 / Tri 4 | 1,600 |
| **G7** | ECS 实体持久化 | Dr → Tri | `Dr.Integration.Ecs.WorldPersist` ↔ `Tri.NoSql` / 关系表 | Dr 5.5 / Tri 7 | 1,800 |
| **G8** | 可观测 | Tri → Dr | 算子 span → `Dr.Diagnostics.Trace`；`Tri.Stat` → `Metrics`；慢查询 → `Logger` | Dr 6.1 · 6.2 / Tri 8 | 1,500 |
| **G9** | 并发原语与调度 | Tri → Dr | `Mutex` / `TaskScheduler` / `Watchdog` 驱动锁、VACUUM、CHECKPOINT | Dr 14.x / Tri 1 · 8 | 1,400 |
| **G10** | 测试协同 | 双向 | `DataStoreSimulator` 即 `SimulatorPort` 后端；端到端场景套件 | Dr 15 / Tri 1 | 2,200 |

集成层合计：**18,900 行核心**（Deuterium 侧 18 模块 8,400 行；TritiumSQL 侧 14 模块 5,700 行；两套集成测试 4,800 行见 §4）。

---

## 2. 关键接缝的接口（动工前先冻结这四个）

### 2.1 Port（G2）— 已是 Step 30 的定义，此处补三点

```lua
export type Port = {
	GetAsync:    (key: string) -> (any?, string?),
	SetAsync:    (key: string, value: any) -> (boolean, string?),
	UpdateAsync: (key: string, transform: (any?) -> any?) -> (any?, string?),
	RemoveAsync: (key: string) -> (boolean, string?),
	Stats:       () -> { requests: number, budget: number, queued: number },
	SetLimit:    (base: number, perPlayer: number) -> (),   -- 新增：G2 显式设限
}
```

补三点：① `Stats` 增加 `queued`（排队 ≠ 失败，`SCALE.md` §1.3）；② 新增 `SetLimit`（`SetRateLimitForRequestType` 的封装）；③ 错误返回值必须是**三态字符串**（`"queued"` / `"throttled"` / `"failed:<code>"`）。

### 2.2 ChangeStream（G4）— 全新

```lua
export type Change = {
	lsn: number,
	table: string,
	op: "INSERT" | "UPDATE" | "DELETE",
	rowId: string,
	before: any?,
	after: any?,
	txnId: number,
	ts: number,
}

export type ChangeStream = {
	Subscribe: (table: string, opts: { since: number? }) -> Subscription,
	Poll:      (sub: Subscription, max: number) -> { Change },
	Ack:       (sub: Subscription, lsn: number) -> (),
	Watermark: (table: string) -> number,
}
```

契约要点：
- `Change` 由 `Tri.Wal` 的提交路径**顺带**发射（不额外扫表），因此**只在已提交事务后可见**——复制天然不会看到未提交数据。
- `lsn` 全序单调；重连一律用 `since = lastAck` 补齐；重复投递必须被消费方幂等吸收（`rowId + lsn` 去重）。
- 背压：`Poll` 返回上限由调用方给，`Watermark` 与 `Ack` 的差就是积压量。**没有背压能力的订阅者不允许上线**（否则内存会无界增长）。

### 2.3 RowPredicate（G5）— 全新，安全关键

```lua
export type RowPredicate = {
	table: string,
	expr: Expr,          -- 已解析的表达式树（I11：不是字符串）
	trusted: boolean,    -- false = 禁止优化器下推/折叠
	principal: string,   -- 判定主体，写审计日志
}
```

契约要点（这条是**真实的安全陷阱**，不是形式）：
- `PolicyEngine` 编译出的行谓词必须在 **Analyzer 之后、Optimizer 之前**注入 `Tri.Query`。
- `trusted = false` 时禁止三件事：**常量折叠**、**谓词下推到 Scan 之下**、**参与索引选择**。否则优化器会把「只能返回自己的行」折叠成常量真值或绕过谓词直接走索引，形成越权读取。
- 每次注入都发审计事件（`principal` + 谓词摘要 + 命中的表）。

### 2.4 ResultSet / Codec（G6）— 复用 I9 的同一份 Codec

```lua
export type ResultSet = {
	columns: { string },
	rows: { { any } },
	affected: number,
	schemaVersion: number,
}
-- 编解码走 Dr.Types.Transform.Codec（I9），带 schema 版本做双端一致性校验
```

契约要点：跨服/跨端传行必须携带 `schemaVersion`，版本不一致时**拒绝解码并回报**，而不是「尽力解析」——静默半对的数据比报错危险。

---

## 3. 启动时序（G1）

```
Kernel.Register(Tri.Integration.DeuteriumProvider)
   │  Construct: 拓扑解析（Tri 依赖 Dr.Runtime/FOUNDATION/TOOLING）
   ▼
Init:  RunContext
    → Configuration（读 `TritiumSQL` 段：db 名 / 分区策略 / 限额 base & perPlayer / 是否启用 WAL）
    → HA（CircuitBreaker + RetryPolicy + Timeout，包裹 Port）
    → Tri.Runtime（端口绑定 + SetLimit）
    → Tri.Catalog（Schema 载入 → BootMigrator 跑未完成的迁移）
    → Dr.Data（TritiumAdapter 就绪，六段流水的最后一段接管）
    → Dr.State（ChangeStream 以 since = Watermark 订阅需要复制的表）
    → Dr.ECS（WorldPersist 注册持久化字段）
    ▼
Start: PageCache 预热 → ChangeStream 开始消费 → Watchdog 接管 VACUUM / CHECKPOINT 周期
    ▼
客户端首帧: Replicator 用 since = lastAck 补齐断线期间变更
```

硬约束：**`Tri.Catalog` 必须早于 `Dr.Data` Init**（否则适配器无表可写）；**`Dr.State` 必须晚于 `Tri.Wal`**（否则变更流无游标）。这两条在 `BootGate` 里显式断言，不依赖拓扑排序「碰巧」正确。

---

## 4. 100,000 行预算与记分板

### 4.1 预算表（取代 `SCALE.md` §2.2）

| 区域 | 模块 | 核心 | 测试 | 示例/工具 | 小计 |
| --- | --- | --- | --- | --- | --- |
| Deuterium 框架本体 | 313 | 26,000 | 9,000 | — | 35,000 |
| **`Dr.Integration`** | **18** | **8,400** | **4,500** | — | **12,900** |
| TritiumSQL 引擎本体 | 95 | 22,000 | 9,500 | — | 31,500 |
| **`Tri.Integration`** | **14** | **5,700** | **3,500** | — | **9,200** |
| 端到端 / 场景 / 故障注入矩阵 | — | — | 5,000 | — | 5,000 |
| 示例（≥5）· 基准 · CLI/Studio 工具 · 发布脚本 | — | — | — | 6,400 | 6,400 |
| **合计** | **440** | **62,100** | **31,500** | **6,400** | **100,000** |

- **测试占 31.5%**。这是有意的：440 个模块、可崩溃的存储层、可解析的 SQL 方言，测试低于 25% 就等于没测。
- 分档指导（A/B/C 见 `SCALE.md` §5）：**A 档核心路径 250–600 行/模块**（页、B+ 树、事务、优化器、解析器、锁、请求预算、以及 G4/G5 两个集成路径）；**B 档 120–250 行**；**C 档 40–120 行**。
- 这是**下限**。A 档按「不封顶」标准写，实际会到 120,000–135,000 行；低于 100,000 视为功能面缩水，不是「写得紧凑」。

### 4.2 记分板（`scripts/loc-budget.luau`）

统计各区域的 `*.luau` 行数，与预算表比对，输出：

```
区域               实际      预算      占比     判定
Deuterium 本体     26,412    26,000    101.6%   OK
Dr.Integration      3,140     8,400     37.4%   UNDER
...
合计               41,220   100,000     41.2%   FLOOR-NOT-MET
```

判定规则：
- **release 分支**：合计 < 100,000 或任一区域 < 预算 70% → **阻断**。
- **日常分支**：只 warn（否则 CI 永远红，反而没人看）。
- 数据入 `metrics/loc-history.csv`，每次 release 追加一行 → 顺带得到「进度曲线」，比「完成度百分比」可靠。

---

## 5. 集成层模块清单（写码顺序即此顺序）

### 5.1 `Deuterium/Integration/`（18 模块 = Step 50–57）

| Step | 模块 | 行 | 职责 |
| --- | --- | --- | --- |
| 50 | `Types.luau` | 150 | 四个接缝的类型（§2） |
| 50 | `Capability.luau` | 250 | 能力探测：Tri 缺失/版本不符时降级（框架必须能无 DB 启动） |
| 51 | `Provider.luau` | 200 | 把 `Tri.Integration.DeuteriumProvider` 注册进 Kernel |
| 51 | `Configuration.luau` | 150 | `TritiumSQL` 配置段读取与校验 |
| 51 | `BootGate.luau` | 250 | §3 的两条硬顺序断言 + 迁移触发 |
| 52 | `Persistence/TritiumAdapter.luau` | 700 | 六段流水最后一段落到关系表 |
| 52 | `Persistence/SessionStore.luau` | 600 | 会话态 ↔ 表 + 列的映射 |
| 53 | `Persistence/SagaBridge.luau` | 800 | `Dr.Data.Reliability.Transaction` ↔ `Tri.Txn` 的协调与逆序回滚 |
| 54 | `Replication/ChangeStream.luau` | 700 | ChangeStream 客户端（订阅/游标/背压/重连） |
| 54 | `Replication/ReplicaBridge.luau` | 600 | Change → `Dr.State.Sync.Replicator` |
| 54 | `Replication/ConvergenceGuard.luau` | 500 | 乱序/重复检测、幂等吸收、`lastAck` 持久化 |
| 55 | `Security/RowPredicate.luau` | 700 | `PolicyEngine` → 行谓词编译（Expr 树） |
| 55 | `Security/PredicateInjector.luau` | 500 | 注入点 + 三种优化禁用 + 审计 |
| 56 | `Net/ResultCodec.luau` | 450 | ResultSet ↔ Net 包（带 schemaVersion） |
| 56 | `Net/QueryService.luau` | 400 | 客户端可安全调用的查询门面（白名单 + RBAC） |
| 57 | `Ecs/WorldPersist.luau` | 600 | World 快照 ↔ Tri（批量 upsert 经 `BatchExecutor`） |
| 57 | `Observe/QuerySpan.luau` | 350 | 算子级 span |
| 57 | `Observe/SqlMetrics.luau` | 300 | `Tri.Stat` → Metrics |
| — | `TestKit/E2E.luau` | 400 | 端到端场景骨架（计入集成测试） |

### 5.2 `TritiumSQL/Tri/Integration/`（14 模块 = Step 60–65）

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

---

## 6. 集成层验收（每条都可断言）

| # | 验收 | 归属 |
| --- | --- | --- |
| A1 | 框架在 `TritiumSQL` 缺失时仍能完整启动，且 `Capability` 给出明确降级日志（不是报错崩） | G1 |
| A2 | `BootGate` 的两条顺序断言在人为打乱时**必须失败**（负例测试） | G1 |
| A3 | 断网 60s 内不雪崩：Circuit 打开 → 请求排队 → 恢复后 30s 内自愈 | G2 |
| A4 | Saga 任一步中断逆序回滚，会话态与关系表**双双回到起点**（用两次快照比对） | G3 |
| A5 | DB 写入 100 行 → 客户端收到 100 个变更，**顺序严格按 lsn**，无重复效果（幂等） | G4 |
| A6 | 客户端断线 30s 期间写入 50 行 → 重连用 `lastAck` 补齐，最终一致（逐行比对） | G4 |
| A7 | 订阅者不 `Ack` 时积压有上界（背压生效），内存不无界增长 | G4 |
| A8 | **越权负例**：用户 A 的谓词无法通过索引选择/常量折叠绕过并读到用户 B 的行（≥10 个攻击用例） | G5 |
| A9 | 每次行谓词注入都有审计记录（主体 + 摘要 + 表） | G5 |
| A10 | `schemaVersion` 不一致时拒绝解码并回报，不产生半对数据 | G6 |
| A11 | 1e3 实体的 World 快照往返一致；批量写请求数满足预算 | G7 |
| A12 | 每个算子在 Trace 树里有 span；慢查询进日志 | G8 |
| A13 | I15 的加锁顺序被 `LockBridge` 强制执行，反序调用直接报错（负例测试） | G9 |
| A14 | 同一套端到端场景在 `SimulatorPort` 与真实 DataStore 上**结果一致** | G10 |

---

## 7. 集成层风险

| 风险 | 等级 | 对策 |
| --- | --- | --- |
| **RLS 被优化器绕过**（谓词下推/常量折叠/索引选择） | 极高 | 四个接口层的 `trusted` 标记 + A8 的 ≥10 个攻击用例，安全用例进 CI 阻断 |
| 复制看到未提交数据 / 乱序 / 丢变更 | 高 | 变更只从提交路径发射（§2.2）+ lsn 单调 + `lastAck` 补齐 + A5/A6 |
| 启动顺序耦合（Tri 未就绪时 Dr.Data 已 Init） | 高 | `BootGate` 显式断言 + A2 负例 |
| **两套锁体系互相死锁且不可见** | 高 | I15 固定顺序 + `LockBridge` 强制 + A13 |
| 集成层变成「什么都往里塞」的垃圾场 | 中 | I14 只约束方向；集成层模块必须实现 §1 的十条路径之一，否则进不了目录 |
| 订阅者无背压导致内存无界 | 中 | A7；契约里写明「没有背压能力的订阅者不允许上线」 |
| 100k 行变成凑行数（灌水模块） | 中 | §4.2 记分板只防止缩水、不奖励超额；新增模块必须对应 `SCALE.md` §4.2 的 In 列或 §1 的十路径，否则不进仓库 |

---

未读/未验证：`Dr.Signal` 在 `SCALE.md` 里被提前到 Phase 2，但 G4/G8 的集成路径我按「直接调用 + 可选 Signal 广播」写的，如果 Signal 未就绪则集成层用回调数组（性能更好、依赖更少），落地时二选一 —— 这个选择会影响到 Step 54/57 的接口形状。风险：G4（复制）与 G5（RLS）是集成层里唯一两个**同时压安全与一致性**的路径，合计 5,400 行核心 + 攻击用例，是全局最不能压缩的部分；如果排期吃紧，应砍 G7（ECS 持久化）而不是这两个。
