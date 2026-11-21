# 执行手册（Execution Steps）

> 把 Wave 拆成「动哪个文件 → 跑什么命令 → 什么算过」。
> **规则：WIP = 1。** 一个 Step 未达完成判据，不开下一个。
> 权威划分：不变量/门禁/决策/风险 → `README.md`；预算与功能面 → `SCALE.md`；互通接口 → `INTEGRATION.md`。

## Step ↔ Wave ↔ AC 对照

| Step | Wave | AC | 项目 |
| --- | --- | --- | --- |
| S1–S3 | — | — | 环境 |
| 1–12 | `D0.1` | `AC-D0.1` | Deuterium |
| 16.5 | `D0.5` + `T0.5` | `AC-D0.5` / `AC-T0.5` | 两端接缝（**spike，不入认证范围**） |
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
| **70–75** | **C1–C6** | **`AC-C1`…`AC-C6`** | **合规（阻断全部功能 Wave，见 `CERT.md`）** |

**保留号段**（预留给后续 Wave，不要复用）：`22–29` → `D4.x`–`D8`；`48–49` → `T3`（事务/WAL）；`58–59` → 集成收口；`66–69` → `T4`–`T11`；`76+` → 认证线的后续 Phase。

> **次序不是按编号排的。** Steps 70–71（C1–C2）要先于 Steps 7–12；完整交错图见「二点五」。

## 进度登记

| Step | 状态 | Step | 状态 | Step | 状态 |
| --- | --- | --- | --- | --- | --- |
| S1 ✅ S2 ☐ S3 ✅ | ◐ | 20 | ☐ | 44–47 | ☐ |
| 1–12 ✅ | ✅ | 21 | ☐ | 50–57 | ☐ |
| 13–15 | ☐ | 30–35 | ☐ | 60–65 | ☐ |
| 16 ☐ / **16.5 ✅** | ◐ | 36–43 | ☐ | — | — |
| 17–19 | ☐ | **70（C1）✅ · 71（C2）✅** | ✅ | — | — |
| — | — | **72（C3）✅ · 73（C4）✅ · 74–75（C5–C6）☐** | ◐ | — | — |

### 完成日志

| 日期 | Step | 结果 | 证据 |
| --- | --- | --- | --- |
| 2026-10-24 | S1 | ✅ 工具链就位 | `rokit list` 列出 5 工具；五个二进制直连 `--version` 均有输出 |
| 2026-10-24 | S3 | ✅ 分支约定生效 | `main` 有 git 守卫阻止直接提交（`git branch -b` + 分支提交已验证） |
| 2026-10-24 | **Step 1** | ✅ | `rokit.toml` 已提交（`chore(ci): pin dev toolchain via rokit`）；`rokit install` 幂等 exit 0 |
| 2026-10-24 | **Step 2** | ✅ | `rojo build` exit 0（174,927 B）；`rojo sourcemap` 的 ModuleScript 数 == 69 == `.luau` 文件数 |
| 2026-10-24 | **Step 3** | ✅ | 5 个文件 429 行；build exit 0；ModuleScript 75（含 Debug 双映射）；StructuredLog 在 Lune 实测通过 |
| 2026-10-25 | **Step 4** | ✅ | `.luaurc`；修正开关为 `--base-luaurc`（非 `--settings`） |
| 2026-10-25 | **Step 5** | ◐ | `stylua.toml` 逐键实测通过；`.gitattributes` 修行尾；**selene 已移除**（0.32.0 在 Luau 插值字符串上 panic 且无新版） |
| 2026-10-25 | **Step 5b** | ✅ | `scripts/p0-check.sh` 基线 26 / 48 / 0，棘轮生效 |
| 2026-10-25 | **Step 6** | ◐ | 22 个文件已格式化，`stylua --check` exit 0；p0 OK；luau-lsp 阻塞于 defs（Step 8） |
| 2026-10-25 | **Step 70（C1）** | ✅ | 危害/DAL/范围固化；预算 12,400→11,200+800；`ErrorHandler` 按 I16 净化（p0 棘轮 48→47）；**门禁 10 交付并自检 9/9** |
| 2026-10-25 | **Step 71（C2）** | ✅ | 7 份认证文档（PSAC/SDP/SVP/SCMP/SQAP/REQ-STD/TYPES）+ `docs/cert/README.md` 索引；分表目标数经三源核实并做自洽校验（53+9+9=71）；偏差 DV-1…DV-5 固化 |
| 2026-10-25 | **Step 7** | ✅ | `docs/headless.md`：`debug.sethook` 不可用（C4 改源码插桩）；拓扑序 setfenv loader 跑通；**真 SelfTest 8/8，修掉 3 个真 bug** |
| 2026-10-25 | **Step 9** | ✅ | `AGENTS.md` + `MEMORY.md`；Scribe 审计结论=**本仓库不存在**（与规格声明不符）；运行期外部依赖为零；**D6 关闭** |
| 2026-10-25 | **Step 10** | ✅ | 前提修正为 headless：10/10 SelfTest 的 `RunAll()` 在 Lune 里执行且通过 |
| 2026-10-25 | **Step 11** | ✅ | 判据过时：18 处已由 codemod 变为相对 require（17 + 1 带 WaitForChild），均不碰 game |
| 2026-10-25 | **Step 16.5** | ✅ | 纵切 36/36 断言；Spike 4 文件 + `tests/walkthrough.luau` + `.plan/SEAMS.md`；暴露 6 接口 / 4 证伪 / D12·D13 |
| 2026-10-25 | **Step 12** | ✅ | 四件套全绿 + tag `v0.1.0-alpha`（D0.1 收口） |
| 2026-10-26 | **第三方融合（Scribe/QuickZone）** | ✅ | 上游源码融合进 `src/ReplicatedStorage/{Scribe,QuickZone}/`（46+13 文件 / 48,611 行；Scribe **2.6.1**、QuickZone **1.5.1**，两者 MIT，各带 LICENSE）；新增审计器兼 I20 门禁 `scripts/thirdparty-audit.luau`（自检 5 组）+ 产物 `docs/thirdparty/{AUDIT.md,LOCK.txt,LICENSE…}`；**五步审计机器化关闭**（后门面 0 违规、1 处动态 require 登记为接受）；CI 接入；`default.project.json`/\\`rojo build\\` 不受影响；测试仍 PASS 10 · FAIL 0 · SKIP 0 |
| 2026-10-26 | **D0.6（①审计 ③门禁）** | ✅ | 见上一行；**剩余 ② 5 个适配器骨架**（随 D4.x/D6.6 落地） |
| 2026-10-26 | **Step 72（C3）** | ✅ | 需求基线 10 HLR + 12 LLR（4 个既有认证模块反向补需求）· 源码 12 处 `-- LLR-…` 注解 · 认证线用例 17 个 / 89 断言（独立 runner `tests/cert/run.luau`）· 门禁 11 `scripts/cert-trace-check.luau`（自检 1 正控 + 7 负例）· `docs/cert/{TRACE.md,verify/*}` 生成物 · CI 新增 `cert` job ；`AC-C3` 两条负例在真实仓库上证明 |
| 2026-10-26 | **Step 73（C4）** | ✅ | statement 覆盖工具（自研插桩器：源码插桩 + 括号深度 + 编译裁判）· 探针 P1–P8 · 门禁 12 · 范围 4 模块 **58/58 = 100.0%** · 插桩器自检 8 组（含它自己抓到的构造器注入 bug 回归）· R18 关闭 / R21 缓解 · 新工具事实 3 条入 MEMORY |
| 2026-10-25 | **Step 8** | ✅ | `.gitlab-ci.yml` 四阶段（本地逐条 exit 0）；`luau-lsp analyze` **首次真跑：TypeError 0**（经 MCP 找到 Cloudflare CDN 取到类型定义并 vendor）；抓到 **1 个真运行时 bug**（Debug 双映射 → 相对 require 指向错处） |
| 2026-10-25 | **Step 10 前置** | ✅ | 建好 `Configs/Deuterium/{init,FeatureFlags}.luau` + 映射（folder-module 布局，否则 `IsA("ModuleScript")` 或子节点二者必失其一） |
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

