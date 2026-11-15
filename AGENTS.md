# AGENTS.md — 在本仓库工作的约定

> 面向 AI agent 与人类协作者。**先读这里，再读 `.plan/CARBON.md`。**
> 本仓库是 **Carbon**：19 个平级组件的综合基础设施（总图 `.plan/CARBON.md`）。本文件写于 Carbon 之前，2026-11-14 按 Carbon 更新了 §1、§3 的开头和第三方规则；其余小节仍是旧内容，仍然适用。
> 本文件只管「怎么做」；「为什么」在 `.plan/`，合规证据在 `docs/cert/`。

---

## 1. 这是什么

| 位置 | 内容 |
| --- | --- |
| `src/ReplicatedStorage/<组件>/` | **19 个 Carbon 组件**，每个一个目录。清单、层次、依赖、预算在 `scripts/carbon-manifest.luau`；17 个新组件目前只有 `README.md` |
| `src/ReplicatedStorage/Deuterium/` | 框架（微内核/生命周期/网络/会话态/复制/安全） |
| `src/ReplicatedStorage/TritiumSQL/` | 数据库引擎（页/B+树/事务/WAL/查询） |
| `src/ReplicatedStorage/Configs/` | 项目配置（`Deuterium/init.luau` folder-module + `FeatureFlags.luau`） |
| `src/ReplicatedStorage/Debug.luau` | 遗留 require 垫片（绝对路径）——见本文件 §5 |
| `example/` | **只作参考的第三方库**：Scribe、QuickZone 的原件与审计文档。不随 Carbon 发布，**任何组件不得 require** |
| `src/ServerScriptService/` | 服务端专属（认证范围之外） |
| `.plan/` | **计划层**：不变量 · 门禁 · 决策 · 风险 · 排期 · 执行步骤 |
| `docs/cert/` | **DO-178C 认证线证据**（DAL C，≤12k 行子集） |
| `docs/headless.md` | headless 能力基线（测试与覆盖怎么做） |
| `scripts/` · `tests/` · `types/` | 门禁脚本（Lune/bash）· headless 测试入口 · vendor 的 Roblox 类型定义 |

> **组件之间的四条规则**（`scripts/carbon-deps-check.luau` 强制）：① 只能 require 更低层、且在清单里声明过的组件；② 同层组件与端口依赖只能在 `<组件>/Integration/` 里接线；③ L0 组件（`Platinum`/`Tin`/`Krypton`/`Neon`）不得触碰引擎；④ 不得 require Scribe/QuickZone，组件根目录下不得出现清单外的条目。既有违规登记在 `scripts/carbon-deps-baseline.txt`，只许减少。
> **`Host/` 规则（门禁已强制，`.plan/CARBON.md` §3.2）**：引擎 API 只许出现在每个组件自己的 `Host/` 目录（`Deuterium` 是既有的 `Runtime/`）；核心代码只认宿主接口，不得 require 自己的 `Host/`。新写的代码现在就按这条来。
> 每个组件的功能块划分见 `.plan/COMPONENTS.md`；按什么顺序做、每一步的判据见 `.plan/PHASES.md`（当前在 Phase 1）。

**阅读顺序**：`.plan/CARBON.md`（总图，冲突时以它为准）→ `.plan/README.md`（不变量与门禁的定义）→ `.plan/STEPS.md`（当前该做哪一步）→ 需要动某一层时读对应的 `Deuterium.md` / `TritiumSQL.md` / `CERT.md`。

## 2. 硬规则（违反会被 CI 或评审挡住）

| # | 规则 | 强制方式 |
| --- | --- | --- |
| 1 | **禁止直接提交 `main`** | git 守卫会拒绝；必须开分支 |
| 2 | commit subject **≤72 字符** | git 守卫 |
| 3 | **一次只推进一个 Step**（WIP=1） | `STEPS.md` 的规则；Step 未达判据不开下一个 |
| 4 | 认证范围（`docs/cert/scope.txt`）内的文件**不得**碰 `game`/网络/非认证层，且依赖必须在范围内 | 门禁 10（含依赖闭包 + 自检） |
| 5 | 认证范围内**先有 LLR 再写码** | I18；门禁 11（待 C3） |
| 6 | 声明"完成"必须给**可复现的命令与结果**，不能只给结论 | 评审 |
| 7 | **工具非 0 退出即失败，即使没有输出** | 曾把 `stylua` 的 `exit=2`＋零输出误读成"全部合格" |

## 3. 已验证的工具调用（照抄，别猜）

CI 的命令清单只有一处：`scripts/ci.sh`。GitLab CI 与 GitHub Actions 都只调它，**加减门禁改它，不要改两份 YAML**。

