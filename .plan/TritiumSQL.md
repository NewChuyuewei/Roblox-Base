# TritiumSQL — 实施计划（Plan of Record）

> **来源**：重写自 `Text File.txt`（原代号 VoxDB / VQL，已废弃）
> **命名**：产品 **TritiumSQL**；模块前缀 `Tri.*`（对齐 Deuterium 的 `Dr.*`）；查询方言 **TriSQL**；DataStore 键前缀 `tri:`；发布包 `vospek/tritiumsql`
> **一句话**：在 `DataStoreService`（本质 KV）之上，做出关系型严谨性 + NoSQL 灵活性 + B+ 树索引 + 企业级扩展的数据库引擎。
> **依赖**：`Deuterium` 的 RUNTIME + FOUNDATION + TOOLING 三层（见 `README.md` 边界铁律）。不依赖 `Dr.Net` / `Dr.Data` / `Dr.State`。

---

## 0. 前提与物理天花板（所有设计都要围绕它展开）

| 约束 | **已核实值**（官方文档） | 设计后果 |
| --- | --- | --- |
| data store name / **key name** / scope | **各 50 字符（硬限）** | 键名预算只有 50 字符是**可行性前提**而非优化：长值一律走短哈希 |
| 单值大小 | **4,194,304 字节（4 MiB）** | 页目标容量取 **4KB**，留足序列化余量 |
| 请求限速 | `rateLimit = baseLimit + perPlayerLimit × numPlayers`，且可由 `DataStoreService:SetRateLimitForRequestType` **运行期覆盖** | `RequestBudget` **不硬编码常量**：启动时显式设限并读回实际值，它是配额的唯一真相来源 |
| 超限语义 | 请求进队列（Set / OrderedSet / Get / OrderedGet），**键级节流**会跳过该键的请求而非失败 | 区分「排队」「键级节流」「真失败」三态；**不把排队当丢弃** |
| Lua 无多线程 | 并发靠 `task.spawn` 协程 | 锁实现必须避免协程饥饿；等待必须让出 |
| 树高 | 每层 = 最坏多一次读 | 树高控制 ≤ 3，超过即触发重构 |

> 完整来源与推论见 `SCALE.md` §1.3；功能面验收口径见 `SCALE.md` §4.2。

**I12（请求次数是验收指标）**：本计划每个波次的验收都包含 DataStore 请求次数断言，结果正确不足以通过。

---

## 1. 模块地图

```
Tri.Runtime/     StorePort · MemoryStorePort · Bindings（Standalone | Deuterium）· RuntimeTypes
Tri.Catalog/     Catalog · SchemaStore · TableRegistry · NamespaceCodec · Partitioner
Tri.Format/      ── 不建：统一用 Dr.Types.Transform.Codec（I9）
Tri.Storage/     PageManager · Page · Slot · PageCache · HeapLayout · Vacuum
Tri.Index/       BPlusTree · NodeCodec · IndexScan · UniqueGuard · CompositeKey · PartialFilter
Tri.Request/     RequestQueue · TokenBucket · BatchExecutor · RequestBudget
Tri.Txn/         TransactionManager · Mvcc · LockManager · WaitForGraph · UndoLog · Isolation
Tri.Wal/         WalWriter · WalReader · Checkpoint · Recovery
Tri.Query/       Lexer · Parser · Ast · Analyzer · LogicalPlan · Optimizer · PhysicalPlan
                 PreparedStatement · Executor · Operators/
Tri.Stat/        StatisticsCollector · Histogram · Cardinality · IndexCostModel
Tri.Ddl/         OnlineDdl · MigrationWorker · VersionGate
Tri.NoSql/       JsonPath · FunctionIndex · TimeSeries · GraphEdge
Tri.Adapters/    DrDataAdapter（供 Deuterium Dr.Data 反向调用）
Tri.Testing/     SimulatorBindings · Fixtures · RequestAssert
```

---

## 2. 关键设计决定（重写时确定的，需遵守）

