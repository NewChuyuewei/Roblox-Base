# TritiumSQL — 实施计划

> **来源**：重写自原 `Text File.txt`（原代号 VoxDB / VQL，已废弃）—— 该文件已于 commit `5d4fabe` 删除，历史里可查；本文件自此是 SQL 的唯一计划出处。
> **命名**：产品 **TritiumSQL** · 模块前缀 `Tri.*`（对齐 `Dr.*`）· 方言 **TriSQL** · 键前缀 `tri:` · 发布包 `vospek/tritiumsql`
> **定位**：在 `DataStoreService`（本质 KV）之上，做关系型严谨性 + NoSQL 灵活性 + B+ 树索引 + 企业级扩展。
> **权威划分**：物理天花板与功能面 → `SCALE.md` §1.3 / §5；规模预算 → `SCALE.md` §2；与 Deuterium 的互通 → `INTEGRATION.md`；执行步骤 → `STEPS.md` Step 30–47 / 60–65；**DAL 与认证约束 → `CERT.md`**。
> ⚠ `CERT.md` 限制了本项目的规模与次序：认证线 ≤12k 行、先 HLR/LLR 再写码、C1–C6 先于 `T0`。
> Wave ID 统一为 `T<phase>`。

---

## 1. 依赖与边界

```
TritiumSQL ──依赖──▶ Deuterium 的 RUNTIME + FOUNDATION + TOOLING 三层
TritiumSQL ──不依赖──▶ Dr.Net / Dr.Data / Dr.State / Dr.ECS
TritiumSQL ◀─可选反向调用─ Deuterium，但只在 Dr.Integration/ 内（I14）
```

**独立可发布**：不依赖游戏工程，只依赖框架的底座三层，打包为 Wally 包 `vospek/tritiumsql`。

**物理天花板**（完整表与出处见 `SCALE.md` §1.3）：键名/作用域/库名各 **50 字符硬限**；单值 **4 MiB**；限速 `base + perPlayer × numPlayers` 且可由 `SetRateLimitForRequestType` 运行期覆盖；超限进**队列**，键级节流是**跳过**而非失败。所有设计围绕「减少请求次数」展开 —— 页聚合、缓存、批处理、优先级队列是核心而非优化项。

---

## 2. 模块地图（≈95 模块）

```
Tri.Runtime/     StorePort · MemoryStorePort · Bindings（Standalone | Deuterium | Simulator）· RuntimeTypes
Tri.Catalog/     Catalog · SchemaStore · TableRegistry · NamespaceCodec · Partitioner · Sequence
Tri.Storage/     PageManager · Page · HeapLayout · PageCache · RowStore · Vacuum
Tri.Index/       BPlusTree · NodeCodec · IndexScan · UniqueGuard · CompositeKey · PartialFilter · ExprIndex
Tri.Request/     RequestQueue · TokenBucket · BatchExecutor · RequestBudget · Priority
Tri.Txn/         TransactionManager · Mvcc · LockManager · WaitForGraph · UndoLog · Isolation · Savepoint
Tri.Wal/         WalWriter · WalReader · Checkpoint · Recovery
Tri.Query/       Lexer · Parser · Ast · Analyzer · LogicalPlan · Optimizer · PhysicalPlan · PreparedStatement
                 · Executor · PlanCache · Explain
Tri.Query.Operators/  SeqScan · IndexScan · IndexRangeScan · Filter · Project · Sort · Limit · Offset
                      · NestedLoopJoin · HashJoin · MergeJoin · HashAggregate · StreamAggregate
                      · Union · Intersect · Except · Subquery（标量/IN/EXISTS/相关）
Tri.Types/       TypeSystem · Coercion · ThreeValuedLogic · Functions · Numeric · Cast
Tri.Stat/        StatisticsCollector · Histogram · Cardinality · IndexCostModel · Analyze
Tri.Ddl/         OnlineDdl · MigrationWorker · VersionGate · View · Sequence · ExportImport
Tri.NoSql/       JsonPath · FunctionIndex · TimeSeries · GraphEdge
Tri.Integration/ （14 模块，见 INTEGRATION.md §5.2）
Tri.Testing/     SimulatorPort · PortContract · Fixtures · RequestAssert
```

### DAL 归属（DO-178C，见 `.plan/CERT.md`）

