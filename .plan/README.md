# Plan of Record — 宪法

> 仓库：`gitlab.com/vospek/roblox-dev/framework`
> 本目录是**计划层**（排期 / 边界 / 验收 / 决策）。规格层在原位：`../Deuterium/Deuterium.md`（框架规格）、`../Text File.txt`（SQL 原始设想，已由 `TritiumSQL.md` 取代、原位保留对照）。

## 0. 文件地图与阅读顺序

| 顺序 | 文件 | 唯一权威的内容 |
| --- | --- | --- |
| 1 | **本文件** | 不变量（I8–I15）· 统一门禁 · 决策登记（D1–D8）· **全局风险登记表** · 验收 ID 规范 · 关键路径 · 进度 |
| 2 | `SCALE.md` | 对标实测（Knit / PG / DataStore 限额）· **100k 行预算表** · 里程碑 · 纵切策略 · 质量分档 · 附录 B 功能追踪矩阵 |
| 3 | `Deuterium.md` | 框架：完成度审计 · 规格修订清单 · Wave 计划（`D*`） |
| 4 | `TritiumSQL.md` | 数据库：物理天花板 · 模块地图 · 设计决定（`T1–T12`）· Wave 计划（`T*`） |
| 5 | `INTEGRATION.md` | 两项目互通：十条路径（`G1–G10`）· 四个接缝接口 · 启动时序 · 验收 `AC-G*` |
| 6 | `STEPS.md` | 执行手册：每个 Step 的「动哪个文件 → 跑什么命令 → 什么算过」· Step↔Wave↔AC 对照 |

**写码前只读 1 和 6**；改接口时读 2 和 5。

## 1. 不变量

- **I1–I7** 在规格 `Deuterium/Deuterium.md` §0（静态胜于动态 / 服务器权威 / 隔离舱壁 / 外部调用兜底 / 面向数据 / 可观测 / VerySafe 供应链）。
- **I8–I15** 由本计划增补，**定义只在此处**，其余文档一律引用编号：

| # | 不变量 | 后果 / 强制方式 |
| --- | --- | --- |
| I8 | **持久化不在框架内** | 页、索引、MVCC、WAL、查询语义一律归 TritiumSQL；`Dr.Data` 只做会话态与编排 |
| I9 | **一份 Codec** | 序列化唯一实现在 `Dr.Types.Transform.Codec`；`Dr.Net` 与 TritiumSQL 都调用它，禁止第三份 |
| I10 | **引擎 API 单一出入口** | Roblox API 只出现在 `Dr.Runtime`；TritiumSQL 经 `Tri.Runtime.StorePort` 端口，Standalone 绑定是唯一例外文件（需显式标注） |
| I11 | **SQL 编译期化** | SQL 字符串只在 Init/Construct 期解析为 `PreparedStatement`；热路径禁止解析 |
| I12 | **请求次数是验收指标** | 涉及 DataStore 的波次必须断言请求次数；且区分「排队 / 键级节流 / 真失败」三态 |
| I13 | **薄入口** | 对外公共符号经 `API/Deuterium.luau` 收口（≤40 个），其余走 `Dr.*` 命名空间 |
| I14 | **集成方向单一出入口** | `Dr.*` 调 `Tri.*` 只允许在 `Deuterium/Integration/`；CI grep 阻断 |
| I15 | **锁顺序** | 先 `Dr.Concurrency.Sync.Mutex`（进程内短临界区）→ 后 `Tri.Txn.LockManager` 行锁（持久/跨服），禁止反向 |

## 2. 统一门禁（两项目共用，无例外）

| # | 门禁 | 强制方式 |
| --- | --- | --- |
| 1 | **可运行**：`rojo build` 成功且 `SelfTest.RunAll()` 全绿 | CI `build` 阶段 |
| 2 | **可测**：headless 测试在 CI 跑（Lune）；「Studio 手点」不能作为唯一验收 | CI `test` 阶段 |
| 3 | **可静态检查**：`stylua --check` + `luau-lsp analyze` + `scripts/p0-check.sh` | CI `lint`/`types` 阶段 |
| 4 | **可观测**：每个决策点有结构化日志；黑盒代码视为未完成 | Review |
| 5 | **P0 规约**：热路径禁字符串查表 / 匿名闭包分配 / `table.insert` 扩容 | `scripts/p0-check.sh` 基线只降不升 |
| 6 | **依赖门禁**：运行期外部依赖仅 Scribe / PlayerState / QuickZone，且走规格 §2 五步审计；开发期工具不计入 | `MEMORY.md` 审计留档 |
| 7 | **预算门禁**（SQL/集成）：断言 DataStore 请求次数与三态语义（I12） | 测试断言 |
| 8 | **LOC 记分板**：合计 ≥ 100,000 且各区域 ≥ 预算 70% | `scripts/loc-budget.luau`，**仅 release 分支阻断**（日常只 warn） |
| 9 | **集成方向**：`Dr.*` 中 `Deuterium/Integration/` 之外出现 `Tri.*` → 阻断（I14） | CI grep |