| # | 决定 | 理由 |
| --- | --- | --- |
| T1 | **请求管线（`Tri.Request`）在 Phase 1，不留在「企业级特性」章节** | 限速是物理天花板；先有预算层，后续每层的写路径才能被计量与限流 |
| T2 | **L1 页缓存在 Phase 1** | 无缓存则 CRUD 的请求次数不可接受，后续索引/事务的测试都会因超配额而失真 |
| T3 | **序列化不引入 `Dr.Net.Processing.Serializer`** | 那是 SERVICE 层；TritiumSQL 只用 FOUNDATION 的 `Dr.Types.Transform.Codec`（I9） |
| T4 | **引擎 API 经 `Tri.Runtime.StorePort` 端口** | 满足 Deuterium I10；Standalone 绑定（直连 `DataStoreService`）是唯一例外文件，独立成文件并标注；Deuterium 绑定走 `Dr.Runtime.Platform.DataStoreProxy`（Deuterium Wave 0.4） |
| T5 | **SQL 必须在 Init/Construct 期编译**（D3） | Deuterium I11 / P0：运行期热路径禁止解析与字符串查表。`Compile(sql) -> PreparedStatement`，缓存按 SQL 文本哈希 |
| T6 | **同时提供类型化构建器** | 热路径首选；避免 SQL 字符串成为唯一入口 |
| T7 | **WAL 用 `OrderedDataStore`** | 其有序性天然按 LSN 顺序存储 |
| T8 | **默认隔离级别 = Read Committed** | Roblox 请求限制下性能最优；MVCC 与 2PL 作为可选升级 |
| T9 | **软删除 + 异步 VACUUM** | 删除路径不阻塞写；合并半满兄弟节点延后 |
| T10 | **元数据全在 `tri:__catalog__:*`** | 表目录、分区路由、Schema 版本、序列、锁，全部集中可审计 |
| T11 | **与 Deuterium 的全部互通只在 `Tri/Integration/`** | 双向配合、单向依赖（Dr 也只在 `Dr.Integration/` 调 Tri）；10 条集成路径 G1–G10 见 `INTEGRATION.md` |
| T12 | **变更流从提交路径发射** | `Tri.Wal` 提交时顺带发射 `Change`，不额外扫表；未提交事务天然不可见。这是 G4（DB → 客户端复制）的地基 |

---

## 3. 存储层（Phase 0–1 主体）

### 3.1 命名空间（`Tri.Catalog.NamespaceCodec`）

```
tri:[db]:[table]:[partition]:[key_type]:[value]

  tri:main:users:p0:row:u_10023          → 行（实际在页内）
  tri:main:users:p0:pg:0007              → 页
  tri:main:users:p0:idx:email:a@b.com    → 二级索引条目
  tri:main:users:meta:schema             → 表结构定义
  tri:__catalog__:tables                 → 全局表目录
  tri:__catalog__:routes                 → 分区路由
  tri:__txn__:lock:u_10023               → 行级锁（UpdateAsync 原子执行）
  tri:__seq__:users:id                   → 自增序列
  tri:__wal__:<lsn>                      → WAL 条目（OrderedDataStore）
```

**验收**：编码器对任意输入断言 key ≤ 50 字符（长值入短哈希表）；解码唯一性单测（round-trip 1000 例）。

### 3.2 页（`Tri.Storage.Page`）

```
Page = {                          -- 一个 DataStore value
  pageId, tableId, partition,
  slots: [ { slotId, rowId, data, deleted, txnId } ],   -- 类 PostgreSQL heap page
  freeSpace, nextPageId, lsn
}
```

页容量目标 **4KB 等效数据**。`HeapLayout` 负责槽位复用与碎片统计。

**验收**：4KB 页内 ≥ 32 行（典型行）；页满触发分裂且分裂后两页均 ≥ 40% 占用；删除后可被 VACUUM 回收的空洞有断言。

### 3.3 分区（`Tri.Catalog.Partitioner`）

| 策略 | 场景 |
| --- | --- |
| Hash | 主键均匀分布、点查询为主 |
| Range | 时间序列、数值范围 |
| List | 枚举（region / gamemode） |

分区元数据入 `tri:__catalog__:routes`，由路由层决定访问分片。
**验收**：三种策略各 1 组数据下，点查询命中的分区唯一且正确；扩容新增分区不改变既有行的路由结果。

### 3.4 请求管线（`Tri.Request`，决定 T1）

```
上层操作 → RequestQueue（P0..P3 优先级）
        → TokenBucket（按 60 + 10×玩家数 预算）
        → BatchExecutor（合并可批量操作）
        → StorePort
```

优先级：`P0` 事务提交 / 崩溃恢复 → `P1` 玩家数据读写 → `P2` 索引维护 → `P3` VACUUM / 统计收集。

**验收**：人为把配额设为 10 req/min，写入 100 行：**0 丢失**、排队而非报错、`RequestBudget` 计数与实际 `StorePort` 调用数完全一致；P0 抢在 P3 之前执行（用时间戳断言）。

---

## 4. 索引层（Phase 2 / 6）

### 4.1 B+ 树在 KV 上的映射