| 组 | DAL | 说明 |
| --- | --- | --- |
| `Tri.Txn` · `Tri.Wal` · `Tri.Storage` · `Tri.Index` · `Tri.Query` · `Tri.Request` · `Tri.Catalog` · `Tri.Types` | **C** | 落进认证范围（≤12k 行硬上限）；H1/H2/H4/H5/H6 |
| `Tri.Runtime/`（端口与三绑定） | **E** | 碰 `game` 与网络，不可鉴定（`CERT.md` §4.1） |
| `Tri.Testing.SimulatorPort` | **（范围内）** | 它不是被测软件，是**认证信用所依赖的确定性底座**（`CERT.md` §4.3） |
| `Tri.Integration/` | **E** | 与框架互通，出范围 |
| `Tri.NoSql` · `Tri.Ddl` · `Tri.Stat` | **D/E** | 未列入首批认证范围；若纳入必须先做范围变更（`CERT.md` §3.1） |

---

## 3. 设计决定

| # | 决定 | 理由 |
| --- | --- | --- |
| T1 | **请求管线在 `T1`，不留在「企业级特性」章节** | 限速是物理天花板；先有预算层，后续每层的写路径才能被计量与限流 |
| T2 | **L1 页缓存在 `T1`** | 无缓存则 CRUD 请求次数不可接受，后续索引/事务的测试都会因超配额而失真 |
| T3 | **不引入 `Dr.Net.Processing.Serializer`** | 那是 SERVICE 层；只用 FOUNDATION 的 `Dr.Types.Transform.Codec`（I9） |
| T4 | **引擎 API 经 `Tri.Runtime.StorePort`** | 满足 I10；Standalone 绑定是唯一例外文件（需显式标注）；Deuterium 绑定走 `Dr.Runtime.Platform.DataStoreProxy` |
| T5 | **SQL 在 Init 期编译** | I11 / P0：热路径禁解析与字符串查表。`Compile(sql) → PreparedStatement`，按 SQL 文本哈希缓存 |
| T6 | **同时提供类型化构建器** | 热路径首选；避免 SQL 字符串成为唯一入口 |
| T7 | **WAL 用 `OrderedDataStore`** | 其有序性天然按 LSN 顺序存储 |
| T8 | **默认隔离级别 = Read Committed** | Roblox 请求限制下性能最优；MVCC 与 2PL 作为可选升级 |
| T9 | **软删除 + 异步 VACUUM** | 删除路径不阻塞写；合并半满兄弟节点延后 |
| T10 | **元数据全在 `tri:__catalog__:*`** | 表目录、分区路由、Schema 版本、序列、锁集中可审计 |
| T11 | **与 Deuterium 的全部互通只在 `Tri/Integration/`** | 双向配合、单向依赖；十条路径 G1–G10 |
| T12 | **变更流从提交路径发射** | `Tri.Wal` 提交时顺带发射 `Change`，**不额外扫表**；未提交事务天然不可见。这是 G4（DB → 客户端复制）的地基 |
| T13 | **`RequestBudget` 不硬编码限额** | 启动时 `SetRateLimitForRequestType` 显式设限并读回实际值，它是配额唯一真相来源（I12） |
| T14 | **类型转换矩阵显式定义** | implicit / assignment / explicit 三级；隐式规则不明写会变成随机行为 |

---

## 4. 存储层

### 4.1 命名空间（`Tri.Catalog.NamespaceCodec`）

```
tri:[db]:[table]:[partition]:[key_type]:[value]

tri:main:users:p0:row:u_10023         → 行（实际在页内）
tri:main:users:p0:pg:0007             → 页
tri:main:users:p0:idx:email:a@b.com   → 二级索引条目
tri:main:users:meta:schema            → 表结构定义
tri:__catalog__:tables                → 全局表目录
tri:__catalog__:routes                → 分区路由
tri:__catalog__:hashes                → 长值短哈希登记
tri:__txn__:lock:u_10023              → 行级锁（UpdateAsync 原子执行）
tri:__seq__:users:id                  → 自增序列
tri:__wal__:<lsn>                     → WAL 条目（OrderedDataStore）
```

长值（如 email）走 `#<8位>` 短哈希并登记到 `hashes`。**50 字符是可行性前提**（`SCALE.md` §1.3），超长输入必须哈希而非静默截断。

### 4.2 页（`Tri.Storage.Page`）