## 3. 决策登记（ADR 索引）

规则：任何新增/变更的**接口或边界**决策追加一行，状态为 `OPEN` 的阻塞其「阻塞」列对应的 Wave。

| # | 决策 | 选项 | 结论 | 状态 | 阻塞 |
| --- | --- | --- | --- | --- | --- |
| D1 | PlayerState 上游来源 | 用户指定仓库 / 放弃 | 用户指定（待定） | **OPEN** | D4.1 |
| D2 | PlayerState 是否仍必要 | 保留 / 全改走 TritiumSQL | **保留但降为纯复制组件**：TritiumSQL Phase 3（T3.x）落地后，持久化职责全部移交；且明确 **TritiumSQL 的存储层能力被 DataStore 封顶**（无 fsync / 缓冲池 / 共享内存），不对标 PG 的存储层 | DECIDED | — |
| D3 | 引擎 API 形态 | 只 SQL 字符串 / 只类型化构建器 / 两者 | 两者，但 SQL 必须 Init 期编译（I11） | DECIDED | T0.x |
| D4 | headless 测试运行时 | Lune / 自研伪 shim | Lune；`game` 注入能力由 Step 7 探针决定，失败则 CI 只覆盖纯逻辑模块 | DECIDED | — |
| D5 | 发布形态 | Wally 包 / submodule | Wally：`vospek/deuterium` + `vospek/tritiumsql`，独立版本号 | DECIDED | D7.6 / T10 |
| D6 | Scribe 审计 | 审计后保留 / 换自研 | 审计后保留（约 30 分钟人工），结论入 `MEMORY.md` | DECIDED | Step 9 |
| D7 | QuickZone 是否引入 | 引入 / 不引入 | 引入，推迟到世界层动工前 | DECIDED | D6.6 |
| D8 | 目录落地 | 现树 + Rojo 映射 / 迁到 `src/ReplicatedStorage/` | **现树 + Rojo 映射**（现有 require 字符串已与现树一致） | DECIDED | Step 2 |
| D9 | 集成层事件机制 | 直接回调 / `Dr.Signal` 广播 | 待 `Dr.Signal`（D2.0）落地后定；默认先回调（依赖更少、更快），Signal 作为可选广播 | **OPEN** | Step 54/57 |

## 4. 关键路径

```
Step 1–12   Phase 0.1  工具链与工程骨架（Debug/Logger、Rojo、CI、静态检查）   ← 阻塞一切
    │
Step 16.5   Phase 0.5  端到端纵切（内存版全链，3 天，只求暴露接缝）→ SEAMS.md
    │
Step 13–16  Phase 0.2–0.4  Foundation 前置件 + Simulator + 引擎端口
    │
    ├──▶ D2.x 安全 ──┐
    ├──▶ D2.0 Signal ┤
    ├──▶ D3.1/3.2 HA┴─┐
    └──▶ T0–T2 引擎 ──┴──▶ T3 事务/WAL ──▶ T4/T5 查询 ──▶ G1–G3 集成 ──▶ G4/G5 ──▶ D4 会话态 ──▶ T9/T10 + D7 发布
```

## 5. 进度登记

| 项目 | 按模块计 | 按 LOC 计 | 当前 Wave | 下一个 Step |
| --- | --- | --- | --- | --- |
| Deuterium 本体 | 69 / 313 ≈ 22% | 4,894 / 26,000 ≈ 19% | 已完成 D1.1–D1.7、D2.2–D2.4 | **Step 1（Phase 0.1 未开工）** |
| TritiumSQL 引擎 | 0 / 95 | 0 / 22,000 | 未开工 | 依赖 Step 16.5 |
| 集成层 | 0 / 32 | 0 / 14,100 | 未开工 | 依赖 T0–T2 |
| **合计** | 69 / 440 ≈ 16% | **4,894 / 100,000 ≈ 5%** | — | — |

> 完成度按「文件存在」计，不等价于功能经独立验证；Step 10（`RunAll()` 跑通）之前，D1/D2 已完成波次都是**未验证**状态。

## 6. 全局风险登记表（唯一处）

