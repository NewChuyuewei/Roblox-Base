# 规模标定

> 回答：**「堪比 Knit 的 Framework + 堪比小型 PostgreSQL 的 SQL，两项目互相配合」意味着多少模块、多少行、多少个 Wave、什么东西必须做。**
> 本文件是**规模、预算、里程碑、功能面**的唯一出处。排期细节见 `Deuterium.md` / `TritiumSQL.md`；执行细节见 `STEPS.md`。

---

## 1. 对标实测

### 1.1 Knit（可用性对标，**不是规模对标**）

| 指标 | 实测 |
| --- | --- |
| 文件 / 体积 / LOC | 40 文件 / 105.3 KB / ≈2,800 行 |
| 发布产物 / 提交数 | `Knit.rbxm` 127.8 kB / 525 |
| 状态 | **已归档**（2020–2023） |
| API 面 | 极薄：`Service` / `Controller` / `Component` + `Signal` + 网络自动桥接 + 生命周期 |

Deuterium 已是 Knit 的数倍规模，所以「堪比 Knit」在这里指**可用性**。Knit 有而我们缺的四样：**薄入口**、**文档站 + CHANGELOG + SemVer + 发布产物**、**完整示例**、**从 Knit 的迁移指南**。落地在 `Deuterium.md` 的 `D7.x`（含新不变量 I13）。

### 1.2 PostgreSQL（功能面对标，**存储层被封顶**）

PG 主体约 140 万行 C。可以做到对标的只有五个面：**SQL 表面 · 查询引擎 · 索引 · 事务语义 · 错误语义**。

**封顶声明（必须写进首页与每个 release note，决策 D2）**：Roblox 拿不到 PG 的存储原语 —— 无 `fsync` 与持久化时机控制、无页缓存/缓冲池控制权、无共享内存与多线程、无复制协议、无存储引擎可插拔层。因此**不对标 PG 的存储层**，也不假装它不存在。

### 1.3 DataStore 上限（已对官方文档核实）

| 项 | 值 | 设计后果 |
| --- | --- | --- |
| data store name / **key name** / scope | **各 50 字符（硬限）** | 键名只有 50 字符是**可行性前提**而非优化：长值一律走短哈希 |
| 单值大小 | **4,194,304 字节（4 MiB）** | 页目标容量 **4KB**，留足序列化余量 |
| 限速 | `rateLimit = baseLimit + perPlayerLimit × numPlayers`，可由 `DataStoreService:SetRateLimitForRequestType` **运行期覆盖** | `RequestBudget` 不硬编码常量：启动时显式设限并读回实际值，它是配额的唯一真相来源 |
| 超限语义 | 进队列（Set / OrderedSet / Get / OrderedGet）；**键级节流**会跳过该键的请求而非失败 | 必须区分「排队 / 键级节流 / 真失败」三态（I12）；**不把排队当丢弃** |
| 官方建议 | 每个玩家用一或少数几个键 | 与页聚合方向一致 |

### 1.4 现状

| 区域 | 文件 | LOC |
| --- | --- | --- |
| `Core` / `Net` | 21 / 23 | 1,432 / 1,870 |
| `Runtime` / `Security` | 14 / 2 | 958 / 241 |
| `Testing` / `Types` / `Extensions` | 5 / 3 / 1 | 304 / 47 / 42 |
| **合计** | **69** | **4,894** |

规格模块地图：77 目录 / 313 去重模块名 → 文件覆盖率 ≈22%。

---

## 2. 100,000 行预算（唯一出处）

**目标：v1.0 下限 100,000 行**（核心 + 测试 + 示例工具；不含文档）。

| 区域 | 模块 | 核心 | 测试 | 示例/工具 | 小计 |
| --- | --- | --- | --- | --- | --- |
| Deuterium 框架本体 | 313 | 26,000 | 9,000 | — | 35,000 |
| `Dr.Integration` | 18 | **8,400** | 4,500 | — | 12,900 |
| TritiumSQL 引擎本体 | 95 | 22,000 | 9,500 | — | 31,500 |
| `Tri.Integration` | 14 | **5,700** | 3,500 | — | 9,200 |
| 端到端 / 场景 / 故障注入矩阵 | — | — | 5,000 | — | 5,000 |
| 示例（≥5）· 基准 · CLI/Studio 工具 · 发布脚本 | — | — | — | 6,400 | 6,400 |
| **合计** | **440** | **62,100** | **31,500** | **6,400** | **100,000** |