**Step 4 · `.luaurc`** —— 已完成（2026-10-25）。文件内容：

```json
{ "languageMode": "strict", "lint": { "*": true }, "lintErrors": true, "typeErrors": true }
```

**修正**：读取 `.luaurc` 的开关是 **`--base-luaurc`**，不是原计划写的 `--settings`（`--settings` 传的是 LSP-style settings，两回事）。已用 `luau-lsp analyze --help` 核实。

判据：待 Step 8（需 `globalTypes.d.luau` 才能真正 typecheck）；目前只确认文件存在且格式合法。

**Step 5 · `stylua.toml`（✅ 已完成）· `selene.toml`（❌ 已取消）**

```toml
# stylua.toml — 每个键都对 stylua 2.6.0 实测过（stylua 严格解析配置，未知键直接报错）
column_width = 110
indent_type = "Tabs"
quote_style = "AutoPreferDouble"
call_parentheses = "Always"
syntax = "Luau"
```

**selene 被移除**（不是跳过，是工具本身不可用）：

| 事实 | 证据 |
| --- | --- |
| selene 0.32.0 在 **Luau 反引号插值字符串**上 panic | 最小复现：只有 `local n = 7` / `` local s = `value={n}` `` 的文件 → `internal error: entered unreachable code`（full_moon 3.0.0 tokenizer）。纯 Lua / `+=` / `..=` 均正常 |
| 本仓库**到处**用插值字符串 | 既有 69 文件里 ErrorHandler/Kernel/FeatureFlags 全在用；Step 3 新增的 5 个文件中 3 个（StructuredLog/LogSink/SelfTest）触发了 panic |
| **无升级路径** | `api.github.com` 查到 selene 最新 release 就是 0.32.0 |
| 它的 roblox std 也不可用 | `std = "roblox"` 会在运行时拉 `raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/API-Dump.json`（第三方供应链 + 网络依赖），本环境代理也不通 |

**替代方案（已落到门禁 3）**：`luau-lsp analyze` 本身就跑 luau-analyze（**lint + 类型一次完成**），P0 正则规则交给 Step 5b 的 grep 基线脚本。结果：**工具少一个、供应链少一项、能力不降**。

**行尾陷阱（已修）**：`core.autocrlf=true` 且无 `.gitattributes` 时，工作区是 CRLF、索引是 LF，而 stylua 只输出 LF → `stylua --check` 对**每个文件**报全文 diff，门禁完全失效。已加 `.gitattributes`（`* text=auto eol=lf`）。另：`line_endings` 在 stylua 2.6.0 只接受 `Unix`/`Windows`（**没有 `Auto`**，实测报错），故不设它，靠 `.gitattributes` 把工作区刷成 LF。

**Step 5b · `scripts/p0-check.sh`** —— 已完成（2026-10-25）。统计热路径目录下 `table.insert(`、`game:GetService(`、`loadstring(` 的出现次数，与 `scripts/p0-baseline.txt` 比较（**棘轮：只允许下降**），并给 `--write-baseline` 重录。

基线（首次）：`table.insert(` **26** · `game:GetService(` **48** · `loadstring(` **0**。

判据（已达）：复跑退出码 0 并输出对照表。

> **副产品发现**：`Core/`+`Net/` 里有 **48 处 `game:GetService(`** —— 而 I10 要求引擎 API 只出现在 `Dr.Runtime`。这正是不变量 I10 要收敛的东西，也是 headless 测试难的根因（每个模块都在加载期碰 `game`）。不在本 Step 修，作为 `D0.4` 之后的固定项登记。

