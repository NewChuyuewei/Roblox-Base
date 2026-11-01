# Plan of Record — 宪法

> 仓库：`gitlab.com/vospek/roblox-dev/framework`
> 本目录是**计划层**（排期 / 边界 / 验收 / 决策）。规格层：`../Deuterium/Deuterium.md`（框架规格）、`TritiumSQL.md`（SQL 计划）。
> 原 `Text File.txt`（SQL 原始设想）已由 `TritiumSQL.md` 取代并**删除**（commit `5d4fabe`）—— 历史里仍可查。

## 0. 文件地图与阅读顺序

| 顺序 | 文件 | 唯一权威的内容 |
| --- | --- | --- |
| 1 | **本文件** | 不变量（I8–I15）· 统一门禁 · 决策登记（D1–D8）· **全局风险登记表** · 验收 ID 规范 · 关键路径 · 进度 |
| 2 | `SCALE.md` | 对标实测（Knit / PG / DataStore 限额）· **100k 行预算表** · 里程碑 · 纵切策略 · 质量分档 · 附录 B 功能追踪矩阵 |
| 3 | `Deuterium.md` | 框架：完成度审计 · 规格修订清单 · Wave 计划（`D*`） |
| 4 | `TritiumSQL.md` | 数据库：物理天花板 · 模块地图 · 设计决定（`T1–T12`）· Wave 计划（`T*`） |
| 5 | `INTEGRATION.md` | 两项目互通：十条路径（`G1–G10`）· 四个接缝接口 · 启动时序 · 验收 `AC-G*` |
| 6 | `STEPS.md` | 执行手册：每个 Step 的「动哪个文件 → 跑什么命令 → 什么算过」· Step↔Wave↔AC 对照 |
| 7 | **`CERT.md`** | **DO-178C 适配（PSAC-lite）**：危害分析与 DAL 分配 · **认证范围切割** · 平台/工具鉴定 · 生命周期数据 16 项 · 验证改革 · C1–C6 前置 Phase · 已知偏差 |

**写码前只读 1 和 6**；改接口时读 2 和 5；**动认证范围内任何文件时先读 7**。

| 8 | **`THIRDPARTY.md`** | **第三方集成契约**：Scribe/QuickZone 的实测事实 · **所有权划分表** · 适配器（I20）· 不变量豁免登记 · **不计入 100k 的规则** · 审计义务 |

> ⚠ `CERT.md` 是**约束性**的：它把范围砍到 ≤12k 行（认证线），并把 C1–C6 插到所有功能 Wave **之前**。
> ⚠ `THIRDPARTY.md` 同样约束性：它决定了 `Dr.Data`/`Dr.State` 的哪些波次要**取消**（不重复造）。
> 认证线的**生命周期数据**在仓库另一处：`docs/cert/`（索引入口 `docs/cert/README.md`，含真实进度表）。两处的分工是：`.plan/` 管**排期与约束**，`docs/cert/` 管**证据与产物**。

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
| I16 | **认证核心不依赖非认证代码** | 认证范围内模块不得 require `game` / `Dr.Runtime` / `Dr.Net` / `Dr.Security` / `Dr.Diagnostics` / `Dr.Testing`；CI 静态守卫（与 I14 同机制）。定义见 `CERT.md` §3 |
| I17 | **边界输入一律防御** | `Port` / `ResultSet` / `Codec` 三个接口的入参在核心内**先验后用**；这是用设计隔离代替“鉴定引擎”的具体手段 |
| I18 | **需求先于代码** | 认证范围内任何新文件必须先有 LLR；CI 检查“无 LLR 的新增认证范围文件” |
| I19 | **确定性底座** | 认证信用只能跑在 `SimulatorPort` + 受控 Luau 上；碰网络/引擎的测试属产品线，不计入认证证据 |
| I20 | **第三方只经适配器** | `src/ReplicatedStorage/Deuterium/**` 内除 `*/Adapter/*` 外不得 require `Scribe`/`QuickZone`；门禁强制（`scripts/thirdparty-check.luau`，待交付）。见 `THIRDPARTY.md` §3 |
| I21 | **不重复造** | Scribe 已有的能力（玩家数据/复制/经济/排行榜）不在 `Dr.Data`/`Dr.State` 重实现；见 `THIRDPARTY.md` §2 所有权表 |

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
| 10 | **认证范围**（I16）：认证范围模块触碰引擎/网络/非认证层，**或依赖范围外模块** → 阻断 | ✅ 已交付 `scripts/cert-scope-check.luau`（Lune，A 字面 + B 依赖闭包，自带 `--selftest`） |
| 11 | **追溯完整性**：每条 HLR/LLR 有测试；认证范围内无“无需求的可执行语句” | **门禁 11 已交付**：`scripts/cert-trace-check.luau`（CI）→ `docs/cert/TRACE.md`；四向机器化，方向④归 C4 |
| 12 | **结构覆盖**：认证范围达 100% statement，未覆盖行必须解释 | **门禁 12 已交付**：`scripts/coverage.luau`（自研插桩器 + 括号深度 + 编译裁判）→ `docs/cert/coverage/<MOD>.json`；未覆盖行须登记在 `docs/cert/coverage/UNCOVERED.md` |

