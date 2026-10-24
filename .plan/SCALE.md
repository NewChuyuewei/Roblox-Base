# 规模标定与能力清单（Scale Calibration）

> 回答一个问题：**「堪比 Knit 的 Framework + 堪比小型 PostgreSQL 的 SQL」到底意味着多少模块、多少行、多少个阶段、什么东西必须做。**
> 本文档是对 `.plan/*.md` 的**加严**，不是替代。读完本文档后，`Deuterium.md` / `TritiumSQL.md` 的功能面以本文档附录 A/B 为准，排期以 `.plan/STEPS.md` 为准。

---

## 1. 两个对标物的实测事实

### 1.1 Knit（可用性对标，**不是规模对标**）

| 指标 | 实测 |
| --- | --- |
| 文件数 | 40 |
| 源码体积 | 105.3 KB |
| 估算 LOC | ≈ 2,800 |
| 发布产物 | `Knit.rbxm` 127.8 kB |
| 提交数 | 525 |
| 状态 | **已归档**（2020–2023），作者因 Studio 智能提示与 Luau 的发展而停止维护 |
| API 面 | 极薄：`Service` / `Controller` / `Component` + `Signal` + 网络自动桥接 + 生命周期 |

**结论**：Deuterium 当前 69 文件 / 4,894 行，规划 313 个模块，**规模早已是 Knit 的数倍**。「堪比 Knit」对 Deuterium 不是规模目标，而是**可用性目标** —— Knit 有而我们缺的四样东西：

1. **薄入口**：Knit 新人只需理解三个概念；Deuterium 现在把 60+ 模块全暴露，新人无从下手。
2. **文档站 + CHANGELOG + SemVer + 发布产物**（`.rbxm` / Wally）。
3. **完整示例**（Knit 有模板项目；Deuterium 只有一个 `Extensions/Demo.luau`）。
4. **从 Knit 的迁移指南** —— 这是最大的采用驱动力，且成本极低。

### 1.2 PostgreSQL（功能面对标，**存储层被封顶**）

PG 主体约 140 万行 C。所谓「小型」通常指 SQLite（≈15 万行）或早期 PG。

**必须先说清楚的封顶**：Roblox 上拿不到 PG 的存储/持久化原语 —— 没有 `fsync` 与可控的持久化时机、没有页缓存/缓冲池的任何控制权、没有共享内存与多线程、没有复制协议、没有存储引擎可插拔层。因此**不可能**在存储层与 PG 对标。

可以做到对标的是：**SQL 表面 + 查询引擎 + 索引 + 事务语义 + 错误语义**。本计划的目标定义：

> 在 SQL / 查询 / 索引 / 事务 / 错误码五个面上达到小型关系库的功能对齐；存储层的能力上限由 DataStore 决定，并把这一上限**显式写进文档**而不是假装不存在。

### 1.3 DataStore 上限（已对官方文档核实，替换 `TritiumSQL.md` §0 的「规划假设」）

| 项 | 官方值 | 出处 |
| --- | --- | --- |
| Data store name | 50 字符 | Data store error codes and limits |
| **Key name** | **50 字符** | 同上 |
| Scope | 50 字符 | 同上 |
| **Value（key value）** | **4,194,304 字节（4 MiB）** | 同上 |
| 限速公式 | `rateLimit = baseLimit + perPlayerLimit × numPlayers`，且可由 `DataStoreService:SetRateLimitForRequestType(requestType, baseLimit, perPlayerLimit)` **在运行期覆盖** | DataStoreService 类参考 |
| 队列语义 | 超限请求进入队列（Set / OrderedSet / Get / OrderedGet 四类），**键级节流**会让该键的请求被跳过而非失败 | Data store error codes and limits |
| 官方建议 | 「每个玩家用一或少数几个键」以摊薄请求 | Best practices for data stores |

**由此产生的三处具体修正**：

1. `Tri.Request.RequestBudget` 不再硬编码常量，改为**启动时调 `SetRateLimitForRequestType` 显式设限并读取实际值**；预算层是唯一的配额真相来源（原来 Step 38 的「探针实测」降级为「核对覆盖是否生效」）。
2. 「超限」的正确行为是**排队 + 键级节流感知**，不是丢弃（原计划 §5 验收里的「超限丢弃」语义要改成「排队且不丢」；丢弃只适用于我们自己的 P0 保护策略）。
3. 键名 50 字符是**已核实的硬限**，Step 34 的 `NamespaceCodec` 断言从「规划假设」升级为**架构约束**：`tri:[db]:[table]:[p]:[type]:[val]` 在长值时必须走短哈希，这不是优化而是可行性前提。

