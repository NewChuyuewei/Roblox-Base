# 实施步骤（Execution Steps）

> 本文件是 `.plan/*.md` 的**执行手册**：把 Wave 拆成「动哪个文件 → 跑什么命令 → 看到什么算过」。
> 规则：**WIP = 1**。一个 Step 未达完成判据，不开下一个 Step。Step 编号可被 commit message 引用（`feat(deut): step 0.3 collections`）。

## Step ↔ Wave 对照

| Step | 对应 Wave | 项目 |
| --- | --- | --- |
| S1–S3 | 一次性准备 | 环境 |
| 1–12 | Deuterium Phase 0.1 | Deuterium |
| 13–15 | Deuterium Phase 0.2 · 0.3 | Deuterium |
| 16 | Deuterium Phase 0.4 | Deuterium |
| **16.5** | **Phase 0.5 端到端纵切** | **两端接缝** |
| 17–19 | Deuterium Phase 2.5–2.7 | Deuterium |
| 20–21 | Deuterium Phase 3.1 · 3.2 | Deuterium |
| 30–35 | TritiumSQL Phase 0 | TritiumSQL |
| 36–43 | TritiumSQL Phase 1 | TritiumSQL |
| 44–47 | TritiumSQL Phase 2 | TritiumSQL |
| **50–57** | **`Dr.Integration`（G1–G10 的 Deuterium 侧）** | **集成** |
| **60–65** | **`Tri.Integration`（G1–G10 的 SQL 侧）** | **集成** |
| — | 其余波次 | 见 `.plan/Deuterium.md` §5 / `.plan/TritiumSQL.md` §12（Wave 级粒度足够，开动时再展开为本表） |

---

## 一、一次性准备（人做，一次）

**S1 · 装工具链**

```bash
# Windows: 用 rokit（Rust 工具链管理器，跨平台）
curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
rokit add rojo lune selene stylua luau-lsp      # 由 rokit 解析当前稳定版本并写入 rokit.toml
rokit install
```

判据：`rojo --version` / `lune --version` / `selene --version` / `stylua --version` 四条都有输出。

**S2 · GitLab 仓库设置**

1. 主分支 `main` 设为受保护（禁止直接 push）。
2. CI/CD Variables：无需 secret（本仓库不连外部服务）。**不要**配 Roblox Open Cloud key。
3. Settings → Merge requests：开启 "Pipelines must succeed"（让 Step 8 的门禁成为硬门禁）。

判据：直接 push `main` 被拒。

**S3 · 分支与提交约定**

- 分支：`feat/deut-0-3-collections`、`feat/tri-1-5-pagemanager` 形式。
- 提交：Conventional Commits（`feat:` / `fix:` / `chore:` / `docs:` / `test:` / `refactor:`），scope 取 `deut` / `tri` / `ci`。
- 一个 Step = 一到多个原子提交；Step 完成时 commit message 末尾带 `(step X.Y)`。

---

## 二、Deuterium Phase 0.1 · 让仓库可运行（Step 1–12）

**Step 1 · `rokit.toml`（S1 已生成）**
判据：文件在仓库根、已被 git 跟踪。动作：`git add rokit.toml && git commit -m "chore(ci): pin dev toolchain via rokit"`。

**Step 2 · `default.project.json`（Rojo 映射）**

```json
{
  "name": "framework",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "$className": "ReplicatedStorage",
      "Deuterium": { "$path": "Deuterium" },
      "TritiumSQL": { "$path": "TritiumSQL" },
      "Debug": { "$path": "Deuterium/Diagnostics/Logging/Debug.luau" }
    },
    "ServerScriptService": {
      "$className": "ServerScriptService",
      "DeuteriumServer": { "$path": "src/ServerScriptService" }
    }
  }
}
```

