# Plan of Record — Framework + SQL

> 仓库：`gitlab.com/vospek/roblox-dev/framework`
> 本目录是**实施计划**（排期 / 边界 / 验收 / 决策）。规格文档仍在原位：
> - Framework 规格：`../Deuterium/Deuterium.md`
> - SQL 规格：`../Text File.txt`（已重写为 `./TritiumSQL.md`；原文件**原位保留**未改动，供对照）

## 计划文件

| 文件 | 内容 |
| --- | --- |
| `Deuterium.md` | 框架实施计划：完成度审计、与规格的偏差、边界重划、Phase 0 前置波次、剩余波次排期 |
| `TritiumSQL.md` | 数据库实施计划：命名重写（VoxDB→TritiumSQL、VQL→TriSQL）、模块地图、9 个阶段路线图、验收 |
| `STEPS.md` | **执行手册**：把 Wave 拆成「动哪个文件 → 跑什么命令 → 什么算过」的可执行 Step（S1–S3、1–21、16.5、30–47） |
| `SCALE.md` | **规模标定**：Knit/PG 对标实测、v1 功能清单（In/Out）、纵切优先策略、路线图修订 |
| `INTEGRATION.md` | **集成契约**：两项目互相配合的十条路径（G1–G10）、四个接缝的接口、启动时序、**100k 行预算与记分板**、440 模块清单 |
| `README.md` | 本文件：两项目交界、依赖顺序、统一门禁、开放决策 |

## 两项目关系（唯一设计决定）

```
Deuterium        = 框架总线（微内核 / 生命周期 / 网络 / 会话态 / 复制 / 安全 / ECS）
TritiumSQL       = 持久化引擎（页 / B+树 / 事务 / WAL / 查询 / 索引）

依赖方向（单向，无环）：
  TritiumSQL ──依赖──▶ Deuterium 的 RUNTIME + FOUNDATION + TOOLING 三层
  Deuterium  ──不依赖──▶ TritiumSQL（只有 Dr.Data 的可选适配器反向调用）
```

**边界铁律**（消除规格里的重复造轮子）：

| 关注点 | 归属 | 理由 |
| --- | --- | --- |
| 页 / 槽 / 分区路由 | TritiumSQL | 持久化世界 |
| B+ 树索引 | TritiumSQL | 持久化世界 |
| MVCC / 行锁 / WAL / Checkpoint / 崩溃恢复 | TritiumSQL | 持久化世界 |
| 查询解析 / 优化 / 算子 | TritiumSQL | 持久化世界 |
| DataStore 请求预算 / 令牌桶 / 批处理 | TritiumSQL | 唯一物理天花板所在层 |
| 玩家**会话态**（在线数据、PlayerState 封装、六段写入） | Deuterium `Dr.Data` | 与持久化无关，生命周期跟随玩家连接 |
| **复制**（server → client） | Deuterium `Dr.State` | 复制 ≠ 持久化 |
| 跨存储 Saga（会话态 ↔ 持久化） | Deuterium `Dr.Data.Reliability.Transaction` | 协调者，不是事务引擎 |
| 序列化 Codec | Deuterium `Dr.Types.Transform.Codec`（FOUNDATION） | 一份实现，Net 与 SQL 共用 |
| 集合 / 内存池 / 缓冲 / 协程同步原语 | Deuterium `Dr.Collections`·`Dr.Memory`·`Dr.Concurrency` | 通用底座 |
| **两项目的互通** | `Deuterium/Integration/` + `TritiumSQL/Tri/Integration/`（只此两处） | 双向配合、单向依赖：**I14** |
| 跨两套锁体系的加锁顺序 | 固定「Dr Mutex → Tri 行锁」（**I15**） | 没有统一死锁检测器，只能靠固定顺序 |

> 两条新不变量（I14 集成方向、I15 加锁顺序）见 `INTEGRATION.md` §0。
>
> 后果：`Deuterium.md` 原 Phase 4 的 4.3（Reliability）与 4.4（Processing/Observe）大部分**移出**框架，改由 `TritiumSQL.md` Phase 1–3 承担。这是本次计划改写省下的最大一块重复工作量。

## 唯一关键路径