---

## 2. 规模量化

### 2.1 现状

| 区域 | 文件 | LOC |
| --- | --- | --- |
| `Core` | 21 | 1,432 |
| `Net` | 23 | 1,870 |
| `Runtime` | 14 | 958 |
| `Security` | 2 | 241 |
| `Testing` | 5 | 304 |
| `Types` | 3 | 47 |
| `Extensions` | 1 | 42 |
| **合计** | **69** | **4,894** |

规格模块地图：**77 个目录 / 313 个去重模块名** → 文件覆盖率 **≈22%**；平均 71 行/文件（含 SelfTest）。

### 2.2 目标与工作量（→ 已由 `INTEGRATION.md` §4 取代）

**目标：两项目合计 100,000 行（v1.0 下限）**，含核心 + 测试 + 示例工具，不含文档。逐区域预算表、记分板脚本与判定规则见 **`INTEGRATION.md` §4**。摘要：

| 区域 | 模块 | 小计 LOC |
| --- | --- | --- |
| Deuterium 框架本体 | 313 | 35,000 |
| `Dr.Integration` | 18 | 12,900 |
| TritiumSQL 引擎本体 | 95 | 31,500 |
| `Tri.Integration` | 14 | 9,200 |
| 端到端/场景/故障注入测试 | — | 5,000 |
| 示例 · 基准 · 工具 · 发布脚本 | — | 6,400 |
| **合计** | **440** | **100,000**（其中测试 31,500） |

日历换算（按经验速度 300–600 行/有效工作日，含测试、审查与集成）：

| 人力 | 估算 |
| --- | --- |
| 单人 | 14 – 22 个月 |
| 双人（一条框架线 + 一条 SQL 线，在 Step 14.14/16 与四个接缝 §2 交汇） | 8 – 12 个月 |
| 双人 + agent 辅助 | 6 – 9 个月（压缩的是写码与测试，不是决策与调试） |

> 这组数字的作用是**防止开局烂尾**：如果实际目标只是「能用的游戏数据层 + 能查的关系表」，正确做法是砍 §4 的 Out 列与 `INTEGRATION.md` 的 G7，而不是压缩每个模块的深度。
>
> 100,000 是**下限而非配额**：A 档核心路径按不封顶标准写，实际会到 120,000–135,000 行。

### 2.3 里程碑（可演示，不是波次）

| 里程碑 | 内容 | 累计投入 |
| --- | --- | --- |
| **M0** | 仓库可构建、CI 四阶段绿、`SelfTest.RunAll()` 过 | Phase 0.1 |
| **M1** | **端到端纵切**跑通（见 §5），允许脏 | +3 天 |
| **M2** | `v0.1.0-alpha`：`CREATE TABLE` / `INSERT` / 主键 `SELECT` 走完 Parser→Plan→Index→Page→Port | TritiumSQL Phase 0–2 |
| **M3** | `v0.5.0-beta`：事务 + WAL + 崩溃恢复 + `UPDATE`/`DELETE`/`JOIN` + 集成 G1/G2/G3 | TritiumSQL Phase 3–5 |
| **M4** | `v1.0.0`：附录 B 的 v1 列全部落地 | TritiumSQL Phase 6–8 |
| **M5** | Deuterium `v1.0.0` 发布：Wally `.rbxm` + 文档站 + 示例 + 迁移指南 | Deuterium Phase 7 |

---

## 3. Deuterium 能力清单（可用性对标 Knit）

