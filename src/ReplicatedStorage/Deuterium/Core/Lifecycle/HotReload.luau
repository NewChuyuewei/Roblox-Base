--!strict
-- Dr.Core.Lifecycle.HotReload
-- STUDIO-ONLY: watch a folder of provider modules, re-run BootSequencer on change.
-- Uses task.defer to coalesce multi-file saves into a single reload. Production: no-op.
-- Known limit: watches DescendantAdded only — NEW modules trigger reload; source edits
-- of existing scripts do not (full source-swap reload is backlog).

local RunContext = require(game:GetService("ReplicatedStorage").Deuterium.Runtime.Environment.RunContext)
local Contract = require(script.Parent.Parent.Foundation.Contract)

local HotReload = {}

function HotReload.IsEnabled(): boolean
	return RunContext.IsStudio()
end

-- Watch `root` for any ModuleScript change; call onReload once per burst.
function HotReload.Watch(root: Instance, onReload: () -> ()): () -> ()
	Contract.Invariant(RunContext.IsStudio(), "HOT.PROD", "HotReload is Studio-only")
	Contract.IsA(root, "Instance", "HOT.ROOT", "root must be an Instance")
	Contract.IsA(onReload, "function", "HOT.CALLBACK", "onReload must be a function")

	local scheduled = false
	local conn = root.DescendantAdded:Connect(function(desc)
		if desc:IsA("ModuleScript") then
			if scheduled then
				return
			end
			scheduled = true
			task.defer(function()
				scheduled = false
				onReload()
			end)
		end
	end)
	return function()
		conn:Disconnect()
	end
end

return table.freeze(HotReload)
