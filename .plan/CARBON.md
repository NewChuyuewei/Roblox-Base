# Carbon 总图

> **Carbon** 是这套综合基础设施的总名：它不是第 20 个组件，而是 19 个平级组件的合称。
> **状态：S0（工程骨架）已完成，2026-11-14**；进度见 §9。用户已拍板的五件事：① 组件清单（§2）② 旧约束全部沿用（§1）③ 全部代码合计 **300,000 行**（§5）④ Framework 与 SQL 从旧项目**拿过来改** ⑤ Scribe 与 QuickZone **只作参考**，其能力写进 Carbon 自己的组件（§1.4）。
> 分层、每组件行数、推进次序是提议，未经纵切验证。
>
> **与旧计划的关系**：`.plan/` 下其余九份文件（`README.md` · `SCALE.md` · `STEPS.md` · `CERT.md` · `Deuterium.md` · `TritiumSQL.md` · `INTEGRATION.md` · `SEAMS.md` · `THIRDPARTY.md`）写于 Carbon 之前，约束继续有效；
> **与本文件冲突时以本文件为准**（主要是：第三方库的定位、被拆成独立组件的 `Dr.*` 命名空间、行数目标）。`THIRDPARTY.md` 的适配器方案已作废，仅存档。
> `example/` 现在只放两个第三方库的原件及其审计文档，作参考用。

---

## 0. 结论先行

1. Carbon = **19 个平级组件**，每个独立目录、独立命名空间、独立版本、可单独发布。
2. 组件分 **4 层**，只许向下依赖；同层之间只经端口（接口表）互通。
3. 旧项目的不变量、门禁、硬规则、认证线**全部沿用**；随 Framework 与 SQL 一起带回的脚本、测试、认证证据继续有效（§1.3）。
4. 规模目标是 **30 万行**。按旧风险表 R10 的单人节奏（10 万行 14–22 个月）线性外推约 **3.5–5.5 年**（§8）。
5. Carbon **不再有运行期第三方依赖**：Scribe 与 QuickZone 留在 `example/` 作参考，需要的能力在 Carbon 组件里自己实现。

## 1. 沿用的约束

### 1.1 原样沿用（定义不变，出处仍在旧文件）

| 约束 | 出处 | 内容摘要 |
| --- | --- | --- |
| 不变量 **I1–I7** | `src/ReplicatedStorage/Deuterium/Deuterium.md` §0 | 静态胜于动态 · 服务器权威 · 隔离舱壁 · 外部调用兜底 · 面向数据 · 可观测 · 供应链安全 |
| 不变量 **I8–I19** | `.plan/README.md` §1 | 持久化不在框架内 · 一份 Codec · 引擎 API 单一出入口 · SQL 编译期化 · 请求次数是验收指标 · 薄入口 · 集成方向单一 · 锁顺序 · 认证核心隔离 · 边界防御 · 需求先于代码 · 确定性底座（I20/I21 见 §1.2） |
| 门禁 **1–12** | `.plan/README.md` §2 | 可运行 · 可测 · 可静态检查 · 可观测 · P0 规约 · 依赖门禁 · 预算门禁 · LOC 记分板 · 集成方向 · 认证范围 · 追溯完整性 · 结构覆盖 |
| 硬规则 **1–7** | `AGENTS.md` §2 | 不直接提交 `main` · commit 标题 ≤72 字符 · WIP=1 · 认证范围隔离 · 先 LLR 再写码 · 完成须给可复现命令 · 非 0 退出即失败 |
| **认证线** | `.plan/CERT.md` | DO-178C DAL C；认证范围 ≤12,000 行核心（硬上限）；三条线不得互借信用 |
| 质量分档 A/B/C | `.plan/SCALE.md` §3 | A 档核心路径不封顶，须有边界用例、故障注入、性能预算 |

### 1.2 沿用但需要改写措辞（待评审）

