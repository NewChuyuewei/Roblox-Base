# 执行手册（Execution Steps）

> 把 Wave 拆成「动哪个文件 → 跑什么命令 → 什么算过」。
> **规则：WIP = 1。** 一个 Step 未达完成判据，不开下一个。
> 权威划分：不变量/门禁/决策/风险 → `README.md`；预算与功能面 → `SCALE.md`；互通接口 → `INTEGRATION.md`。

## Step ↔ Wave ↔ AC 对照

| Step | Wave | AC | 项目 |
| --- | --- | --- | --- |
| S1–S3 | — | — | 环境 |
| 1–12 | `D0.1` | `AC-D0.1` | Deuterium |
| 16.5 | `D0.5` + `T0.5` | `AC-D0.5` / `AC-T0.5` | 两端接缝 |
| 13–15 | `D0.2` · `D0.3` | `AC-D0.2` · `AC-D0.3` | Deuterium |
| 16 | `D0.4` | `AC-D0.4` | Deuterium |
| 17 | `D2.5` | `AC-D2.5` | Deuterium |
| 18 | `D2.6b` | `AC-D2.6b` | Deuterium |
| 19 | `D2.7` | `AC-D2.7` | Deuterium |
| 20 | `D3.1` | `AC-D3.1` | Deuterium |
| 21 | `D3.2` | `AC-D3.2` | Deuterium |
| 30–35 | `T0` | `AC-T0` | TritiumSQL |
| 36–43 | `T1` | `AC-T1` | TritiumSQL |
| 44–47 | `T2` | `AC-T2` | TritiumSQL |
| 50–57 | G1–G3 · G5–G10 | `AC-G1`…`AC-G10` | `Dr.Integration` |
| 60–65 | G1–G10 | `AC-G1`…`AC-G10` | `Tri.Integration` |

**保留号段**（预留给后续 Wave，不要复用）：`22–29` → `D4.x`–`D8`；`48–49` → `T3`（事务/WAL）；`58–59` → 集成收口；`66+` → `T4`–`T11`。

## 进度登记

| Step | 状态 | Step | 状态 | Step | 状态 |
| --- | --- | --- | --- | --- | --- |
| S1 ✅ S2 ☐ S3 ✅ | ◐ | 20 | ☐ | 44–47 | ☐ |
| 1–3 ✅ / 4–12 ☐ | ◐ | 21 | ☐ | 50–57 | ☐ |
| 13–15 | ☐ | 30–35 | ☐ | 60–65 | ☐ |
| 16 / **16.5** | ☐ | 36–43 | ☐ | — | — |
| 17–19 | ☐ | — | — | — | — |

### 完成日志

| 日期 | Step | 结果 | 证据 |
| --- | --- | --- | --- |
| 2026-10-24 | S1 | ✅ 工具链就位 | `rokit list` 列出 5 工具；五个二进制直连 `--version` 均有输出 |
| 2026-10-24 | S3 | ✅ 分支约定生效 | `main` 有 git 守卫阻止直接提交（`git branch -b` + 分支提交已验证） |
| 2026-10-24 | **Step 1** | ✅ | `rokit.toml` 已提交（`chore(ci): pin dev toolchain via rokit`）；`rokit install` 幂等 exit 0 |
| 2026-10-24 | **Step 2** | ✅ | `rojo build` exit 0（174,927 B）；`rojo sourcemap` 的 ModuleScript 数 == 69 == `.luau` 文件数 |
| 2026-10-24 | **Step 3** | ✅ | 5 个文件 429 行；build exit 0；ModuleScript 75（含 Debug 双映射）；StructuredLog 在 Lune 实测通过 |
| — | S2 | ☐ | 待人在 GitLab 侧设 `main` 保护 + Pipelines must succeed |

---

## 一、一次性准备（人做，一次）

**S1 · 装工具链**

```bash
curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
rokit add rojo lune selene stylua luau-lsp      # rokit 解析当前稳定版本并写入 rokit.toml
rokit install
```

判据：`rojo --version` / `lune --version` / `selene --version` / `stylua --version` 四条都有输出。

**S2 · GitLab 仓库设置**

1. `main` 设为受保护（禁止直接 push）。2. CI/CD Variables：无需 secret（**不要**配 Roblox Open Cloud key）。3. Settings → Merge requests：开启 "Pipelines must succeed"（让 Step 8 的门禁成为硬门禁）。

判据：直接 push `main` 被拒。

**S3 · 分支与提交约定**