> 门禁 10–12 是 `CERT.md` 的强制装置，但它们本身也分阶段交付 —— 在 C1–C4 完成前，门禁 10–12 **不存在**，认证线因此不得开工。这与“C1–C3 前冻结功能 Wave”是同一条规则的两面。

## 3. 决策登记（ADR 索引）

规则：任何新增/变更的**接口或边界**决策追加一行，状态为 `OPEN` 的阻塞其「阻塞」列对应的 Wave。

| # | 决策 | 选项 | 结论 | 状态 | 阻塞 |
| --- | --- | --- | --- | --- | --- |
| D1 | PlayerState 上游来源 | 用户指定仓库 / 放弃 | 用户指定（待定） | **OPEN** | D4.1 |
| D2 | PlayerState 是否仍必要 | 保留 / 全改走 TritiumSQL | **保留但降为纯复制组件**：TritiumSQL Phase 3（T3.x）落地后，持久化职责全部移交；且明确 **TritiumSQL 的存储层能力被 DataStore 封顶**（无 fsync / 缓冲池 / 共享内存），不对标 PG 的存储层 | DECIDED → **已被下表较新的 D2 行取代（CLOSED：取消）** | — |
| D3 | 引擎 API 形态 | 只 SQL 字符串 / 只类型化构建器 / 两者 | 两者，但 SQL 必须 Init 期编译（I11） | DECIDED | T0.x |
| D4 | headless 测试运行时 | Lune / 自研伪 shim | Lune；`game` 注入能力由 Step 7 探针决定，失败则 CI 只覆盖纯逻辑模块 | DECIDED | — |
| D5 | 发布形态 | Wally 包 / submodule | Wally：`vospek/deuterium` + `vospek/tritiumsql`，独立版本号 | DECIDED | D7.6 / T10 |
| D6 | Scribe 审计 | 审计后保留 / 换自研 | **实测结论：本仓库根本没有 Scribe**（无 `Libraries/`，全仓 grep 命中 0）→ 无可审计，无需五步流程。规格 §3 的「已内置」声明与仓库事实不符，已列入规格修订清单 | **CLOSED** | — |
| D7 | QuickZone 是否引入 | 引入 / 不引入 | 引入，推迟到世界层动工前 | DECIDED | D6.6 |
| D8 | 目录落地 | 现树 + Rojo 映射 / 迁到 `src/ReplicatedStorage/` | **已由用户改为 `src/ReplicatedStorage/`**（与规格 §4 一致）。代价：`scope.txt`（CC1）与全部工具路径已随之重写；收益：与规格一致、`Scribe`/`QuickZone` 有自然位置 | **SUPERSEDED** | — |
| D6 | Scribe 审计 | 审计后保留 / 换自研 | **原结论已作废**：当时「本仓库根本没有 Scribe」（全仓 grep 命中 0）—— 用户 2026-10-26 提供了上游源码（`Scribe-main`）并已融合为 `src/ReplicatedStorage/Scribe/`（46 文件/42,077 行，v2.6.1）。五步审计**已机器化关闭**（`docs/thirdparty/AUDIT.md`），结论：**保留**，经适配器使用。规格 §3 对 Scribe 的角色描述（「日志/观测」）是错的 → 见 THIRDPARTY §2 所有权划分 | **SUPERSEDED** | 已完成 |
| **D11** | Scribe 与 QuickZone 是否可用 | 先审计后使用 / 直接用 | **审计已完成**（2026-10-26）：① 锁版本 ② 后门面扫描 0 违规 ③ 按可达闭包收敛审计面 ④ Overrides 约定 ⑤ 许可与哈希留档 —— 全部有产物（`docs/thirdparty/` + `scripts/thirdparty-audit.luau`，进出 CI）。headless 实测：Scribe 三入口可装载、QuickZone 不可（桩缺 `:Connect`）。**剩余：适配器骨架（D0.6 ②）** | **AUDIT CLOSED** | `D0.6` |
| D2 | PlayerState 是否仍必要 | 保留 / 全改走 TritiumSQL | **取消**：Scribe 自带 `Internal/Store/ProfileStore` 且就是玩家数据载体 → PlayerState 的存在理由消失 | **CLOSED（取消）** | — |
| D2-bis | PlayerState 是否被 Scribe 顶替 | — | **是**：`Dr.Data.Store.PlayerData` / `Dr.State.Sync.Replicator` 由 Scribe 承担（经适配器）；我们只保留 Saga 协调与与 TritiumSQL 的桥 | **CLOSED** | — |
| D9 | 集成层事件机制 | 直接回调 / `Dr.Signal` 广播 | 待 `Dr.Signal`（D2.0）落地后定；默认先回调（依赖更少、更快），Signal 作为可选广播 | **OPEN** | Step 54/57 |
| **D12** | **TritiumSQL 的发布依赖** | ① 依赖 Deuterium FOUNDATION ② 自带错误类型 | 纵切证实 Tri→Dr.FOUNDATION 可行；倾向 ①（少一份错误实现） | **OPEN** | T3 之前 |
| **D13** | **SQL 错误的最终形状** | ① 扩 `DrError`（动认证范围）② Tri 侧 `SqlError` 包一层 | 倾向 ②（不动认证范围的 `CoreTypes`） | **OPEN** | T3 之前 |
| D10 | 合规目标定性 | 适航级全合规 / 航空级可靠性工程 | **可审查的航空级可靠性工程，保留 DO-178C 目标结构与升级路径**（理由与四项裁剪：`docs/cert/HAZARD.md` §1）。升级为全合规是**加法**而非重写 | **DECIDED** | — |

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
> **注（纵切后修正）**：`C3–C6`（认证线的需求基线 / 覆盖 / 工具鉴定 / 配置管理）横在 **Step 16.5 之后、Step 13+ 之前** —— 因为 `D0.2/D0.3` 的产物落在认证范围内，I18 要求先有 LLR。原图漏了这一段，两处文档不一致已在此处对齐。

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