- **测试占 31.5%**，有意为之：440 个模块、可崩溃的存储层、可解析的 SQL 方言，测试低于 25% 等于没测。
- 这是**下限不是配额**：A 档核心路径按不封顶标准写，实际会到 120,000–135,000 行。低于 100,000 视为功能面缩水，不是「写得紧凑」。
- 各区域模块清单与逐模块 LOC 见 `INTEGRATION.md` §5（集成层）与各项目文档（本体）。
- 记分板：`scripts/loc-budget.luau` 输出「实际 / 预算 / 占比 / 判定」，release 分支合计 <100,000 或任一区域 <70% 则**阻断**，日常分支只 warn；数据入 `metrics/loc-history.csv` 得到进度曲线。

### 2.1 工作量与日历

按 300–600 行/有效工作日（含测试、审查、集成）：

| 人力 | 估算 |
| --- | --- |
| 单人 | 14 – 22 个月 |
| 双人（一条框架线 + 一条 SQL 线，在接缝 `INTEGRATION.md` §2 与 Step 14.14/16 交汇） | 8 – 12 个月 |
| 双人 + agent 辅助 | 6 – 9 个月（压缩的是写码与测试，不是决策与调试） |

若实际目标只是「能用的游戏数据层 + 能查的关系表」，正确做法是砍 §5 的 Out 列与集成路径 G7，**不压缩单模块深度**。

---

## 3. 质量分档（440 模块的资源分配）

| 档 | 模块 | 标准 |
| --- | --- | --- |
| **A · 核心路径** | 页管理 · B+ 树 · 事务/MVCC · WAL/恢复 · 解析器 · 优化器 · 锁管理器 · 请求预算 · **G4 复制 · G5 RLS** | 边界用例 + 故障注入 + 请求次数断言 + 性能预算；**单模块 LOC 不封顶**（250–600+） |
| **B · 支撑** | 编解码 · 类型系统 · 统计 · 目录 · 缓存 · 集合/内存/并发原语 · 其余 G 路径 | 单测覆盖正常 / 边界 / 失败三例（120–250 行） |
| **C · 外围** | 监控面板 · 导出导入 · 诊断 · Util · 文档站 | 够用即止，允许薄实现 + `shortcut:` 标注（40–120 行） |

---

## 4. 里程碑（可演示，不是 Wave）

| 里程碑 | 内容 | 累计投入 |
| --- | --- | --- |
| **M0** | 仓库可构建、CI 四阶段绿、`SelfTest.RunAll()` 过 | Phase 0.1（Step 1–12） |
| **M1** | **端到端纵切**跑通（内存版全链），产出 `SEAMS.md` | +3 天（Step 16.5） |
| **M2** | `v0.1.0-alpha`：`CREATE TABLE` / `INSERT` / 主键 `SELECT` 走完 Parser→Plan→Index→Page→Port | TritiumSQL `T0`–`T2` |
| **M3** | `v0.5.0-beta`：事务 + WAL + 崩溃恢复 + `UPDATE`/`DELETE`/`JOIN` **+ 集成 G1/G2/G3** | `T3`–`T5` + G1–G3 |
| **M4** | `v1.0.0`（引擎）：附录 B 的 In 列全部落地 | `T6`–`T11` |
| **M5** | Deuterium `v1.0.0` 发布：Wally `.rbxm` + 文档站 + 示例 + 迁移指南 | `D7.x` |

---

## 5. 能力面：In / Out（v1 验收口径）

### In — v1 必做

