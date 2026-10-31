# SEAMS.md — Phase 0.5 端到端纵切的接缝清单

> 产出方：`Step 16.5`（Phase 0.5 纵切）。代码在 `src/ReplicatedStorage/TritiumSQL/Tri/Spike/`
> （**DAL E、非认证范围、验收后可删**），入口有两个：`lune run tests/walkthrough.luau`
> 与 `tests/run.luau` 的同名套件。结果：**36/36 断言通过**（全量套件 PASS 10 · FAIL 0 · SKIP 0）。
>
> 本文件的目的**不是**记录「纵切成功了」，而是记录**它把哪些设想证伪、哪些接口必须先正式化**。
> 这三类结论直接改后面的 Wave（T0–T5）。

---

## 1. 被证实成立的接缝（可以按现状往下走）

| 接缝 | 证据 |
| --- | --- |
| **Port（`INTEGRATION.md` §2.1）形状够用** | spike 按该形状实现内存版，`Get/Set/Update/Remove/Stats/SetLimit` 全程够用；三态错误（`queued` / `throttled` / `failed:<code>`）的实现位置清楚 |
| **请求次数可计量（I12）** | 一次 INSERT 恰好产生 **2** 次端口请求（页写 + 索引写），断言 `== 2` 通过 |
| **I11 编译期化成立且可断言** | `Compile` 一次、`Run` 三次，`parseCount` 不变（断言通过） |
| **跨项目依赖方向可行** | `Tri/Spike/TriSQL.luau` 用相对路径 require 到 `Deuterium/Core/Foundation/ErrorHandler`，在 **Rojo 与 headless 两处都解析成功** |
| **错误语义可复用** | TriSQL 直接返回 `DrError`（`code` 即 SQLSTATE），`ErrorHandler.IsDrError` 断言通过 |
| **索引点查不退化成全扫** | 断言 `indexLookups ≥ 1` 且 `fullScans == 0`（含缺失主键的情形） |
| **键长 50 是可达的** | 实际键 `tri:main:t:p0:pg:0001`（21 字符），断言全部键 ≤ 50 通过 |

## 2. 需要**先正式化**的接口（否则 T1–T5 会各写一份）

| # | 缺口 | 纵切暴露的事实 | 建议 |
| --- | --- | --- | --- |
| S1 | **Codec 不存在（I9 悬空）** | `Dr.Types.Transform.Codec` 属 `D0.3`，**现在没有**。spike 只能内联一个制表符格式；而 `Net/Processing/Serializer` 另有一套长度前缀格式 | `D0.3` 交付时必须**同时**把 Net 的 Serializer 与 Tri 的页/行编码收敛到同一份 Codec。否则会出现**第三种格式** |
| S2 | **SQL 错误对象比 `DrError` 多两个字段** | SQL 客户端需要 `code + message + position + hint`；`DrError` 只有 `code/message/source`，`Render` 是框架风格 | 要么扩 `DrError`（动认证范围的 `CoreTypes`），要么在 Tri 侧定义 `SqlError = DrError & { position, hint }`。**倾向后者**（不动认证范围） |
| S3 | **`Port.Stats` 的语义未定义** | `requests/budget/queued` 是**累计值还是窗口值**？spike 只能猜（用了累计） | 在 `INTEGRATION.md` §2.1 写死语义，否则 T1 的预算验收无法判定 |
| S4 | **`UpdateAsync` 的重试语义未覆盖** | Roblox 的 `UpdateAsync` 内部重试时**会再次调用 transform**（副作用会重复），spike 的同步 transform 没暴露这点 | T0 的 `StandaloneBinding` 必须覆盖「transform 被调用两次」的用例，并在 Port 契约里写明「transform 必须幂等」 |
| S5 | **索引可观测性属于谁** | spike 用私有的 `indexLookups/fullScans` 计数器做断言；而 T2 的验收（实际读数 ≤ 树高）**也需要类似可观测面** | 把「扫描/查找计数器」正式化为 `Tri.Index` 的观测接口，而不是每个实现各写一份 |
| S6 | **表名长度会顶到 50 字符硬限** | `tri:main:<table>:p0:idx:pk` 在表名 > 20 字符时超限 | `Tri.Catalog.TableRegistry` 必须做**表名 → 短 id** 映射并把映射落盘。**这是可行性前提，不是优化** |