| 约束 | 原措辞 | 在 Carbon 里的含义 |
| --- | --- | --- |
| I9 一份 Codec | 唯一实现在 `Dr.Types.Transform.Codec` | 唯一实现在 `Tin` 组件 |
| I10 引擎 API 单一出入口 | Roblox API 只出现在 `Dr.Runtime` | 只出现在 Framework 的运行时端口；其余 18 个组件经端口拿 |
| I14 集成方向 | `Dr.*` 调 `Tri.*` 只许在 `Deuterium/Integration/` | 推广为：任意组件调同层组件只许在各自的 `Integration/` |
| I16 认证核心隔离 | 不得 require `Dr.Runtime` / `Dr.Net` 等 | 认证范围扩到 L0 库的子集后（P4 已定），按新范围重列禁止清单 |
| 门禁 8 LOC 记分板 | 合计 ≥100,000 | 合计 ≥**300,000**，各区域 ≥ 预算 70%，仍只在 release 分支阻断 |
| I20 第三方只经适配器 | `Deuterium/**` 除 `*/Adapter/*` 外不得 require Scribe/QuickZone | **收紧**：Carbon 任何组件都不得 require `example/` 下的任何东西（含 Scribe/QuickZone）；适配器方案取消 |
| I21 不重复造 | Scribe 已有的能力不在 `Dr.Data`/`Dr.State` 重实现 | **反转**：Scribe/QuickZone 的能力由 Carbon 自己实现（§1.4）；改为「同一能力在 Carbon 内只实现一份」 |
| 门禁 6 依赖门禁 | 运行期外部依赖仅 Scribe / PlayerState / QuickZone | 运行期外部依赖为**零** |

### 1.3 从旧项目带回来的东西，以及它们的效力

Framework 与 SQL「拿过来改」，所以旧项目里与它们绑定的东西一并回到了根目录（S0）：

| 带回的东西 | 位置 | 效力 |
| --- | --- | --- |
| `Deuterium/`（约 5.7k 行）· `TritiumSQL/`（约 0.9k 行）· `Configs/` · `Debug.luau` | `src/ReplicatedStorage/` | 代码未改动，是两个组件的起点 |
| 门禁脚本、测试、类型定义 | `scripts/` · `tests/` · `types/` | 原样可用；S0 逐条重跑通过（§9） |
| 认证证据（危害分析、需求、追溯表、覆盖率、验证记录） | `docs/cert/` | 认证范围内的 4 个模块**一字未改**，证据随之带回；重跑后 `TRACE.md` 与 `verify/*.md` 与原件逐字一致。**一旦改动这些模块，按 I18 先改 LLR** |
| CI | `.gitlab-ci.yml` · `.github/workflows/ci.yml` · `scripts/ci.sh` | 双平台，两份配置都只调 `scripts/ci.sh`。**未在真实 runner 上跑过** |
| 旧计划九份 | `.plan/` | 约束有效；与本文件冲突时以本文件为准 |

没有带回、留在 `example/` 的：Scribe 与 QuickZone 原件、它们的审计文档（`example/docs/thirdparty/`）与审计脚本。

旧进度（`.plan/STEPS.md` 的完成日志、`.plan/README.md` §5）描述的是 Carbon 之前的状态，保留作历史；Carbon 的进度只记在本文件 §9。

### 1.4 Scribe 与 QuickZone：参考并写入

两个库留在 `example/`，不随 Carbon 发布、不被 require。它们的能力按下表落到 Carbon 组件里（提议，待评审）：

| 来源能力 | 参考位置（`example/src/ReplicatedStorage/`） | 落到的 Carbon 组件 |
| --- | --- | --- |
| 玩家数据载入/保存、会话锁 | `Scribe/Internal/Store/ProfileStore` · `Server/Persistence` | `Deuterium`（会话态）+ `TritiumSQL`（持久化，I8） |
| 数据复制到客户端 | `Scribe/Internal/{Wire,Transport,Node}` · `Client/` | `Cesium` |
| 模板、默认值、数据类型、迁移 | `Scribe/Internal/{Template,Defaults,Datatypes,Conform}` | `Tin` |
| 排行榜 | `Scribe/Server/Leaderboards` | `Mercury`（有序集合） |
| 经济、交易、内购 | `Scribe/Server/{Exchanges,Monetization}` · `Internal/Exchange*` | `Deuterium`（事务编排）+ `TritiumSQL` |
| 日志、指标、健康检查 | `Scribe/Internal/{Log,Metrics,Health}` | `Neon` · `Phosphorus` |
| 大数、随机数 | `Scribe/Internal/{Big,Rng}` | `Platinum` |
| 区域检测、BVH、几何 | `QuickZone/` 全部 | `Platinum`（空间索引与几何）+ `Titanium`（重叠查询） |

> **许可**：Scribe 与 QuickZone 是 MIT，Scribe 内含的 ProfileStore 分支是 Apache-2.0（文本在 `example/docs/thirdparty/`）。
> 「参考后重写」若保留了原代码的实质部分，仍需按许可保留版权声明；ProfileStore 派生部分还需保留 NOTICE 并标注改动。每个吸收点立项时登记来源。

## 2. 组件清单

