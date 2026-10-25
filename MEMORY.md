# MEMORY.md — 依赖审计与环境事实留档

> 规格 `Deuterium/Deuterium.md` §2 要求：任何内置的外部库必须「锁版本 → 全量审计 → 剥离 → Overrides 改造 → 留档」，本文件是那条链的**留档处**。
> 同时记录**会被后来者重复踩到的环境事实**。CC1（随 `.plan/SCMP.md`）。

---

## 1. 运行期外部依赖（门禁 6：只允许 Scribe / PlayerState / QuickZone）

| 依赖 | 规格声称的状态 | **审计实测结论** | 版本/来源 | 审计人 | 结论 |
| --- | --- | --- | --- | --- | --- |
| **Scribe** | 「已内置 `Libraries/Scribe`，⚠️ 待审计」 | **本仓库中根本不存在**：无 `Libraries/` 目录；全仓 `grep -rn Scribe` 命中 **0** 处（`.luau` 与配置均无） | 无 | 本会话（2026-10-25） | **规格的这条声明与仓库事实不符**。不存在则无可审计 → 无需五步流程。将来真正引入时必须按 §2 走完五步并回填本表 |
| **PlayerState** | 「待引入，⛔ 未审计，不得用」 | 未引入（0 引用） | 无 | — | 保持 ⛔；引入前先关决策 D1（上游来源待定） |
| **QuickZone** | 「计划内置 MIT，⛔ 未审计」 | 未引入（0 引用） | 无 | — | 保持 ⛔；推迟到世界层动工前 |

**结论**：当前运行期外部依赖为**零**。这既是最干净的供应链状态，也意味着 `CERT.md` §4 的工具鉴定只需面对**开发期工具**。

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
| `documents/` 里 `Text File.txt` 已被删除（工作区 ` D`，**未提交**） | 仓库根的状态未定 | 待人工决定：提交删除 or 恢复。`.plan/README.md` 记为"原位保留对照"与事实不符，需随之更正 |

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

未读/未验证：Scribe/PlayerState/QuickZone 的审计基于**全仓文本检索**（结论：不存在），未检查网络来源；`Text File.txt` 的删除原因未知（非本次会话所为）；`luau-lsp 1.70.1` 的实际分析结果尚未跑通（缺 `globalTypes.d.luau`，Step 8）。