| # | 风险 | 等级 | 触发条件（如何知道） | 对策 | 承载 |
| --- | --- | --- | --- | --- | --- |
| R1 | Phase 0.1 被跳过，在不可运行仓库上叠模块 | 极高 | Step 10 或 Step 12 不绿 | Phase 0.1 是唯一硬门禁，未绿不得开任何 Wave | `STEPS.md` Step 1–12 |
| R2 | 两项目各自跑通但从未合练 | 极高 | Phase 0.5 无 `SEAMS.md`；G1–G3 排在 M3 之后 | 四个接缝在纵切时冻结；G1–G3 进 M3 | `INTEGRATION.md` §2 |
| R3 | **RLS 被优化器绕过**（谓词下推 / 常量折叠 / 索引选择） | 极高 | `AC-G5` 的 ≥10 个越权用例有任何一个通过 | `trusted=false` 禁用三种优化 + 安全用例进 CI 阻断 | `INTEGRATION.md` §2.3 |
| R4 | 广度压倒深度：440 模块每个都「有」但核心不健壮 | 极高 | A 档模块 LOC < 250 或缺少边界/故障注入用例 | 纵切优先 + A/B/C 质量分档，A 档不封顶 | `SCALE.md` §5 |
| R5 | 复制看到未提交数据 / 乱序 / 丢变更 | 高 | `AC-G4` 顺序或幂等断言失败 | 变更只从提交路径发射 + lsn 全序 + `lastAck` 补齐 | `INTEGRATION.md` §2.2 |
| R6 | 两套锁体系互相死锁且不可见 | 高 | 反序加锁未被拦下 | I15 固定顺序 + `LockBridge` 强制 + 负例测试 | `INTEGRATION.md` §6 |
| R7 | 启动顺序耦合（Tri 未就绪时 `Dr.Data` 已 Init） | 高 | `BootGate` 断言失败 | 显式顺序断言 + 负例测试 `AC-G1` | `INTEGRATION.md` §3 |
| R8 | 请求限速下性能不达标 | 高 | 波次请求次数断言失败 | 预算层先行 + 页聚合 + 每 Wave 请求断言 | `TritiumSQL.md` §3.4 |
| R9 | 协程锁饥饿 / 死锁在 Studio 复现不了 | 高 | 压力用例偶发失败且不可复现 | Simulator 强制定序交错 + 专门压力用例 | `STEPS.md` Step 14.8 |
| R10 | 单人推进 14–22 个月中途失速 | 高 | 连续两个 Wave 无 tag | 里程碑 M0–M5 全部是**可演示产物**，每 Phase 打 tag | `SCALE.md` §4 |
| R11 | 存储层封顶被外部当作 PG 承诺 | 中 | 发布说明未写封顶声明 | 封顶声明进 `README` 首页与每个 release note（D2） | `SCALE.md` §1.2 |
| R12 | 边界被打破（`Dr.Data` 里出现页/索引/MVCC，或 `Dr` 直接 require `Tri`） | 中 | 门禁 9 失败；Review 发现页/索引概念 | I8 + I14 + CI grep | 本文件 §2 |
| R13 | 接口漂移（Port 契约、Codec 两份） | 中 | 三绑定跑同一 `PortContract` 结果不一致 | 契约测试；接缝冻结后不得私改 | `STEPS.md` Step 60/61 |
| R14 | 集成层变成垃圾场 | 中 | 目录内出现不实现 G1–G10 的模块 | 集成层模块必须映射到某条 G 路径，否则不进目录 | `INTEGRATION.md` §1 |
| R15 | 100k 行变成凑行数 | 中 | 新增模块不映射到 `SCALE.md` 附录 B 的 In 列 | 记分板只防缩水、不奖励超额；新增模块必须挂功能点 | `SCALE.md` §3 |

## 7. 验收 ID 规范

| 形式 | 含义 |
| --- | --- |
| `AC-D<wave>` | Deuterium 某 Wave 的验收（例：`AC-D2.5`） |
| `AC-T<phase>` | TritiumSQL 某 Phase 的验收（例：`AC-T3`） |
| `AC-G<n>` | 集成路径 n 的验收（`AC-G1`…`AC-G10`，定义在 `INTEGRATION.md` §6） |

规则：每个 Wave 至少一个 AC；`STEPS.md` 的 Step 完成判据引用 AC；release 前逐条勾选。

## 8. 变更记录

| 版本 | 变更 |
| --- | --- |
| v1 | 从 `Deuterium.md` §8 与仓库审计重写；`Text File.txt` 路线图重排为 `TritiumSQL.md` |
| v2 | 引入规模标定（`SCALE.md`）、执行手册（`STEPS.md`）、纵切优先策略、Phase 0 |
| v3 | 引入集成契约（`INTEGRATION.md`）与 100k 行预算 + 记分板 |
| **v4** | **全面一致性优化**：不变量/门禁/决策/风险各自收口为唯一出处；Wave ID 统一；修正 LOC 加总错误（集成层核心 8,200→8,400、G4+G5 5,400→4,950）；补 `D2.0 Signal`；新增进度登记与验收 ID 规范；`SCALE.md` 附录 B 升级为功能追踪矩阵 |