**命名规则（用户 2026-11-14）**：整体叫 **Carbon**；内部每个组件用一个元素周期表的元素命名，元素名同时是目录名和命名空间。
「可参考」列指可以借鉴的既有实现：仓库里的旧代码，或 `example/` 里的第三方库。

| # | 组件 | 元素名 | 层 | 一句话范围 | 可参考 |
| --- | --- | --- | --- | --- | --- |
| 1 | Framework | `Deuterium` | L1 | 微内核 · 生命周期 · DI · 传输层 · 运行时端口 · 弹性 | **搬回改**：旧 `Deuterium/`（约 5.7k 行）；Scribe 的玩家数据部分 |
| 2 | SQL | `TritiumSQL` | L2 | 页 · B+ 树 · 事务 · WAL · 查询 | **搬回改**：旧 `TritiumSQL/Tri/Spike/` 与 `TritiumSQL.md` |
| 3 | 物理引擎 | `Titanium` | L2 | 确定性刚体：粗/窄检测 · 约束求解 · 角色控制器 · 弹道 · CCD | — |
| 4 | KV/缓存引擎 | `Mercury` | L2 | MemoryStore 之上：TTL · 有序集合 · 队列 · 分布式锁 · 本地二级缓存 · 排行榜 | Scribe 的 `Leaderboards` |
| 5 | 序列化/Schema | `Tin` | L0 | 模式定义 · 二进制编解码 · 版本迁移 · 校验 | 旧 `Net/Processing/{Serializer,ProtocolBuffer}` |
| 6 | 压缩与加密库 | `Krypton` | L0 | LZ4/Deflate · SHA-2 · HMAC · 签名 · CRC | 旧 `Security/Crypto/{Sha256,Hmac}` · `Compressor` |
| 7 | 数学库 | `Platinum` | L0 | 定点数 · 线性代数 · 几何求交 · 空间索引 · 确定性随机数 · 噪声 | QuickZone 的 `LinearBVH`/`Geometry` · Scribe 的 `Big`/`Rng` |
| 8 | ECS 引擎 | `Helium` | L1 | 实体存储 · 查询 · 系统调度 · CommandBuffer · 快照 | 旧规格的 `Dr.ECS` 设计 |
| 9 | AI 引擎 | `Silicon` | L2 | 寻路 · 行为树 · 效用 AI · 群体转向 · 感知 | — |
| 10 | 动画引擎 | `Gallium` | L2 | 补间与曲线 · 动画状态图 · IK · 程序化动画 | — |
| 11 | 体素/地形引擎 | `Bismuth` | L2 | 分块存储 · 网格化 · 程序生成 · 流式加载 · 编辑与持久化 | — |
| 12 | 并行作业系统 | `Uranium` | L1 | Actor 池 · 任务图 · 帧预算 · 并行 for · 数据分片 | — |
| 13 | 同步引擎 | `Cesium` | L3 | 快照/增量 · 兴趣管理 · 客户端预测 · 回滚 · 延迟补偿 | 旧 `Net/`（仅传输层） |
| 14 | 集群层 | `Copper` | L3 | 服务发现 · 成员关系 · 选主 · 匹配 · 跨服 RPC | 旧 `Runtime/Platform/{ServerRegistry,ServerBrowser}` |
| 15 | 消息队列 | `Sodium` | L3 | 跨服发布订阅 · 持久队列 · 延迟任务 · 至少一次投递 · 死信 | — |
| 16 | 脚本虚拟机 | `Vanadium` | L1 | 沙箱解释器：词法 · 语法 · 字节码 · 指令预算 · 宿主绑定 | — |
| 17 | 可观测平台 | `Phosphorus` | L1 | 指标 · 追踪 · 日志聚合 · 剖析 · 告警 · 导出 | 旧 `Diagnostics/Logging/` |
| 18 | 反作弊引擎 | `Boron` | L3 | 移动/行为校验 · 服务端重放 · 统计异常检测 · 取证 | — |
| 19 | 集成式控制台打印系统 | `Neon` | L0 | 统一打印入口 · 级别/频道/过滤 · 格式化 · 游戏内控制台 · 命令输入 | 旧 `Debug.luau` · `StructuredLog` |

### 2.1 元素名的由来