| # | 能力 | 归属 | 状态 |
| --- | --- | --- | --- |
| 1 | 服务/控制器/组件三分（对应 `Provider` + `Extension` + `Component`） | `Core.Container` + `Extensions` | ◐ 有 Provider/Extension，**缺 Component 语义** |
| 2 | 依赖注入与生命周期 | `Core.Container/Lifecycle` | ✅ |
| 3 | Signal / EventBus | `Dr.Signal`（**未实现**） | ⛔ 规划在 SERVICE 层，但 Knit 把它当基础设施 → **提前**到 Phase 2 |
| 4 | 网络自动桥接（方法/信号） | `Net.Bridge` | ✅ 桥存在，**缺 Knit 那种「声明即生成」的开发者体验** |
| 5 | 类型化定义 + 静态检查 | `Core.Reflection` + `Types` | ◐ 有 Reflection，缺面向用户的重导出 |
| 6 | **薄入口**（三个概念、五行代码） | 新增 `API/Deuterium.luau` 门面 | ⛔ **必须新增** |
| 7 | 文档站 | 新增 `docs/`（moonwave 或 MkDocs） | ⛔ |
| 8 | CHANGELOG + SemVer + 发布产物（`.rbxm` / Wally） | 新增 Phase 7 | ⛔ |
| 9 | 完整示例项目（≥3 个：最小、带持久化、带客户端复制） | 新增 `examples/` | ⛔ |
| 10 | 从 Knit 迁移指南 | 新增 `docs/migration-knit.md` | ⛔ |
| 11 | 基准报告（宣称的 ≥60% 带宽下降等必须有数字） | `Dr.Testing.Perf` + Phase 7 | ⛔ |
| 12 | 超出 Knit 的部分（安全 / HA / ECS / 诊断 / 数据 / 状态） | 各层 | 见 `.plan/Deuterium.md` §5 |

**判据（Phase 7）**：一个没读过本仓库的人，从零到跑通示例 ≤30 分钟；`Deuterium.luau` 门面导出的公共符号 ≤40 个（其余走 `Dr.*` 命名空间）；CHANGELOG 覆盖全部已发布版本。

---

## 4. TritiumSQL 模块清单与能力边界

### 4.1 模块数（≈95）

| 组 | 模块数 | Phase |
| --- | --- | --- |
| `Tri.Runtime`（端口 + 3 绑定） | 6 | 0 |
| `Tri.Catalog`（命名空间 / 目录 / Schema / 序列） | 6 | 0 · 4 |
| `Tri.Request`（预算 / 队列 / 批处理 / 优先级） | 5 | 1 |
| `Tri.Storage`（页 / 堆布局 / 页管理 / 缓存 / VACUUM） | 8 | 1 · 8 |
| `Tri.Index`（B+ 树 / 节点编解码 / 扫描 / 唯一 / 复合 / 部分 / 表达式） | 9 | 2 · 6 |
| `Tri.Txn`（事务 / MVCC / 锁 / 等待图 / 撤消 / 隔离） | 9 | 3 |
| `Tri.Wal`（写 / 读 / Checkpoint / 恢复） | 6 | 3 |
| `Tri.Query`（词法 / 语法 / AST / 语义 / 逻辑 / 优化 / 物理 / 执行 / 计划缓存） | 12 | 4 · 5 |
| `Tri.Query.Operators`（扫描 3 / 过滤 / 投影 / 排序 / 限制 / 连接 3 / 聚合 2 / 集合运算 4 / 子查询 3） | 18 | 4 · 5 |
| `Tri.Types`（类型系统 / 转换规则 / 三值逻辑 / 函数库） | 6 | 4 |
| `Tri.Stat`（统计 / 直方图 / 基数 / 代价模型） | 5 | 5 |
| `Tri.Ddl`（在线 DDL / 迁移 worker / 版本门 / 视图 / 序列） | 6 | 8 |
| `Tri.NoSql`（JSON 路径 / 表达式索引 / 时序 / 图） | 5 | 7 |
| `Tri.Adapters`（Deuterium 桥） | 2 | 8 |

### 4.2 能力边界（**这份列表是 v1 的验收口径**）

#### In — v1 必做

