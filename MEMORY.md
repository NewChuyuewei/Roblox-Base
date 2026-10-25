# MEMORY.md — 依赖审计与环境事实留档

> 规格 `Deuterium/Deuterium.md` §2 要求：任何内置的外部库必须「锁版本 → 全量审计 → 剥离 → Overrides 改造 → 留档」，本文件是那条链的**留档处**。
> 同时记录**会被后来者重复踩到的环境事实**。CC1（随 `.plan/SCMP.md`）。

---

## 1. 运行期外部依赖（门禁 6：只允许 Scribe / PlayerState / QuickZone）

| 依赖 | 规格声称的状态 | **审计实测结论** | 版本/来源 | 审计人 | 结论 |
| --- | --- | --- | --- | --- | --- |
| **Scribe** | 「已内置 `Libraries/Scribe`，**日志/观测**，⚠️ 待审计」 | **现已存在于 `src/ReplicatedStorage/Scribe/`（45 文件 / 38,717 行）**。实测事实：① 它**不是日志库**，而是**玩家数据/复制库**（自带 `Internal/Store/ProfileStore.luau`）—— 规格对它的角色描述**错了**；② 35 处 `game:GetService(`、14 处 `DataStoreService`；③ 无 `loadstring`、无数字 id `require` | **无版本标识**（无 tag/hash/file）；**无 LICENSE 文件** | 未审计 | ⛔ **未审计不得使用**（规格 §2） |
| **PlayerState** | 「待引入，⛔ 未审计」 | **仍不存在**（0 引用）。注意：Scribe 已内置 ProfileStore，因此 PlayerState 可能**不再需要** | — | — | 决策 **D2 需重开**（Scribe 可能顶替它） |
| **QuickZone** | 「计划内置 `ldgerrits/quickzone@^1.4.x`，MIT，⛔ 未审计」 | **现已存在于 `src/ReplicatedStorage/QuickZone/`（13 文件 / 6,534 行）**，头部标 `--v1.5.1 • LDGerrits`（实际版本 **1.5.1**，高于规格写的 ^1.4.x）。无 `loadstring` / 数字 `require` | v1.5.1（无 hash） | 未审计 | ⛔ **无 LICENSE 文件** + 无 hash + 未审计 |

### 1.1 审计义务：**决定集成，但五步未做 → 阻塞任务 `D0.6`**

**决策（2026-10-25，用户）：把 Scribe 与 QuickZone 集成进框架**；两库**不计入 100k 行与 440 模块**（适配器计入）。
**集成方式、所有权划分、适配器清单、不变量豁免全部写在 `.plan/THIRDPARTY.md`** —— 以那份为准，本表只留**审计状态**。

规格 §2 的五步（锁版本 → 全量审计 → 剥离 → Overrides 改造 → 本文件留档）**每步都未做**。

> **顺序很重要**：先**剥离**（把 38.7k 行压到实际用到的部分）再审计 —— 反过来会白审一大半。Scribe 含 `Monetization`/`Leaderboards`/`Analytics`/`Commands` 等我们可能不用的大块。

当前缺口清单：

| 缺口 | 影响 | 最小关闭动作 |
| --- | --- | --- |
| 两者**都没有 LICENSE 文件** | 合规基础缺失（QuickZone 声称 MIT，但树里无声明文本） | 补 LICENSE 或在上游确认后另存引用 |
| Scribe **无版本标识** | 无法锁版本、无法判断上游变更 | 定位上游 tag/commit，记 hash |
| QuickZone 版本 1.5.1 但**无 commit hash** | 同上 | 同上 |
| 未做**剥离**（用不到的模块/注释） | 38k+6.5k 行进仓库，供应链面与审查面都变大 | 按实际用到的入口裁剪 |
| 未做 **Overrides 层** | 无法在不改上游的前提下适配 | 建 `Overrides.luau` 约定 |