| 元素 | 组件 | 为什么是它 |
| --- | --- | --- |
| `Platinum` | 数学库 | 铂铱合金曾是米与千克的国际原器：度量与数的基准 |
| `Tin` | 序列化/Schema | 锡罐：把数据装罐、封存、原样取出 |
| `Krypton` | 压缩与加密库 | 名字来自希腊语 kryptos「隐藏」，与 crypto 同源 |
| `Neon` | 集成式控制台打印系统 | 霓虹灯：把信息显示出来 |
| `Vanadium` | 脚本虚拟机 | 首字母 V 对应 VM；钒钢是工具钢，宿主里的工具 |
| `Helium` | ECS 引擎 | 惰性气体不成键：组合而不是继承；也最轻 |
| `Phosphorus` | 可观测平台 | 名字意为「带来光者」：让系统内部可见 |
| `Uranium` | 并行作业系统 | 裂变：把一份工作拆成多份并发进行 |
| `Titanium` | 物理引擎 | 高强度刚性金属：刚体 |
| `Silicon` | AI 引擎 | 硅基智能 |
| `Bismuth` | 体素/地形引擎 | 铋晶体天然长成阶梯状方块，形似体素 |
| `Gallium` | 动画引擎 | 握在手里就会熔化流动的金属：运动与形变 |
| `Mercury` | KV/缓存引擎 | 水银 quicksilver：快 |
| `Cesium` | 同步引擎 | 铯原子钟：时间同步的基准 |
| `Copper` | 集群层 | 铜线：把机器连在一起 |
| `Boron` | 反作弊引擎 | 控制棒与装甲材料：吸收失控、抵御攻击 |
| `Sodium` | 消息队列 | 钠离子在神经元之间传递信号 |

> ⚠ **`Deuterium` 与 `TritiumSQL` 还没有改名**：氘和氚是氢的同位素，不是元素，严格说不符合上面的规则。
> 它们没有随这次一起改，是因为改名会动到认证范围内 4 个模块的路径，进而要重新生成 `docs/cert/` 下的范围表、追溯表、覆盖率与验证记录，
> 而这些证据只能用真工具链生成（§9）。是否改、改成什么，是待决事项 **P1**。

**不在清单内（用户未选）**：UI 框架、特效/粒子、音频、独立的测试套件。测试运行器作为工具线的一部分。

## 3. 分层与依赖

```
L3 分布式与对抗   Cesium 同步 · Copper 集群 · Sodium 消息队列 · Boron 反作弊
                      │
L2 领域引擎       TritiumSQL · Mercury KV · Titanium 物理 · Bismuth 体素 · Silicon AI · Gallium 动画
                      │
L1 运行时底座     Deuterium · Helium ECS · Uranium 作业 · Vanadium 虚拟机 · Phosphorus 可观测
                      │
L0 纯库（零依赖） Platinum 数学 · Tin 序列化 · Krypton 压缩与加密 · Neon 控制台
```

| 规则 | 内容 | 强制方式 |
| --- | --- | --- |
| **单向向下** | 组件只能 require 更低层的组件，且必须在清单里声明 | `scripts/carbon-deps-check.luau`（已交付，自带 `--selftest`）；清单是 `scripts/carbon-manifest.luau` |
| **同层走端口** | 同层互通只经接口表注入；接线代码放各组件的 `Integration/` | 同上（I14 的推广） |
| **L0 不碰引擎** | L0 四个库不得出现 `game`/`workspace`/`task`，可在 Lune 里完整运行 | 同上 |
| **`Neon` 在最底层** | 所有组件都要打印，所以它零依赖；游戏内界面需要引擎，放在哪里是 `Neon` 立项时要定的事（门禁目前对 L0 不留豁免） | 同上 |
| **不得依赖第三方** | 任何 require 里不得出现 `Scribe` / `QuickZone`；组件根目录下不得出现清单外的条目 | 同上 |

### 3.1 各组件的直接依赖

| 组件 | 依赖 |
| --- | --- |
| `Platinum` · `Krypton` · `Neon` | 无 |
| `Tin` | 无；经端口可选用 `Krypton` 的 CRC（同层） |
| `Deuterium` | `Neon` · `Tin` · `Krypton` |
| `Uranium` · `Helium` · `Vanadium` · `Phosphorus` | `Neon` · `Tin` |
| `TritiumSQL` | `Deuterium` · `Tin` · `Krypton` |
| `Mercury` | `Deuterium`（运行时端口）· `Tin` |
| `Titanium` | `Platinum` · `Uranium`；经端口接 `Helium` |
| `Bismuth` | `Platinum` · `Uranium` · `Tin` · `Krypton`（压缩） |
| `Silicon` | `Platinum` · `Uranium`；经端口查询 `Titanium` / `Bismuth` |
| `Gallium` | `Platinum`；经端口接 `Helium` |
| `Cesium` | `Deuterium`（传输）· `Tin` · `Helium` · `Titanium` |
| `Copper` | `Deuterium` · `Mercury` · `Tin` |
| `Sodium` | `Mercury` · `Tin`；经端口接 `Copper`（同层） |
| `Boron` | `Titanium` · `Phosphorus`；经端口接 `Cesium`（同层） |