要点：
- 现有代码 require 的是 `ReplicatedStorage.Debug` 与 `ReplicatedStorage.Deuterium.*`，此映射**不改任何 require 字符串**即可对上。
- `Debug` 指向 Deuterium 内部实现（Diagnostics.Logging 属框架，不新开 `src/` 根）。
- `Deuterium/Deuterium.md` 是非 Lua 文件，Rojo 会跳过；**若 build 报未知扩展名**，把它移到 `docs/Deuterium.md` 并同步更新各处引用。

判据：`rojo build -o /tmp/place.rbxlx` 退出码 0，且 `src/ServerScriptService/` 已建（可先放 `.gitkeep`）。

**Step 3 · `Deuterium/Diagnostics/Logging/`（4 个文件）**

按依赖顺序写：

| 文件 | 职责 |
| --- | --- |
| `LogSink.luau` | 后端接口 + 默认 `StudioSink`（`print`/`warn`）。禁在此处 require `game` 之外的东西 |
| `StructuredLog.luau` | 构造 `{level, tag, msg, data, ts}` 纯表 + 单行格式化（无副作用，**Lune 可测**） |
| `Logger.luau` | `Logger.New(tag)` → `logger:info/warn/error(fmt, ...)`；按 level 过滤；转发 Sink |
| `Debug.luau` | 兼容层：导出 `print/warn/err`，内部持一个默认 Logger，tag 为 `"Dr"`。18 个既有文件靠它 |

要点：`Debug.luau` **不得** require `ReplicatedStorage.Debug`（自引用）；Scribe 缺失时静默降级到 StudioSink。

判据（Studio 命令栏）：
```lua
local Debug = require(game.ReplicatedStorage.Debug)
Debug.print("hello", 1)   -- 输出带 [Dr] 前缀
```

**Step 4 · `.luaurc`**

```json
{
  "languageMode": "strict",
  "lint": { "*": true },
  "lintErrors": true,
  "typeErrors": true
}
```

判据：`luau-lsp analyze --settings=.luaurc Deuterium/Diagnostics/Logging/Logger.luau` 无 error。

**Step 5 · `stylua.toml` + `selene.toml`**

```toml
# stylua.toml
column_width = 110
indent_type = "Tabs"
quote_style = "AutoPreferDouble"
call_parentheses = "Always"
```

```toml
# selene.toml
std = "roblox"
exclude = ["Deuterium/Deuterium.md"]
```

要点：**不自研 selene 插件**做 P0 巡检（成本高）；改用 Step 5b 的 grep 基线脚本。

**Step 5b · `scripts/p0-check.sh`（P0 规约守卫）**

逻辑：统计 `Core/`、`Net/`、`Storage/`、`Index/`、`Request/` 目录下 `table.insert(`、`game:GetService(`、`loadstring(` 的出现次数，与 `scripts/p0-baseline.txt` 比较，**只允许下降**。

判据：`bash scripts/p0-check.sh` 在当前树上退出码 0；人为加一行 `table.insert` 后退出码非 0。

**Step 6 · 静态检查全绿**

```bash
stylua --check Deuterium
selene Deuterium
bash scripts/p0-check.sh
```

判据：三条全绿。此处通常需要一次全仓库 `stylua Deuterium` 格式化 → 单独一个 `style:` 提交，避免污染后续 diff。

**Step 7 · headless 探针（15 分钟 spike，决定 CI 测试策略）**

目的：确认 Lune 里能否让 `game:GetService("ReplicatedStorage")` 生效。

```bash
lune run scripts/probe-headless.luau
```

探测内容（依次试，记录哪一级成功）：
1. `_G.game = { GetService = ... }` 后 `require` 一个含 `game` 的模块 → 能否解析全局 `game`？
2. `luau.load(source, { environment = { game = ... } })` 形式注入 → 能否？
3. 都不行 → 结论：CI 只跑**纯逻辑**模块（不含 `game` 的），其余靠 Studio 回归。

判据：`docs/headless.md` 写下探测结果与选定策略（这是 `README.md` 门禁 2 的落地依据，必须留档）。

