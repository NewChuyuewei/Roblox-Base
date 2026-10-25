# AGENTS.md — 在本仓库工作的约定

> 面向 AI agent 与人类协作者。**先读这里，再读 `.plan/`。**
> 本文件只管「怎么做」；「为什么」在 `.plan/`，合规证据在 `docs/cert/`。

---

## 1. 这是什么

| 位置 | 内容 |
| --- | --- |
| `src/ReplicatedStorage/Deuterium/` | 框架（微内核/生命周期/网络/会话态/复制/安全） |
| `src/ReplicatedStorage/TritiumSQL/` | 数据库引擎（页/B+树/事务/WAL/查询） |
| `src/ReplicatedStorage/Configs/` | 项目配置（`Deuterium/init.luau` folder-module + `FeatureFlags.luau`） |
| `src/ReplicatedStorage/Debug.luau` | 遗留 require 垫片（绝对路径）——见本文件 §5 |
| `src/ReplicatedStorage/{Scribe,QuickZone}/` | **第三方依赖树**（⚠ 未审计，见 `MEMORY.md` §1.1）；不得被认证核心 require |
| `src/ServerScriptService/` | 服务端专属（认证范围之外） |
| `.plan/` | **计划层**：不变量 · 门禁 · 决策 · 风险 · 排期 · 执行步骤 |
| `docs/cert/` | **DO-178C 认证线证据**（DAL C，≤12k 行子集） |
| `docs/headless.md` | headless 能力基线（测试与覆盖怎么做） |
| `scripts/` · `tests/` · `types/` | 门禁脚本（Lune/bash）· headless 测试入口 · vendor 的 Roblox 类型定义 |

> **第三方树的三条规则**：① 不进 stylua/analyze 门禁（改它们排版后无法与上游 diff 比对）；② 认证核心不得 require 它们（I16，门禁 10 会拦）；③ 使用前必须走完 `MEMORY.md` §1.1 的审计缺口清单。

**阅读顺序**：`.plan/README.md`（宪法）→ `.plan/STEPS.md`（当前该做哪一步）→ 需要动某一层时读对应的 `Deuterium.md` / `TritiumSQL.md` / `CERT.md`。

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

## 6. 写文件时

1. `--!strict`，模块末尾 `return table.freeze(M)`；
2. 文件头写：职责 + 对应 Wave + 引用的不变量编号；
3. 认证范围文件：每个导出函数头标 `-- LLR-<MOD>-nnn`；
4. 已知限制写 `shortcut: <限制>, <何时升级>`；
5. 非平凡逻辑配测试，且**测试必须真的被跑过**（未执行的测试等于注释）。

## 7. 收工动作

CI/门禁绿 → 勾 `.plan/STEPS.md` 的「进度登记」与「完成日志」→ 有新决策补 `.plan/README.md` §3 → 有新风险补 §6 → **若推翻了假设，改 plan 文档，不要只改代码**。
