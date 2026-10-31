--!strict
-- Dr.Net.Bridge.ServerBridge
-- Server-produced, server-consumed channel handle. Fire targets Players; any nil target
-- is a runtime contract violation (fail fast with a named error).

local Channel = require(script.Parent.Parent.Core.Channel)
local Types = require(script.Parent.Parent.Parent.Core.Container.Types)

local ServerBridge = {}

export type Handle = {
	Name: string,
	Connect: (self: Handle, fn: (player: Player, ...any) -> ()) -> RBXScriptConnection,
	Fire: (self: Handle, player: Player, ...any) -> (),
	FireAll: (self: Handle, ...any) -> (),
}

function ServerBridge.Open(name: string): Handle
	local channel = Channel.Open(name)
	assert(channel:IsServer(), `[Dr.ServerBridge] {name} opened on a client`)

	local handle: Handle = {
		Name = name,
		Connect = function(_self: Handle, fn: (player: Player, ...any) -> ()): RBXScriptConnection
			assert(type(fn) == "function", "[Dr.ServerBridge] Connect expects fn")
			return channel:Connect(function(player, ...)
				assert(
					typeof(player) == "Instance" and player:IsA("Player"),
					"[Dr.ServerBridge] first arg must be Player"
				)
				fn(player :: Player, ...)
			end)
		end,
		Fire = function(_self: Handle, player: Player, ...: any)
			assert(
				typeof(player) == "Instance" and player:IsA("Player"),
				"[Dr.ServerBridge] Fire requires a Player target"
			)
			channel:Fire(player, ...)
		end,
		FireAll = function(_self: Handle, ...: any)
			channel:FireAll(...)
		end,
	}
	return table.freeze(handle)
end

-- Used by Services to compose their outgoing surface without ever naming RemoteEvent.
function ServerBridge.OpenFor(provider: Types.Provider, name: string): Handle
	assert(
		type(provider) == "table" and type(provider.Name) == "string",
		"[Dr.ServerBridge] OpenFor expects provider"
	)
	return ServerBridge.Open(`{provider.Name}::{name}`)
end

return table.freeze(ServerBridge)