| 类别 | 功能 |
| --- | --- |
| **DDL** | `CREATE/DROP TABLE` · `TRUNCATE` · `ALTER TABLE`（加/删列、加/删约束）· `CREATE/DROP INDEX`（唯一/复合/部分/表达式）· `REINDEX` · `CREATE SEQUENCE` / auto-increment |
| **DML** | `INSERT`（多行 / `DEFAULT VALUES`）· `SELECT`（WHERE / JOIN / GROUP BY / HAVING / ORDER BY / LIMIT / OFFSET / DISTINCT / 别名 / 表达式）· `UPDATE` · `DELETE` · `UPSERT`（`ON CONFLICT DO NOTHING / DO UPDATE`）· `INSERT … RETURNING` |
| **查询构造** | 标量子查询 · `IN` · `EXISTS` · 相关子查询（correlated）· `UNION` / `UNION ALL` / `INTERSECT` / `EXCEPT` · `CASE` / `COALESCE` / `NULLIF` · 内连接 / 左连接 |
| **类型** | `INT` / `BIGINT` / `FLOAT` / `NUMERIC(p,s)`（以整数+标度模拟）· `VARCHAR(n)` / `TEXT` / `BOOLEAN` / `TIMESTAMP` / `DATE` / `UUID` / `JSON` / `ARRAY<T>` / `ENUM` |
| **语义** | **NULL 三值逻辑**（`AND`/`OR`/`NOT` 真值表、`IS NULL`、`IS DISTINCT FROM`）· 显式定义的类型转换矩阵（implicit / assignment / explicit 三级，对齐 PG 的分类） |
| **约束** | `NOT NULL` · `DEFAULT` · `PRIMARY KEY` · `UNIQUE` · `CHECK` · `FOREIGN KEY`（`CASCADE` / `SET NULL` / `RESTRICT`） |
| **索引** | B-tree 点查 / 范围 / 复合（列优先级）/ 唯一 / 部分 / 表达式；`ANALYZE` 收集统计 |
| **事务** | `BEGIN` / `COMMIT` / `ROLLBACK` / `SAVEPOINT` · 四种隔离级别 · 行/页/分区/表四级锁 + 意向锁 · 等待图死锁检测与受害者回滚 · MVCC 快照与可见性 · WAL redo/undo · Checkpoint · 崩溃恢复 |
| **错误语义** | SQLSTATE 风格错误码表（`23505` unique_violation · `23503` fk_violation · `23502` not_null_violation · `22001` string_data_right_truncation · `22003` numeric_value_out_of_range · `42P01` undefined_table · `42703` undefined_column · `42601` syntax_error · `40001` serialization_failure · `40P01` deadlock_detected · `55P03` lock_not_available · `57014` query_canceled），错误对象含位置、列路径、提示 |
| **会话/API** | `PreparedStatement` + 参数绑定 + 计划缓存 · 流式结果集 / 分页游标 · `EXPLAIN` / `EXPLAIN ANALYZE`（文本） |
| **算子** | SeqScan · IndexScan · IndexRangeScan · Filter · Project · Sort（分块归并）· Limit/Offset · NestedLoopJoin · HashJoin · MergeJoin · HashAggregate · StreamAggregate |
| **优化** | 谓词下推 · 投影消除 · 常量折叠 · 基于统计的索引选择 · Join 重排（小表驱动，**启发式 + 简单代价，不做搜索空间枚举**） |
| **运维** | `VACUUM` · `CHECKPOINT` · 在线 DDL 渐进迁移 · 监控指标（表统计 / 预算 / 缓存命中率 / 锁等待 / 慢查询日志）· 导出导入（JSON / CSV 文本）· 快照备份 |
| **NoSQL 扩展** | JSON 路径查询 + 表达式索引 · 时序表 + 降采样 + 滑动窗口 · 图边表 + 双向索引 · 跨服 L2（MemoryStore）热点共享 |

#### In — v1.5（明确排期但不在 v1）

`CREATE VIEW` · CTE（`WITH` / `WITH RECURSIVE`）· `SELECT … FOR UPDATE` 显式锁子句 · 仅索引扫描（index-only scan）· 参数化计划的多计划缓存（generic vs custom plan）· `EXPLAIN (FORMAT JSON)`

#### Out — v2 或永不做

| 项 | 决定 | 理由 |
| --- | --- | --- |
| 窗口函数 | v2 | 算子复杂度高，游戏场景需求低 |
| 存储过程 / 触发器 / PL | v2 | 会引入第二套执行模型 |
| `GRANT` / `REVOKE` | **永不做** | 权限由 Deuterium RBAC 在最上层裁决；库内做是重复 |
| 网络线协议 / 多语言驱动 | **永不做** | 无场景 |
| 物理/流复制、PITR、逻辑订阅 | **永不做** | DataStore 不提供所需原语 |
| 自定义类型 / 扩展 API / `tsvector` / 几何 / 范围类型 | 永不做 | 收益远低于维护成本 |
| GIN / GiST / BRIN / Hash 索引 | 永不做 | B-tree + JSON 表达式索引已覆盖目标场景 |
| 优化器完整搜索空间（DP / Volcano）、并行查询、JIT | **永不做** | 与 DataStore 的请求预算相比，优化器收益上限很低 |
| 用户声明的声明式分区语法 | 永不做 | 分区是内建策略（`TriSQL.md` §3.3），不暴露语法 |
| 跨服分布式事务 / 2PC | 永不做 | 用 Saga（Deuterium `Dr.Data.Reliability.Transaction`）在上层表达 |