> 注：TritiumSQL 的核心（页布局 / B+ 树 / MVCC / 编解码 / 请求预算）**全部是纯逻辑**，只有 Port 绑定碰 `game`。所以三级结论都不阻塞 TritiumSQL 的 CI 覆盖。

**Step 8 · `.gitlab-ci.yml` 四阶段**

```yaml
stages: [lint, types, build, test]

default:
  image: ubuntu:24.04
  before_script:
    - apt-get update -qq && apt-get install -y -qq curl unzip git
    - curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
    - export PATH="$HOME/.rokit/bin:$PATH"
    - rokit install

lint:
  stage: lint
  script:
    - stylua --check Deuterium
    - selene Deuterium
    - bash scripts/p0-check.sh

types:
  stage: types
  script:
    - rojo sourcemap default.project.json -o sourcemap.json
    - luau-lsp analyze --sourcemap=sourcemap.json --defs=types/globalTypes.d.luau Deuterium

build:
  stage: build
  script: [rojo build default.project.json -o place.rbxlx]
  artifacts: { paths: [place.rbxlx] }

test:
  stage: test
  script: [lune run tests/run.luau]
```

要点：
- `types/globalTypes.d.luau`（Roblox 全局类型）需**一次性**取得并入库固化，来源在首次跑通时确认（从 luau-lsp 发布物或 Roblox API Dump 生成），之后不再联网。
- 保留 GitLab 默认 SAST 模板（`include: Security/SAST.gitlab-ci.yml`），它是免费的额外信号。
- 首次跑通前，`types`/`test` 可先 `allow_failure: true`；Step 9 完成后全部改回阻断。

判据：Pipeline 四阶段可见；`lint` 与 `build` 为绿（阻断）；Pipeline 结果写入 `MEMORY.md`。

**Step 9 · `AGENTS.md` + `MEMORY.md`**

| 文件 | 内容 |
| --- | --- |
| `AGENTS.md` | 分层依赖规则（上层只可向下）、`Dr.*` 命名、I8–I12 不变量摘要、门禁命令清单、禁止事项（热路径三禁、`Dr` 层出现 `game`） |
| `MEMORY.md` | 依赖审计留档表：Scribe（版本 / commit / 审计人 / 结论 / 改动点）、后续 PlayerState / QuickZone 占位 |

Scribe 审计（约 30 分钟）：搜 `loadstring` / `HttpService` / `require(<数字 id>)` / `getfenv`，逐条判断。
判据：`MEMORY.md` 有 Scribe 那一行且审计人、结论已填；决策 D6 关闭。

**Step 10 · 全仓库 require 冒烟**

Studio 命令栏：
```lua
local ok, err = pcall(function() require(game.ReplicatedStorage.Deuterium.Testing.SelfTest).RunAll() end)
print(ok, err)
```

判据：`RunAll()` 返回 true。**这条不过就不许继续** —— 它证明 Phase 1/2 已完成模块是真的能加载，而不只是文件存在。

**Step 11 · `Debug` 全量替换登记**

`grep -rl 'WaitForChild("Debug")' Deuterium | wc -l` 应等于 18。不改写这些文件（现路径已可用），只在 `AGENTS.md` 记一条：新代码一律 `require(ReplicatedStorage.Debug)`（不 `WaitForChild`），旧文件在各自被改动时顺手去掉 `WaitForChild`。

**Step 12 · Phase 0.1 收口**

```bash
rojo build -o /tmp/place.rbxlx && lune run tests/run.luau && bash scripts/p0-check.sh
```

判据：CI 四阶段全绿（含 `test`）；`README.md` 门禁 1–3 全部可用。打 tag `v0.1.0-alpha`。

---

## 三、Deuterium Phase 0.2 / 0.3 / 0.4（Step 13–16）

**Step 13 · `Dr.Core.Foundation` 补件（0.2）**