```bash
bash scripts/ci.sh lint      # 也可以是 types / build / test / cert / all
```

组件以元素命名（`Platinum` = 数学库，`Krypton` = 压缩与加密……对照表在 `.plan/CARBON.md` §2.1，或看 `scripts/loc-budget.luau` 输出的 `ROLE` 列）。

Carbon 新增的两道门禁（2026-11-14）：

```bash
"$LUNE" run scripts/carbon-deps-check.luau                 # 依赖方向（CARBON.md §3）
"$LUNE" run scripts/carbon-deps-check.luau --selftest
"$LUNE" run scripts/loc-budget.luau                        # 门禁 8：LOC 记分板（日常只报告）；第二张表按 PURE/HOST/INTEGRATION/TEST 分列
"$LUNE" run scripts/loc-budget.luau --release              # release 分支：不达标则 exit 1
"$LUNE" run scripts/loc-budget.luau --selftest
```

格式检查的范围现在是 `src scripts`（原来是 `$DS $TS scripts`）。下面是旧内容，路径是 Windows 写法：

```bash
# 工具在 tool-storage 里的真实路径（rokit 的 bin 是 shim，需要目录内有 rokit.toml）
STYLUA="$HOME/.rokit/tool-storage/johnnymorganz/stylua/2.6.0/stylua.exe"
LUNE="$HOME/.rokit/tool-storage/lune-org/lune/0.11.1/lune.exe"
ROJO="$HOME/.rokit/tool-storage/rojo-rbx/rojo/7.7.1/rojo.exe"

DS="src/ReplicatedStorage/Deuterium"; TS="src/ReplicatedStorage/TritiumSQL"
"$STYLUA" --config-path stylua.toml --check $DS $TS scripts ; echo "exit=$?"
bash scripts/p0-check.sh                                   # P0 棘轮（26 / 47 / 0）
"$LUNE" run scripts/cert-scope-check.luau --quiet           # 门禁 10
"$LUNE" run scripts/cert-scope-check.luau --selftest        # 门禁 10 自检
"$LUNE" run tests/run.luau                                  # 门禁 2（headless，含 SKIP 计数）
"$LUNE" run scripts/probe-headless.luau                     # headless 能力基线
# 门禁 3 的类型部分（需 vendor 的 Roblox 定义；不联网）
"$ROJO" sourcemap default.project.json -o sourcemap.json
LUAU_LSP analyze --sourcemap=sourcemap.json --definitions:@roblox=types/globalTypes.None.d.luau --base-luaurc=.luaurc $DS $TS
"$ROJO" build -o /tmp/place.rbxlx                           # 结构冒烟
```

# 门禁 11/12（认证线）：追溯完整性 + statement 覆盖
"$LUNE" run scripts/cert-trace-check.luau                  # 门禁 11 → docs/cert/TRACE.md
"$LUNE" run scripts/cert-trace-check.luau --selftest
"$LUNE" run scripts/coverage.luau                          # 门禁 12 → docs/cert/coverage/*.json
"$LUNE" run scripts/coverage.luau --selftest                # 插桩器自己的测试（8 组）
"$LUNE" run tests/cert/run.luau                             # 认证线用例 → docs/cert/verify/*.md
"$LUNE" run scripts/probe-coverage.luau                     # 覆盖机制的成功性探针（P1–P8）
**坑位（都踩过）**：

| 坑 | 事实 |
| --- | --- |
| PATH 上的 `stylua`/`luau-lsp`/`rojo` | 命中的是 **aftman 的坏 shim**（全局 `aftman.toml` 里那些行被注释了）。用绝对路径，或先 `export PATH="$HOME/.rokit/bin:$PATH"` 且当前目录在 `rokit.toml` 之下 |
| `/tmp` 给 git 用 | git 是原生 Windows 程序，`/tmp/x` 会解析到别处 → **用 heredoc 或仓库内相对路径** |
| 长 commit message | 走 shell 引号会被反引号做命令替换 → 用 `git commit -F - <<'MSGEOF'` |
| 行尾 | 工作区可能是 CRLF（`core.autocrlf`），`stylua --check` 会报全文 diff → `.gitattributes` 已设 `eol=lf`；必要时光 `git checkout-index -f -- <file>` 刷新 |
| 工具下载 | GitHub release 直连会被 reset；`api.github.com` 通。需要时设 `HTTPS_PROXY`（见 `rokit.toml` 注释） |

## 4. 两条线，别混