---

## 5. 策略修正：纵切优先（本规模下最重要的一条）

现状规划是**横铺**：按层把模块一个个填满。313 + 95 个模块的规模下，横铺会在第 4–6 个月暴露致命问题 —— 每个模块 200 行看着齐，但**架构接缝从未被真实验证过**，返工发生在最贵的阶段。

**改为纵切优先**：Phase 0 之后立刻插入 **Phase 0.5 · 端到端纵切**（约 3 天，允许脏，产出接缝清单）：

```
Kernel.Boot
  → Tri.Catalog.SchemaStore（内存版）
  → TriSQL.Compile("CREATE TABLE t (id INT PRIMARY KEY, name TEXT)")
  → TriSQL.Compile("SELECT name FROM t WHERE id = 1")   -- 走 IndexScan
  → Tri.Index.BPlusTree（内存版）
  → Tri.Storage.PageManager（内存版）
  → Tri.Runtime.StorePort → SimulatorPort
  → 读回并断言结果
```

规则：
- 允许内存占位与 `shortcut:` 标注，**不做持久化、不做事务、不做优化器**。
- 唯一目标：让接缝暴露。产出「接缝清单」写入 `.plan/SEAMS.md`（哪些接口需要正式化、哪些设想不成立）。
- 接缝清单确认后，才回到横铺顺序继续（`STEPS.md` Step 14 起）。

**质量分档**（规模下的资源分配）：

| 档 | 模块 | 标准 |
| --- | --- | --- |
| **A · 核心路径** | 页管理 · B+ 树 · 事务/MVCC · WAL/恢复 · 解析器 · 优化器 · 锁管理器 · 请求预算 | 边界用例 + 故障注入 + 请求次数断言 + 性能预算，单模块 LOC 上不封顶 |
| **B · 支撑** | 编解码 · 类型系统 · 统计 · 目录 · 缓存 · 集合/内存/并发原语 | 单测覆盖正常/边界/失败三例 |
| **C · 外围** | 监控面板 · 导出导入 · 诊断 · Util · 文档站 | 够用即止，允许薄实现 + `shortcut:` |

---

## 6. 路线图修订

### 6.1 Deuterium

| 变更 | 内容 |
| --- | --- |
| 新增 **Phase 0.5** | 端到端纵切（§5），插入在 Phase 0.4 之后、Step 14 之前 |
| `Dr.Signal` **提前** | 从 SERVICE 层规划位置提前到 Phase 2（Knit 把 Signal 当基础设施，没有它薄入口立不住） |
| 新增 **Phase 7 · 发布与生态** | 薄入口门面 `API/Deuterium.luau` · 文档站 · `examples/`（≥3）· `docs/migration-knit.md` · CHANGELOG + SemVer · `.rbxm` + Wally 发布 · 基准报告 · `Component` 语义补件 |
| 新增 **Phase 8 · Studio 插件**（可选） | 代码生成 / 类型导出，对标 Knit 的插件体验；v1 不阻塞发布 |

### 6.2 TritiumSQL

从 9 个 Phase 扩到 **12 个**：

