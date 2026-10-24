--!strict
-- Dr.Net.Bridge.ClientBridge
-- Client-only channel handle. Fire targets the server; server never sees a raw RemoteEvent.

local Channel = require(script.Parent.Parent.Core.Channel)
local RunContext = require(game:GetService("ReplicatedStorage").Deuterium.Runtime.Environment.RunContext)

local ClientBridge = {}

export type Handle = {
	Name: string,
	Connect: (self: Handle, fn: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: Handle, ...any) -> (),
}

function ClientBridge.Open(name: string): Handle
	assert(RunContext.IsClient(), "[Dr.ClientBridge] Open is client-only")
	local channel = Channel.Open(name)
	assert(not channel:IsServer(), `[Dr.ClientBridge] {name} opened on a server`)

	local handle: Handle = {
		Name = name,
		Connect = function(_self: Handle, fn: (...any) -> ()): RBXScriptConnection
			assert(type(fn) == "function", "[Dr.ClientBridge] Connect expects fn")
			return channel:Connect(fn)
		end,
		Fire = function(_self: Handle, ...: any)
			channel:Fire(nil, ...) -- server target slot unused
		end,
	}
	return table.freeze(handle)
end

return table.freeze(ClientBridge)
