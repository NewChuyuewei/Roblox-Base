# 第三方依赖审计（生成物 — 勿手改）

> 由 `scripts/thirdparty-audit.luau` 生成。权威契约是 `.plan/THIRDPARTY.md`；
> 证据归属 CC1；锁文件 `docs/thirdparty/LOCK.txt` 用于漂移检测。

## 1. 版本锁定（§7 步 1）

| 库 | 版本 | 上游 | 文件 | LOC | 字节 | 内容哈希（FNV-1a 32） |
| --- | --- | --- | --- | --- | --- | --- |
| Scribe | 2.6.1 | ericplane/scribe | 46 | 42077 | 1545868 | `3d797da3` |
| QuickZone | 1.5.1 | ldgerrits/quickzone | 13 | 6534 | 165495 | `9babdda8` |

锁文件状态：**与锁一致**（哈希是漂移检测，不是防篡改 —— Lune 0.11.1 无 @lune/crypto）。

## 2. 后门面扫描（§7 步 2）

**违规 0 处**（模式：loadstring · getfenv · setfenv · getgenv · debug.getinfo · debug.setupvalue · require(%d · _G. · HttpService:GetAsync · HttpService:PostAsync · HttpService:RequestAsync）

### 引擎触点清单（登记而非违规 —— I10 例外，THIRDPARTY.md §4）

| 模式 | 出现处（文件数） | 命中总数 |
| --- | --- | --- |
| `DataStoreService` | 5 | 15 |
| `HttpService` | 5 | 21 |
| `MarketplaceService` | 3 | 16 |
| `MessagingService` | 1 | 7 |
| `Players` | 12 | 73 |
| `RunService` | 13 | 52 |
| `game:GetService(` | 23 | 46 |

## 3. 可达闭包 = 真正的审计面（§7 步 3）

| 库 | 入口 | 可达文件 | 可达 LOC |
| --- | --- | --- | --- |
| Scribe | `src/ReplicatedStorage/Scribe/init.luau` | 46 | 42077 |
| Scribe | `src/ReplicatedStorage/Scribe/Server/init.luau` | 43 | 35429 |
| Scribe | `src/ReplicatedStorage/Scribe/Client/init.luau` | 22 | 15227 |
| **Scribe 并集** | — | **46** / 46 | **42077** / 42077 |
| QuickZone | `src/ReplicatedStorage/QuickZone/init.luau` | 13 | 6534 |
| **QuickZone 并集** | — | **13** / 13 | **6534** / 6534 |

### 已审阅并接受的例外（非违规）

| 库 | 种类 | 文件 | 理由 |
| --- | --- | --- | --- |
| Scribe | 动态 require | `src/ReplicatedStorage/Scribe/Server/Persistence.luau` | 依赖注入逃逸口 require(injected)：注入点由我们的适配器控制，不引入外部代码路径 |

## 4. I20 检查（第三方只经适配器）

`Deuterium/**` 内**没有**绕过适配器直接 require 第三方的文件。

## 5. 五步义务状态（§7）

| 步 | 状态 | 证据 / 关闭动作 |
| --- | --- | --- |
| 1 锁版本 | ✅ | 版本表 + `LOCK.txt`（升级上游时 `--write-lock` 重建） |
| 2 全量审计（后门面） | ✅ 按可达闭包 | §2 的扫描；形状不认识的 require 会报错而非跳过 |
| 3 剥离 | ◐ | **不改上游文件**（可机械升级）；审计面按 §3 的闭包口径收敛。真删文件等适配器定下入口集 |
| 4 Overrides 层 | ✅ 约定 | 适配器优先、不改上游；必须改时放 `Overrides.luau`（漂移锁会拦下未登记的改动） |
| 5 留档 | ✅ | `docs/thirdparty/{LICENSE,NOTICE,licenses,wally.toml}` + 本文件 + `LOCK.txt` |

---

未读/未验证：闭包口径是 **require 静态可达**，不含运行期才被访问的路径；
`game:GetService` 的实际调用时序未验证（两库需要引擎，headless 下无法执行）。
