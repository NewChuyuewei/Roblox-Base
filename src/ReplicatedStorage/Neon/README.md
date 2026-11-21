# Neon — 集成式控制台打印系统

> Carbon 组件 · **L0 纯库（零依赖，不得触碰引擎）** · 状态：**已立项，施工中**（`P2.W1` · `P2.W2` 已落）
> 总图：`.plan/CARBON.md`；本页的层次、依赖、预算是 `scripts/carbon-manifest.luau` 的镜像，以清单为准。

| 项 | 内容 |
| --- | --- |
| 范围 | 统一打印入口 · 级别/频道/过滤 · 格式化 · 游戏内控制台 · 命令输入 |
| 可直接依赖 | 无 |
| 只经 `Integration/` 接线 | 无 |
| 核心行数预算 | 5,000 行（清单里 `core = 5000`；口径：只算核心，测试/集成/工具另算） |
| 可参考 | `src/ReplicatedStorage/Debug.luau`、`Deuterium/Diagnostics/Logging/` |
| 入口 | `require(ReplicatedStorage.Neon.Neon)`（总图 §3.1：入口是 `<root>/<组件名>.luau`） |

## 已落下的接缝（每个模块只有一个 owner）

| 模块 | 负责什么 | 行 |
| --- | --- | --- |
| `Level.luau` | 五个级别的名字、序、规范化。**只有这里有顺序表**：入口、过滤器、格式化共用它 | 119 |
| `Record.luau` | 记录结构 `{time, level, channel, message, fields}`、构造期校验、冻结，以及**可注入时钟** | 153 |
| `Publish.luau` | 唯一的发射路径：校验级别 → 构造记录 → 投递。`Neon.Log` 与 `Channel` 都走这里 | 52 |
| `Sink.luau` | 输出端契约 `{ name, Write }`、注册表、带错误隔离的广播、投递计数 | 173 |
| `RingSink.luau` | 内存环形缓冲：容量固定、写满覆盖最旧、`Records()` 由旧到新 | 140 |
| `Channel.luau` | 绑定频道与固定上下文的记录器（`.` 调用；`With` 派生不改父记录器） | 80 |
| `Neon.luau` | 门面：`Log` + 五个简写 + `Channel` + `AddSink/RemoveSink` + `SetClock` + `Stats/Reset` | 116 |
| `SelfTest.luau` | 19 例判据断言（headless，`tests/run.luau` 的 `Neon.Core` 套件执行） | 471 |

核心合计 **833** 行（不含自检），对应 `P2.W1`(0.7k) + `P2.W2`(0.6k) 的预算 1.3k。

## 三条已经钉住的设计决定

1. **记录是调用时刻的快照，且冻结**。输出端拿到同一个引用（省内存、可断言），代价是「先打印后改表」不会影响日志。
2. **未登记的级别当场抛错**，不降级成 `info`；`"INFO"` 这类大小写差异可以接受。被猜出来的级别会伪装成一条正常记录。
3. **级别过滤不属于输出端**（那是 `P2.W4` 的过滤器）。`Sink.Write` 只有 `name` 与 `Write` 两个字段：接缝每多一个必选方法，第三方输出端就多一处会漏实现的地方。

## 还没做的（按 Wave 排）

| Wave | 内容 | 状态 |
| --- | --- | --- |
| `P2.W3` | 格式化：单行文本、表的安全打印（深度上限/循环引用/键排序）、超长截断 | 未开始 |
| `P2.W4` | 过滤与限速：最低级别、每频道每秒条数、重复折叠（依赖已就位的注入时钟） | 未开始 |
| `P2.W5` | 命令系统：注册、参数解析、补全、权限钩子 | 未开始 |
| `P2.W6` | `Host/StdSink`：唯一碰引擎的地方（`game` 相关只在 `Host/`） | 未开始 |
| `P2.W7` | 游戏内控制台界面 | 未开始 |
| `P2.W8` | 迁移：`Deuterium` 的打印改走 `Neon`，删 `Debug.luau` 垫片，依赖基线 20 → 3 | 未开始 |

> `P2.W8` 的基线口径以命令为准，别信任何文档里抄走的数字：
'> `awk '$2=="OUTSIDE"' scripts/carbon-deps-baseline.txt | wc -l` —— 本次实测 **20** 条（其中 1 条是 `Configs`），
> 目标是降到 3 条以内。`.plan/COMPONENTS.md` 写的「17 处」是**要改的打印点**数，与基线条数是两件事。