```
Page = { pageId, tableId, partition,
         slots: [ { slotId, rowId, data, deleted, txnId } ],   -- 类 PG heap page
         freeSpace, nextPageId, lsn }
```

目标 **4KB 等效数据/页**；`HeapLayout` 负责槽位复用与碎片统计。分裂后两页均需 ≥40% 占用。

### 4.3 分区（`Tri.Catalog.Partitioner`）

| 策略 | 场景 |
| --- | --- |
| Hash | 主键均匀分布、点查询为主 |
| Range | 时间序列、数值范围 |
| List | 枚举（region / gamemode） |

路由元数据入 `tri:__catalog__:routes`。扩容新增分区**不得改变既有行的路由结果**。

### 4.4 请求管线（决定 T1）

```
上层操作 → RequestQueue（P0..P3）→ TokenBucket（预算）→ BatchExecutor（合并）→ StorePort
```

优先级：`P0` 事务提交/崩溃恢复 → `P1` 玩家数据读写 → `P2` 索引维护 → `P3` VACUUM/统计。

---

## 5. 索引层（`T2` / `T6`）

```
内部节点：{ nodeId, isLeaf: false, keys: [k1,k2,k3], children: [n1..n4] }
叶子节点：{ nodeId, isLeaf: true, entries: [ { key, rowId, pageId, slotId } ], prevLeaf, nextLeaf }
```

根节点 ID 入表元数据；**树高 ≤ 3**，超限告警并触发重构（每层 = 最坏多一次读）。

| 类型 | 语义 |
| --- | --- |
| PRIMARY | 聚簇，行随主键排序 |
| SECONDARY | 非聚簇，叶存 `secondary_key → primary_key` |
| UNIQUE | 插入前验唯一（需锁） |
| COMPOSITE | 多列联合键，按列优先级排序 |
| PARTIAL | 带 WHERE 的稀疏索引 |

维护：写 → 找叶 → 插 entry → 满则 split → 向上传播；删 → 软删除标记 → 异步 merge；`Vacuum` → 清软删除 + 重构过疏页。**任意写路径不得产生孤儿索引条目。**

---

## 6. 关系模型

### 6.1 Schema（`Tri.Catalog.SchemaStore`）

```
{ tableId, tableName, version,
  columns: [ { name, type, nullable, default, primaryKey, unique } ],
  constraints: [ { type:"FK", column, refTable, refColumn, onDelete } | { type:"CHECK", expr } ],
  indexes: [ { indexId, columns, type, unique, where? } ] }
```

`version` 驱动在线 DDL：不锁表，旧行按需迁移。

### 6.2 类型与语义

`INT`（`±2^31`）· **`BIGINT`（`±2^53`，不是 2^63 —— Luau 装不下 64 位精确整数，这是对 SQL 语义的已知降级，必须在文档与错误信息里说明）** · `FLOAT` · `NUMERIC(p,s)`（整数+标度模拟，`p-s ≤ 15`）· `VARCHAR(n)`（超长**报错**，不静默截断）· `TEXT`（超长分块）· `BOOLEAN` · `TIMESTAMP` · `DATE` · `UUID` · `JSON` · `ARRAY<T>` · `ENUM`。

**NULL 三值逻辑**必须显式实现并单测：`AND`/`OR`/`NOT` 真值表、`IS NULL`、`IS DISTINCT FROM`。**转换矩阵**（T14）三级：implicit / assignment / explicit。

### 6.3 外键与完整性

无原生支持 → **执行引擎层强制**：INSERT/UPDATE 验引用行存在；DELETE 按 `ON DELETE`（CASCADE / SET NULL / RESTRICT）；检查失败即事务回滚。

---

## 7. 事务与并发（`T3`）

| 项 | 设计 |
| --- | --- |
| 事务模型 | `BEGIN → [读写] → COMMIT/ROLLBACK`，持有 `txnId / startTimestamp / status / readSet / writeSet / undoLog` |
| 隔离级别 | Read Uncommitted · **Read Committed（默认，T8）** · Repeatable Read（MVCC 快照读）· Serializable（2PL） |
| MVCC | `Row = { rowId, data, createdTxnId, expiredTxnId }`；读看见 `created ≤ 当前txn` 且 `expired = null 或 > 当前txn`；写建新版本并给旧版本置 `expired`；旧版本由 VACUUM 清 |
| 锁 | 粒度 Table → Partition → Page → Row；类型 `S` / `X` / `IS` / `IX`；状态存 `tri:__txn__:lock:*`，`UpdateAsync` 保证原子 |
| 死锁 | 等待图（Wait-For Graph）检环 → 回滚**代价最小**的事务 |
| 错误语义 | SQLSTATE 风格错误码表（清单见 `SCALE.md` §5），错误对象含位置、列路径、提示 |
| 锁顺序 | 跨两套锁体系时遵守 **I15**：先 `Dr` Mutex → 后 `Tri` 行锁 |

