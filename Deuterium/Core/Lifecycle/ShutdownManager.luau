--!strict
-- Dr.Core.Lifecycle.ShutdownManager
-- Reverse-order Stop of every provider, then kernel reset. Double-run is a contract violation.

local Contract = require(script.Parent.Parent.Foundation.Contract)
local Kernel = require(script.Parent.Parent.Container.Kernel)
local Debug = require(game:GetService("ReplicatedStorage"):WaitForChild("Debug"))

local ShutdownManager = {}

local _ran = false

function ShutdownManager.Run(): ()
	Contract.Invariant(not _ran, "SHUTDOWN.ONCE", "ShutdownManager.Run must run exactly once")
	_ran = true

	-- Reverse order: consumers before their producers.
	for _, name in Kernel.GetOrder() do
		local provider = Kernel.Get(name)
		if provider.Stop ~= nil then
			local ok, err = pcall(function()
				provider.Stop(provider)
			end)
			if not ok then
				Debug.warn(`[Dr.Shutdown] {name} Stop failed: {tostring(err)}`)
			end
		end
	end
	Kernel.Reset()
end

function ShutdownManager.IsRan(): boolean
	return _ran
end

return table.freeze(ShutdownManager)