**Step 6 · 静态检查全绿** —— 部分完成（2026-10-25）。

| 门禁 | 结果 |
| --- | --- |
| `stylua --check Deuterium TritiumSQL` | ✅ exit **0**（第一次跑出 **22 个文件**需要格式化，已用一次 `style:` 提交格式化完毕） |
| `scripts/p0-check.sh` | ✅ OK（棘轮基线 26/48/0，格式化后未变） |
| `luau-lsp analyze` | ⏭ 阻塞于 `globalTypes.d.luau`（Step 8） |
| ~~`selene`~~ | ❌ 已移除，见 Step 5 |

**实测补充：原计划预判对了。** 代码本来确实是 tabs + 双引号，但仍有 22 个文件需要格式化——差异是**列宽 110 的换行**，例如 `DependencyInjector.luau`：

```lua
-- before
return { order = nil, error = `[Dr.DependencyInjector] {p.Name} depends on missing provider {dep}` }
-- after
return {
	order = nil,
	error = `[Dr.DependencyInjector] {p.Name} depends on missing provider {dep}`,
}
```

### ⚠ 方法论陷阱（很重要，差点让门禁假绿）

我第一次读到的结果是「0 个文件需要格式化」，**那是假的**：那一次 stylua 因为我写了个非法配置键（`line_endings = "Auto"`，2.6.0 只认 `Unix`/`Windows`）而 **exit=2 且无任何输出**，而我的判定命令是 `grep -c '^Diff in'` ——空输入自然得 0，于是“工具跑挂了”看起来像“全部合格”。

**规则：门禁的判定必须同时断言工具的退出码，不能只数输出行。** 这一条对 `scripts/p0-check.sh`（已用 `set -e` + 显式 exit 1）、Step 8 的 CI（`set -e` 逐条脚本）同样适用。已在 STEPS 的 DoD 里加一条：**工具返回非 0/非预期退出码 = 失败，即使没有输出**。

判据：以 **Step 8 的 CI 四阶段全绿**为最终判据。

**Step 7 · headless 探针** —— ✅ 已完成（2026-10-25）。完整结果固化在 **`docs/headless.md`**（25 项探针，三轮）。

**第二轮 + 第三轮实测（推翻了两条原计划假设，找到一条更好的路）**：

| 能力 | 结果 | 后果 |
| --- | --- | --- |
| `debug.sethook` | **不存在** | **行钩子覆盖路线作废**（原计划 C4 的机制） |
| `loadstring` + `setfenv` | 均可用 | **源码插桩 + 加载** 可行 |
| 文本插桩端到端 | **跑通**：插桩后 `f(4)=210`，命中行可报告，且能区分取/不取的分支 | C4 路线改为**源码插桩** |
| `luau` 库 / `_G` 当作全局表 | **都不行** | `luau.load(environment)` 路线作废；env 必须**显式拷标准库名** |
| 拓扑序 + `setfenv` + 恒等 `require` 加载真模块 | **跑通** | **Q1 从“不能”变为“能”**：`script.Parent` 模块可 headless 加载 |
| headless 跑真 SelfTest | **8/8 通过** | 门禁 2 从“应该有”变为“已证明可行” |

**最大副产品（写进门禁 2 的理由）**：把测试跑起来当场找到并修掉 **3 个真 bug** —— `Logger` 方法写成无 self 的闭包、调用方用冒号，导致 `self` 漏进 varargs（`log:info("a",1)` 的消息变成 `table: 0x…\ta\t1`，`log:SetLevel("debug")` 直接报 `invalid level: table`）。**之前没人跑过那 8 个用例** —— 未执行的测试不是测试，是注释。

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

**Step 8 · `.gitlab-ci.yml` 四阶段** —— ✅ 已完成（2026-10-25）。真实内容见仓库根的 **`.gitlab-ci.yml`**（上面的草稿已废弃）。

**四阶段全部已在本地逐条跑通**（命令与 CI 完全一致）：

| 阶段 | 内容 | 本地结果 |
| --- | --- | --- |
| `lint` | stylua --check · p0 棘轮 · 门禁 10 · 门禁 10 自检 | exit 0 / 0 / 0 / 0 |
| `types` | rojo sourcemap + **luau-lsp analyze** | **exit 0 · TypeError 0** |
| `build` | rojo build + artifact | OK |
| `test` | `lune run tests/run.luau` | PASS 1 · FAIL 0 · **SKIP 10** |

**解锁阻塞（用 MCP 查到）**：`luau-lsp analyze` 需要 `globalTypes.d.luau`，而 GitHub 直连被 reset。官方文档给出的**Cloudflare CDN**（绕开 GitHub 限流）可用：
`https://luau-lsp.pages.dev/type-definitions/globalTypes.None.d.luau`（302 到根路径，697,978 B）。已 **vendor 进仓库** `types/globalTypes.None.d.luau`（指纹记在 `MEMORY.md` §3.5）—— types 阶段因此**不联网且可复现**。选 `None` 安全级 = 游戏运行时。

**首次真跑类型检查抓到 5 类问题，其中 1 个是真运行时 bug**：

| # | 问题 | 性质 | 处置 |
| --- | --- | --- | --- |
| 1 | `Debug.luau` 被**双映射**到 `ReplicatedStorage.Debug`；副本的 `script.Parent` 是 `ReplicatedStorage`，于是它自身的 `require(script.Parent.Logger)` **运行时必然失败** —— 而 18 个文件 require 的正是这个副本 | **真运行时 bug** | 新增 DAL E 垫片 `src/ReplicatedStorage/Debug.luau`（允许绝对路径），真实现只在 Deuterium 树里映射一次 |
| 2 | `os.date("%H:%M:%S")` 违反 Roblox 定义（`os.date` 被声明为只收字面量 `"!*t"` 或 `"*t"`） | 类型定义限制 | 改用 `os.date("*t")` 自拼时分秒 |
| 3 | 同 2 的变体：`pcall(os.date, "*t")` 里字面量被**放宽成 `string`** | Luau 推断限制 | 包成闭包（闭包内直接调用保住上下文类型） |
| 4 | `SelfTest` 里 `pcall(StructuredLog.New, "info", …)` 同一机制 | 同上 | 同样包闭包 |
| 5 | `cert-scope-check.luau` 的 `trim(string.gsub(...))` 多传了一个返回值 | 真小错 | 双括号丢弃第二返回值 |

