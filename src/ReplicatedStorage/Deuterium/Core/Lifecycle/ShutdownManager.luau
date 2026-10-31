--!strict
-- Dr.Core.Lifecycle.ShutdownManager
-- Reverse-order Stop of every provider, then kernel reset. Double-run is a contract violation.

local Contract = require(script.Parent.Parent.Foundation.Contract)
local Kernel = require(script.Parent.Parent.Container.Kernel)
local Debug = require(script.Parent.Parent.Parent.Parent.Debug)

local ShutdownManager = {}

local _ran = false

function ShutdownManager.Run(): ()
	Contract.Invariant(not _ran, "SHUTDOWN.ONCE", "ShutdownManager.Run must run exactly once")
	_ran = true

	-- Reverse order: consumers before their producers.
	-- （文件头与函数内注释都承诺逆序，旧代码却是正序 —— 消费方的 Stop 会看到还活着的生产方。
	--   独立复审 subagent, core lane 2026-10-25 报出。）
	local order = Kernel.GetOrder()
	for index = #order, 1, -1 do
		local name = order[index]
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
	-- Kernel.Reset() 按契约是 Studio-only；不问就调会让**生产环境的关机路径每次必抛**，
	-- 而且此时 _ran 已经是 true，二次进入会再抛一次。故这里显式加门。
	local RunContext = require(script.Parent.Parent.Parent.Runtime.Environment.RunContext)
	if RunContext.IsStudio() then
		Kernel.Reset()
	end
end

function ShutdownManager.IsRan(): boolean
	return _ran
end

return table.freeze(ShutdownManager)