## 3. 被**证伪或修正**的设想

| # | 原设想 | 纵切实测 | 修正 |
| --- | --- | --- | --- |
| F1 | 「页容量用槽位数控制就够了」 | spike 按**槽位数**（32）实现；而规格按 **4KB 字节** | **T1 的验收必须改成字节断言**（页内数据 ≤ 4096 − 头部），spike 的槽位断言不能沿用 |
| F2 | 「写失败只影响那一次调用」 | 注入 `SetAsync` 失败后，**内存态若不回滚就会出现「内存有、存储无」的不一致**（spike 首版就是这样，回滚后才对） | 把「**端口写失败必须回滚内存态**」写成 `TritiumSQL.md` T1 的显式验收项（规格里原来没有） |
| F3 | 「类型校验放哪都行」 | spike 把 `typeOk` 内联在 `Run` 里，立刻变成第二份类型规则（第一份是 `Dr.Types.Validation` 的计划） | 类型/转换规则只允许一处实现（`TYPES.md` 的转换矩阵），T4 必须**复用** `Dr.Types.Validation` 而不是重写 |
| F4 | 「`TritiumSQL` 可以独立发布为不依赖框架的包」 | 它现在**必须**依赖 `Deuterium` 的 FOUNDATION（错误语义）。这在 headless 与 Rojo 下都能跑，但「零依赖发布」不成立 | 见 §5 的 D12 |

## 4. 纵切**未覆盖**（后续 Wave 必须补，不能当作已完成）

- 持久化：spike 全程内存；`Port` 的真实语义（限额、排队、键级节流）只有 StandaloneBinding 能验证
- 事务 / 锁 / MVCC / WAL：完全未涉及（T3）
- 并发：spike 是单进程同步调用，没有协程竞争（T3 的锁与死锁图）
- 查询：只有 `WHERE <pk> = <literal>`；无范围、无 JOIN、无聚合、无多列投影（T4–T5）
- 索引：有序数组而非 B+ 树；无分裂、无树高、无范围扫描（T2）
- 分区：只有 `p0`（T0 的 Partitioner 未涉及）
- `ResultSet` 只被 Walkthrough 自己消费过，**没有真正跨过网络边界** → `INTEGRATION.md` §2.4 的 `schemaVersion` 校验仍是纸面设计

## 5. 需要拍板的两个决策（纵切强制它们提前暴露）

| # | 决策 | 选项 | 影响 |
| --- | --- | --- | --- |
| **D12** | TritiumSQL 的发布依赖 | ① 依赖 Deuterium FOUNDATION ② 自带错误类型 | 决定 `wally.toml` 的依赖图与「TritiumSQL 能否单独发布」 |
| **D13** | SQL 错误的最终形状 | ① 扩 `DrError`（动认证范围）② Tri 侧 `SqlError` 包一层 | 决定 T3/T4 的错误码表落在哪一层 |

> 两者都不阻塞 T0/T1（只用到 Port 与页），但**必须在 T3 之前定**（错误语义要在事务阶段定型）。

## 6. 纵切代码的处置

`Tri/Spike/{SpikePort,SpikeStore,TriSQL,Walkthrough}.luau` 标记 **DAL E**：
- 不在 `docs/cert/scope.txt`（门禁 10 不理它们）
- **零引擎依赖**（装载巡检 79/79 含它们）
- 头部都有 `shortcut:` 标注
- **处置：保留** —— 它们现在是接缝的可执行证据与 T1–T2 的对照实现；到 T2 结束、真实现覆盖同等断言后再删，
  删除时同步删 `tests/walkthrough.luau` 与 `tests/run.luau` 的对应套件

---

未读/未验证：spike 的 `ResultSet` 未跨网络边界（见 §4）；`Port.Stats` 数字是自造语义（S3）；**50 字符键限未在真实 DataStore 上实测**（只有官方文档 + 本机推导）。