| R16 | **把 440 模块/100k 行整体宣称合 DO-178C**（自欺） | 极高 | 发布说明或对外材料把整体标成 DAL C/D | `CERT.md` §0/§3.3 三分线切割；封顶 12k；§10 边界声明写进发布说明 | `CERT.md` |
| R17 | **需求先于代码被违反**（已发生：先写了 5k 行） | 极高 | 认证范围内出现无 LLR 的文件 | I18；C3 做 PDS 式反补需求；冻结范围外代码 | `CERT.md` §9.2 |
| R18 | **覆盖工具做不出来**（`debug.sethook` 在 Lune 不可用） | 高 | C4 的成功性探针失败 | C4 第一步先做探针；失败则 7.2 目标无法关闭，**DAL C 本身需重新评估**（已写入 `CERT.md` 末尾的未决项） | `CERT.md` §7.2 |
| R19 | **假独立性**（拿同一会话的复审当独立验证） | 高 | §7.5 的偏差未被记录 | 永久偏差登记 + 独立会话留证；**不声称**组织独立性 | `CERT.md` §7.5 |
| R20 | **工具鉴定被默认豁免**（“用工具不签定”） | 中 | 某工具有产出却被当作自动免鉴定 | `CERT.md` §4.4 逐条关闭 TQL 判定，无一件“默认” | `CERT.md` §4.4 |
| R21 | **插桩器自身出错污染覆盖结论**（高估→假绿；低估→无谓返工） | 高 | 插桩器统计的可执行行与 `debug.info` 的函数范围不一致 | 插桩器必须有自己的测试；两来源交叉校验；R18 已部分关闭（路线已通，剩这个） | `docs/headless.md` §7 |
| R22 | **第三方未审计即集成**（Scribe 38.7k + QuickZone 6.5k 行，无 LICENSE、无 hash） | 极高 | 有代码 require 到它们；或发布时被质证供应链 | `THIRDPARTY.md` §7 五步逐条关闭（顺序：**先剥离再审计**，否则白审一大半）；门禁 10 拦住认证核心的越界依赖 | `THIRDPARTY.md` §7 |
| R24 | **两边都造一遍**（Scribe 已含 Log/Metrics/Signal/Sched/Transport，我们也规划了同类） | 高 | 出现两套同名能力的实现 | **I21** + `THIRDPARTY.md` §2 所有权表；区分「框架级设施」与「库内部实现」；评审时按表核 | `THIRDPARTY.md` §2 |
| R25 | **仓库 90% 行数不是我们写的**（5.5k → 50k） | 中 | `git log`/`grep`/评审噪声变大；误把第三方向数当成进度 | 门禁范围已排除两棵树；`loc-budget` 按路径排除并**单独展示**其行数；100k 目标不含它们 | `THIRDPARTY.md` §5 |
| R26 | **两套形状断言对“类型名”的定义不一致**（`Contract.IsA` 用 `type` → 对实例得 `"userdata"`；`Interface.Conform` 用 `typeof` → 得 `"Part"`） | 中 | 对 Roblox 实例做 `Contract.IsA(x, "Part")` 会**误报失败** | **已修（pass 1）**：改为 `typeof` + 显式支持伪类型 `"Instance"`；**且确有真实调用方**（ModuleLoader/HotReload，之前误判为“零调用方”）—— 它们的加载路径原本必然抛错。已加回归断言 | **CLOSED** |
| R27 | **Luau 插值写成 `${expr}`**（正确写法是 `{expr}`；`$` 会当字面量输出） | 中 | 日志/报告被打脏，且很难一眼看出 | 全仓库 .luau 的 6 处已修（含产品代码 `TestContext.note`）；规则已写进 `AGENTS.md` §6。**`.sh`/`.yml` 的 `${VAR}` 是 shell 语法，不得批量替换** | `AGENTS.md` §6 |
| R28 | **桩保真度不足会让测试假失败/假通过** | 高 | 桩缺方法、语义不等价（如 `Destroy` 不触发 `Destroying`）→ 看起来像产品 bug | 本轮补了 6 处保真度缺口（typeof 包装 / Instance 迷你树 / Destroy 信号 / 名字校验 / Fire / Raycast）；新增桩能力必须用**真实调用点**验证 | `docs/headless.md` §8.2 |
| R29 | **新代码把引擎依赖放到加载期** → 静默失去 CI 覆盖 | 高 | 某模块从“可装载”变成“需桩”，而没人注意到 | `tests/run.luau` 的**不加桩装载数**就是哨兵：每批改动后它必须仍是 75/75（或上升） | `docs/headless.md` §8.1 |
| R23 | **迁移到 `src/` 后路径引用漂移**（工具、门禁、文档各自写路径） | 中 | 任一门禁找不到文件但仍然通过（如 p0 扫描目录不存在 → 计数为 0 → 假绿） | 扫描类工具必须**断言目录存在**而非静默跳过；本次已核对 p0 计数前后一致（26/47/0） | `scripts/p0-check.sh` |

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
| **v18** | **C4（Step 73）交付：statement 覆盖工具 + 门禁 12** —— 按 Step 73 的判据**先做成功性探针**（`scripts/probe-coverage.luau`，P1–P8）：`debug.sethook` 在 Lune 0.11.1 **不存在**、`@lune/luau` 只有 `compile`/`load`（无 parser、无 `getcoverage`）→ 原生覆盖路线不可用，机制定为**源码插桩**。工具分两个模块：`scripts/instrument.luau`（纯插桩器，可单测）+ `scripts/coverage.luau`（跑认证线用例 → 报告 + 门禁判定）。**认证范围 4 模块 58/58 可执行行 = 100.0%**，未覆盖 0 行；插桩器自检 **8 组**（含它自己抓到的真 bug 的回归）。探针还查出三条平台约束（`loadstring` 语法错会**抛**、`_G` 在 Lune 是**空表**、表构造器前缀会被当**数组元素**）；R18 关闭、R21 缓解（交叉校验 + 自检 + 行为级断言） |
| **v17** | **C3（Step 72）交付：需求基线 + 追溯生成器 + 门禁 11** —— 认证线现在有了**需求→代码→用例**的四向闭环：① `docs/cert/req/<MOD>.md` ×4（**10 HLR / 12 LLR**，对 4 个**既有**认证模块反向补需求）② 源码 12 处 `-- LLR-<MOD>-nnn` 注解 ③ `tests/cert/cases/<MOD>.luau` ×4（**17 用例 / 89 断言**，正常·边界·错误三类齐备）④ 认证线独立 runner `tests/cert/run.luau` → 生成 `docs/cert/verify/<MOD>.md` ⑤ 门禁 11 `scripts/cert-trace-check.luau`（生成 `TRACE.md`，自检 1 正控 + 7 负例）。**AC-C3 在真实仓库上证明**：去掉测试 → `UNTESTED_REQ`；加无注解代码 → `UNSOURCED_CODE`（`Interface.luau:40`），还原后重新变绿。CI 新增独立 `cert` job（两条线报告不合并）。**方向④（需求→覆盖）仍未自动化**，归 C4 |
| **v16** | **第三方融合（Scribe 2.6.1 / QuickZone 1.5.1）+ 审计五步机器化关闭**：上游源码融合进 `src/ReplicatedStorage/{Scribe,QuickZone}/`（46+13 文件 / 48,611 行，两者 MIT 且各带 LICENSE）；新增审计器兼 I20 门禁 `scripts/thirdparty-audit.luau`（自检 5 组、进 CI）+ 产物 `docs/thirdparty/{AUDIT.md,LOCK.txt,许可文本}`；**后门面 0 违规**、1 处动态 require 登记为接受、审计面按要求闭包收敛（Scribe 46/46、Server 入口 43、Client 入口 22）；实测 **Scribe 三入口可在 Lune 装载、QuickZone 不能**（桩缺 `:Connect`）；D6 原结论作废、D11 审计关闭；`default.project.json`/`rojo build`/全部门禁不受影响 |
| **v15** | **Phase 0.5 端到端纵切（Step 16.5）交付**：内存版全链（Port→页→索引→TriSQL 编译/执行→读回）**36/36 断言通过**，两个入口（`lune run tests/walkthrough.luau` 与 CI 套件），产物含 `.plan/SEAMS.md`。**它改动了两处规约**：T1 的页容量验收改为**按字节**（原来只有槽位）、新增「端口写失败必须回滚内存态」。另收口 Step 10–12（Step 10 的前提由「Studio 手工」改为 headless；Step 11 的 18 处判据已被 codemod 取代）。新增决策 **D12/D13**（TritiumSQL 的发布依赖 / SQL 错误形状），须在 T3 之前拍板 |
| **v14** | **变异测试补洞**（`code-review-and-quality` skill 的 Step 2 要求“用实验而非阅读回答测试是否有效”）：对本批 8 处修复逐个做反向变异 → **4 处未被任何测试抓住**（=缺失用例）。已补 3 处：`ProtocolBuffer` 条件冻结、`ShutdownManager` 逆序停、`ModuleLoader` 的 `.selftest` 后缀排除（新增套件，含 Kernel 三个 provider 的启停顺序断言）；**第 4 处（`MockBridge.Reset` 清 listeners）如实标注为“内存卫生修复，公开 API 无法观测”**，未编造测试。补洞后重跑变异：三处均**已被抓住**。另：把“不加引擎桩装载数”从打印改成**断言**（R29 的哨兵以前不会响），并用负例证明它会拦 |