| Phase | 内容 | 新增/变更 |
| --- | --- | --- |
| 0 | 端口 · 命名空间 · 目录 · Schema · 序列 | 不变 |
| **0.5** | **端到端纵切**（内存版全链） | **新增** |
| 1 | 请求管线 · 页 · CRUD · L1 缓存 | 不变（`RequestBudget` 改为显式设限，见 §1.3） |
| 2 | B+ 树（主键）+ 索引扫描 | 不变 |
| 3 | 事务 · MVCC · 锁 · WAL · 崩溃恢复 · **SQLSTATE 错误码** | **加错误码表** |
| 4 | 词法/语法/语义/逻辑计划 · 核心算子 · 类型系统 · **三值逻辑** · PreparedStatement | **加三值逻辑与类型转换矩阵** |
| 5 | 连接算子 · 优化器 · 统计 · EXPLAIN · **子查询 · 集合运算** | **加子查询与集合运算（原属 v1.5，现提到 v1）** |
| 6 | 二级/复合/唯一/部分/**表达式**索引 | 加表达式索引 |
| 7 | NoSQL 扩展（JSON/时序/图） | 不变 |
| 8 | 在线 DDL · VACUUM · 监控 · 导出导入 · 快照 · **适配器** | 加导出导入与快照 |
| **9** | **v1.0 硬化**：故障注入矩阵 · 压力测试 · 性能预算达成 · 文档 | **新增** |
| **10** | **发布**：`vospek/tritiumsql` Wally 包 · API 文档 · 迁移与兼容策略 | **新增** |
| **11** | v1.5 功能（视图 · CTE · `FOR UPDATE` · 仅索引扫描 · JSON 格式 EXPLAIN） | **新增** |

---

## 7. 规模自身的风险

| 风险 | 等级 | 对策 |
| --- | --- | --- |
| **两个项目各自跑通但从未合练**（集成在最后才发现接缝不成立） | 极高 | `INTEGRATION.md` §2 的四个接缝在 Phase 0.5 纵切时就冻结；G1–G3 排在 M3 而非最后 |
| **广度压倒深度**：408 个模块每个都「有」，但核心路径不够健壮 | 极高 | §5 纵切优先 + A/B/C 质量分档；核心路径单模块不封顶，外围允许薄 |
| 规模导致决策蔓延（每个模块都要重新讨论接口） | 高 | 先出接缝清单（Phase 0.5），接口冻结后再横铺；新增接口走 ADR |
| 单人推进 12–20 个月，中途失去动力 | 高 | 里程碑 M0–M5 全部是**可演示产物**；每个 Phase 末打 tag |
| 对标 PG 的功能面被外部当作承诺，而存储层封顶被忽略 | 中 | §1.2 的封顶声明写进 `README.md` 首页与发布说明 |
| 官方限额与队列语义误解（把「排队」当「失败」） | 中 | §1.3 已核实并回写；`RequestBudget` 实现必须区分「排队」「键级节流」「真失败」三种状态 |
| 两个项目并行时接口漂移（Port 契约、Codec） | 中 | Step 14.14 与 Step 16 是唯一交汇点，接口冻结后加契约测试（`Tri/Testing/PortContract.luau`） |

---

## 附录 A · 对既有计划文档的修订清单

| 文档 | 修订 |
| --- | --- |
| `.plan/README.md` | 关键路径插入 Phase 0.5；门禁 7（预算门禁）补「排队而非丢弃」；§开放决策 D2 补「TritiumSQL 存储层封顶」的说明 |
| `.plan/Deuterium.md` | 新增 Phase 7 / Phase 8；`Dr.Signal` 提前到 Phase 2；§0 增补 I13（薄入口：对外公共符号必须经 `API/Deuterium.luau` 收口） |
| `.plan/TritiumSQL.md` | §0 的「规划假设」替换为 §1.3 的**已核实值**；§12 扩到 12 个 Phase；功能面以本文档附录 B 为准；「超限丢弃」改为「排队 + 键级节流」 |
| `.plan/STEPS.md` | Phase 0.4 之后插入 Step 16.5「端到端纵切」；Step 38 改为「核对 `SetRateLimitForRequestType` 覆盖是否生效」 |

## 附录 B · v1 功能清单（验收口径，等同于 §4.2 的 In 列）

以 §4.2 的 In — v1 表格为唯一口径。v1.0 发布前逐行勾选；任何未勾选项必须移入 v1.5 并写明理由，不允许「默认算做过」。

---

未读/未验证：PostgreSQL 的功能分类（implicit/assignment/explicit 转换三级、SQLSTATE 具体码值）依印象给出、**未逐一核对 PG 文档**，Step 34 与 Phase 3/4 动工前需对一遍官方附录；`rokit` 安装脚本可用性、Lune 环境注入能力仍是 `.plan/STEPS.md` Step 7 的探测项；LOC 与工作量区间是经验估算，误差可能达 ±50%。风险：§4.2 的 In 列如果全按 v1 承诺，M4 的日历估算会偏乐观 1–2 个月。