另两处属预期：`Configs/Deuterium/FeatureFlags` 缺失（已在 Step 10 前置建好）；`scripts/@lune/*` 是 Lune 宿主专属 require → `scripts/` 不进 analyze 范围（已写进 CI 注释）。

**一条值得记的教训**：同一源文件被 Rojo 映射两次时，它的 `script.Parent` 相对依赖会指向**两个不同地方**。新增顶层映射前先问「它的相对 require 还成立吗」。

判据（已达）：四阶段命令 exit 0；`test` 阶段**如实报告 SKIP 数**（10 个需 Studio 的 SelfTest 不被误计为通过）。

**Step 9 · `AGENTS.md` + `MEMORY.md`** —— ✅ 已完成（2026-10-25）。

`AGENTS.md`：仓库结构、7 条硬规则、**已验证的工具调用（含 5 个踩过的坑位）**、两条线不混、headless 怎么写、收工动作。
`MEMORY.md`：依赖审计留档 + 开发期工具链 + 网络/环境事实 + 本会话交付物清单。

**Scribe 审计的实测结论（与规格声明不符，必须记下）**：`Deuterium.md` §3 称「Scribe 已内置 `Libraries/Scribe`，⚠️ 待审计」，但**本仓库没有 `Libraries/` 目录，全仓 `grep Scribe` 命中 0 处**。→ 不存在则无可审计，无需五步流程；将来真正引入时再走。**运行期外部依赖目前为零**（Scribe/PlayerState/QuickZone 均无引用）。
判据：达成 —— 三行已填（含实测结论）；**决策 D6 关闭**。

**Step 10 · 全仓库 require 冒烟** —— ✅ 已完成（2026-10-25）。

**前提已修正**：原计划写「Studio 命令栏手工跑」，但仓库现在有 headless harness —— **10 个 SelfTest 的 `RunAll()` 全部在 Lune 里执行且通过**（含 `Testing/SelfTest` 这个聚合入口）。所以这一条进 CI（`tests/run.luau` 的引擎套件），不再依赖人工点 Studio。证据：全量套件 **PASS 10 · FAIL 0 · SKIP 0**，其中 `实际执行 10/10 · 通过 10`。

原文留档：**Step 10 · 全仓库 require 冒烟**（Studio 命令栏）

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

**Step 11 · `Debug` 全量替换登记** —— ✅ 已完成（2026-10-25）。

**判据已过时**：pass 1 的 codemod 把 18 处遗留调用改成了**相对 require** —— 实测现在是 **17 个文件用 `…Parent.Debug` 相对路径 + 1 个（`Runtime/Interop/SelfTest`）保留 `:WaitForChild("Debug")`**，两者指向同一个 `Debug` 节点，且**都不再碰 game**（这正是它们能被 headless 装载的原因）。规则已落在 `AGENTS.md`：新代码一律 `require(ReplicatedStorage.Debug)`，旧文件在被改动时顺手去掉 WaitForChild。

原文留档：**Step 11 · `Debug` 全量替换登记**：`grep -rl 'WaitForChild("Debug")' Deuterium | wc -l` 应等于 **18**。不改写这些文件（现路径已可用），只在 `AGENTS.md` 记：新代码一律 `require(ReplicatedStorage.Debug)`（不 `WaitForChild`），旧文件在各自被改动时顺手去掉。

**Step 12 · `D0.1` 收口** —— ✅ 已完成（2026-10-25）。四件套全绿 + tag `v0.1.0-alpha`。

原文留档：**Step 12 · `D0.1` 收口**：`rojo build` + `lune run tests/run.luau` + `p0-check.sh`。
判据：`AC-D0.1` —— CI 四阶段全绿（含 `test`，不再是 `allow_failure`）。打 tag `v0.1.0-alpha`。

---

## 二点五、DO-178C 认证线（Step 70–75）—— **阻断全部功能 Wave**

> 权威：`.plan/CERT.md`。本节只说**何时做、门槛是什么**。
> 硬规则（`CERT.md` §9.1）：**C1–C3 完成前，不得新建任何认证范围内的文件** —— 而 `D0.2`/`D0.3` 的前置件（Foundation/Collections/Memory/Concurrency/Codec）**全部落在认证范围内**（`CERT.md` §3.1），所以它们必须等 C3。

### 正确的交错次序

```
Steps 1–6 ✅  D0.1 工具链（已完成）
   ↓
Step 70–71    C1 危害分析/DAL 固化  →  C2 五份计划 + 需求标准      ← 纯文档，不依赖 CI
   ↓
Steps 7–12    D0.1 收口（headless 探针 / CI 四阶段 / AGENTS+MEMORY / 冒烟）
   ↓  门禁 10–12 在这里获得宿主
Step 72–73    C3 需求基线+追溯生成器  →  C4 覆盖工具（先做成功性探针）
   ↓
Step 74–75    C5 工具鉴定登记 + stylua 只读化  →  C6 配置管理机制化
   ↓
Step 13+      D0.2 / D0.3 起（认证范围内的模块，此后每件先有 LLR）
```

