# Krypton — 压缩与加密库

> Carbon 组件 · **L0 纯库（零依赖，不得触碰引擎）** · 状态：**未立项**（只有目录，没有代码）
> 总图：`.plan/CARBON.md`；本页的层次、依赖、预算是 `scripts/carbon-manifest.luau` 的镜像，以清单为准。

| 项 | 内容 |
| --- | --- |
| 范围 | LZ4/Deflate · SHA-2 · HMAC · 签名 · CRC |
| 可直接依赖 | 无 |
| 只经 `Integration/` 接线 | 无 |
| 核心行数预算 | 5,000 行（粗估，立项纵切后校准） |
| 可参考 | `Deuterium/Security/Crypto/{Sha256,Hmac}`、`Deuterium/Net/Processing/Compressor` |

## 立项前要做的

1. 把上面的「范围」展开成功能点清单，每个功能点对应预算里的一块。
2. 做一次纵切，产出接缝清单（做法同 `.plan/STEPS.md` 的 Step 16.5）。
3. 进认证范围的部分先写 LLR 再写码（I18）。

命名：Carbon 的组件一律以元素命名。**Krypton**：名字来自希腊语 kryptos「隐藏」，与 crypto 同源。
