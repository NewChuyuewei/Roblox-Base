--!strict
-- ReplicatedStorage.Configs.Deuterium —— 配置清单（folder-module）。
--
-- 为什么必须是 `init.luau`（而不是 `Deuterium.luau` 文件、也不是纯文件夹）：
-- 两处调用方同时要求它是 **一个名为 Deuterium 的 ModuleScript** 且**能带子节点**：
--   Configuration.Load()          -> configs:WaitForChild("Deuterium") 然后 IsA("ModuleScript") 然后 require()
--   FeatureFlags.LoadFromConfig() -> deuterium:WaitForChild("FeatureFlags") 然后 IsA("ModuleScript")
-- 纯文件满足前者但装不下子节点；纯文件夹满足后者但 IsA("ModuleScript") 失败。
-- `init.luau` 生成的正好是"能带子节点的 ModuleScript"。
--
-- 形状要求（Configuration.Load 会校验）：键=section 名，值必须是 table。

return table.freeze({
	FeatureFlags = require(script.FeatureFlags),
})