| Step | Wave | 交付 | 判据（`AC-C*`） |
| --- | --- | --- | --- |
| ~~70~~ | **C1** ✅ | 已完成：`docs/cert/HAZARD.md`（H1–H7 × DAL × 资产 × 模块）+ `docs/cert/scope.txt` + **门禁 10 实现** `scripts/cert-scope-check.luau` | `AC-C1` 6/6（见 HAZARD.md §7） |
| ~~71~~ | **C2** ✅ | 已完成：`docs/cert/` 7 份文档 + 索引；`PSAC.md` §4 的分表目标关闭表（含自洽校验）；`REQ-STD.md`/`TYPES.md` 两份工作标准 | 五份计划互不矛盾 ✅；目标**按表**标注（行级编号需标准原文，已声明未达成） |
| — | — | 插入 Steps 7–12（D0.1 收口）与门禁 10–12 宿主 | — |
| 72 | **C3** ✅ | **已交付（2026-10-26）** —— ① `docs/cert/req/<MOD>.md` ×4（10 HLR / 12 LLR，反向补需求）② 源码 12 处 `-- LLR-…` 注解 ③ `tests/cert/cases/<MOD>.luau` ×4（17 用例 / 89 断言）④ `tests/cert/run.luau` → `docs/cert/verify/<MOD>.md` ⑤ `scripts/cert-trace-check.luau`（门禁 11）→ `docs/cert/TRACE.md`；CI 加独立 `cert` job | `AC-C3` **在真实仓库上证明**：去掉测试 → `UNTESTED_REQ`；加无注解代码 → `UNSOURCED_CODE`；还原 → 0 违规。**方向④（需求→覆盖）留 C4** |
| 73 | **C4** ✅ | **已交付（2026-10-26）** —— 探针 `scripts/probe-coverage.luau`（P1–P8，实测：sethook 无 / @lune/luau 无 parser 与覆盖 / loadstring 会抛 / _G 空 / 构造器陷阱）；插桩器 `scripts/instrument.luau`（纯函数 + 可注入编译谓词）；工具 `scripts/coverage.luau`（跑认证线用例 → `docs/cert/coverage/<MOD>.json`）；登记表 `docs/cert/coverage/UNCOVERED.md` | `AC-C4`：范围 4 模块 **58/58 = 100.0%**；插桩器自检 8 组；未覆盖行 0（有则必须登记理由） |
| 74 | **C5** | 工具鉴定登记逐条关闭；`stylua` 在认证范围只跑 `--check`（只读）；加 AST 等价性检查 | 每件工具有 TQL 判定与理由；无一件“默认免鉴定” |
| 75 | **C6** | 基线 / 问题报告 / 状态记帐自动产出 | `BASELINE.md`/`PROBLEMS.md`/`STATUS.md` 由 CI 生成；改一个认证范围文件能触发变更控制 |

### 三条交互规则（容易搞错）

1. **纵切（Step 16.5）是 spike，其代码一律不入认证范围。** 允许写，但只能落在非认证路径（如 `TritiumSQL/Tri/Spike/`），事后删除或标注 DAL E。
2. **既有 `SelfTest` 不得作为认证证据**（`CERT.md` §9.2）。两条线的报告分开存放，不得合并。
3. **认证线不并行产品线**：`SCALE.md` §2.1 的结论是认证线独立交付 6–10 个月。并行只会让两边都不达标。

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

**Step 16.5 · `D0.5` + `T0.5` 端到端纵切** —— ✅ 已完成（2026-10-25）。

| 产物 | 说明 |
| --- | --- |
| `TritiumSQL/Tri/Spike/{SpikePort,SpikeStore,TriSQL,Walkthrough}.luau` | 内存版全链（DAL E、非认证范围、**零引擎依赖**） |
| `tests/walkthrough.luau` + `tests/run.luau` 同名套件 | 两个入口；**36/36 断言通过**，进 CI |
| `.plan/SEAMS.md` | 接缝清单：**6 条需正式化的接口 · 4 条被证伪的设想 · 2 个待拍板决策（D12/D13）** |

关键结果：Port 形状够用 · 请求次数可计量（INSERT = **2** 次端口请求）· I11 可断言 · **跨项目依赖 Tri→Dr.FOUNDATION 在 Rojo 与 headless 下都成立** · 点查不退化成全扫 · 键长 50 可达。

**它改动了两处规约**（已回写 `TritiumSQL.md` 的 `AC-T1`）：页容量改为**按字节**断言（F1）；新增「端口写失败必须回滚内存态」（F2）。

原文（链路定义）：

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
6. 本地跑齐门禁，**并检查退出码**（工具非 0 退出 = 失败，即使没有输出）：

```bash
stylua --config-path stylua.toml --check Deuterium TritiumSQL \
  && bash scripts/p0-check.sh \
  && luau-lsp analyze --sourcemap=sourcemap.json --base-luaurc=.luaurc Deuterium \
  && lune run tests/run.luau
```

7. commit（Conventional Commits + `(step X.Y)`）→ 推分支 → CI 绿 → 更新本文件「进度登记」→ 开下一个 Step。

**若该文件落在认证范围内（`CERT.md` §3.1），额外四项（门禁 10–12）：**

8. **先有 LLR**（I18）—— 先写 `docs/cert/req/LLR-<module>.md`，再写代码。
9. **需求 ID 写进代码注释**：每个导出函数头上标 `-- LLR-<MOD>-nnn`，追溯生成器靠它建矩阵。
10. **不依赖非认证代码**（I16）：`grep` 守卫通过。
11. **声明本文件的 DAL**（DAL C 或 D），并保证 statement 覆盖报告能覆盖到它。

> 认证线不适用本文的“先实现再补测”：门禁 11 要求需求→代码→测试→覆盖四向可追。

---

## 九、会话开工 / 收工流程

**开工**：读 `README.md` §4「关键路径」→ 找当前 Step → 复述该 Step 的判据与 AC → `git checkout -b feat/<scope>-<step>`。

**收工**：CI 绿 → 勾选「进度登记」→ 若产生新决策追加 `README.md` §3 决策登记（含状态）→ 若推翻假设，改对应 plan 文档（**不要只改代码**）→ 若发现新风险，追加 `README.md` §6 风险登记表。

