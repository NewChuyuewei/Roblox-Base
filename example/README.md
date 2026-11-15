# example/ — 只作参考的第三方库

这里不是 Carbon 的一部分：不随 Carbon 发布，Carbon 的任何组件都不得 require 这里的东西（`scripts/carbon-deps-check.luau` 会拦）。

| 位置 | 内容 |
| --- | --- |
| `src/ReplicatedStorage/Scribe/` | Scribe 2.6.1 原件（46 文件 / 42,077 行，MIT；内含 Apache-2.0 的 ProfileStore 分支）：玩家数据、复制、经济、排行榜 |
| `src/ReplicatedStorage/QuickZone/` | QuickZone 1.5.1 原件（13 文件 / 6,534 行，MIT）：区域检测、BVH |
| `docs/thirdparty/` | 审计报告、版本锁、许可文本 |
| `scripts/thirdparty-audit.luau` | 当初的审计脚本，仅存档。**现在跑不通**：它的「只经适配器」检查要扫描 `Deuterium/`，而 Framework 已搬回仓库根目录；这项检查已由 `scripts/carbon-deps-check.luau` 的「不得依赖第三方」取代 |

它们的哪些能力会被 Carbon 的哪个组件吸收，见 `.plan/CARBON.md` §1.4。参考重写时若保留了原代码的实质部分，要按许可保留版权声明并登记来源。

不要改这里的文件：保持与上游一致，才能继续拿来对照。