分支 `feat/deut-0-3-collections` / `feat/tri-1-5-pagemanager`。提交用 Conventional Commits（`feat:`/`fix:`/`chore:`/`docs:`/`test:`/`refactor:`），scope 取 `deut`/`tri`/`ci`/`integration`。一个 Step = 一到多个原子提交，commit message 末尾带 `(step X.Y)`。

---

## 二、`D0.1` · 让仓库可运行（Step 1–12）

**Step 1 · `rokit.toml`** —— 已完成（2026-10-24）。

```toml
[tools]
rojo     = "rojo-rbx/rojo@7.7.1"
selene   = "Kampfkarren/selene@0.32.0"
stylua   = "JohnnyMorganz/StyLua@2.6.0"
luau-lsp = "JohnnyMorganz/luau-lsp@1.70.1"
lune     = "lune-org/lune@0.11.1"
```

**实测补充（换机器/上 CI 时会再碰到的三件事）**

1. **首次必须先 `trust`**：`rokit add <tool>` 会报 `has not been marked as trusted`，即使写成全限定名也一样。正确顺序是
   `rokit trust <owner/repo>` → `rokit add <owner/repo> [alias]`。（`rokit add` 一次只收一个工具。）
2. **直连 GitHub release 下载会被 reset**（`GitHub error: reqwest error: error decoding response body`；`raw.githubusercontent.com` 连接被重置，而 `api.github.com` 通）。
   带代理重跑即可：`HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=... rokit install --no-trust-check`。**CI 若同受限，需在 GitLab CI 配代理变量**（Step 8）。
3. **PATH 遮蔽**：本机 `~/.aftman/bin` 排在 `~/.rokit/bin` **之前**，而 aftman 的 `rojo/stylua/luau-lsp/wally` 四个 shim 因全局 `aftman.toml` 中对应行被注释而全部报错。
   因此裸命令 `rojo` / `stylua` / `luau-lsp` 目前命中的是**坏 shim**（`lune` / `selene` 命中 rokit，正常）。
   修法（二选一，均需人工）：① 从 Windows 用户 PATH 移除 `C:\Users\31401\.aftman\bin`（推荐，aftman 已被 rokit 取代）；
   ② 删除 `~/.aftman/bin/` 下四个坏 shim（真二进制在 `~/.aftman/tool-storage`，74 MB，不受影响）。

判据：`rokit.toml` 在仓库根且已被 git 跟踪；`rokit install` 幂等。**AC-D0.1 尚未达成**（Step 2–12 未做）。

**Step 2 · `default.project.json`（Rojo 映射）** —— 已完成（2026-10-24）。

```json
{
  "name": "framework",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "$className": "ReplicatedStorage",
      "Deuterium": { "$path": "Deuterium" },
      "TritiumSQL": { "$path": "TritiumSQL" }
    },
    "ServerScriptService": {
      "$className": "ServerScriptService",
      "DeuteriumServer": { "$path": "src/ServerScriptService" }
    }
  }
}
```

附带 `.gitignore`（`place.rbxlx` / `sourcemap.json` / `*.rbxl*`）避免 Step 8 生成的产物混入提交。

**与计划的修正**：`Debug` 节点**不在本 Step 加** —— 它指向的 `Deuterium/Diagnostics/Logging/Debug.luau` 尚未存在，而 `$path` 指向不存在的文件会让 `rojo build` 失败。该节点随文件一起在 **Step 3** 加，届时二者同一次提交。

**实测补充**

1. `Deuterium/Deuterium.md` 与 `.gitkeep` 这类非 Lua 文件 **Rojo 会静默跳过**（不报未知扩展名），无需把它们移出树。原计划里「若 build 报错则移到 `docs/`」的预案作废。
2. **空目录会被 Rojo 拒绝**（`$path` 不存在即报错），而 git 不跟踪空目录 → 新建的空目录必须放 `.gitkeep`，否则**全新 clone 后 CI 的 build 会挂**。已加 `TritiumSQL/.gitkeep` 与 `src/ServerScriptService/.gitkeep`。
3. `rojo sourcemap` 是比 `build` 更精细的验证手段，也是 Step 8 的 types 阶段要用的命令。

判据（已达）：`rojo build -o /tmp/place.rbxlx` 退出码 **0**，产物 174,927 字节；`rojo sourcemap` 得到的 **ModuleScript 数 == 69 == 仓库 `.luau` 文件数**（另有 21 Folder / 92 节点），关键节点 `Deuterium/Core/Container/Kernel` 等抽查存在，`Debug` 节点按预期为 0。