**禁止**：跳过 Step 10 / Step 12 / Step 16.5；在 `test` 阶段为红的情况下开新 Step；在 `T3` 未完成前写 `T4` 的算子（依赖 WAL 的快照语义）。

---

未读/未验证：`rokit` 安装脚本 URL、`luau.load(..., {environment=...})` 确切签名、`globalTypes.d.luau` 取得方式 —— 三项都在 Step 7 与 Step 8 里做成了显式的「一次确认并固化」动作，未确认前不写死。风险：Step 8 的 CI 首次跑通可能需要一轮调试（镜像/网络），预算半小时。

---

## 附：零调用方清单（backlog，由全量复审登记）

> 规则（AGENTS.md §6.5）：**未被执行过的路径不算证据**。这些导出目前无调用方，但属计划中声明的 API，
> 因此**登记保留**而非删除；它们各自被接线时必须同时补用例。

| 导出 | 位置 | 处置 |
| --- | --- | --- |
| `ScopeContainer.New` | `Core/Container/ScopeContainer.luau` | 保留（Bulkhead 隔离单元，待 `D4.x`） |
| `ModuleLoader.LoadProviders` | `Core/Lifecycle/ModuleLoader.luau` | 保留（`D0.5` 纵切后接线） |
| `HotReload.IsEnabled` / `Watch` | `Core/Lifecycle/HotReload.luau` | 保留（Studio 工装） |
| `ServiceContainer.Has` · `ServiceRegistry.Has/Count` | `Core/Container/*` | 保留（容器查询 API） |
| `TestRunner.RunAll` | `Testing/TestRunner.luau` | 保留（门禁 1 约定 `RunAll` 入口） |
| `TestContext.note` | `Testing/TestContext.luau` | 保留（报告细节） |
| `InstanceTracker.ReleaseAll` | `Runtime/Platform/InstanceTracker.luau` | 保留（ShutdownManager 安全网，待接线） |
| `UnreliableChannel`（整模块） | `Net/Core/UnreliableChannel.luau` | 保留：文件头自述“当前与 Channel 同一注册表，待 W2.5 换 UnreliableRemoteTransport” |


---

## 2026-11-21 · P2.W1 + P2.W2（`Neon` 立项：打印入口 + 输出端与环形缓冲）

- 新增 `src/ReplicatedStorage/Neon/`：`Level` · `Record` · `Publish` · `Sink` · `RingSink` · `Channel` · `Neon` 七个核心模块（实测 **833** 行，预算 1.3k）+ `SelfTest.luau`（**471** 行、**19** 例，全部 headless）。
- 发射路径只有一个 owner（`Publish.Emit`）：入口与 `Channel` 记录器共用，避免「两处校验不一致」。
- 三条语义钉死：记录是调用时刻快照且冻结；未登记级别抛错而非降级；级别过滤不属于 `Sink`（归 `P2.W4`）。
- 接入门禁：`tests/run.luau` 加 `Neon.Core` 套件；`scripts/ci.sh` 的 `types` 步骤把 `src/ReplicatedStorage/Neon` 纳入 `luau-lsp analyze`（照 ci.sh 原注释的指示「组件立项后把目录加到这一行」）；`AGENTS.md` 的本地复用清单同步。
- `Neon` 零依赖、L0 不碰引擎：`grep -rn "game:\|game\.\|GetService(\|workspace\|Instance.new(\|task\." src/ReplicatedStorage/Neon/*.luau`（剔注释后）为空。
- 门禁反馈实录（同一个 Wave 内跑了 4 轮 CI 才绿，记下来免得后人当成环境噪声）：`math.type` 在这个 Luau 构建里不存在（类型与运行期同时报）；`pcall` 保护一个不返回值的函数时，类型系统只给一个 boolean，接不住 `err`；可变表字段上的字符串字面量被放大成 `string`，于是 `Record.New(Level.Info, …)` 反而过不了 strict —— 改成「运行时 `Level.Rank` 校验 + 记录字段仍标 `Level.Level`」；`Dropped` 早先算成 `written - count`，把 `Reset()` 清掉的条数记成了丢失，被自己的自检当场抓住。
- 待办：`P2.W3` 格式化 · `P2.W4` 过滤与限速 · `P2.W5` 命令 · `P2.W6` `Host/StdSink` · `P2.W7` 控制台界面 · `P2.W8` 迁移（基线 `OUTSIDE` 20 → ≤3）。


---

## 2026-11-21 · P2.W3（`Neon` 格式化）+ 打印热路径收敛

- 新增 `src/ReplicatedStorage/Neon/Format.luau`（实测 **396** 行，预算 0.7k）：`Format.Line` / `Value` / `Time` / `SetLimits` / `Limits` / `Reset`。核心 8 模块合计 **1264** 行，`SelfTest.luau` **709** 行 **32** 例（新增 13 例）。
- 钉住的语义：渲染只依赖记录本身（不读时钟、不印地址、按键排序）⇒ 同一记录两次渲染逐字节相同；循环判定只看当前递归路径（兄弟位置重复出现照常展开）；截断标 `(+N)` 且省略号计入上限；控制字符转 `\n\r\t`；时间戳走 UTC 且自己做算术；四项上限非法值抛错、先全校验后赋值、`Limits()` 返回冻结快照、`Reset()` 给夹具复位。
- 两处优化（各有用例）：`Sink.Broadcast` 零输出端返回共享的冻结 `EMPTY_RESULT`、`errors` 惰性分配（happy path 零分配）；「可打印标识符」的判定统一成 `Record.IsOneLine`（`Record.New` / `Channel.New` / `Sink` 的 name 三处原本是三份各写一个 `[\r\n]` 模式，现在两条定长 `find` 短路，且它在每条记录上都要跑）。
- **CI 打回 3 轮的根因实录**（本地无 Lune，`types`/`test` 只能靠 CI，所以每条都得有明确的复现方式才敢改）：
  1. `test` 6 例红。三处是**代码**错：字符串渲染少一个收尾引号（`${...}` 手改时丢了 `"`）；折叠摘要写 `<table:{#value}>`，而 `{a=1,b=2}` 的 `#` 是 0 ⇒ 摘要说「下面有 0 个」正是它唯一要说的事说反了，改成数键、数到 64 就报 `64+`；`Format.Line` 漏了频道（文件头的示例格式里有，实现里没有 —— 文档与实现各写一次必然漂移，这里以文档为准补实现）。
  2. 一处是**测试**错：给冻结表赋值断言错误文本含 `frozen`，而措辞归运行时（Lune 与 Studio 不同）。规则：只断言「抛了错」，不断言运行时的报错句式。
  3. `types` 红两连：`local errors: { string }? = nil` 靠 `~= nil` 判别，赋值后类型不收窄，`table.insert` 报 `Expected {string} but {string}?` ⇒ 非空类型 + 独立 `ownErrors` 旗标；`os.date("!%H:%M:%S", …)` 在本仓 vendor 定义里只声明 `"*t"`/`"!*t"` ⇒ 弃用 `os.date`，时间戳取模算时分秒（顺带省掉每条日志一次宿主调用，`P1` 复审时 `StructuredLog` 也撞过同一条，见上文门禁反馈表第 2 行）。