## 4. 平台约束（动工前逐条实测）

以下来自对 Roblox 平台的一般了解，**未联网核实**；各组件立项时须对官方文档核对并留档（做法同 `SCALE.md` §1.3）。

| 约束 | 影响的组件 | 后果 |
| --- | --- | --- |
| 浮点运算跨客户端平台不保证逐位一致 | `Platinum` · `Titanium` · `Cesium` | 要确定性就得用定点数，或只在服务端模拟（决策 **P3**） |
| Parallel Luau 以 Actor 为单位，跨 Actor 只能传消息或用共享表，并行阶段可调用的引擎 API 受限 | `Uranium` · `Titanium` · `Bismuth` · `Silicon` | 作业数据必须可序列化或放共享表；任务粒度过小会被消息开销吃掉 |
| MemoryStore 有条目大小、过期时间和按玩家数缩放的请求配额 | `Mercury` · `Copper` · `Sodium` | 与 I12 一致：请求次数是验收指标 |
| MessagingService 消息体很小且只尽力投递 | `Copper` · `Sodium` | 「至少一次」只能靠 `Mercury` 的持久队列加确认实现 |
| 客户端不可用 `loadstring`，且平台对动态执行代码有政策限制 | `Vanadium` | 先核对平台条款，确认自研解释器的允许范围（决策 **P5**） |
| Lune 无 `debug.sethook`、无原生覆盖（`MEMORY.md` §2） | 全部 | 覆盖率继续靠源码插桩 |

## 5. 规模预算：300,000 行

**口径（沿用 `SCALE.md` §2）**：核心 + 测试 + 示例/工具；不含文档；**不含 `example/`**（因此不含 Scribe/QuickZone 原件）。
搬回的 Framework 与 SQL 旧代码计入。单位：千行。

下表的机器可读镜像是 `scripts/carbon-manifest.luau`，`scripts/loc-budget.luau`（门禁 8）据此出记分板；改预算时两处一起改，记分板的自检会核对各行之和等于 300,000。

### 5.1 这个数怎么来的

不是从总数往下分，而是**每个组件按「做到可用」估核心行数，再加测试与工具**：

| 依据 | 性质 |
| --- | --- |
| 旧计划给 `Deuterium` 26k 核心、`TritiumSQL` 22k 核心 + 约 14k 集成层 | 仓库内已有的估算（`.plan/SCALE.md` §2） |
| Scribe 原件 42k 行、QuickZone 6.5k 行 | 仓库内实测 |
| 其余 17 个组件的行数 | **我按同类开源库的体量做的判断，未验证**；立项纵切后校准 |
| 测试占全体约 31%、工具约 4% | 沿用旧预算的比例 |

### 5.2 分配

| 层 | 组件（核心行数） | 核心 | 测试 | 小计 |
| --- | --- | --- | --- | --- |
| L0 | `Platinum` 8 · `Tin` 6 · `Krypton` 5 · `Neon` 3 | 22 | 10 | 32 |
| L1 | `Deuterium` 28 · `Vanadium` 11 · `Helium` 6 · `Phosphorus` 6 · `Uranium` 4 | 55 | 25 | 80 |
| L2 | `TritiumSQL` 26 · `Titanium` 20 · `Silicon` 11 · `Bismuth` 9 · `Gallium` 7 · `Mercury` 6 | 79 | 36 | 115 |
| L3 | `Cesium` 13 · `Copper` 8 · `Boron` 5 · `Sodium` 4 | 30 | 14 | 44 |
| — | 跨组件集成层（各组件的 `Integration/`） | 9 | — | 9 |
| — | 端到端 / 场景 / 故障注入矩阵 | — | 8 | 8 |
| — | 示例 · 基准 · 门禁脚本 · CLI/Studio 工具 | — | — | 12 |
| | **合计** | **195** | **93** | **300** |

### 5.3 为什么不是 20 万或 50 万

| 总量 | 后果 |
| --- | --- |
| 20 万 | `Deuterium` 与 `TritiumSQL` 按旧计划的量就占去约三分之一，其余 17 个组件平均不到 4k 行核心，物理、虚拟机、同步这类组件做不到可用 |
| **30 万** | 19 个组件都能做到「核心功能完整、有测试」，但没有余量做第二套实现或大量可选特性 |
| 50 万 | 比自下而上的估算多出约 20 万行，没有对应的功能点可挂，直接触发旧风险 R15（凑行数） |