> 注意：sourcemap 只能证明**结构对**，不能证明 require 字符串在运行时可解析 —— 那要等 Step 10 的 `SelfTest.RunAll()`。

**Step 3 · `Deuterium/Diagnostics/Logging/`（5 文件 = 4 + SelfTest）** —— 已完成（2026-10-24）。

实际依赖顺序（与原计划略异：先纯后纯，Sink 反而依赖 StructuredLog 的 `Record` 类型）：
`StructuredLog.luau`（117）→ `LogSink.luau`（41）→ `Logger.luau`（83）→ `Debug.luau`（25）→ `SelfTest.luau`（163）。共 429 行。

**关键约束（新发现，比计划里写的更重要）**：`ErrorHandler` 已经 require 了 `Debug`（见 `ErrorHandler.Report`），而 `Debug` → `Logger`。因此 **Logging 内部绝不能 require `ErrorHandler`**，否则成环（ErrorHandler→Debug→Logger→ErrorHandler）。结果：这三个模块的程序性错误一律用 `assert`，Logging 成为框架里**唯一不依赖 ErrorHandler 的子系统**。

**另一个必须遵守的约束**：既有 51 处 `Debug.print/warn` 调用是 **`print` 式可变参数**（如 `Debug.print("[Dr.Kernel] Init ok:", name)`），不是 printf。所以 `Logger`/`StructuredLog.Join` 按 `print` 语义用 `\t` 拼接；若做成 `string.format`，这些调用会**静默丢掉第二个参数**。

**Scribe**：全仓库 **0 处**引用 Scribe（`Libraries/Scribe` 不存在），所以“缺失时降级”无需任何探测代码 —— 默认 Sink 直接就是 `StudioSink`，Scribe 接入是 `D6.1b` 的事。没有写任何投机性的探测分支。

判据（部分已达）：
- `rojo build` 退出码 **0**；sourcemap ModuleScript **75** = 74 个 `.luau` + `Debug` 双映射（`ReplicatedStorage.Debug` 与 `...Logging.Debug` 同一文件），Logging 下 5 个节点均在位。
- **纯逻辑部分已在 Lune 真实跑通**（见 Step 7 的预答）：`Join("a:", 1, true)` → `a:\t1\ttrue`；`Format(New("warn","Dr.K","hi",{n=3,z="x"}))` → `[warn][Dr.K] hi {n=3 z=x}`；循环引用不挂死。
- 未验：`Debug.print` 在 Studio 的实际输出前缀、`SelfTest.RunAll()` 的 8 个用例。两者都需要 `game`（下一步 Step 10 才能跑），且静态门禁（stylua/selene/luau-lsp）要等 Step 4–6 才能跑。

**Step 4 · `.luaurc`**