**规模对比（必须意识到）**：Scribe **38,717 行 = 框架本体（5,486 行）的 7 倍**；两个依赖合计 **45,251 行**。对本项目而言，这比“允许两个例外”的初衷大得多。

**对 DO-178C 认证线的影响**：两者都是**无可鉴定的 COTS/PDS**（直接调 DataStore/引擎），因此**不得被认证核心 require**（I16）—— 门禁 10 的 B 段（依赖闭包）已经能把这类越界抓出来。认证线继续只用自已的 `Port`。

**另外一条未验证的判断**：`Dr.Data`/`Dr.State` 的原计划底层是 PlayerState，而 Scribe 自带 ProfileStore 且是玩家数据/复制库 —— 规格与选型需要重新对齐（决策 D2 重开）。

> 审计方法（可复现）：`grep -rn "Scribe\|PlayerState\|QuickZone" Deuterium TritiumSQL --include=*.luau` 及 `ls Libraries/`。
> 待办：规格 §3 的依赖表应据此更正（`Deuterium.md` §2 的修订清单已含此项）。

## 2. 开发期工具链（不计入门禁 6，但需固定）

`rokit.toml` 固定：`rojo 7.7.1` · `lune 0.11.1` · `stylua 2.6.0` · `luau-lsp 1.70.1`。

| 工具 | 用途 | 鉴定立场（`docs/cert/PSAC.md` §5 / `CERT.md` §4.4） |
| --- | --- | --- |
| `lune` | 测试宿主、脚本运行时 | 输出作为验证信用 → 需评估 |
| `stylua` | 格式检查 | **认证范围只读**（只跑 `--check`） |
| `luau-lsp` | 静态分析 | 咨询；发现进问题报告 |
| `rojo` | 实例树构建 | 不用于认证信用 |
| ~~`selene`~~ | **已移除** | ✂ 见下 |

### `selene` 移除记录（2026-10-25）

**理由**：`selene 0.32.0`（**其最新 release**）在 full_moon 3.0.0 的 tokenizer 上对 **Luau 反引号插值字符串** panic（`internal error: entered unreachable code`）。最小复现仅 3 行：`local n = 7` + `` local s = `value={n}` ``。本仓库到处在用该语法（既有 `ErrorHandler`/`Kernel`/`FeatureFlags`，Step 3 新增 5 个文件中 3 个触发）。
**替代**：`luau-lsp analyze`（本身就跑 luau-analyze，lint + 类型一次完成）+ `scripts/p0-check.sh` 的 P0 正则棘轮。
**副作用**：工具少一个、供应链少一项；`selene.toml` 与自建 std 已删除。

## 3. 网络与环境事实（会被重复踩到）

| 事实 | 影响 | 处置 |
| --- | --- | --- |
| `raw.githubusercontent.com` 直连被 reset | 工具下载失败（`error decoding response body`） | `HTTPS_PROXY=http://127.0.0.1:7890` 后重跑；代理**不稳定**（时通时断） |
| `api.github.com` 直连可用 | 查版本/发布信息可用 | 无需代理 |
| `rokit add` 首次需先 `rokit trust <owner/repo>` | 否则报 `has not been marked as trusted` | `rokit trust` → `rokit add` |
| PATH 上 `~/.aftman/bin` 早于 `~/.rokit/bin`，且 aftman 的 4 个 shim 因其全局 manifest 里对应行被注释而**全部报错** | 裸命令 `rojo`/`stylua`/`luau-lsp` 会命中坏 shim | 用 tool-storage 绝对路径（见 `AGENTS.md` §3） |
| git 已装守卫：禁直提 `main`、subject ≤72 字符 | 提交与常规习惯不同 | 功能分支 + heredoc 式消息 |
| `Text File.txt` 与 `.mcp.json` | 仓库根状态曾未定 | **已解决**：用户 commit `5d4fabe` 同时提交了 `.mcp.json` 与 `Text File.txt` 的删除。相关文档引用已同步更正（`Text File.txt` 由 `TritiumSQL.md` 取代，历史可查） |