### 5.4 分阶段的里程碑线

30 万是终点，不必一次承诺。按 §6 的次序累计（含测试与工具的近似值）：

| 做到 | 累计 | 得到什么 |
| --- | --- | --- |
| S0–S2（骨架 + L0） | 约 4.5 万 | 四个可独立发布的纯库 |
| S3（+ L1，不含 `Vanadium`） | 约 11 万 | 可用的框架与 ECS |
| S4（+ `TritiumSQL` · `Mercury` · `Titanium`） | 约 19 万 | 数据与物理齐备 |
| S5（+ L3 的同步、集群、消息队列） | 约 23 万 | 多服与联机齐备 |
| S6（其余） | 30 万 | 全部 19 个组件 |

- Scribe 原件 4.2 万行，`Deuterium` 的 28k 里只留了约 5k 给吸收它的玩家数据能力：§1.4 的吸收只能是**子集**（决策 **P8**）。
- 认证线的 **12k 行硬上限不变**，占全体 4%。其余属于产品线，不主张任何 DAL。
- 旧规则保留：这是**下限不是配额**，记分板只防缩水、不奖励超额；新增模块必须挂到某个功能点上。

## 6. 推进次序（提议）

WIP=1 沿用：同一时间只推进一个 Step，未达判据不开下一个。

| 阶段 | 内容 | 判据（可演示产物） |
| --- | --- | --- |
| ~~S0~~ ✅ | 工程骨架：19 个组件目录、Rojo 工程、组件清单、依赖方向门禁、LOC 记分板、CI 更新；旧 `Deuterium/` 与 `TritiumSQL/` 搬回并重跑全部旧门禁 | 已达成，见 §9 |
| **S1** | 认证线前置：把危害分析与范围表扩到新组件（P4 已定可以扩）；双平台 CI 在真工具链上把 §9 的命令跑通 | 两个平台上 `scripts/ci.sh` 五个阶段全部 exit 0；范围表更新且门禁 10 自检通过 |
| **S2** | L0 四个库，逐个做：`Neon` → `Platinum` → `Tin` → `Krypton` | 各自在 Lune 里独立跑通；进认证范围的部分先有 LLR |
| **S3** | L1：`Deuterium`（在搬回的代码上改：换用 L0 的 `Neon`/`Tin`/`Krypton`，吸收 Scribe 的玩家数据能力）→ `Helium` → `Uranium` → `Phosphorus`（`Vanadium` 可后置） | 5000 实体更新基准；并行 for 的加速比 |
| **S4** | L2 第一批：`TritiumSQL`（从 Spike 起步，沿旧 `TritiumSQL.md` 的 Wave）→ `Mercury` → `Titanium` | 确定性回放：同输入两次模拟逐位一致 |
| **S5** | L3：`Cesium` → `Copper` → `Sodium` | 两个服务端加一个客户端的预测与回滚演示 |
| **S6** | 其余：`Bismuth` · `Silicon` · `Gallium` · `Boron` · `Vanadium` | 各自的纵切演示 |

每个组件立项走同一套动作：一页范围说明 → 一次纵切（学旧 Step 16.5）→ 接缝清单 → 再排 Wave。

## 7. 待决事项

| # | 决策 | 选项 | 倾向 | 阻塞 |
| --- | --- | --- | --- | --- |
| **P1** | `Deuterium` 与 `TritiumSQL` 是否改成元素名 | 保留（氢的同位素，作为历史例外）/ 改名（如 Framework → `Hydrogen`，SQL 另选一个元素） | 其余 17 个组件**已定**为元素名（§2.1）。这两个未定：改名要重做认证证据的路径，需在真工具链上进行 | 改 `Deuterium`/`TritiumSQL` 代码之前 |
| ~~P2~~ | Framework 与 SQL 的起点 | 完全重写 / 从 `example/` 搬回再改 | **已定：搬回再改** | — |
| **P3** | `Titanium` 的确定性级别 | 跨端逐位一致（定点数）/ 仅服务端权威（浮点） | 未定；决定 `Platinum` 的一半工作量 | S2 |
| ~~P4~~ | 新的认证范围 | — | **已定：可以扩**。`Platinum`·`Tin`·`Krypton` 的核心子集可进认证范围；具体文件在各库立项时随 LLR 一起加入 `docs/cert/scope.txt`（I18）。12k 行硬上限不变 | — |
| **P5** | `Vanadium` 的语言与用途 | Luau 子集 / 自定义 DSL / 仅表达式求值 | 未定；需先核对平台条款 | S6 |
| ~~P10~~ | CI 平台 | — | **已定：双平台**。`.gitlab-ci.yml` 与 `.github/workflows/ci.yml` 都只调 `scripts/ci.sh`，命令清单只有一处 | — |
| **P7** | 发布形态 | 每组件一个 Wally 包 / 一个总包 | 沿用旧 D5：每组件独立包 | 发布前 |
| **P8** | 吸收 Scribe / QuickZone 的哪些能力 | §1.4 全表 / 只取玩家数据 + 区域检测 / 其他子集 | 未定；方向已定（只作参考、写入 Carbon），范围受 §5 预算限制 | S2 的 `Platinum`、S3 |
| ~~P9~~ | 30 万行这个数及其口径 | — | **已定：30 万**，口径同 §5 | — |