| 类别 | 功能 |
| --- | --- |
| **DDL** | `CREATE/DROP TABLE` · `TRUNCATE` · `ALTER TABLE`（加/删列、加/删约束）· `CREATE/DROP INDEX`（唯一/复合/部分/表达式）· `REINDEX` · `CREATE SEQUENCE` |
| **DML** | `INSERT`（多行 / `DEFAULT VALUES`）· `SELECT`（WHERE / JOIN / GROUP BY / HAVING / ORDER BY / LIMIT / OFFSET / DISTINCT / 别名 / 表达式）· `UPDATE` · `DELETE` · `UPSERT` · `INSERT … RETURNING` |
| **查询构造** | 标量子查询 · `IN` · `EXISTS` · 相关子查询 · `UNION` / `UNION ALL` / `INTERSECT` / `EXCEPT` · `CASE` / `COALESCE` / `NULLIF` · 内连接 / 左连接 |
| **类型** | `INT` / `BIGINT` / `FLOAT` / `NUMERIC(p,s)`（整数+标度模拟）· `VARCHAR(n)` / `TEXT` / `BOOLEAN` / `TIMESTAMP` / `DATE` / `UUID` / `JSON` / `ARRAY<T>` / `ENUM` |
| **语义** | **NULL 三值逻辑**（真值表、`IS NULL`、`IS DISTINCT FROM`）· 类型转换矩阵（implicit / assignment / explicit 三级） |
| **约束** | `NOT NULL` · `DEFAULT` · `PRIMARY KEY` · `UNIQUE` · `CHECK` · `FOREIGN KEY`（`CASCADE` / `SET NULL` / `RESTRICT`） |
| **索引** | B-tree 点查 / 范围 / 复合 / 唯一 / 部分 / 表达式；`ANALYZE` 统计 |
| **事务** | `BEGIN`/`COMMIT`/`ROLLBACK`/`SAVEPOINT` · 四种隔离级别 · 四级锁 + 意向锁 · 等待图死锁检测与受害者回滚 · MVCC 快照与可见性 · WAL redo/undo · Checkpoint · 崩溃恢复 |
| **错误语义** | SQLSTATE 风格错误码（`23505`/`23503`/`23502`/`22001`/`22003`/`42P01`/`42703`/`42601`/`40001`/`40P01`/`55P03`/`57014`），错误对象含位置、列路径、提示 |
| **会话/API** | `PreparedStatement` + 参数绑定 + 计划缓存 · 流式结果集 / 分页游标 · `EXPLAIN` / `EXPLAIN ANALYZE` |
| **算子** | SeqScan · IndexScan · IndexRangeScan · Filter · Project · Sort（分块归并）· Limit/Offset · NestedLoop/Hash/Merge Join · HashAggregate · StreamAggregate |
| **优化** | 谓词下推 · 投影消除 · 常量折叠 · 基于统计的索引选择 · Join 重排（启发式 + 简单代价，**不枚举搜索空间**） |
| **运维** | `VACUUM` · `CHECKPOINT` · 在线 DDL 渐进迁移 · 监控指标 · 导出导入（JSON/CSV）· 快照备份 |
| **NoSQL 扩展** | JSON 路径查询 + 表达式索引 · 时序表 + 降采样 + 滑动窗口 · 图边表 + 双向索引 · 跨服 L2（MemoryStore）热点共享 |
| **集成** | `G1`–`G10`（`INTEGRATION.md`） |

### In — v1.5（排期但不在 v1）

`CREATE VIEW` · CTE（`WITH` / `WITH RECURSIVE`）· `SELECT … FOR UPDATE` · 仅索引扫描 · 参数化计划（generic vs custom）· `EXPLAIN (FORMAT JSON)`

### Out — v2 或永不做

| 项 | 决定 |
| --- | --- |
| 窗口函数 · 存储过程/触发器/PL | v2（会引入第二套执行模型） |
| `GRANT` / `REVOKE` | **永不做** —— 权限由 `Dr.Security` RBAC 在上层裁决 |
| 线协议 / 多语言驱动 · 物理与流复制 · PITR · 逻辑订阅 | **永不做** —— 无场景 / DataStore 不提供原语 |
| 自定义类型 / 扩展 API / `tsvector` / 几何 / 范围类型 | 永不做 |
| GIN / GiST / BRIN / Hash 索引 | 永不做 —— B-tree + JSON 表达式索引已覆盖 |
| 优化器完整搜索空间（DP/Volcano）· 并行查询 · JIT | **永不做** —— 相对请求预算，收益上限很低 |
| 用户声明的声明式分区语法 | 永不做 —— 分区是内建策略 |
| 跨服分布式事务 / 2PC | 永不做 —— 用 Saga 在上层表达 |