## 8. WAL（`T3`）

```
{ lsn, txnId, type, tableId, rowId, before, after, timestamp }
type: INSERT | UPDATE | DELETE | COMMIT | ROLLBACK | CHECKPOINT
```

先写 WAL 再写页；入 `OrderedDataStore`（T7）；`Checkpoint` 定期落状态并截断旧 WAL；`Recovery` Redo 已提交 / Undo 未提交。**提交路径同时发射变更流**（T12）。

## 9. 查询引擎（`T4` / `T5`）

```
TriSQL → Lexer/Parser → AST → Analyzer（验表/列/类型）→ LogicalPlan（关系代数）
       → Optimizer（代价估算）→ PhysicalPlan → Executor → ResultSet      [Compile 期完成，I11]
```

TriSQL 语法与 SQL 兼容（降低学习成本），并支持 JSON 路径扩展：

```sql
SELECT u.name, o.total FROM users u JOIN orders o ON u.id = o.user_id
WHERE u.region = 'Asia' AND o.total > 100 ORDER BY o.total DESC LIMIT 20;

SELECT * FROM events WHERE payload->>'type' = 'kill' AND payload->'meta'->>'weapon' = 'rifle';
```

优化：谓词下推 · 索引选择（统计驱动）· Join 重排（小表驱动）· 投影消除 · 常量折叠；**不枚举搜索空间**。`EXPLAIN` 必须输出决策理由。

算子清单见 §2 的 `Tri.Query.Operators`。安全注入点见 `INTEGRATION.md` §2.3（RLS 谓词在 Analyzer 之后、Optimizer 之前注入）。

## 10. NoSQL 扩展（`T7`）

| 模式 | 内容 |
| --- | --- |
| 文档 | `JSON` 列 + 路径表达式索引：`CREATE INDEX idx_weapon ON events ((payload->>'weapon'));` |
| 时序 | 主键 `(entity_id, timestamp)` + 时间分区；自动降采样；滑动窗口聚合 |
| 图 | 边表 `(src_id, edge_type, dst_id, properties)` + 双向索引支持出/入边 |

## 11. 企业级特性

| 特性 | 落点 | Wave |
| --- | --- | --- |
| 请求队列 / 令牌桶 / 批处理 | `Tri.Request` | `T1`（T1） |
| L1 缓存（LRU 按页 / 热点节点 / Schema） | `Tri.Storage.PageCache`（用 `Dr.Collections.Map.LRUCache`） | `T1`（T2） |
| L2 缓存（跨服热点行）+ 分布式锁辅助 | `Tri.Runtime.MemoryStorePort` | `T3`+ |
| 缓存一致性 | Write-Through 默认；Write-Behind 依赖 WAL | `T3` |
| 统计收集 | `Tri.Stat`（行数估算/基数/直方图/min-max/树高/页数），异步 | `T5` |
| 在线 DDL | Schema `version+1` → 后台渐进迁移 → 读时惰性迁移 → 切 active → 清旧元数据 | `T8` |
| 导出导入 / 快照 | `Tri.Ddl.ExportImport` / 快照备份 | `T8` |

---

## 12. Wave 计划