顺序：`Metadata.luau` → `Context.luau` → `EventLoop.luau`。
- `Metadata`：对一个 provider 表提取 `Name/Dependencies/Init/Start/Stop` 形状，供 `Inspector` 用。
- `Context`：不可变键值袋，`Context.With(parent, k, v)` 返回新袋（禁原地改写）；`Kernel.contexts` 改用它。
- `EventLoop`：`task.spawn` 的一层调度封装，提供 `EventLoop.Run(fn)` / `EventLoop.Yield()`，便于 headless 下替换。

判据：`Metadata` ↔ `Core/Reflection/Descriptor` 互通单测；`Context.With` 不改父袋（断言父袋键数不变）。

**Step 14 · Foundation 前置件（0.3）——按此顺序，每件「实现 + 单测」一次提交**

| # | 文件（`Deuterium/` 下） | 关键接口 | 单测要点 |
| --- | --- | --- | --- |
| 14.1 | `Collections/Map/HashMap.luau` | `New/Get/Set/Has/Delete/Len/Iterate` | 冲突、扩容、删除后迭代正确 |
| 14.2 | `Collections/Map/LRUCache.luau` | `New(cap, onEvict)/Get/Set/Peek/Invalidate` | 逐出顺序 = 最久未用；`Get` 提升优先级；容量 0/1 边界 |
| 14.3 | `Collections/Sorted/PriorityQueue.luau` | `New(cmp)/Push/Pop/Peek/Len` | 同优先级 FIFO；与 `Dr.HA`/`Tri.Request` 的 P0–P3 语义对齐 |
| 14.4 | `Collections/Linear/RingBuffer.luau` | `New(cap)/Push/Pop/Peek/IsFull/IsEmpty` | 满时行为（拒写，不覆盖）+ 读写指针回绕 |
| 14.5 | `Collections/Linear/Queue.luau` · `Set/Set.luau` | 常用集 | — |
| 14.6 | `Memory/Buffer/ByteBuffer.luau` | `New(size)/WriteU8..F64/WriteString/Read*/Seek/Len/Reset` | 边界越界报错（不静默）；`WriteString` 长度前缀；LE/BE 明确 |
| 14.7 | `Memory/Pool/ObjectPool.luau` · `TablePool.luau` | `New(factory, reset)/Acquire/Release` | 复用计数；Release 时 reset 被调且清引用 |
| 14.8 | `Concurrency/Sync/Mutex.luau` | `Mutex.New()` → `Lock()`/`Unlock()`/`WithLock(fn)` | 协程串行化；重入报错；等待者被唤醒顺序 FIFO |
| 14.9 | `Concurrency/Async/AsyncQueue.luau` | `Push/Pop/Close/Wait` | `Pop` 无数据时让出而不忙等（断言 CPU 让出） |
| 14.10 | `Concurrency/Scheduling/TaskScheduler.luau` | `Schedule(delayMs, fn)/Update(nowMs)/Cancel` | 同刻多任务顺序稳定；`Update` 可被 headless 手动驱动（**关键：让定时逻辑可测**） |
| 14.11 | `Concurrency/Async/Promise.luau` | `New/resolve/reject/AndThen/Catch/Await` | — |
| 14.12 | `Types/Primitives/{TypeChecker,TypeGuard,Branded}.luau` | `TypeChecker.IsX` 系列 | — |
| 14.13 | `Types/Validation/{SchemaBuilder,Schema,Validator,Coercion}.luau` | `Schema.String{max=}`, `Validator.Validate(schema, value) -> (ok, errs)` | 负例样例集 100% 拒绝；错误含列路径 |
| 14.14 | `Types/Transform/Codec.luau` | `Codec.Encode(value) -> string` / `Codec.Decode(str) -> value` | **I9 唯一 Codec**：round-trip 稳定性；深度/循环引用报错；大小可预测 |

判据（每件）：单测在 CI 的 `test` 阶段运行且绿。14.14 完成后，`Dr.Net.Processing.Serializer` 改造为调用它（一次 `refactor(deut)` 提交，Net SelfTest 必须仍绿）。

