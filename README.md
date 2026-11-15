# Carbon

Carbon 是一套面向 Roblox（Luau）的综合基础设施，由 19 个平级组件组成，分四层，只许向下依赖。规模目标是全部代码合计 300,000 行。

总图在 [`.plan/CARBON.md`](.plan/CARBON.md)：沿用的约束、组件清单、分层、预算、推进次序、待决事项和进度。

## 组件

整体叫 Carbon，内部每个组件用一个元素命名。

| 层 | 组件 |
| --- | --- |
| L3 分布式与对抗 | `Cesium` 同步引擎 · `Copper` 集群层 · `Sodium` 消息队列 · `Boron` 反作弊 |
| L2 领域引擎 | `TritiumSQL` SQL · `Mercury` KV/缓存 · `Titanium` 物理引擎 · `Bismuth` 体素/地形 · `Silicon` AI 引擎 · `Gallium` 动画引擎 |
| L1 运行时底座 | `Deuterium` Framework · `Helium` ECS · `Uranium` 并行作业 · `Vanadium` 脚本虚拟机 · `Phosphorus` 可观测 |
| L0 纯库 | `Platinum` 数学库 · `Tin` 序列化 · `Krypton` 压缩与加密 · `Neon` 控制台打印 |

**当前状态**：工程骨架已搭好。`Deuterium` 与 `TritiumSQL` 有旧代码（约 6,600 行），其余 17 个组件只有目录和一页范围说明。`Deuterium` 与 `TritiumSQL` 是氢的同位素而不是元素，是否改名尚未决定。

## 目录

| 位置 | 内容 |
| --- | --- |
| `src/ReplicatedStorage/<组件>/` | 19 个组件，每个一个目录 |
| `scripts/` | 门禁脚本。`carbon-manifest.luau` 是组件清单（层次、依赖、预算）的机器可读出处 |
| `tests/` | headless 测试入口（在 Lune 里跑，不需要 Roblox Studio） |
| `.plan/` | 计划层：`CARBON.md` 是总图，其余是 Carbon 之前的计划，约束仍有效 |
| `docs/cert/` | DO-178C（DAL C）认证线的证据 |
| `example/` | 只作参考的第三方库 Scribe 与 QuickZone，不是 Carbon 的一部分 |
| `AGENTS.md` · `MEMORY.md` | 协作约定与环境事实 |

## 常用命令

工具链由 `rokit.toml` 固定（rojo、lune、stylua、luau-lsp）。

```bash
lune run tests/run.luau                         # headless 测试
lune run scripts/carbon-deps-check.luau         # 组件依赖方向
lune run scripts/loc-budget.luau                # 行数记分板
stylua --config-path stylua.toml --check src scripts
rojo build default.project.json -o place.rbxlx
```

CI 支持 GitLab 与 GitHub 两个平台，两边都只调 `scripts/ci.sh`；完整的门禁列表就在这个脚本里：

```bash
bash scripts/ci.sh all    # 或单独跑 lint / types / build / test / cert
```