（`P6` 已关闭：用户确认旧约束全部沿用，WIP=1 与认证线前置不放宽。）

## 8. 风险

| 风险 | 等级 | 触发条件 | 对策 |
| --- | --- | --- | --- |
| **工期**：30 万行按旧 R10 的单人节奏约 3.5–5.5 年 | 极高 | 连续两个阶段无可演示产物 | 每阶段必须可演示并打 tag；定期复核目标是否仍成立 |
| **铺得太薄**：`Sodium`、`Uranium`、`Neon` 等只有 3–4k 行，容易只剩外壳 | 高 | 某组件立项时功能点列不满预算，或列出的功能点远超预算 | 每组件先列功能点再分行数；做不深的组件明确标为「最小可用」或后置 |
| **广度压倒深度**：19 个组件都开了头、没有一个可用（旧 R4） | 极高 | 同时在推进的组件超过 1 个 | WIP=1；纵切优先 |
| **认证线被稀释**：12k 认证核心淹没在 30 万行里，对外被误读为整体合规（旧 R16） | 高 | 发布材料把整体标成 DAL C | 三条线切割写进每份发布说明 |
| `Titanium` 确定性做不到，拖垮 `Cesium` 与 `Boron` | 高 | S4 的逐位一致回放不过 | P3 先决；失败则降级为服务端权威 |
| 平台配额让 `Mercury`/`Copper`/`Sodium` 达不到设想的语义 | 高 | 请求次数断言不过 | 立项时先做配额实测，再定语义 |
| **吸收第三方时的许可遗漏**：参考重写保留了原代码实质部分却没带声明 | 中 | 吸收点没有来源登记 | 每个吸收点立项时登记来源与许可（§1.4） |
| 规模估计偏差大 | 中 | 首个纵切的实际行数偏离 §5 一倍以上 | 每组件纵切后回写预算 |

## 9. 进度

| 阶段 | 状态 | 证据 |
| --- | --- | --- |
| S0 工程骨架 | ✅ 2026-11-14 | 见下 |
| S1 认证线前置 | ◐ 进行中 | 决策已定（范围可扩、双平台 CI、元素命名）；剩余：在真工具链上跑通 CI、扩范围表 |

### S0 完成记录

**做了什么**：旧 Framework/SQL、脚本、测试、认证证据、旧计划搬回根目录；新建 17 个组件目录（各一页 `README.md`）；`default.project.json` 改名 `Carbon` 并映射全部 19 个组件；新增 `scripts/carbon-manifest.luau`、`scripts/carbon-deps-check.luau`（+ 基线 `scripts/carbon-deps-baseline.txt`）、`scripts/loc-budget.luau`；CI 更新。

**怎么验证的（重要的限制）**：本次工作环境装不上 `rokit.toml` 固定的工具链（发布包下载被网络策略拦截）。替代做法是：
用官方 Luau 0.747 源码编出的解释器加一个很薄的 `@lune/fs`·`process`·`serde`·`task` 模拟层来跑 `lune run …`，用 npm 上的 StyLua 2.6.0（wasm）做格式检查。
先在搬动之前的旧项目上跑了一遍，结果与 `.plan/STEPS.md` 完成日志里登记的数字一致，再用于下表。**这不是真 Lune**，下表是指示性结果；以真工具链在 CI 上的结果为准。