**Step 15 · `Dr.Testing.Integration`（0.3 收尾）**

| 文件 | 内容 |
| --- | --- |
| `DataStoreSimulator.luau` | 内存 KV，支持 `GetAsync/SetAsync/UpdateAsync/RemoveAsync`、配额（每分钟请求数）、故障注入（`timeout` / `quotaExceeded` / `writeFail`）、**`RequestCount()`** |
| `RequestAssert.luau` | `RequestAssert.Exactly(sim, n, fn)` / `AtMost(sim, n, fn)`，失败时打印实际调用栈 |

判据：注入 `quotaExceeded` 后，被测代码必须走 fallback 而非抛错；`RequestCount` 与实际调用一一对应。

**Step 16 · `Dr.Runtime.Platform` 端口（0.4）**

`DataStoreProxy.luau`、`MemoryStoreProxy.luau`：包装 `DataStoreService` / `MemoryStoreService`，暴露与 `DataStoreSimulator` **完全相同的方法签名**（这样 TritiumSQL 的两种绑定可以互换测试），附请求计数与配额节流。

判据：`grep -rn "GetService(\"DataStoreService\")" Deuterium` 只命中这两个文件；代理与模拟器互换后 TritiumSQL Phase 1 的测试无需改动。

**Step 16.5 · 端到端纵切（Phase 0.5，`SCALE.md` §5）——在写任何横向模块之前做**

动作：新建一条临时链路 `tests/walkthrough.luau`，按纵切顺序打穿：

```
SchemaStore（内存）→ TriSQL.Compile("CREATE TABLE t (id INT PRIMARY KEY, name TEXT)")
→ Compile("SELECT name FROM t WHERE id = 1")  → IndexScan（内存 B+ 树）
→ PageManager（内存页）→ SimulatorPort → 读回断言
```

规则：允许内存占位、允许 `shortcut:` 标注；**不做**持久化、事务、优化器、Lune 网络部分。

判据：链路在 Studio 与 CI 各跑通一次，断言 `SELECT` 返回插入的值；`.plan/SEAMS.md` 产出（需正式化的接口 / 被证伪的设想 / 需要新增的模块）；总耗时 ≤3 天。**这是横铺（Step 14 起）的准入条件。**

---

## 四、Deuterium 安全 / HA（Step 17–21）

**Step 17 · 2.5 `Dr.Security.Access` + `Input`**
顺序：`PolicyEngine` → `CapabilityToken` → `Guard` → `Permission` → `Sanitizer` → `SchemaEnforcer` → `ContentFilter`。
判据：RBAC 图在 Init 期编译完成（运行期零解析）；非授权请求 100% 拒绝且拒绝原因结构化。

**Step 18 · 2.6b `Dr.Security.Crypto` + `Monitor`**
顺序：`TokenGenerator` → `Obfuscator` → `AuditLog` → `Fingerprint` → `AntiExploit` → `ThreatDetector` → `BanManager` → `SecurityDashboard`。
判据：日志经 Scribe；禁令生效后重连被拒。

**Step 19 · 2.7 `Dr.Security.Compliance` + 全链联调**
判据：作弊样本集 0 误放行；AuditLog 字段完整（含 txnId / 玩家 / 决策点）。

**Step 20 · 3.1 `Dr.HA.Circuit`**（TritiumSQL 依赖，**先做**）
顺序：`CircuitState` → `CircuitBreaker` → `CircuitRegistry`。
判据：关→半开→开状态机单测 + 锯齿边界（半开期多次失败/成功）用例过。

**Step 21 · 3.2 `Dr.HA.Recovery`**（TritiumSQL 依赖，**先做**）
顺序：`RetryPolicy` → `Timeout` → `Fallback` → `Bulkhead` → `Hedging`。
判据：重试曲线含 ±10% 抖动；`Hedging` 场景下副作用只发生一次（用计数器断言）。

