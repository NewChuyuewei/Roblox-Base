# SDP — 软件开发计划

> C2 交付，CC1。上游：`PSAC.md`（范围/级别/目标）· `HAZARD.md`（危害→模块）· `REQ-STD.md`（需求怎么写）· `TYPES.md`（类型规约）。
> 本文件只写**开发侧**的做事方式；验证侧在 `SVP.md`。

---

## 1. 生命周期模型

**V 模型（精简版）** —— 每个认证范围模块走一次完整的 V，不允许跳过左半边：

```
        HLR ─────────────────────────────────▶ HLR 覆盖测试
         │                                          ▲
         ▼                                          │
        LLR ──────────────────────────▶ LLR 覆盖测试
         │                                          ▲
         ▼                                          │
     代码 + 设计描述 ──▶ 单元测试 ──▶ 结构覆盖 ─────┘
```

| 阶段 | 入口准则 | 出口准则（transition criteria） |
| --- | --- | --- |
| **S1 需求** | 危害已定 DAL（`HAZARD.md` §3） | HLR 通过可验证性检查（`REQ-STD.md` §4）；每条挂危害 ID |
| **S2 设计** | HLR 基线冻结 | LLR 覆盖每个分支/循环/错误路径；设计描述（CC2）存在 |
| **S3 编码** | LLR 基线冻结 | `--!strict` 通过；门禁 3 全绿；**每个导出函数头标 `-- LLR-<MOD>-nnn`** |
| **S4 集成** | 模块级测试通过 | 模块可被上依赖层装配；`Port` 边界防御校验到位（I17） |
| **S5 验证** | 代码冻结 | `SVP.md` 的 5 项判据全过；覆盖报告入库 |
| **S6 基线** | 验证通过 | `BASELINE.md` 记录 `path+sha256+DAL+需求ID范围`；打 tag |

**S3 的硬前置**：`.plan/STEPS.md` 的 C3 完成前不得写认证范围代码（I18）。

## 2. 阶段间禁止事项

| 禁止 | 理由 |
| --- | --- |
| 先写代码再补 LLR | 这正是本项目**已经犯过的错**（先写了 5k 行）；`HAZARD.md` §5 与 `CERT.md` §9.2 记了成本 |
| 在认证范围内写"以后要用"的 API | 无 LLR 支撑的代码 = 意外功能，DO-178C 明确要查的东西 |
| 未经 LLR 修改已冻结的认证范围文件 | 走 `SCMP.md` §4 变更控制 |
| 认证范围模块 `require` 范围外模块 | I16，门禁 10 阻断（含 B 段依赖闭包） |

## 3. 开发标准（本项目事实）

| 项 | 规定 |
| --- | --- |
| 语言 | Luau，`--!strict`（`.luaurc`：`languageMode=strict`, `lintErrors`, `typeErrors`） |
| 模块形状 | 导出表 `table.freeze(M)`；文件头写职责 + Wave + 引用的不变量编号 |
| 依赖方向 | 认证核心只允许**同树相对 require**（`script.Parent…`）；禁止跨树路径与字面路径 require（门禁 10 B 段） |
| 依赖注入 | 核心逻辑的**范围外依赖必须作为参数传入**，不得 require（`.plan/STEPS.md` Step 7 的实测结论：`script.Parent` 使模块无法 headless 测试） |
| 类型与转换 | 遵守 `TYPES.md`（DO-178C §6.7/6.7.1 对动态语言的要求） |
| 格式化 | `stylua --check`；认证范围内**只读**，不用于改写（`PSAC.md` DV-3） |
| 热路径 | 遵守 P0 规约，`scripts/p0-check.sh` 棘轮只降不升 |

## 4. 开发环境与工具链

| 工具 | 版本 | 作用 | 鉴定立场 |
| --- | --- | --- | --- |
| `lune` | 0.11.1（`rokit.toml`） | 测试宿主、脚本运行时 | 见 `CERT.md` §4.4 |
| `luau`（官方，pin hash） | 认证线待固定 | 认证核心的**语义参考实现** | 倾向鉴定；否则逐项人工复核其输出 |
| `rojo` | 7.7.1 | 生成实例树（生命周期数据） | 不用于认证信用；结构由 sourcemap 人工评审 |
| `stylua` | 2.6.0 | 格式检查 | 只读 |
| `luau-lsp` | 1.70.1 | 静态分析（lint + 类型） | **咨询**，发现进问题报告 |
| Roblox 引擎 | 不固定 | 目标环境 | 不可鉴定（DV-2） |

工具链由 `rokit.toml` 固定；CI 无网络依赖（除 `rokit install` 首次拉取，`CERT.md`/`rokit.toml` 已记录代理问题）。

## 5. 目录职责（认证线）

| 路径 | 内容 | CC |
| --- | --- | --- |
| `docs/cert/req/HLR-<MOD>.md` · `LLR-<MOD>.md` | 两级需求 | CC1 |
| `docs/cert/design/<MOD>.md` | 设计描述 | **CC2**（DAL C） |
| `TritiumSQL/Tri/**` · `Deuterium/{Core,Types,Collections,Memory,Concurrency}/**` | 源码（仅 `scope.txt` 列出的文件） | CC1 |
| `docs/cert/verify/<MOD>.md` | 验证用例与结果 | CC1 |
| `docs/cert/coverage/<MOD>.json` | 结构覆盖报告 | CC1 |

**范围外代码**（`Dr.Runtime`/`Dr.Net`/`Dr.Security`/`Dr.Diagnostics`/`Dr.Testing`/`Tri.Integration`/示例/工具）继续按产品线节奏演进，但**不得**被范围内核 require。

## 6. 代码评审要求（认证范围）

每个文件必须有一次**独立会话评审**（`SQAP.md` §3），检查单：

1. `LLR` 是否逐条落到代码（含错误路径与边界）？
2. 是否有**无 LLR 的可执行语句**（意外功能）？
3. 边界输入是否防御校验（I17）？
4. 依赖是否全部在范围内（门禁 10）？
5. 类型与转换是否遵守 `TYPES.md`（含数值边界）？
6. 已知限制是否用 `shortcut:` 标注（含升级条件）？

## 7. 转换到验证的判据

| 条件 | 说明 |
| --- | --- |
| 全部 LLR 有代码映射 | 由 `TRACE.md` 生成器检查，不靠人眼 |
| 门禁 3 + 10 全绿 | CI 阻断 |
| 无未关闭的问题报告（阻塞级） | `PROBLEMS.md` |
| 设计描述已评审 | CC2 文件但同样要评审 |

---

未读/未验证：§4 的「luau pin hash」尚未执行（需先决定鉴定路线，`CERT.md` §4.4）；认证线的 S3 尚未开始（`scope.txt` 里 51 个文件为 PLANNED）。
