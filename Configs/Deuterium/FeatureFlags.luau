--!strict
-- ReplicatedStorage.Configs.Deuterium.FeatureFlags —— 特性开关定义清单。
--
-- 消费方：Dr.Runtime.Environment.FeatureFlags.LoadFromConfig()
-- 每项形状（validateEntry 会校验）：{ name: string, default: boolean, studioOverride: boolean? }
-- name 必须匹配 `^[%a][%w_%.]*$`。
--
-- 两条容易搞错的约束：
--  1) 必须是**数组**（数字键）：加载器用 `for index, def in defs` 迭代，且
--     Runtime/Environment/SelfTest 断言 `table.isfrozen(raw[1])`。
--  2) **不要**给 Dr.Security.StrictSchema 设 studioOverride=false ——
--     那样它在 Studio 里会被解析成 false，而三个 SelfTest 都断言它 == true。

local defs: { { name: string, default: boolean, studioOverride: boolean? } } = {
	-- 三个 SelfTest 断言它必须为 true：Runtime/Environment、Testing、Reflection
	{ name = "Dr.Security.StrictSchema", default = true },
	-- 只断言类型（boolean），值不敏感；true 为合理默认
	{ name = "Dr.Diagnostics.StructuredLogs", default = true },
}

for _, entry in defs do
	table.freeze(entry)
end

return table.freeze(defs)