| | 认证线（DAL C） | 产品线 |
| --- | --- | --- |
| 范围 | `docs/cert/scope.txt` 列出的 ≤12k 行 | 其余全部 |
| 标准 | 需求驱动 + 双向追溯 + statement 覆盖 + 变更控制 | `.plan/SCALE.md` 的 A/B/C 分档 |
| 证据 | `docs/cert/` | 普通 CI 报告 |

**认证证据里不得出现产品线测试输出**（含 `SelfTest`），反之亦然。`SelfTest` 是开发者自测，**不是认证证据**。

## 5. headless 测试怎么写

见 `docs/headless.md`。要点：

- 模块用 `require(script.Parent.X)` 也能测 —— 用**拓扑序 + `setfenv` + 恒等 `require`** 的 loader；
- **`_G` 不是全局环境表**，env 里要显式拷标准库名字；
- `warn` 不存在，loader 必须提供（映射到 `print`）；
- 日志类对象的方法**必须**是显式 `self` + 冒号调用（无 self 的闭包配冒号会把对象漏进 varargs —— 这个 bug 真的发生过）。

## 5.5 headless 能力现状（2026-10-25 起）

- **第一方 75/75 模块可 headless 装载**（不需要引擎桩）；`tests/run.luau` = **PASS 8 · FAIL 0 · SKIP 0**
- 引擎绑定的 SelfTest 也能跑：`{ engineStub = true, studio = true }` 启用 `scripts/rbx-stub.luau`
  （Vector3/Instance/Enum/task/typeof 桩）+ Studio 桩
- 由此发现的三个真 bug 类别（复現见提交 `af29cde`/`578a8ec`）：
  加载期引擎依赖、`table.freeze` 对已冻结表抛错、Luau 插值写成 `${expr}`

**新增/改代码时请自问**：这个模块还能在不加引擎桩的情况下被装载吗？做不到就说明它把引擎依赖放到了加载期。
### 5.6 认证线怎么加东西（C3 之后的规矩，门禁 11 会拦）

改动认证范围（`docs/cert/scope.txt` 列出的文件）时，**先有需求，再写码**（I18）。三步缺一不可：

1. **加需求**：`docs/cert/req/<MOD>.md`（每模块一份，含 HLR 段与 LLR 段）。HLR 八个字段、LLR 五个字段**全为必填**；HLR 的「危害追溯」必须是 `HAZARD.md` 里的 `H1`–`H7` 或 Dr 纯底座的 `基础`；LLR 的「上级需求」必须指向存在的 HLR。
2. **在源码上标注解**：每个导出函数 / `export type` 上方贴 `-- LLR-<MOD>-nnn`（`<MOD>` = 文件末段大写，例 `Contract.luau` → `CONTRACT`）。**漏标不是风格问题，是"无需求代码"**，门禁 11 直接失败。
3. **加用例**：`tests/cert/cases/<MOD>.luau`。文件头写 `-- covers: TC-…, LLR-…, HLR-…`，每条用例写 `id`/`kind`（正常·边界·错误）/`covers = {...}`。用例**不得** require `Dr.Testing`/`SelfTest`（两条线的证据不能混）。

跑：`lune run scripts/cert-trace-check.luau`（门禁 11）· `lune run tests/cert/run.luau`（认证线用例，生成 `docs/cert/verify/`）。
`docs/cert/TRACE.md` 与 `docs/cert/verify/*.md` 都是**生成物**，手改会被下次运行覆盖 —— 改需求要改 `req/`，改结果要改用例。

## 6. 写文件时

1. `--!strict`，模块末尾 `return table.freeze(M)`；
2. 文件头写：职责 + 对应 Wave + 引用的不变量编号；
3. 认证范围文件：每个导出函数头标 `-- LLR-<MOD>-nnn`；
4. 已知限制写 `shortcut: <限制>, <何时升级>`；
5. 非平凡逻辑配测试，且**测试必须真的被跑过**（未执行的测试等于注释）。
6. **修 bug 要配“会响”的测试**：写完修复后，把修复**反向改回**跑一遍 —— suite 仍然绿就说明这条修复没有测试保护（缺失用例）。
   （本轮 8 处修复里有 4 处是这样发现的。）
7. **Luau 插值语法是 `{expr}`，不是 `${expr}`** —— `${expr}` 里的 `$` 是字面量，会打脏输出
   （已踩：含产品代码 `TestContext.note`）。另：`table.freeze` 对**已冻结**的表会**抛错**（非幂等），
   冻结外部传入的表前先 `table.isfrozen` 判一下。

## 7. 收工动作

CI/门禁绿 → 勾 `.plan/STEPS.md` 的「进度登记」与「完成日志」→ 有新决策补 `.plan/README.md` §3 → 有新风险补 §6 → **若推翻了假设，改 plan 文档，不要只改代码**。