- 待办：`P2.W4` 过滤与限速 · `P2.W5` 命令 · `P2.W6` `Host/StdSink` · `P2.W7` 控制台界面 · `P2.W8` 迁移（基线 `OUTSIDE` 20 → ≤3）。


---

## 2026-11-21 · P2 加固轮（`Neon` W1–W3 复审，无新 Wave）

- 用户选定的下一步不是 `W4` 而是「先给已落的 W1–W3 再做一轮加固」，所以这一轮只改**有具体失效方式**的地方，不做风格性重写。
- **控制字符整类处理**（`Format.toSingleLine` + `Record.IsOneLine`）。原先正文只折叠 `\n\r\t`、标识符只挡 `\n\r`。漏掉的码位各有后果：正文里一个 `\0` 让 grep / ripgrep 把整份日志文件判成二进制并**停止打印匹配行**（症状与「日志没打出来」完全一样，而 CI 的按行断言会静默漏检），一个 `\027[` 让终端执行日志内容里的 ANSI 序列。现在正文里 `%c` 一律转成 `\n`/`\r`/`\t`/`\xNN`，标识符里 `%c` 直接抛错；判据仍只有一份（`Record.IsOneLine`，三处共用）。代价持平：一次 `%c` 单遍扫描 vs 原先两到三遍 plain find。
- **`maxDepth` 拆不掉了**：`math.floor(math.huge) == math.huge` 成立，所以「整数 + 下界」的校验会把 `+inf` 放成合法上限，而无穷深度 = 折叠被关掉 = 一个几千层的表（反序列化出来的链式结构）把宿主 Lua 栈撑爆 —— 那种失败连测试报告都留不下。现在四项都必须是有限数，`maxDepth` 另有 `MAX_DEPTH_LIMIT = 32` 上界。
- **`RingSink.Records()`**：写明并测「返回的是快照」（W7 的控制台要攥着这份数组跨帧渲染），同时把每元素的 `table.insert` 换成自己数下标（数组已按 `count` 预分配，`table.insert` 每次还要回头量长度）。
- 新增 5 例（共 **37** 例）：控制字符电池（`Format.Value` 与整行都不许残留裸控制字符）、`(+N)` 按渲染后字节计（钉住转义放大这条规则，`(+5)` 是手算出来的）、标识符拒 NUL/ESC/TAB、`maxDepth` 的 `+inf`/`nan`/过大值三例 + 200 层深表「不炸且被折叠」、`Records()` 快照。核心 8 模块 1264 → **1292** 行。
- 本轮 CI 一次过（5/5 全绿，run `44869251878`）。与上一轮「三轮才绿」的差别不在运气：这一轮每处改动都在本地把手算的期望值写进用例（例如 `(+5)` 的推导：4 个换行 → 8 字节渲染 → 上限 6 含省略号 3 字节 → 留 3 → 丢 5），凡是「得跑一遍才知道实际文本」的断言一律不写。
- 记下的下一轮候选（本轮判定为不做，避免与加固混在一个改动里）：`Level.Describe` 仍按字节截 40（中文会切半个字，影响的是报错可读性，不影响判据）；`Format.Value` 对纯数组打的是 `{1="a", 2="b"}`，是否改成 `["a", "b"]` 属格式取向问题，留给 `W4` 之前一起定；`Sink.Snapshot()` 交出去的是活引用（文档已写明，测试要的就是它）。
- 待办：`P2.W4` 过滤与限速 · `P2.W5` 命令 · `P2.W6` `Host/StdSink` · `P2.W7` 控制台界面 · `P2.W8` 迁移（基线 `OUTSIDE` 20 → ≤3）。


---

## 2026-11-21 · P2.W4（`Neon` 过滤与限速）