| 命令 | 结果 |
| --- | --- |
| `stylua --check src scripts` | exit 0（91 个文件，0 个需格式化） |
| `bash scripts/p0-check.sh` | exit 0（`table.insert(` 26 / 基线 26） |
| `lune run scripts/cert-scope-check.luau` · `--selftest` | exit 0 · 门禁 10 OK，违规 0 · 自检 9 例 |
| `lune run scripts/carbon-deps-check.luau` · `--selftest` | exit 0 · 新增违规 0，登记在册的既有违规 20 · 自检 25 例 |
| `lune run scripts/loc-budget.luau` · `--selftest` | exit 0 · 合计 12,208 / 300,000（4.1%）· 自检 27 例 |
| `lune run scripts/cert-trace-check.luau` · `--selftest` | exit 0 · HLR 10 / LLR 12 / 违规 0 · 自检 8 例；生成的 `TRACE.md` 与原件无差异 |
| `lune run scripts/coverage.luau` · `--selftest` | exit 0 · 58/58 = 100.0% · 自检 8 组 |
| `lune run tests/cert/run.luau` | exit 0 · 用例 17 / 失败 0 / 断言 89；生成的 `verify/*.md` 与原件无差异 |
| `lune run tests/run.luau` | exit 0 · PASS 10 · FAIL 0 · SKIP 0 |
| `lune run tests/walkthrough.luau` | exit 0 · 36/36 |

**门禁会失败的证明**（判据「每道新门禁在一个故意的违规上失败，还原后通过」）：临时加入三处违规 ——
L0 的 `Platinum` require `Deuterium` 并调用 `game:GetService`；`Deuterium` require `Scribe`；组件根目录下多出 `Scribe/` ——
依赖方向门禁 exit 1，报出 `UPWARD` 1、`ENGINE_IN_L0` 2、`THIRDPARTY` 1、`OUTSIDE` 1、`STRAY` 1；删除后 exit 0。
LOC 记分板加 `--release` 时 exit 1（27 项未达标），符合预期。

**门禁在写的过程中抓到的真问题**：本文件 §3.1 最初把 `Boron → Cesium`（反作弊 → 同步）和 `Sodium → Copper`（消息队列 → 集群） 写成直接依赖，而它们同在 L3，违反「同层走端口」。清单自洽性检查把这两条报了出来，已改成端口依赖。

**没有验证的**：

| 项 | 原因 |
| --- | --- |
| `rojo build` / `rojo sourcemap` | 没有 rojo。新映射了 17 个只含 `README.md` 的目录，预期生成空 Folder，但**未实测** |
| `luau-lsp analyze` | 没有 luau-lsp。新增的三个脚本不在分析范围内（`scripts/` 历来不分析） |
| 两份 CI 配置 | 没有 runner，也还没有推送。两份 YAML 只做过语法解析；`scripts/ci.sh` 的 `lint` / `test` / `cert` 三个阶段在替代环境下跑过（见下），`types` / `build` 因缺工具没跑 |
| 覆盖率 JSON 的重新生成 | 模拟层的 JSON 键序与 Lune 不同，重跑后已还原为原件，未提交模拟层的产物 |

**遗留的 20 条既有违规**（登记在 `scripts/carbon-deps-baseline.txt`，只许减少）：`Deuterium` 经遗留垫片 `Debug.luau` 打印 17 处、读取 `Configs` 2 处、1 处无法静态追溯的 require。前 17 处在 `Neon` 落地后清零。

### S1 进行中（2026-11-14）

**做了什么**：17 个新组件改为元素名（目录、清单、Rojo 映射、各自的 `README.md`）；新增 `scripts/ci.sh` 作为两个 CI 平台共用的唯一命令清单；新增 `.github/workflows/ci.yml`；`.gitlab-ci.yml` 改为只调 `scripts/ci.sh`；记分板输出加了一列功能代号（`ROLE`），方便对照元素名。

| 命令（替代环境，限制同上） | 结果 |
| --- | --- |
| `bash scripts/ci.sh lint` | exit 0 · 12 步全过 |
| `bash scripts/ci.sh test` | exit 0 · 2 步（headless 测试 + 纵切演练） |
| `bash scripts/ci.sh cert` | exit 0 |
| `CARBON_RELEASE=1 bash scripts/ci.sh lint` | exit 1 · 在第 5 步（LOC 记分板 `--release`）停下，符合预期 |
| `bash scripts/ci.sh nope` | exit 2 · 打印用法 |
| `bash scripts/ci.sh types` | exit 127 · 没有 rojo，**未验证** |

**S1 还剩**：把分支推上去，让两个平台各跑一次 `scripts/ci.sh` 的五个阶段；按 P4 把危害分析与范围表扩到 L0 的库（随各库立项进行）。