---

## 五、TritiumSQL Phase 0（Step 30–35）

> 前置门禁：Deuterium Step 14.14（Codec）、Step 15（Simulator）、Step 16（Proxy）已绿。

**Step 30 · `TritiumSQL/Tri/Runtime/RuntimeTypes.luau`**

```lua
export type Port = {
  GetAsync:    (key: string) -> (any?, string?),      -- (value, err)
  SetAsync:    (key: string, value: any) -> (boolean, string?),
  UpdateAsync: (key: string, transform: (any?) -> any?) -> (any?, string?),
  RemoveAsync: (key: string) -> (boolean, string?),
  Stats:       () -> { requests: number, budget: number },
}
```

判据：类型可被 `luau-lsp analyze` 通过；无实现、无 `game`（纯类型文件）。

**Step 31 · `Tri/Runtime/Bindings/StandaloneBinding.luau`**
唯一允许出现 `DataStoreService` 的 TritiumSQL 文件，文件头加 `-- EXCEPTION(I10): 本文件是唯一的引擎 API 触点`。
判据：`grep -rn "DataStoreService" TritiumSQL` 只命中此文件 + `Tri/Testing/SimulatorPort.luau`。

**Step 32 · `Tri/Runtime/Bindings/DeuteriumBinding.luau`**
转发到 `Dr.Runtime.Platform.DataStoreProxy`。
判据：与 StandaloneBinding 跑同一组契约测试（共用 `Tri/Testing/PortContract.luau`），两者结果一致。

**Step 33 · `Tri/Testing/SimulatorPort.luau`**
内存 Port 实现 + 请求计数 + 故障注入（不依赖 Deuterium 的 Simulator，保证 TritiumSQL 可独立测试）。
判据：`PortContract.luau` 三绑定全过。

**Step 34 · `Tri/Catalog/NamespaceCodec.luau`**

```lua
Codec.Encode({ db, table, partition, keyType, value }) -> string
Codec.Decode(key) -> components | nil, err
Codec.AssertKey(key) -- 长度 ≤ 50 或报错
```

要点：`tri:` 前缀；长值（如 email）走短哈希 `#<8位>` 并登记到 `tri:__catalog__:hashes`。
判据：round-trip 1000 随机例唯一；任意输入 `#key <= 50` 恒成立；超长输入自动哈希而非静默截断。

**Step 35 · `Tri/Catalog/Catalog.luau` + `TableRegistry.luau` + `SchemaStore.luau`**
顺序：`SchemaStore`（Schema 读写 + `version`）→ `TableRegistry`（表名 ↔ tableId，常驻内存）→ `Catalog`（聚合 + 分区路由 `routes`）。
判据：冷启动读请求次数 == 表数（断言，非估算）；Schema 版本加一后旧行仍可读；`Catalog` 缓存失效路径有单测。

---

## 六、TritiumSQL Phase 1（Step 36–43）

**Step 36 · `Tri/Request/RequestBudget.luau`**
令牌桶 + 计数，桶容量与速率来自 `Port.Stats()`；`TriSQL.md` §0 的限额假设集中在此一个文件里（便于 Step 38 的探针校正）。
判据：速率 10/min 下灌 100 次 → 0 丢弃、排队、计数精确。

**Step 37 · `Tri/Request/RequestQueue.luau` + `BatchExecutor.luau`**
优先级 `P0..P3`（用 14.3 的 `PriorityQueue`），`BatchExecutor` 合并同表同类型的读。
判据：P0 严格先于 P3（时间戳断言）；合并后请求数 < 合并前（量化）。

**Step 38 · 限额覆盖核对（真实环境一次）**

数字已在 `SCALE.md` §1.3 对官方文档核实（key/scope/name 各 50、value 4,194,304 B、`rateLimit = base + perPlayer × numPlayers`），此处不再「实测上限」，改为**核对覆盖是否生效**：写 `scripts/probe-ratelimit.luau`，在 Studio 调
`DataStoreService:SetRateLimitForRequestType(requestType, base, perPlayer)`，再用压测确认 `RequestBudget` 读回的实际值与之致。