```
内部节点：{ nodeId, isLeaf: false, keys: [k1,k2,k3], children: [n1..n4] }
叶子节点：{ nodeId, isLeaf: true,
            entries: [ { key, rowId, pageId, slotId } ],
            prevLeaf, nextLeaf }              -- 双向链表，范围扫描用
```

根节点 ID 入表元数据；**树高 ≤ 3**，超限告警并触发重构。

### 4.2 索引类型

| 类型 | 语义 |
| --- | --- |
| PRIMARY | 聚簇，行随主键排序 |
| SECONDARY | 非聚簇，叶存 `secondary_key → primary_key` |
| UNIQUE | 插入前验唯一（需锁） |
| COMPOSITE | 多列联合键，按列优先级排序 |
| PARTIAL | 带 WHERE 的稀疏索引 |

### 4.3 维护路径

- 写：找目标叶 → 插 entry → 满则 split → 向上传播
- 删：软删除标记 → 异步 merge 半满兄弟
- `Vacuum`：清软删除条目、重构过疏页

**验收**：1e4 行建索引后点查的 DataStore 读次数 ≤ 树高（断言实际读数，非仅结果）；范围扫描全走叶链、无回父节点；节点分裂后父子键区间无空洞（区间一致性断言）；**二级索引与主键一致性**——任意写路径不产生孤儿索引条目。

---

## 5. 关系模型（Phase 0 / 4）

### 5.1 Schema（`Tri.Catalog.SchemaStore`）

```
{ tableId, tableName, version,
  columns: [ { name, type, nullable, default, primaryKey, unique } ],
  constraints: [ { type:"FK", column, refTable, refColumn, onDelete }
                 { type:"CHECK", expr } ],
  indexes: [ { indexId, columns, type, unique, where? } ] }
```

`version` 驱动在线 DDL，不锁表，旧行按需迁移。

### 5.2 类型系统

| TriSQL 类型 | 内部表示 | 注意 |
| --- | --- | --- |
| `INT`/`BIGINT` | number | Lua number 精度边界需显式断言 |
| `FLOAT` | number | |
| `VARCHAR(n)` | string | 超长截断验证明示报错，不静默 |
| `TEXT` | string | 超长分块 |
| `BOOLEAN` | boolean | |
| `TIMESTAMP` | number (Unix ms) | |
| `UUID` | string | 生成策略见 `Tri.Catalog` |
| `JSON` | table（嵌套） | NoSQL 入口 |
| `ARRAY<T>` | table | |
| `ENUM` | string + 校验集合 | |

### 5.3 外键与完整性

外键无原生支持，**在执行引擎层强制**：INSERT/UPDATE 验引用行存在；DELETE 按 `ON DELETE`（CASCADE / SET NULL / RESTRICT）处理；检查失败 → 事务回滚。

**验收**：三类 `ON DELETE` 各 1 组用例；CHECK 表达式负例 100% 拒绝；越界/超长/类型不符的负例样例集 100% 拒绝并给出列路径。

---

## 6. 事务与并发（Phase 3）

### 6.1 事务模型

```
BEGIN → [读/写] → COMMIT / ROLLBACK
持有：txnId, startTimestamp, status, readSet, writeSet, undoLog
```

### 6.2 隔离级别

| 级别 | 机制 |
| --- | --- |
| Read Uncommitted | 直接读 |
| **Read Committed（默认，T8）** | 读时查行锁 |
| Repeatable Read | MVCC 快照读 |
| Serializable | 两阶段锁 2PL |

### 6.3 MVCC

```
Row: { rowId, data, createdTxnId, expiredTxnId }
```

读看见 `createdTxnId ≤ 当前txn` 且 `expiredTxnId = null 或 > 当前txn` 的版本；写建新版本并给旧版本置 `expiredTxnId`；旧版本由 VACUUM 清理。

### 6.4 锁管理器

粒度：Table → Partition → Page → Row。类型：`S` / `X` / `IS` / `IX`。
死锁：维护等待图（Wait-For Graph），定期检环 → 回滚代价最小的事务。
锁状态存 `tri:__txn__:lock:*`，用 `UpdateAsync` 的原子性保证锁操作原子。

**验收**：故意构造 2.5k 步的环状等待，检环在 ≤ 2× 链路长度内发现并回滚**代价最小**者；隔离级别矩阵测试（脏读/不可重复读/幻读）逐格有断言；P0 场景：崩溃恢复对已提交事务 **100% Redo**、未提交 **100% Undo**。

---

## 7. WAL（Phase 3）

```
{ lsn, txnId, type, tableId, rowId, before, after, timestamp }
type: INSERT | UPDATE | DELETE | COMMIT | ROLLBACK | CHECKPOINT
```