| **v13** | **全量代码优化（Skills + MCP + SubAgents，三批提交）**：5 个只读子代理并行审计全部 79 个第一方文件 → **2 个 blocker + 13 个 major + 一批 minor 已修**（TestKit 永远无法注册用例 / Compressor 拒收自己的输出 / ShutdownManager 正序停与生产必抛 / FeatureFlags 非幂等 / ServerRegistry 降级承诺未兑现 …）；`code-simplification` skill 走流程；context7 MCP 核实 4 条承重语义（`typeof(nil)` / `type` vs `typeof` / `table.freeze` 非幂等 / `os.date` 字面量联合）。**结构性成果**：第一方 **75/75 模块可 headless 装载**（起点 15）、**10/10 引擎绑定 SelfTest 由 SKIP 变为执行且通过**、`tests/run.luau` **PASS 8 · FAIL 0 · SKIP 0**（59 用例）。新增 `scripts/rbx-stub.luau`；修掉 3 个由“可执行性”暴露的产品缺陷（`Configuration.Load` 冻结已冻结表 / `ProtocolBuffer` 同类 / `TestContext.note` 的 `$`）。新增风险 R27–R29 |
| **v12** | **代码优化（用 `code-simplification` skill + context7 MCP）**：① loader 升级为**虚拟实例树**（v1 只能解析同级兄弟 → 认证范围的 `Types/Contract/*` 用三级上跳，**此前无法被任何环境执行**）；② 给认证范围加**首批 headless 断言（22 条）**，CI 的 `test` 从 PASS 1 变 PASS 2；③ `Interface.Conform` 删除冗余 nil 分支（MCP 核实 `typeof(nil)=="nil"`），并修掉与代码不符的头注释（多字段实际不报错）；④ **删掉两个零调用方的死包装** `Types/Contract/{Invariant,Precondition}.luau`（认证范围 -2 文件，`scope.txt` 57→55）—— 认证线要求 100% statement 覆盖，留死代码等于白花验证预算；⑤ 发现并登记 **R26**（`type` vs `typeof` 的不一致缺陷，未修） |
| **v11** | **决定集成 Scribe 与 QuickZone**（新增 `THIRDPARTY.md`）：实测两库真实 API（**Scribe 不是日志库**，而是玩家数据/复制/经济/排行榜库，自带 ProfileStore）→ 定下**所有权划分表**，`Dr.Data`/`Dr.State` 大幅收缩（`D4.1`/`D4.2`/`D4.7` 取消，改为 5 个适配器）；D2/D2-bis **结案（PlayerState 取消）**；D11 决定集成但审计转为阻塞任务 `D0.6`；新增不变量 **I20/I21**；新增 `D0.6` 与风险 **R24/R25**；**两库不计入 100k 行与 440 模块**（适配器计入） |
| **v10** | **目录迁移到 `src/ReplicatedStorage/`（用户执行）+ 两个第三方依赖入库**：`scope.txt`（CC1）与全部工具/文档路径重写并逐门禁复验（build 135 ModuleScript · p0 26/47/0 与迁移前一致 · 门禁 10 自检 9/9 · headless PASS 1/SKIP 10 · analyze TypeError 0）。**新增两个阻塞决策**：D11（Scribe/QuickZone 未审计：无 LICENSE、无版本 hash、未剥离、无 Overrides）与 D2-bis（Scribe 实际是玩家数据/复制库，规格写成日志库 — 错了）。新增风险 R22（第三方供应链）与 R23（迁移后路径漂移，含“扫描目录不存在会静默假绿”） |
| **v9** | **Step 8 完成**：`.gitlab-ci.yml` 四阶段（本地逐条 exit 0）· `tests/run.luau` + `scripts/lune-loader.luau`（headless 测试入口，如实报告 SKIP）· 经 MCP 找到 `luau-lsp.pages.dev` CDN → **vendor** `types/globalTypes.None.d.luau`（指纹入 `MEMORY.md`）→ **首次真跑类型检查：TypeError 0**，并抓到 **1 个真运行时 bug**（`Debug.luau` 双映射导致副本的相对 `require` 指向 `ReplicatedStorage.Logger`）+ 门禁 3 首次全绿 · 新建设 `src/ReplicatedStorage/Debug.luau` 垫片与 `Configs/Deuterium/` 树 |
| **v8** | **Step 7 + Step 9 完成**：`docs/headless.md`（headless 能力基线）· `AGENTS.md` · `MEMORY.md`。**两条原假设被实测推翻**（`debug.sethook` 不存在 → C4 改**源码插桩**；`_G` 不是全局表 → env 必须显式拷标准库）；拓扑序 `setfenv` loader 跑通，**真 SelfTest 8/8**，并当场修掉 **3 个真 bug**（Logger 冒号调用漏 self）。Scribe 审计结论=**本仓库不存在**（D6 关闭），运行期外部依赖为零。新增风险 R21 |
| **v7** | **C2 完成**：7 份认证文档（PSAC/SDP/SVP/SCMP/SQAP/REQ-STD/TYPES）+ `docs/cert/` 索引。**目标关闭表按 Annex A 分表建立并带自洽校验**（明示的 8 表相加 = 53；A-5=9†、A-7=9† 则合计 = 71，与三源一致的 DAL A 总数吻合）。新增 `TYPES.md`（DO-178C §6.7/6.7.1 对动态语言的要求）→ 顺带暴露 `BIGINT` 的 2^53 降级未写明，已在 `TritiumSQL.md` 补上 |
| **v6** | **C1 完成 + 门禁 10 交付**：裁定合规目标（D10）；危害 H1–H7→DAL 固化并逐模块映射；**12k 预算重切**（原表自身超帽子 400 行 → 11,200 + 800 余量）；`ErrorHandler` 按 I16 净化（删 `Report`，零调用方）；`cert-scope-check` 以 Lune 重写并带自检 —— **发现它只查字面、漏依赖闭包** → 补 B 段，并修正 `script.Parent` 语义（N 个 Parent 只向上 N−1 层） |
| **v5** | **引入 DO-178C 适配（`CERT.md`）**：新增不变量 I16–I19·门禁 10–12·风险 R16–R20；范围砍为三条线（认证 ≤12k / 产品 / 工具）；C1–C6 插入所有功能 Wave 之前；COTS/平台/工具鉴定逐条登记；已写 5k 行按 PDS 式评估处理 |
| **v4** | **全面一致性优化**：不变量/门禁/决策/风险各自收口为唯一出处；Wave ID 统一；修正 LOC 加总错误（集成层核心 8,200→8,400、G4+G5 5,400→4,950）；补 `D2.0 Signal`；新增进度登记与验收 ID 规范；`SCALE.md` 附录 B 升级为功能追踪矩阵 |