判据：`RequestBudget` 能区分「排队」「键级节流」「真失败」三态（各 1 个用例）；设限后实测速率与设定值一致；结果附日期回写 `TriSQL.md` §0。

**Step 39 · `Tri/Storage/Page.luau` + `HeapLayout.luau`**
先写 `Page` 的纯数据结构（slots/freeSpace/lsn）与 `HeapLayout` 的插入、软删除、压缩、碎片统计；**不碰 IO**。
判据：4KB 页内 ≥ 32 典型行；页满分裂后两页均 ≥ 40% 占用；软删除后 `freeSpace` 正确回收（全部纯内存断言，CI 可跑）。

**Step 40 · `Tri/Storage/PageManager.luau`**
`AllocPage/ReadPage/WritePage/SplitPage`，经 `Port` + `Dr.Types.Transform.Codec`（I9）。
判据：写 100 页 → 请求数 == 100（无额外读）；页分裂的请求数 ≤ 5；`SetAsync` 失败注入后不产生半写页（可用 `UpdateAsync` 重试断言）。

**Step 41 · `Tri/Storage/PageCache.luau`**
LRU（用 14.2），dirty 标记 + write-back on evict/commit。
判据：命中时不产生读请求（**断言 0 次**）；逐出时 dirty 页被写回且计数正确；容量压到 1 时功能仍正确。

**Step 42 · CRUD（`Tri/Storage/RowStore.luau`）**
`Insert/GetById/Update/Delete` 走 PageManager + PageCache。
判据：点查命中缓存 **0 次 DataStore 读**；未命中 ≤ 1 次；删除为软删除且不影响其他行。

**Step 43 · Phase 1 收口**
判据：1e3 行插入 + 1e3 点查的总请求数 ≤ 目标预算（目标写在 `TriSQL.md` §0 后追加一行）；CI 全绿；tag `tri-v0.1.0-alpha`。

---

## 七、TritiumSQL Phase 2（Step 44–47）

**Step 44 · `Tri/Index/NodeCodec.luau`**
内部节点 / 叶子节点的编解码 + 键比较器（类型化：number / string / timestamp 的确定性全序）。
判据：键全序单测（含 number 与 string 混排的拒绝路径）；节点 round-trip 稳定。

**Step 45 · `Tri/Index/BPlusTree.luau`**
`Search/Insert/Split/RootSplit/Scan`，根 ID 写回表元数据。
判据：1e4 行插入后点查实际 DataStore 读次数 ≤ 树高（**断言实际读数**）；分裂后父子键区间无空洞（区间一致性断言）；树高 > 3 触发告警。

**Step 46 · `Tri/Index/IndexScan.luau`**
点查 + 范围扫描，全程走 `prevLeaf/nextLeaf`。
判据：范围扫描不产生回父节点的读（断言读序列）；扫描 100 行 ≤ 树高 + 1 次读。

**Step 47 · `Tri/Index/UniqueGuard.luau`**
插入前验唯一（依赖 `Tri.Txn.LockManager`，Phase 3 未完成时先用 `Mutex` 单进程占位并标注 `shortcut:`）。
判据：并发两个协程插同一唯一键 → 恰一个成功、一个返回明确冲突错误。

---

## 七点五、集成层（Step 50–57 / 60–65）

> 前置：Step 16.5（纵切）已产出 `SEAMS.md`，`INTEGRATION.md` §2 的四个接缝已冻结。
> 模块清单、行数预算与验收（A1–A14）见 `INTEGRATION.md` §5 · §6；此处只给写码顺序与门禁。

**写入顺序（不可并行到同一接缝）**