- 新增 `src/ReplicatedStorage/Neon/Filter.luau`（实测 **379** 行，预算 0.6k）：全局与每频道最低级别、每频道每秒配额、连续重复折叠。核心 9 模块 **1292 → 1719** 行，`SelfTest.luau` **1075** 行 **48** 例（W4 新增 **11** 例）。
- 挂点只有一个：`Publish.Emit` 在构造记录**之前**问 `Filter.Judge`，所以入口 `Neon.Log` 与 `Neon.Channel` 记录器一起生效（发射路径本来就只有这一个 owner，W1 立这条就是为了今天）。`Sink.Write` 仍然不做过滤 —— 那条边界由 W1/W2 的用例看着。
- 四条钉住的语义：① 过滤只改投递、不改 API 形状（被挡掉的记录照样构造并返回，否则「改一行配置」变成全工程搜索替换）；② 计数不新造记录也不改冻结记录，`repeated` / `rateDropped` 随同频道**下一条真正投递的**记录带出，没有下一条就在 `Filter.Stats()` 里；③ 折叠优先于限速，一条不被记两次账；④ 时间只从 `Record.Now()` 取（W1 的注入点），所以「1 秒内 1000 条相同消息只输出 1 条」在假时钟下是确定的。
- 两处护栏：`Neon.Enabled(level, channel?)` 只读门槛、**不消费配额**（探测一次就吃掉一格的话，加守卫反而让日志更少）；每频道状态最多跟踪 256 个频道，超出的退回只走全局门槛并把 `untrackedChannels` 如实报出来 —— 频道名可以是 `player:78` 这种按人现造的，不设上限就是「日志内容决定内存占用」。
- **CI 反馈**：`test` 一次过（11 例的期望值全部手算：限速那条推的是「同秒第 4、5 条 + 100.9 的同一秒第 6 条 → 3 条被限速」，所以计数字段是 `rateDropped = 3`）。`types` 打回两轮，同一个根因的上下半截：`Level.Trace` 这类常量字段在调用点是 `string`（`Level.luau` 早就记过），我按老办法写 `local TRACE = Level.Trace :: Level.Level` 仍红 —— **没有标注的 local 会把 cast 的结果再摊平一次**。修法两边都占住：`local TRACE: Level.Level = Level.Trace :: Level.Level`，之后各处用 `TRACE` 不再重复 cast。这条已回写进 `Level.luau` 的文件头，免得第三次踩。
- 待办：`P2.W5` 命令 · `P2.W6` `Host/StdSink` · `P2.W7` 控制台界面 · `P2.W8` 迁移（基线 `OUTSIDE` 仍是 **20** → ≤3）。上一轮记下的两个待决项（`Level.Describe` 的 UTF-8 边界、纯数组的渲染风格）仍未做。


---

## 2026-11-21 · P2.W5（`Neon` 命令系统）

- 新增 `src/ReplicatedStorage/Neon/Command.luau`（实测 **639** 行，预算 0.7k）：`Register` / `Remove` / `Names` / `Count` / `Complete` / `Help` / `Parse` / `Run` / `SetPermissionHook` / `Stats` / `Reset`。核心 10 模块 **1719 → 2371** 行，`SelfTest.luau` **1075 → 1506** 行、**48 → 63** 例（W5 新增 **15** 例）。
- 判据落点：引号不闭合、缺参数、类型不符、`nan`/`inf`、参数过多 → 全部返回一行错误文本而不抛错（`第 6 字节`这种位置要能给出来，未知命令顺带列前缀候选）；越权与「钩子自己抛错」都按拒绝处理；`help` 与补全从注册表生成并按键排序（与注册顺序无关，两次调用逐字节相同）；handler 抛错转错误文本且其余命令照跑；三类失败分开记账（`rejected` / `denied` / `errored`）。
- 解析单独导出 `Command.Parse`：「畸形输入不抛错」这条判据属于**纯函数**层 —— 手算期望值才不会因为顺手跑了一条命令而把 `Stats()` 的账改脏；`P2.W7` 的控制台在回车之前也先用它判断这一行值不值得执行。
- 三处形状决定（详版在 `Neon/README.md` 决定 10–12）：运行不抛、注册必抛；错误文本按**尾巴**截断（`errorText`，控制字符整类换空格 + 上限 240 字节 + 掐掉切坏的 UTF-8 续接字节）；`Neon.Reset()` 不清命令注册表。
- **CI 反馈**（run `44913132363` 最终 5/5 全绿）：`test` 一次过，15 例的期望值全部手算（`第 6 字节`、`alpha,help,mid,zeta`、`hi bob`、`<1 个参数>`）。`types` 打回两轮，都不是老毛病：
  1. `kind: "string" | "number" | "boolean"` 在 8 个注册点各报一条同形错误 —— 字符串字面量嵌在**表字面量**里就被摊平成 `string`，而期望类型穿过 `{ArgSpec}?` 这种可选 union 字段时不会传到嵌套元素。改成「类型收 `string` + 注册期用 `KINDS` 挡」（与 `Record.New(level: any)` 同一口径），`ArgKind` 只作为对外别名留下。
  2. 兄弟元素字段不齐的 args 数组：Luau 是在**兄弟之间**统一元素类型（不是拿 `ArgSpec` 逐个判）→ 少一个字段报 missing field；而按直觉把 `default = nil` 抄齐更糟 —— 第一个元素的 `default` 被定成类型 `nil`，第二个的 `default = 1` 就「Expected this to be exactly nil, but got number」。可靠写法只有一种：给数组本身显式标注 `local specs: { Command.ArgSpec } = { ... }`。
- 校准一条旧口径：`{ [string]: any }?` 的局部配 `args ~= nil and args.k` **能**收窄（本轮 CI 绿）。上一轮记的「已赋值的可选局部不收窄」只适用于 `{ T }` 那种数组形状，别当万能挡箭牌用。
- 两处工具性坑（都是这一轮现场撞上的）：`write_file` 在 `--[=[ ]=]` 文档块里留下 19 行字面 `\t`；Python 补丁串里的 `"\128"` 被当成八进制 `\12` + 字面 `8`，把一条中文注释从中间截成两行 —— 症状是 stylua 报 `unexpected token \`8\`，expected \`end\` to close function body block` 这种完全读不出原因的形态。写含字节转义的补丁一律用 raw 串或 `\xNN`。
- 待办：`P2.W6` `Host/StdSink` · `P2.W7` 控制台界面 · `P2.W8` 迁移（基线 `OUTSIDE` 仍是 **20** → ≤3）。两个老待决项（`Level.Describe` 的 UTF-8 边界、纯数组渲染风格）仍未做；`Level.Describe` 按头截 40 字节这件事现在只影响报错可读性，`Command` 已经绕开它。
