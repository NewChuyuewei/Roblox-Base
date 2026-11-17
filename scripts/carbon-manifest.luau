--!strict
-- Carbon 组件清单 —— 机器可读的唯一出处（.plan/CARBON.md §2 / §3 / §5 的镜像）。
--
-- 谁在读它：
--   scripts/carbon-deps-check.luau   依赖方向门禁（层次、deps、ports）
--   scripts/loc-budget.luau          LOC 记分板（门禁 8）
--
-- 命名：Carbon 的组件以元素周期表的元素命名（CARBON.md §2）。
-- 例外：Deuterium 与 TritiumSQL 是氢的同位素，按用户决定保留原名。
--
-- 字段：
--   name   元素名，同时是目录名
--   role   功能代号，只用于报告
--   layer  0..3；组件只能 require 更低层的组件
--   deps   可在组件内任意位置直接 require 的（更低层）组件
--   ports  只允许在 `<组件>/Integration/` 里接线的组件（同层或更低层）
--   core   核心行数预算（行，不含 Integration/ 与 SelfTest）
--
-- 改这里 = 改架构。先改 .plan/CARBON.md 并登记决策，再改本文件（两处必须一致）。
-- 纯数据模块：不得 require 任何东西（两个脚本都靠这一点直接装载它）。

export type Component = {
	name: string, -- 元素名 = 目录名 = 命名空间
	role: string, -- 功能代号（只用于报告，方便人读）
	layer: number,
	deps: { string },
	ports: { string },
	core: number,
}

local components: { Component } = {
	-- L0 纯库：零依赖，且不得触碰引擎
	{ name = "Platinum", role = "Math", layer = 0, deps = {}, ports = {}, core = 9000 },
	{ name = "Tin", role = "Schema", layer = 0, deps = {}, ports = { "Krypton" }, core = 6500 },
	{ name = "Krypton", role = "Crypto", layer = 0, deps = {}, ports = {}, core = 5500 },
	{ name = "Neon", role = "Console", layer = 0, deps = {}, ports = {}, core = 3500 },

	-- L1 运行时底座
	{
		name = "Deuterium",
		role = "Framework",
		layer = 1,
		deps = { "Neon", "Tin", "Krypton" },
		ports = {},
		core = 31000,
	},
	{ name = "Vanadium", role = "VM", layer = 1, deps = { "Neon", "Tin" }, ports = {}, core = 12000 },
	{ name = "Helium", role = "ECS", layer = 1, deps = { "Neon", "Tin" }, ports = {}, core = 6500 },
	{ name = "Phosphorus", role = "Telemetry", layer = 1, deps = { "Neon", "Tin" }, ports = {}, core = 6500 },
	{ name = "Uranium", role = "Jobs", layer = 1, deps = { "Neon", "Tin" }, ports = {}, core = 4500 },

	-- L2 领域引擎
	{
		name = "TritiumSQL",
		role = "SQL",
		layer = 2,
		deps = { "Deuterium", "Tin", "Krypton" },
		ports = {},
		core = 29500,
	},
	{
		name = "Titanium",
		role = "Physics",
		layer = 2,
		deps = { "Platinum", "Uranium" },
		ports = { "Helium" },
		core = 22000,
	},
	{
		name = "Silicon",
		role = "AI",
		layer = 2,
		deps = { "Platinum", "Uranium" },
		ports = { "Titanium", "Bismuth" },
		core = 12000,
	},
	{
		name = "Bismuth",
		role = "Voxel",
		layer = 2,
		deps = { "Platinum", "Uranium", "Tin", "Krypton" },
		ports = {},
		core = 10000,
	},
	{ name = "Gallium", role = "Anim", layer = 2, deps = { "Platinum" }, ports = { "Helium" }, core = 7500 },
	{ name = "Mercury", role = "KV", layer = 2, deps = { "Deuterium", "Tin" }, ports = {}, core = 6500 },

	-- L3 分布式与对抗
	{
		name = "Cesium",
		role = "Netcode",
		layer = 3,
		deps = { "Deuterium", "Tin", "Helium", "Titanium" },
		ports = {},
		core = 14500,
	},
	{
		name = "Copper",
		role = "Cluster",
		layer = 3,
		deps = { "Deuterium", "Mercury", "Tin" },
		ports = {},
		core = 9000,
	},
	{
		name = "Boron",
		role = "AntiCheat",
		layer = 3,
		deps = { "Titanium", "Phosphorus" },
		ports = { "Cesium" },
		core = 5500,
	},
	{
		name = "Sodium",
		role = "MQ",
		layer = 3,
		deps = { "Mercury", "Tin" },
		ports = { "Copper" },
		core = 4500,
	},
}

return {
	-- 组件所在目录：`<root>/<name>/`
	root = "src/ReplicatedStorage",

	components = components,

	-- `root` 下允许存在、但不是组件的条目（项目配置与遗留垫片）。
	-- 组件不得 require 它们；它们也不计入任何组件的行数。
	project = { "Configs", "Debug.luau" },

	-- 任何 require 里都不得出现的名字：只作参考的第三方库（CARBON.md §1.4）。
	forbidden = { "Scribe", "QuickZone" },

	-- 宿主目录（CARBON.md §3.2，规则 H1–H4）：每个组件唯一可以出现引擎 API 的地方。
	hostDir = "Host",
	-- 按组件改名。Deuterium 的宿主目录是既有的 `Runtime/`（不改名）。
	hostDirs = { Deuterium = "Runtime" } :: { [string]: string },
	-- 宿主目录本身就是公开端口层的组件：其核心可以 require 它（H3 不适用），
	-- 别的组件 require 它也不算跨宿主（H4 不适用）。只有 Deuterium：旧 I10 规定全框架
	-- 经 `Runtime/` 取引擎服务，这是它既有的设计，不是待还的债。新增条目须先改 CARBON.md。
	hostRequirable = { "Deuterium" },

	-- 宿主目录之外不得出现的引擎字面（注释行除外）。所有层的组件都适用。
	engineLiterals = { "game:", "game.", "GetService(", "workspace", "Instance.new(", "task." },

	-- 预算（行）。合计必须等于 total —— loc-budget 的自检会核对。
	budget = {
		total = 320000,
		-- 各层的测试预算：组件内的 SelfTest.luau + tests/<组件>/
		testsByLayer = { [0] = 10000, [1] = 25000, [2] = 36000, [3] = 14000 },
		integration = 9000, -- 所有 `<组件>/Integration/`
		endToEnd = 8000, -- tests/ 下不属于任何单个组件的部分
		tools = 12000, -- scripts/ 与示例、基准
	},

	-- release 分支的阻断线：合计达到 total，且每个区域达到自身预算的这个比例。
	releaseFloor = 0.7,
}