---

## 6. 纵切优先（本规模下最重要的策略）

按层横铺到 440 个模块，会在第 4–6 个月暴露致命问题：每个模块 200 行看着齐，但**架构接缝从未被真实验证**，返工发生在最贵的阶段。

**改为纵切优先** —— Phase 0.4 之后立刻插入 **Phase 0.5 · 端到端纵切**（Step 16.5，约 3 天，允许脏）：

```
Kernel.Boot → SchemaStore（内存）→ TriSQL.Compile("CREATE TABLE t (id INT PRIMARY KEY, name TEXT)")
→ Compile("SELECT name FROM t WHERE id = 1") → IndexScan（内存 B+ 树）
→ PageManager（内存页）→ StorePort → SimulatorPort → 读回断言
```

规则：允许内存占位与 `shortcut:`；**不做**持久化、事务、优化器。唯一目标是让接缝暴露，产出 `.plan/SEAMS.md`（需正式化的接口 / 被证伪的设想 / 需新增的模块）。**接缝清单确认后才回到横铺。** Phase 0.5 同时冻结 `INTEGRATION.md` §2 的四个接缝。

---

## 7. 对既有路线图的增量（只写 delta，完整路线图在项目文档）

| 位置 | 增量 |
| --- | --- |
| Deuterium | 新增 `D0.5` 纵切、`D2.0` `Dr.Signal`（提前，Knit 把它当基础设施）、`D7.x` 发布与生态、`D8` Studio 插件；`D5.1–D5.3` 集合/内存/缓冲抽到 `D0.3`；`D6.1` 日志抽到 `D0.1` |
| TritiumSQL | 原 9 个 Phase 扩到 12：新增 `T0.5` 纵切、`T9` 硬化、`T10` 发布、`T11` v1.5；请求管线与 L1 缓存从「企业级特性」上移到 `T1`；**不做** `Tri.Format`（用 I9 的共用 Codec） |
| 集成 | 新增 `G1`–`G10` 与 `Dr.Integration`(18) / `Tri.Integration`(14) 共 32 模块、14,100 行核心 |
| 规格修订 | 见 `Deuterium.md` §2 的修订清单（应用于 `Deuterium/Deuterium.md`） |

---

## 附录 A · v1 功能追踪矩阵

每行：**功能 → 模块 → Wave → Step → 验收**。release 前逐行勾选；未勾选项必须移入 v1.5 并写明理由，**不允许「默认算做过」**。