先写 WAL 再写页；WAL 入 `OrderedDataStore`（T7）；`Checkpoint` 定期落内存状态并截断旧 WAL；`Recovery` 重启时 Redo 已提交 / Undo 未提交。

**验收**：在任意 WAL 边界注入崩溃，恢复后数据库状态 = 崩溃前最后一次 `COMMIT` 的状态（对 20 个注入点逐一断言）；Checkpoint 后重放时间显著下降（有量化对比）。

---

## 8. 查询引擎（Phase 4–5）

### 8.1 TriSQL 语法

主入口与 SQL 兼容，降低学习成本：

```sql
SELECT u.name, o.total FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.region = 'Asia' AND o.total > 100
ORDER BY o.total DESC LIMIT 20;

-- NoSQL 扩展
SELECT * FROM events
WHERE payload->>'type' = 'kill'
  AND payload->'meta'->>'weapon' = 'rifle';
```

**I11 / T5 约束**：以上字符串**只在 Init/Construct 期**经 `Compile` 解析为 `PreparedStatement`；运行期热路径只调 prepared 对象。

### 8.2 规划流水线

```
TriSQL 文本 → Lexer/Parser → AST → Analyzer（验表名/列名/类型）
           → LogicalPlan（关系代数）→ Optimizer（代价估算）
           → PhysicalPlan → Executor → 结果集
```

### 8.3 优化策略

谓词下推 · 索引选择（统计信息驱动）· Join 重排（小表驱动）· 投影消除 · 常量折叠。`EXPLAIN` 必须可输出决策理由。

### 8.4 算子

| 类别 | 算子 |
| --- | --- |
| 基础 | SeqScan · IndexScan · IndexRangeScan · Filter · Project · Sort（分块归并）· Limit/Offset |
| 连接 | NestedLoopJoin · HashJoin · MergeJoin |
| 聚合 | HashAggregate · StreamAggregate |

**验收**：Parser 负例样例集 100% 拒绝并报位置；`Compile` 后热路径重复执行 1000 次**零新增分配/零解析**（用分配计数断言）；同一查询加索引前后 `EXPLAIN` 计划不同且请求次数下降；HashJoin 与 NestedLoop 在 1e3×1e3 上的请求次数有量化对比。

---

## 9. NoSQL 扩展层（Phase 7）

| 模式 | 内容 |
| --- | --- |
| 文档 | `JSON` 列 + 路径函数索引：`CREATE INDEX idx_weapon ON events ((payload->>'weapon'));` |
| 时序 | 主键 `(entity_id, timestamp)` + 时间分区；自动降采样；滑动窗口聚合 |
| 图 | 边表 `(src_id, edge_type, dst_id, properties)`；双向索引支持出/入边 |

**验收**：JSON 路径查询能命中函数索引（断言走 IndexScan 而非 SeqScan）；时序降采样后原始精度查询与聚合查询结果各自正确。

---

## 10. 企业级特性

| 特性 | 落点 | 阶段 |
| --- | --- | --- |
| 请求队列 / 令牌桶 / 批处理 | `Tri.Request` | **Phase 1（T1）** |
| L1 缓存（LRU 按页 / 热点节点 / Schema） | `Tri.Storage.PageCache`（用 `Dr.Collections.Map.LRUCache`） | **Phase 1（T2）** |
| L2 缓存（跨服热点行） | `Tri.Runtime.MemoryStorePort` + 分布式锁辅助 | Phase 3+ |
| 缓存一致性 | Write-Through 默认；Write-Behind 依赖 WAL 保证不丢 | Phase 3 |
| 统计收集 | `Tri.Stat`（行数估算 / 基数 / 直方图 / min-max / 树高 / 页数），异步 | Phase 5 |
| 在线 DDL | `Tri.Ddl`：Schema version+1 → 后台渐进迁移 → 读时按行版本惰性迁移 → 切 active → 清旧元数据 | Phase 8 |

**验收**：在线 DDL 全程不停服，迁移中旧版本行读取 100% 正确；VACUUM 后页数下降且全表校验和不变。

---

## 11. 分层总览

```
┌ 应用 / 游戏脚本 ────────────────────────────────┐   ※ Deuterium 经 Tri.Adapters.DrDataAdapter 接入
├ 查询引擎  Tri.Query ────────────────────────────┤
├ 事务管理  Tri.Txn · Tri.Wal ────────────────────┤
├ 索引      Tri.Index  │  存储  Tri.Storage ──────┤
├ 缓存      PageCache（L1）· MemoryStorePort（L2）┤
├ 请求队列  Tri.Request ──────────────────────────┤
└ 端口      Tri.Runtime.StorePort → DataStoreService / MemoryStoreService
```