```json
{ "languageMode": "strict", "lint": { "*": true }, "lintErrors": true, "typeErrors": true }
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

**Step 5b · `scripts/p0-check.sh`**：统计 `Core/`、`Net/`、`Storage/`、`Index/`、`Request/` 下 `table.insert(`、`game:GetService(`、`loadstring(` 的出现次数，与 `scripts/p0-baseline.txt` 比较，**只允许下降**。
判据：当前树退出码 0；人为加一行 `table.insert` 后退出码非 0。

**Step 6 · 静态检查全绿**：`stylua --check Deuterium` + `selene Deuterium` + `bash scripts/p0-check.sh`。通常需要一次全仓 `stylua Deuterium` 格式化 → 单独一个 `style:` 提交，避免污染后续 diff。

**Step 7 · headless 探针（15 分钟，决定 CI 测试策略）**

`lune run scripts/probe-headless.luau`，依次探测哪一级成功：① `_G.game = {...}` 后 require 含 `game` 的模块；② `luau.load(source, { environment = { game = ... } })`；③ 都不行 → CI 只跑**纯逻辑**模块，其余靠 Studio 回归。

**已部分预答（Step 3 实测，Lune 0.11.1）**：

| 探测 | 结果 |
| --- | --- |
| 零 require 的模块（`StructuredLog`） | ✅ **直接可跑**，且 `os.time` / `os.date` 在 Lune 中可用 |
| `_G.script = { Parent = {...} }` 注入给被 require 的模块 | ❌ **无效** —— 报 `attempt to index nil with 'Parent'`。Lune 中模块环境隔离，调用方设的全局不会传给被 require 的模块 |
| 仍待测 | `luau.load(src, {environment=...})` 形式能否注入（Step 7 开工时试） |

**推论（影响架构，不只是工具链）**：`script.Parent` 等价物是“零 require 模块”与“可 CI 测试模块”的分界线。因此 **A 档核心逻辑应当把依赖以参数传入（构造器注入），而不是用 `script.Parent` 硬接**：这样每个核心模块都能单独 Lune 测试，而不需要任何 `game`/`script` 垫片。TritiumSQL 的页/B+ 树/MVCC/编解码/请求预算本来就该是这个形状，把它写成硬约束。

判据：`docs/headless.md` 写下探测结果与选定策略（门禁 2 的落地依据，必须留档）。
> TritiumSQL 的核心（页布局 / B+ 树 / MVCC / 编解码 / 请求预算）**全是纯逻辑**，只有 Port 绑定碰 `game`，所以三级结论都不阻塞 SQL 的 CI 覆盖。
> 本仓库第一个 CI 可测模块已经是 `Diagnostics/Logging/StructuredLog.luau`（零 require）。

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

要点：`types/globalTypes.d.luau`（Roblox 全局类型）需**一次性**取得并入库固化（来源在首次跑通时确认，之后不联网）；保留 GitLab 默认 SAST 模板作为额外信号；首次跑通前 `types`/`test` 可先 `allow_failure: true`，Step 12 后全部改回阻断。

**Step 9 · `AGENTS.md` + `MEMORY.md`**：`AGENTS.md` 写分层依赖规则、`Dr.*` 命名、I8–I15 摘要、门禁命令、禁止事项；`MEMORY.md` 写依赖审计留档表（Scribe 版本/commit/审计人/结论/改动点 + PlayerState/QuickZone 占位）。Scribe 审计搜 `loadstring` / `HttpService` / `require(<数字 id>)` / `getfenv`。
判据：Scribe 那行已填；**决策 D6 关闭**。

**Step 10 · 全仓库 require 冒烟**（Studio 命令栏）

**前置缺口（Step 3 侦察发现，必须先补）**：`Testing/SelfTest.RunAll()` 会调 `Configuration.Load()` 与 `FeatureFlags.LoadFromConfig()`，而两者都要求
`ReplicatedStorage.Configs.Deuterium`（一个 ModuleScript 清单）+ `Configs/Deuterium/FeatureFlags`（返回 flag 定义数组）——**这棵 `Configs/` 树目前既不存在也没映射**。需补：

| 文件 | 内容 |
| --- | --- |
| `Configs/Deuterium/init.luau` | 清单模块，键为 section 名（至少含 `FeatureFlags`），每值为 table |
| `Configs/Deuterium/FeatureFlags.luau` | 返回定义数组：每项 `{ name, default, studioOverride? }`，至少包含 `Dr.Security.StrictSchema = true` 与 `Dr.Diagnostics.StructuredLogs`（布尔） |
| `default.project.json` | 加 `"Configs": { "$path": "Configs" }` → `ReplicatedStorage` |

```lua
local ok, err = pcall(function() require(game.ReplicatedStorage.Deuterium.Testing.SelfTest).RunAll() end)
print(ok, err)
```

另外至少要手动验一次 Step 3 的判据（否则那一条永远悬着）：
`require(game.ReplicatedStorage.Debug).print("hello", 1)` → 应输出形如 `22:41:03 [info][Dr] hello\t1`；
`require(game.ReplicatedStorage.Debug).warn("x")` → 形如 `... [warn][Dr] x`（走 warn 通道，Studio 警告过滤可见）。

判据：返回 true。**不过就不许继续** —— 它证明 `D1.*`/`D2.2–2.4` 的模块真能加载，而不只是文件存在（风险 R1）。完成后 `Deuterium.md` 里「未验证」全部转 ✅。

**Step 11 · `Debug` 全量替换登记**：`grep -rl 'WaitForChild("Debug")' Deuterium | wc -l` 应等于 **18**。不改写这些文件（现路径已可用），只在 `AGENTS.md` 记：新代码一律 `require(ReplicatedStorage.Debug)`（不 `WaitForChild`），旧文件在各自被改动时顺手去掉。

**Step 12 · `D0.1` 收口**：`rojo build` + `lune run tests/run.luau` + `p0-check.sh`。
判据：`AC-D0.1` —— CI 四阶段全绿（含 `test`，不再是 `allow_failure`）。打 tag `v0.1.0-alpha`。

---

## 三、`D0.2`–`D0.5`（Step 13–16.5）

**Step 13 · `D0.2` `Dr.Core.Foundation` 补件**：`Metadata.luau`（提取 provider 形状供 `Inspector`）→ `Context.luau`（不可变键值袋，`Context.With(parent,k,v)` 返回新袋；`Kernel.contexts` 改用它）→ `EventLoop.luau`（`task.spawn` 封装，提供 `Run(fn)`/`Yield()`，便于 headless 替换）。
判据：`AC-D0.2` —— Metadata ↔ Reflection 互通；`Context.With` 不改父袋。

**Step 14 · `D0.3` Foundation 前置件（逐件「实现 + 单测」一次提交）**

| # | 文件（`Deuterium/` 下） | 关键接口 | 单测要点 |
| --- | --- | --- | --- |
| 14.1 | `Collections/Map/HashMap.luau` | `New/Get/Set/Has/Delete/Len/Iterate` | 冲突、扩容、删除后迭代正确 |
| 14.2 | `Collections/Map/LRUCache.luau` | `New(cap, onEvict)/Get/Set/Peek/Invalidate` | 逐出顺序 = 最久未用；`Get` 提升优先级；容量 0/1 边界 |
| 14.3 | `Collections/Sorted/PriorityQueue.luau` | `New(cmp)/Push/Pop/Peek/Len` | 同优先级 FIFO；与 `Tri.Request` 的 P0–P3 语义对齐 |
| 14.4 | `Collections/Linear/RingBuffer.luau` | `New(cap)/Push/Pop/Peek/IsFull/IsEmpty` | 满时**拒写不覆盖** + 指针回绕 |
| 14.5 | `Collections/Linear/Queue.luau` · `Set/Set.luau` | 常用集 | — |
| 14.6 | `Memory/Buffer/ByteBuffer.luau` | `New(size)/WriteU8..F64/WriteString/Read*/Seek/Len/Reset` | 越界**报错不静默**；`WriteString` 长度前缀；LE/BE 明确 |
| 14.7 | `Memory/Pool/ObjectPool.luau` · `TablePool.luau` | `New(factory, reset)/Acquire/Release` | 复用计数；Release 调 reset 且清引用 |
| 14.8 | `Concurrency/Sync/Mutex.luau` | `Lock()`/`Unlock()`/`WithLock(fn)` | 协程串行化；重入报错；等待者 FIFO 唤醒 |
| 14.9 | `Concurrency/Async/AsyncQueue.luau` | `Push/Pop/Close/Wait` | `Pop` 无数据时**让出**不忙等（断言 CPU 让出） |
| 14.10 | `Concurrency/Scheduling/TaskScheduler.luau` | `Schedule(delayMs, fn)/Update(nowMs)/Cancel` | 同刻多任务顺序稳定；`Update` 可被 headless **手动驱动**（关键：让定时逻辑可测） |
| 14.11 | `Concurrency/Async/Promise.luau` | `New/resolve/reject/AndThen/Catch/Await` | — |
| 14.12 | `Types/Primitives/{TypeChecker,TypeGuard,Branded}.luau` | `TypeChecker.IsX` 系列 | — |
| 14.13 | `Types/Validation/{SchemaBuilder,Schema,Validator,Coercion}.luau` | `Schema.String{max=}` / `Validator.Validate(schema, value) -> (ok, errs)` | 负例集 100% 拒绝；错误含列路径 |
| 14.14 | `Types/Transform/Codec.luau` | `Encode(value) -> string` / `Decode(str) -> value` | **I9 唯一 Codec**：round-trip 稳定；深度/循环引用报错；大小可预测 |

判据：`AC-D0.3` —— 每件三例；14.14 完成后 `Dr.Net.Processing.Serializer` 改为调用它（一次 `refactor(deut)`，Net SelfTest 必须仍绿）。

**Step 15 · `D0.3` 收尾 `Dr.Testing.Integration`**：`DataStoreSimulator.luau`（内存 KV + 配额 + 故障注入 `timeout`/`quotaExceeded`/`writeFail` + `RequestCount()`）与 `RequestAssert.luau`（`Exactly` / `AtMost`，失败打印实际调用栈）。签名必须与 Step 16 的 Proxy **完全一致**。
判据：注入 `quotaExceeded` 后被测代码走 fallback 而非抛错；`RequestCount` 与调用一一对应。

**Step 16 · `D0.4` `Dr.Runtime.Platform` 端口**：`DataStoreProxy.luau` · `MemoryStoreProxy.luau`（请求计数 + 配额节流 + 故障注入）。
判据：`AC-D0.4` —— `grep -rn 'GetService("DataStoreService")' Deuterium` 只命中这两个文件；代理与模拟器互换后上层测试无需改动。

**Step 16.5 · `D0.5` + `T0.5` 端到端纵切 —— 在写任何横向模块之前做**

新建 `tests/walkthrough.luau`，按序打穿：

```
SchemaStore（内存）→ TriSQL.Compile("CREATE TABLE t (id INT PRIMARY KEY, name TEXT)")
→ Compile("SELECT name FROM t WHERE id = 1") → IndexScan（内存 B+ 树）
→ PageManager（内存页）→ SimulatorPort → 读回断言
```

规则：允许内存占位与 `shortcut:`；**不做**持久化、事务、优化器。同时冻结 `INTEGRATION.md` §2 的四个接缝。

判据：`AC-D0.5` / `AC-T0.5` —— 链路在 Studio 与 CI 各跑通一次，断言 `SELECT` 返回插入值；产出 `.plan/SEAMS.md`（需正式化的接口 / 被证伪的设想 / 需新增的模块）；总耗时 ≤3 天。**这是横铺（Step 14 起正式化）的准入条件**（风险 R2）。

---

## 四、安全 / HA（Step 17–21）

**Step 17 · `D2.5`**：`PolicyEngine` → `CapabilityToken` → `Guard` → `Permission` → `Sanitizer` → `SchemaEnforcer` → `ContentFilter`。
判据：`AC-D2.5` —— RBAC 图 Init 期编译（运行期零解析）；非授权请求 100% 拒绝且原因结构化。

**Step 18 · `D2.6b`**：`TokenGenerator` → `Obfuscator` → `AuditLog` → `Fingerprint` → `AntiExploit` → `ThreatDetector` → `BanManager` → `SecurityDashboard`。
判据：`AC-D2.6b` —— 日志经 Scribe；禁令生效后重连被拒。

**Step 19 · `D2.7`**：`DataPrivacy` · `RateLimitPolicy` · `AbuseReporter` + 全链联调。
判据：`AC-D2.7` —— 作弊样本集 0 误放行；AuditLog 字段完整（txnId / 玩家 / 决策点）。

**Step 20 · `D3.1`（TritiumSQL 依赖，先做）**：`CircuitState` → `CircuitBreaker` → `CircuitRegistry`。
判据：`AC-D3.1` —— 关→半开→开状态机 + 锯齿边界（半开期多次失败/成功）用例过。

**Step 21 · `D3.2`（TritiumSQL 依赖，先做）**：`RetryPolicy` → `Timeout` → `Fallback` → `Bulkhead` → `Hedging`。
判据：`AC-D3.2` —— 重试曲线含 ±10% 抖动；`Hedging` 下副作用只发生一次（计数器断言）。

> `D2.0`（`Dr.Signal`）排在 Step 17 之前或与之并行，它是 `AC-D2.0` 的归属；不阻塞 Step 20/21。

---

## 五、`T0` 端口 · 目录 · Schema（Step 30–35）

> 前置：Step 14.14（Codec）· Step 15（Simulator）· Step 16（Proxy）已绿。

**Step 30 · `Tri/Runtime/RuntimeTypes.luau`**：按 `INTEGRATION.md` §2.1 的 `Port` 类型（含 `Stats.queued` 与 `SetLimit`）。
判据：`luau-lsp analyze` 通过；纯类型文件，无实现、无 `game`。

**Step 31 · `Tri/Runtime/Bindings/StandaloneBinding.luau`**：唯一允许出现 `DataStoreService` 的 TritiumSQL 文件，文件头加 `-- EXCEPTION(I10): 本文件是唯一的引擎 API 触点`。
判据：`grep -rn DataStoreService TritiumSQL` 只命中此文件 + `Tri/Testing/SimulatorPort.luau`。

**Step 32 · `Tri/Runtime/Bindings/DeuteriumBinding.luau`**：转发到 `Dr.Runtime.Platform.DataStoreProxy`。
判据：与 Standalone 跑同一份 `Tri/Testing/PortContract.luau`，结果一致。

**Step 33 · `Tri/Testing/SimulatorPort.luau`**：内存 Port + 请求计数 + 故障注入（不依赖 Deuterium 的 Simulator，保证可独立测试）。
判据：`PortContract` 三绑定全过。

**Step 34 · `Tri/Catalog/NamespaceCodec.luau`**：`Encode({db, table, partition, keyType, value})` / `Decode` / `AssertKey`。`tri:` 前缀；长值走 `#<8位>` 短哈希并登记 `tri:__catalog__:hashes`。
判据：`AC-T0` —— round-trip 1000 随机例唯一；任意输入 `#key <= 50` 恒成立；超长**自动哈希而非静默截断**。

**Step 35 · `SchemaStore` → `TableRegistry` → `Catalog`**（含 `Sequence`）。
判据：`AC-T0` —— 冷启动读请求数 == 表数（断言）；Schema 版本 +1 后旧行仍可读；Catalog 缓存失效路径有单测。

---

## 六、`T1` 请求管线与页（Step 36–43）

**Step 36 · `Tri/Request/RequestBudget.luau`**：令牌桶 + 计数，容量/速率来自 `Port.Stats()` 并可 `SetLimit`；**限额常量集中在此一个文件**（T13）。
判据：速率 10/min 灌 100 次 → 0 丢弃、排队、计数精确；三态（排队/键级节流/失败）各有用例。

**Step 37 · `RequestQueue.luau` + `BatchExecutor.luau`**：优先级 P0–P3（用 14.3 的 `PriorityQueue`），合并同表同类型读。
判据：P0 严格先于 P3（时间戳断言）；合并后请求数 < 合并前（量化）。

**Step 38 · 限额覆盖核对（真实环境一次）**：写 `scripts/probe-ratelimit.luau`，在 Studio 调 `DataStoreService:SetRateLimitForRequestType`，用压测确认 `RequestBudget` 读回的实际值与之致（数字已在 `SCALE.md` §1.3 核实，此处不再「实测上限」）。
判据：三态可区分；设限后实测速率与设定值一致；结果附日期回写 `SCALE.md` §1.3。

**Step 39 · `Tri/Storage/Page.luau` + `HeapLayout.luau`**：纯数据结构 + 插入/软删除/压缩/碎片统计，**不碰 IO**。
判据：4KB 页 ≥32 典型行；分裂后两页均 ≥40%；软删除后 `freeSpace` 正确回收（全内存断言，CI 可跑）。

**Step 40 · `Tri/Storage/PageManager.luau`**：`AllocPage/ReadPage/WritePage/SplitPage`，经 `Port` + I9 Codec。
判据：写 100 页 → 请求数 ==100（无额外读）；页分裂请求数 ≤5；`SetAsync` 失败注入后不产生半写页。

**Step 41 · `Tri/Storage/PageCache.luau`**：LRU（14.2）+ dirty 标记 + write-back on evict/commit。
判据：命中时 **0 次读请求**（断言）；逐出时 dirty 页被写回且计数正确；容量压到 1 仍正确。

**Step 42 · CRUD（`Tri/Storage/RowStore.luau`）**：`Insert/GetById/Update/Delete` 走 PageManager + PageCache。
判据：点查命中缓存 **0 次 DataStore 读**；未命中 ≤1 次；删除为软删除且不影响其他行。

**Step 43 · `T1` 收口**：1e3 行插入 + 1e3 点查总请求数 ≤ 目标预算（目标追加到 `SCALE.md` §1.3 之后）；CI 全绿；tag `tri-v0.1.0-alpha`。

---

## 七、`T2` B+ 树（Step 44–47）

**Step 44 · `Tri/Index/NodeCodec.luau`**：内部/叶子节点编解码 + 键比较器（number / string / timestamp 的确定性全序）。
判据：键全序单测（含 number 与 string 混排的拒绝路径）；节点 round-trip 稳定。

**Step 45 · `Tri/Index/BPlusTree.luau`**：`Search/Insert/Split/RootSplit/Scan`，根 ID 写回表元数据。
判据：`AC-T2` —— 1e4 行插入后点查**实际读次数 ≤ 树高**；分裂后父子键区间无空洞；树高 >3 触发告警。

**Step 46 · `Tri/Index/IndexScan.luau`**：点查 + 范围扫描，全程走 `prevLeaf/nextLeaf`。
判据：范围扫描不产生回父节点的读（断言读序列）；扫 100 行 ≤ 树高 + 1 次读。

**Step 47 · `Tri/Index/UniqueGuard.luau`**：插入前验唯一（依赖 `T3` 的 `LockManager`；未完成时用 14.8 的 `Mutex` 单进程占位并标注 `shortcut: 仅单进程唯一, T3 完成后换成行锁`）。
判据：并发两协程插同一唯一键 → 恰一个成功、一个返回明确冲突错误。

---

## 七点五、集成层（Step 50–57 / 60–65）

> 前置：Step 16.5 已产出 `SEAMS.md`，`INTEGRATION.md` §2 的四个接缝已冻结。
> 模块清单与逐模块 LOC 见 `INTEGRATION.md` §4；验收 `AC-G1`…`AC-G10` 见 §5。此处只给顺序与门禁。

| Step | 内容 | 判据 |
| --- | --- | --- |
| 50 | `Dr.Integration.Types` + `Capability` | 框架在 Tri **缺失**时仍能完整启动（`AC-G1` ①） |
| 51 | `Provider` + `Configuration` + `BootGate` | 人为打乱 Init 顺序时断言**必须失败**（`AC-G1` ②，负例） |
| 60/61 | `Tri.Integration.{Types, DeuteriumProvider, Config, Capability, Preload, PortBindings}` | 三绑定跑同一 `PortContract`；HA 包裹下断网 60s 不雪崩（`AC-G2`） |
| 52/53 | `Persistence/*` + `SagaBridge` | Saga 中断逆序回滚，会话态与关系表双双回到起点（`AC-G3`） |
| 62 | `ChangeLog` + `ChangeStreamApi` | 变更从提交路径发射，**不额外扫表**（请求次数断言，T12） |
| 54 | `Replication/*` | 100 行写入 → 客户端严格按 `lsn` 收到且幂等；断线 30s 用 `lastAck` 补齐；背压有上界（`AC-G4`） |
| 63/55 | `RowSecurity` + `Security/*` | **≥10 个越权攻击用例全部被拦** + 每次注入有审计（`AC-G5`，风险 R3） |
| 56 | `Net/*` | `schemaVersion` 不一致时拒绝解码（`AC-G6`） |
| 64/57 | `Scheduler` + `Telemetry` + `Observe/*` + `Ecs/*` | 算子 span 齐全；批量写满足预算（`AC-G7`/`AC-G8`） |
| 65 | `QueryApi` + `BootMigrator` | 端到端场景在 Simulator 与真实 DataStore 上结果一致（`AC-G10`） |

**两个集成硬门禁**

1. **I14 方向门禁**：`grep -rn 'Tri\.' Deuterium --include=*.luau | grep -v '^Deuterium/Integration/'` 必须为空，否则 CI 阻断。
2. **I15 锁顺序门禁**：`LockBridge` 对反序调用直接报错，写成负例测试（`AC-G9`）。

> 排期吃紧时砍 `Ecs/WorldPersist`（G7，600 行），**不砍 G4/G5**（合计 4,950 行，见 `INTEGRATION.md` §6）。

---

## 八、写每个 Step 的统一模板（Definition of Done）

1. `--!strict`，模块末尾 `return table.freeze(M)`。
2. 文件头注释：职责 + 对应 Wave + 引用的不变量编号。
3. 实现只依赖允许的层；新增 require 前自问「这一层允许吗」。
4. 非平凡逻辑配单测（分支 / 循环 / 解析 / 金钱或安全 / 请求计数）。
5. 已知限制写 `shortcut: <限制>, <何时升级>`（如 Step 47）。
6. 本地跑齐门禁：

```bash
stylua --check Deuterium TritiumSQL && selene Deuterium TritiumSQL \
  && bash scripts/p0-check.sh && lune run tests/run.luau
```

7. commit（Conventional Commits + `(step X.Y)`）→ 推分支 → CI 绿 → 更新本文件「进度登记」→ 开下一个 Step。

---

## 九、会话开工 / 收工流程

**开工**：读 `README.md` §4「关键路径」→ 找当前 Step → 复述该 Step 的判据与 AC → `git checkout -b feat/<scope>-<step>`。

**收工**：CI 绿 → 勾选「进度登记」→ 若产生新决策追加 `README.md` §3 决策登记（含状态）→ 若推翻假设，改对应 plan 文档（**不要只改代码**）→ 若发现新风险，追加 `README.md` §6 风险登记表。

**禁止**：跳过 Step 10 / Step 12 / Step 16.5；在 `test` 阶段为红的情况下开新 Step；在 `T3` 未完成前写 `T4` 的算子（依赖 WAL 的快照语义）。

---

未读/未验证：`rokit` 安装脚本 URL、`luau.load(..., {environment=...})` 确切签名、`globalTypes.d.luau` 取得方式 —— 三项都在 Step 7 与 Step 8 里做成了显式的「一次确认并固化」动作，未确认前不写死。风险：Step 8 的 CI 首次跑通可能需要一轮调试（镜像/网络），预算半小时。