| Wave | 内容 | AC |
| --- | --- | --- |
| **`T0`** | `Tri.Runtime.StorePort` + 三绑定 · `NamespaceCodec` · `Catalog` · `SchemaStore` · `Sequence` · Codec 走 I9 | `AC-T0`：round-trip 1000 随机例唯一；任意输入 key ≤50 字符恒成立；三绑定跑同一 `PortContract` 结果一致；冷启动读请求数 == 表数（断言） |
| **`T0.5`** | **端到端纵切**（内存版全链，与 `D0.5` 同一次） | `AC-T0.5`：`CREATE TABLE` → `INSERT` → 主键 `SELECT` 全链跑通；产出 `SEAMS.md` |
| **`T1`** | `RequestBudget`（三态 + 显式设限）· `RequestQueue`/`TokenBucket`/`BatchExecutor` · `Page`/`HeapLayout` · `PageManager` · `PageCache` · CRUD | `AC-T1`：速率 10/min 灌 100 次 → 0 丢弃、排队、计数精确；P0 严格早于 P3（时间戳）；4KB 页 ≥32 典型行；分裂后两页 ≥40%；写 100 页请求数 ==100；命中缓存 **0 次读**；点查未命中 ≤1 次读 |
| **`T2`** | `NodeCodec` · `BPlusTree`（主键/聚簇）· `IndexScan` · `UniqueGuard` | `AC-T2`：1e4 行点查**实际读次数 ≤ 树高**；分裂后父子键区间无空洞；范围扫描不产生回父节点读；唯一键并发插只有一个成功 |
| **`T3`** | 事务 · 隔离级别 · SAVEPOINT · MVCC · 锁管理器 · 等待图 · WAL · Checkpoint · 崩溃恢复 · **SQLSTATE 错误码** | `AC-T3`：20 个 WAL 注入点的恢复状态 == 最后一次 COMMIT；2.5k 步环形等待在 ≤2× 链路长度内发现并回滚代价最小者；隔离级别矩阵逐格断言；`AC-G3` 的 Saga 逆序回滚 |
| **`T4`** | Lexer/Parser/Analyzer · 逻辑/物理计划 · 核心算子 · 类型系统 · **三值逻辑** · 转换矩阵 · PreparedStatement + 计划缓存 | `AC-T4`：Parser 负例集 100% 拒绝并报位置；`Compile` 后热路径执行 1000 次**零新增分配/零解析**；三值逻辑真值表逐格断言 |
| **`T5`** | Join 算子（NL/Hash/Merge）· **子查询**（标量/IN/EXISTS/相关）· **集合运算** · 优化器 · `Tri.Stat` · `EXPLAIN` | `AC-T5`：同查询加索引前后计划不同且请求数下降；HashJoin vs NestedLoop 在 1e3×1e3 上有量化对比；`EXPLAIN` 输出决策理由 |
| **`T6`** | 二级 / 复合 / 唯一 / 部分 / **表达式**索引 | `AC-T6`：二级索引与主键一致性（无孤儿条目）；表达式索引命中走 IndexScan 而非 SeqScan |
| **`T7`** | NoSQL：JSON 路径 + 函数索引 · 时序（降采样/滑动窗口）· 图（双向边索引） | `AC-T7`：JSON 路径查询命中函数索引；降采样后原始精度与聚合查询各自正确 |
| **`T8`** | 在线 DDL · VACUUM · 监控 · 导出导入 · 快照 · `Tri.Adapters` | `AC-T8`：迁移中旧版本行读取 100% 正确；VACUUM 后页数下降且全表校验和不变 |
| **`T9`** | v1.0 硬化：故障注入矩阵 · 压力测试 · 性能预算达成 · 文档 | `AC-T9`：附录 B 发布门禁全绿 |
| **`T10`** | 发布：Wally `vospek/tritiumsql` · API 文档 · 兼容策略 | `AC-T10`：从 Wally 安装即可用；封顶声明入 release note |
| **`T11`** | v1.5：视图 · CTE · `FOR UPDATE` · 仅索引扫描 · 参数化计划 · JSON 格式 EXPLAIN | `AC-T11` |

**与原 `Text File.txt` 路线图的差异**：见 `SCALE.md` §7。

---

## 13. 项目专属风险

R8（限速下性能）、R9（协程锁饥饿）、R13（接口漂移）的完整条目在 `README.md` §6。SQL 侧补充：

| 风险 | 触发条件 | 对策 |
| --- | --- | --- |
| 树高 > 3 造成读放大 | `AC-T2` 实际读数超标 | 建索引后断言实际读数；超限重构 |
| Catalog / Schema 成为单点热键 | 写路径出现 Catalog 实时读 | Catalog 常驻 L1 + 变更广播；写入路径不依赖 Catalog 实时读 |
| 限额假设失真 | 官方限速与实测不符 | `SCALE.md` §1.3 已核实数字；Step 38 核对 `SetRateLimit` 覆盖是否生效 |