| Step | 内容 | 完成判据 |
| --- | --- | --- |
| 50 | `Dr.Integration.Types` + `Capability` | 框架在 Tri **缺失**时仍能完整启动（A1） |
| 51 | `Provider` + `Configuration` + `BootGate` | 人为打乱 Init 顺序时断言**必须失败**（A2） |
| 60/61 | `Tri.Integration.{Types,DeuteriumProvider,Config,Capability,Preload,PortBindings}` | 三绑定跑同一份 `PortContract`；G2 的 HA 包裹下断网 60s 不雪崩（A3） |
| 52/53 | `Persistence/*` + `SagaBridge` | Saga 中断逆序回滚，会话态与关系表双双回到起点（A4） |
| 62 | `ChangeLog` + `ChangeStreamApi` | 提交路径发射变更，**不额外扫表**（请求次数断言） |
| 54 | `Replication/*` | 100 行写入 → 客户端严格按 lsn 收到 100 变更且幂等；断线 30s 用 `lastAck` 补齐（A5/A6/A7） |
| 63/55 | `RowSecurity` + `Security/*` | **≥10 个越权攻击用例全部被拦**，且每个注入有审计（A8/A9） |
| 56 | `Net/*` | `schemaVersion` 不一致时拒绝解码（A10） |
| 64/57 | `Scheduler` + `Telemetry` + `Observe/*` + `Ecs/*` | 算子 span 齐全；批量写满足预算（A11/A12） |
| 65 | `QueryApi` + `BootMigrator` | 端到端场景在 Simulator 与真实 DataStore 上结果一致（A14） |

**集成层的两个硬门禁**

1. **I14 方向门禁**：`grep -rn "Tri\." Deuterium --include=*.luau | grep -v "^Deuterium/Integration/"` 必须为空，否则 CI 阻断。
2. **I15 锁顺序门禁**：Step 63 的 `LockBridge` 对反序调用直接报错（A13，写成负例测试）。

> G4（复制）与 G5（RLS）合计 5,400 行核心 + 攻击用例，是全局最不能压缩的部分。排期吃紧时砍 G7（ECS 持久化），不砍这两个。

---

## 八、写每个 Step 的统一模板（Definition of Done）

1. `--!strict`，模块末尾 `return table.freeze(M)`。
2. 文件头注释：职责 + 对应 Wave + 不变量引用（如需）。
3. 实现只依赖允许的层；新增 require 前自问「这一层允许吗」。
4. 非平凡逻辑配单测（分支 / 循环 / 解析 / 金钱或安全 / 请求计数）。
5. 已知限制写 `shortcut: <限制>, <何时升级>`。
6. 本地跑齐门禁：
   ```bash
   stylua --check Deuterium TritiumSQL && selene Deuterium TritiumSQL \
     && bash scripts/p0-check.sh && lune run tests/run.luau
   ```
7. commit（Conventional Commits + `(step X.Y)`），推分支，CI 绿，再开下一个 Step。

---

## 九、会话开工/收工流程

**开工**：读 `.plan/README.md` 的「唯一关键路径」→ 找当前 Step → `git checkout -b feat/<scope>-<step>` → 复述该 Step 的完成判据。

**收工**：CI 绿 → 更新 `.plan/STEPS.md` 中该 Step 的状态标记 → 若产生了新决策，追加到 `README.md` 的开放决策表 → 若推翻了假设，改对应 plan 文档（**不要只改代码**）。

**禁止**：跳过 Step 10 与 Step 12；在 `test` 阶段为红的情况下开新 Step；在 Phase 3（Tri）未完成前写 Phase 4 的算子（依赖 WAL 的快照语义）。

---

未读/未验证：`rokit` 的安装脚本 URL、`luau.load(..., {environment=...})` 的确切签名、`globalTypes.d.luau` 的取得方式、DataStore 限额数字 —— 这四项都在 Step 7、Step 8、Step 38 里做成了显式的「一次确认并固化」动作，未确认前不写死。风险是 Step 8 的 CI 首次跑通可能需要一轮调试（镜像/网络），预算半小时。
