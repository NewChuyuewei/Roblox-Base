--!strict
-- Dr.Net.Bridge.MockBridge
-- Test double for the full bridge surface. Everything winds up in `Log` so a MockBridge
-- test is a pure table assertion — nothing replicates, nothing touches Player instances.

local RunContext = require(game:GetService("ReplicatedStorage").Deuterium.Runtime.Environment.RunContext)

local MockBridge = {}

export type Record = {
	name: string,
	target: any,
	args: { any },
}

export type Handle = {
	Name: string,
	Connect: (self: Handle, fn: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: Handle, target: any, ...any) -> (),
	FireAll: (self: Handle, ...any) -> (),
	Log: { Record },
	Reset: (self: Handle) -> (),
}

function MockBridge.Open(name: string): Handle
	assert(RunContext.IsStudio(), "[Dr.MockBridge] Studio-only")
	local log: { Record } = {}
	local listeners: { RBXScriptConnection } = {}

	local handle: Handle = {
		Name = name,
		Log = log,
		Connect = function(_self: Handle, fn: (...any) -> ()): RBXScriptConnection
			-- Mocks don't replicate: Connect via a dummy BindableEvent for shape compatibility.
			local b = Instance.new("BindableEvent")
			local conn = b.Event:Connect(fn)
			table.insert(listeners, conn)
			return conn
		end,
		Fire = function(_self: Handle, target: any, ...: any)
			table.insert(log, table.freeze({ name = name, target = target, args = table.pack(...) }) :: any)
		end,
		FireAll = function(_self: Handle, ...: any)
			table.insert(log, table.freeze({ name = name, target = "*all*", args = table.pack(...) }) :: any)
		end,
		Reset = function(_self: Handle)
			table.clear(log)
			for _, conn in listeners do
				conn:Disconnect()
			end
		end,
	}
	return handle :: any
end

return table.freeze(MockBridge)