| 功能 | 模块 | Wave | Step | AC |
| --- | --- | --- | --- | --- |
| 端口 + 三绑定 | `Tri.Runtime.*` | `T0` | 30–33 | AC-T0 |
| 键名编码（≤50 字符） | `Tri.Catalog.NamespaceCodec` | `T0` | 34 | AC-T0 |
| Schema / 目录 / 序列 | `Tri.Catalog.*` | `T0` | 35 | AC-T0 |
| 请求预算 + 三态语义 | `Tri.Request.RequestBudget` | `T1` | 36 | AC-T1 |
| 优先级队列 + 批处理 | `Tri.Request.*` | `T1` | 37 | AC-T1 |
| 页与堆布局 | `Tri.Storage.Page/HeapLayout` | `T1` | 39 | AC-T1 |
| 页管理（读写/分裂） | `Tri.Storage.PageManager` | `T1` | 40 | AC-T1 |
| L1 页缓存 | `Tri.Storage.PageCache` | `T1` | 41 | AC-T1 |
| 基础 CRUD | `Tri.Storage.RowStore` | `T1` | 42 | AC-T1 |
| B+ 树（主键/聚簇） | `Tri.Index.BPlusTree/NodeCodec` | `T2` | 44–45 | AC-T2 |
| 索引扫描（点/范围） | `Tri.Index.IndexScan` | `T2` | 46 | AC-T2 |
| 唯一约束 | `Tri.Index.UniqueGuard` | `T2` | 47 | AC-T2 |
| 事务 / 隔离级别 / 保存点 | `Tri.Txn.*` | `T3` | — | AC-T3 |
| MVCC 快照与可见性 | `Tri.Txn.Mvcc` | `T3` | — | AC-T3 |
| 死锁检测与受害者选择 | `Tri.Txn.WaitForGraph` | `T3` | — | AC-T3 |
| WAL + Checkpoint + 崩溃恢复 | `Tri.Wal.*` | `T3` | — | AC-T3 |
| SQLSTATE 错误码表 | `Tri.Txn/Query` 错误层 | `T3` | — | AC-T3 |
| 词法/语法/语义分析 | `Tri.Query.{Lexer,Parser,Analyzer}` | `T4` | — | AC-T4 |
| 逻辑/物理计划 + 核心算子 | `Tri.Query.*` / `Operators` | `T4` | — | AC-T4 |
| 类型系统 + 三值逻辑 + 转换矩阵 | `Tri.Types.*` | `T4` | — | AC-T4 |
| PreparedStatement + 计划缓存 | `Tri.Query.PreparedStatement` | `T4` | — | AC-T4 |
| 连接算子（NL/Hash/Merge） | `Tri.Query.Operators` | `T5` | — | AC-T5 |
| 子查询（标量/IN/EXISTS/相关） | `Tri.Query.Operators` | `T5` | — | AC-T5 |
| 集合运算（UNION/INTERSECT/EXCEPT） | `Tri.Query.Operators` | `T5` | — | AC-T5 |
| 优化器（下推/折叠/索引选择/Join 重排） | `Tri.Query.Optimizer` + `Tri.Stat` | `T5` | — | AC-T5 |
| `EXPLAIN` / `EXPLAIN ANALYZE` | `Tri.Query.*` | `T5` | — | AC-T5 |
| 二级/复合/唯一/部分/**表达式**索引 | `Tri.Index.*` | `T6` | — | AC-T6 |
| JSON 路径 + 函数索引 / 时序 / 图 | `Tri.NoSql.*` | `T7` | — | AC-T7 |
| 在线 DDL + VACUUM | `Tri.Ddl.*` / `Tri.Storage.Vacuum` | `T8` | — | AC-T8 |
| 监控 + 导出导入 + 快照 | `Tri.Stat` / `Tri.Ddl` | `T8` | — | AC-T8 |
| 会话态持久化 + Saga | `Dr.Integration.Persistence.*` | G3 | 52–53 | AC-G3 |
| DB→客户端复制 | `ChangeLog` + `Replication.*` | G4 | 54, 62 | AC-G4 |
| 行级安全 | `RowSecurity` + `Security.*` | G5 | 55, 63 | AC-G5 |
| 查询结果传输 | `Net/ResultCodec` + `QueryService` | G6 | 56 | AC-G6 |
| ECS 实体持久化 | `Ecs/WorldPersist` | G7 | 57 | AC-G7 |
| 可观测（span/metric/慢查询） | `Observe/*` + `Telemetry` | G8 | 57, 64 | AC-G8 |
| 薄入口 + 文档站 + 示例 + 迁移指南 | `API/Deuterium.luau` 等 | `D7.x` | — | AC-D7 |

## 附录 B · 发布门禁清单

| # | 条件 |
| --- | --- |
| 1 | 门禁 1–9 全绿（`README.md` §2），其中 `test` 阶段不是 `allow_failure` |
| 2 | 附录 A 的 In 行逐条勾选完毕 |
| 3 | LOC 记分板：合计 ≥100,000，各区域 ≥ 预算 70% |
| 4 | 测试占比 ≥ 25%；A 档模块每个都有故障注入用例 |
| 5 | 安全：`AC-G5` 全部越权用例被拦；审计日志字段完整 |
| 6 | 一致性：`AC-G4` 顺序/幂等/断线补齐全过 |
| 7 | 可复现：CI 全绿两次连续运行（排除偶发） |
| 8 | 文档：封顶声明（§1.2）在 README 首页与 release note；CHANGELOG 覆盖本版 |
| 9 | 外部依赖：三个以内且审计留档在 `MEMORY.md` |

---

未读/未验证：PG 的功能分类（转换三级、SQLSTATE 具体码值）依印象给出、**未逐一核对 PG 官方附录**，`T3`/`T4` 动工前需对一遍；LOC 与工作量是经验估算，误差可能达 ±50%。风险：附录 A 的 In 列若全按 v1 承诺，`M4` 日历会偏乐观 1–2 个月。