```
Phase 0  工程骨架 + 工具链 + Foundation 前置件        ← 阻塞一切，当前最优先
   │
Phase 0.5 端到端纵切（内存版全链，3 天，只求暴露接缝）  ← 见 SCALE.md §5
   │
   ├──▶ Deuterium Phase 2.5–2.7（安全）
   ├──▶ Deuterium Phase 3（HA 最小集）─┐
   │                                   │
   └──▶ TritiumSQL Phase 0–2 ─────────┴──▶ TritiumSQL Phase 3（事务/WAL）
                                                  │
Deuterium Phase 3（全量）+ Phase 5/6 ─────────────┘
                                                  │
                                          Deuterium Phase 4（会话态 + 适配器）
```

并行度：Phase 0 之后，**Deuterium 安全/HA** 与 **TritiumSQL 存储/索引** 由两个独立工作流并行推进，仅在 `Tri.Runtime` 端口契约（Wave 0.4）与 Codec（Wave 0.3）处交汇。

## 统一门禁（两项目共用，无例外）

1. **可运行**：`rojo build` 成功，Studio 内 `SelfTest.RunAll()` 全绿。
2. **可测**：headless 测试在 CI 跑（Lune），不允许「Studio 手点」作为唯一验收手段。
3. **可静态检查**：`selene` + `stylua --check` + `luau-lsp analyze` 三件套在 CI 阻断。
4. **可观测**：每个决策点有结构化日志，黑盒代码视为未完成。
5. **P0 规约**：热路径禁字符串查表 / 匿名闭包分配 / `table.insert` 扩容。皆需 CI 静态巡检（selene 自定义规则）。
6. **依赖门禁**：运行期外部依赖只允许 Scribe / PlayerState / QuickZone 三项，且必须走 `Deuterium.md` §2 五步审计流程；开发期工具（rokit / lune / selene / stylua / luau-lsp）不计入。
7. **预算门禁**（SQL 专属）：每个波次的测试断言 **DataStore 请求次数**，不是只断言结果正确；且必须区分「排队」「键级节流」「真失败」三种状态（见 `SCALE.md` §1.3）。
8. **LOC 记分板**（release 分支阻断）：`scripts/loc-budget.luau` 校验合计 ≥ 100,000 且各区域 ≥ 预算 70%；日常分支只 warn（`INTEGRATION.md` §4.2）。
9. **集成方向门禁**：`Dr.*` 中除 `Deuterium/Integration/` 外出现 `require` 到 `Tri.*` → CI 阻断（**I14**）。

## 开放决策（需确认，各自阻塞对应波次）

| # | 决策 | 选项 | 建议 | 阻塞 |
| --- | --- | --- | --- | --- |
| D1 | PlayerState 上游来源 | 用户指定仓库 / 放弃 | 用户指定 | Deuterium 4.x |
| D2 | PlayerState 是否还必要 | 保留（仅做 Replica 复制）/ 全部改走 TritiumSQL | 保留，**降为纯复制组件**：TritiumSQL Phase 3 落地后，PlayerState 的持久化职责全部移交 | Deuterium 4.x |
| D3 | TritiumSQL 引擎 API 形态 | 只给 SQL 字符串 / 只给类型化构建器 / 两者 | **两者，但 SQL 必须在 Init 期编译为 PreparedStatement**（运行期解析违反 P0 不变量） | TritiumSQL 0.x |
| D4 | headless 测试运行时 | Lune / 自研伪 headless shim | Lune（开发期工具，不违反依赖门禁） | Deuterium 0.1 |
| D5 | 发布形态 | Wally 包 `vospek/deuterium` + `vospek/tritiumsql` / Git submodule | Wally，两包独立版本号 | Deuterium 6.7 / SQL 8.x |
| D6 | Scribe 审计 | 审计后保留 / 换成自研 Logger | 审计（约 30 分钟人工），保留 | Deuterium 0.1 |
| D7 | QuickZone 是否仍需引入 | 引入（世界层空间查询）/ 用 TritiumSQL 无关 | 引入，但推迟到世界层动工前 | Deuterium 6.6 |
| D8 | 目录落地路径 | 现树 `Deuterium/` → `ReplicatedStorage.Deuterium`（Rojo 映射） / 迁到规格写的 `src/ReplicatedStorage/` | **保留现树 + Rojo 映射**，因现有代码 require 字符串已与现树一致 | Deuterium 0.1 |

## 变更记录

| 日期 | 变更 |
| --- | --- |
| 首版 | 从 `Deuterium.md` §8 与环境审计重写；原 `Text File.txt` 路线图重排为 `TritiumSQL.md` |