## 3.5 vendor 进仓库的外部产物（需登记来源，便于复现与审计）

| 产物 | 来源 | 大小 | sha256（前 16） | 日期 | 为何入库 |
| --- | --- | --- | --- | --- | --- |
| `types/globalTypes.None.d.luau` | `https://luau-lsp.pages.dev/type-definitions/globalTypes.None.d.luau`（官方 Cloudflare CDN；`type-definitions/` 会 302 到根路径） | 697,978 B | `bb8572d8b4b24075` | 2026-10-25 | `luau-lsp analyze` 需要 Roblox 全局类型；**入库后 CI 的 types 阶段不联网、可复现**。选 `None` 安全级 = 游戏运行时；`PluginSecurity`/`RobloxScriptSecurity` 含无权调用的 API |

更新方式：从同一 URL 重取 → 重度 `luau-lsp analyze` → 更新本表指纹。该文件是**生成物**（官方由 `dumpRobloxTypes.py` 从 Roblox API Dump 生成），不手改。

> 为什么不从 `raw.githubusercontent.com/JohnnyMorganz/luau-lsp/…` 取：本机对该域直连被 reset，且官方自己说 GitHub 对未认证请求限流严格。

## 3.6 类型检查首次真跑抓到的真 bug（2026-10-25）

`luau-lsp analyze` 第一次能够运行（因为拿到了 §3.5 的定义文件）就抓到一个**运行时必现的缺陷**：

- `Deuterium/Diagnostics/Logging/Debug.luau` 被 `default.project.json` **映射两次**（`ReplicatedStorage.Debug` 与 `…/Logging/Debug`）。在 `ReplicatedStorage.Debug` 那个副本里 `script.Parent` 是 `ReplicatedStorage`，因此它自身的 `require(script.Parent.Logger)` 指向不存在的 `ReplicatedStorage.Logger` —— 而**18 个既有模块 require 的正是这个副本**。
- 修法：新增 DAL E 垫片 `src/ReplicatedStorage/Debug.luau`（可用绝对路径），真实现只在 Deuterium 树内映射一次。既保留相对 require（I16 与 headless loader 的前提），又不改任何既有调用方。

教训：**同一个源文件被 Rojo 映射两次时，它的 `script.Parent` 相对依赖会指向两个不同的地方**。以后新增顶层映射时先问一句“它的相对 require 还成立吗”。

## 4. 交付物清单（本会话新增，供后来者定位）

| 路径 | 内容 |
| --- | --- |
| `.plan/`（7 份） | 计划宪法、规模标定、集成契约、两项目计划、执行手册、DO-178C 适配 |
| `docs/cert/`（10 份） | 认证线生命周期数据：HAZARD/PSAC/SDP/SVP/SCMP/SQAP/REQ-STD/TYPES + scope.txt + 索引 |
| `docs/headless.md` | headless 能力基线（含 `debug.sethook` 不可用这一决定性事实） |
| `scripts/` | `p0-check.sh` · `cert-scope-check.luau`（门禁 10，含自检）· `probe-headless.luau` |
| `rokit.toml` · `.luaurc` · `stylua.toml` · `.gitattributes` · `.gitignore` · `default.project.json` | 工程骨架 |
| `Deuterium/Diagnostics/Logging/` | 5 文件（含 `Debug` 兼容层，补上 18 处悬空 require） |

---

未读/未验证：Scribe/PlayerState/QuickZone 的审计基于**全仓文本检索**（结论：不存在），未检查网络来源；`Text File.txt` 的删除原因未知（非本次会话所为，但已随 `5d4fabe` 提交）；`types/globalTypes.None.d.luau` 的**时效性**未跟踪（它是官方从 Roblox API Dump 生成的快照，Roblox 改 API 后会陈旧 —— 更新方式见 §3.5）。