---

## 12. 路线图（重排后）

| Phase | 内容 | 优先级 | 前置 |
| --- | --- | --- | --- |
| **0** | `Tri.Runtime.StorePort` 端口 + 两绑定 · `NamespaceCodec` · `Catalog` · `SchemaStore` · 序列 · `Tri.Format` 走共用 Codec | 基础 | Deuterium Wave 0.1/0.3/0.4 |
| **0.5** | **端到端纵切**（内存版全链，只求暴露接缝，见 `SCALE.md` §5） | 基础 | Phase 0 |
| **1** | `Tri.Request`（队列/令牌桶/批处理）→ `PageManager`（页/槽/分裂）→ 基础 CRUD → `PageCache`(L1) | 核心 | Phase 0 |
| **2** | B+ 树（主键/聚簇）+ IndexScan / IndexRangeScan | 核心 | Phase 1 |
| **3** | 事务 + WAL + 行锁 + MVCC + 崩溃恢复 | 高级 | Phase 2 |
| **4** | Lexer/Parser/Analyzer + PreparedStatement + SeqScan/Filter/Project/Limit + 类型系统 + **NULL 三值逻辑** | 高级 | Phase 2 |
| **5** | Join 算子 + **子查询 · 集合运算** + 优化器 + `Tri.Stat` + EXPLAIN | 进阶 | Phase 4 |
| **6** | 二级 / 复合 / 唯一 / 部分索引 | 进阶 | Phase 2 + 5 |
| **7** | NoSQL 扩展（JSON 路径函数索引 / 时序 / 图） | 扩展 | Phase 6 |
| **8** | 在线 DDL + VACUUM + 监控面板 + 导出导入 + 快照 + `Tri.Adapters` | 完善 | Phase 3 + 6 |
| **9** | v1.0 硬化：故障注入矩阵 · 压力测试 · 性能预算达成 · 文档 | 完善 | Phase 3–8 |
| **10** | 发布 `vospek/tritiumsql`（Wally）· API 文档 · 兼容策略 | 发布 | Phase 9 |
| **11** | v1.5：视图 · CTE · `SELECT … FOR UPDATE` · 仅索引扫描 · JSON 格式 EXPLAIN | 扩展 | Phase 10 |

**与 `Text File.txt` 路线图的差异**：原 Phase 0 拆成「端口/编码（0）」与「请求管线+页+缓存（1）」；原 §9 的请求队列与 L1 缓存从「企业级特性」上移到 Phase 1（T1/T2）；Codec 不再自建（I9）；新增 0.5 纵切、3 个硬化/发布 Phase（9–11）。

**与 `INTEGRATION.md` 的关系**：本 Phase 0–8 是引擎本体；Phase 9–11 的硬化与发布包含与 Deuterium 的合练（G1–G10、验收 A1–A14）。**引擎本体只占 31,500 行，集成层再占 9,200 行**（`INTEGRATION.md` §4）。

**与 `SCALE.md` 的能力面差异**：子查询与集合运算从 v1.5 提到 v1（Phase 5）；不加窗口函数、触发器、存储过程、`GRANT`、线协议、复制、非 B-tree 索引 —— 逐项理由见 `SCALE.md` §4.2 的 Out 表。

---

## 13. 风险

| 风险 | 等级 | 对策 |
| --- | --- | --- |
| 请求限速下性能不达标（页聚合仍不够） | 高 | 预算层先行 + 每波次请求次数断言；必要时提高页容量或引入自适应批处理 |
| 协程锁导致饥饿/死锁在 Studio 复现不了 | 高 | `DataStoreSimulator` 强制造确定性交错；专门的压力用例 |
| 树高 > 3 导致读放大 | 中 | 建索引后断言实际读数；超限重构 |
| 与 Deuterium 边界被打破（复用 `Dr.Net` 或自建 Codec） | 中 | Code Review 检查 `Tri.*` 的 require 列表，只允许 RUNTIME/FOUNDATION/TOOLING |
| 元数据（Catalog/Schema）成为单点热键 | 中 | Catalog 常驻 L1 + 变更走广播；写入路径不依赖 Catalog 实时读 |
| 官方 DataStore 限额假设失真 | 中 | Phase 0 落地后写一个限额探针脚本实测，结果回写本文档 §0 |

未读/未验证：`Text File.txt` 中的限额数字（60 + 10×玩家、4KB 页、树高 3）是按经验与官方文档惯例给的目标值，未在本仓库实测；Phase 0 结束时须用探针脚本校正。
