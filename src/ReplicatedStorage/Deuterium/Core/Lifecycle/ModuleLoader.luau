--!strict
-- Dr.Core.Lifecycle.ModuleLoader
-- Discovers provider modules under a folder and returns their tables.
-- Discovery is Init-time only — after Construct the world is frozen.

local Debug = require(script.Parent.Parent.Parent.Parent.Debug)
local Contract = require(script.Parent.Parent.Foundation.Contract)

local ModuleLoader = {}

-- Returns the list of successfully required provider tables belonging to `folder`.
-- A broken child module is logged by the caller's Bulkhead, NOT silently skipped:
-- we surface both so no dark production failure.
function ModuleLoader.LoadProviders(folder: Instance): { any }
	Contract.IsA(folder, "Instance", "MODULES.FOLDER", "ModuleLoader.LoadProviders expects an Instance")
	local providers = {}
	for _, child in folder:GetDescendants() do
		-- ".selftest" 是 9 个字符；旧代码写 sub(-10) 永远不相等（差一位），排除逻辑完全失效
		--（实际只靠后面的 Name ~= "SelfTest" 撑着）。见 subagent core lane 2026-10-25。
		if child:IsA("ModuleScript") and child.Name:sub(-9) ~= ".selftest" and child.Name ~= "SelfTest" then
			local ok, mod = pcall(require, child)
			if ok and type(mod) == "table" then
				local candidate = mod :: { Name: unknown }
				if type(candidate.Name) == "string" then
					table.insert(providers, mod)
				else
					Debug.warn("[Dr.ModuleLoader] skipped (bad shape):", child:GetFullName())
				end
			else
				if not ok then
					Debug.warn("[Dr.ModuleLoader] skipped (require error):", child:GetFullName(), mod)
				end
			end
		end
	end
	return providers
end

return table.freeze(ModuleLoader)
