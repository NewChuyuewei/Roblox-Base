--!strict
-- Dr.Net.Core.UnreliableChannel
-- Fire-and-forget handle for loss-tolerant traffic (positions, telemetry).
-- HONEST STATUS: currently rides the same RemoteEvent registry as Channel (reliable,
-- ordered). Swapping to true UnreliableRemoteEvent transport is a W2.5+ backlog
-- decision; the handle shape is final, so the swap stays internal.

local NetworkManager = require(script.Parent.NetworkManager)
local RunContext = require(game:GetService("ReplicatedStorage").Deuterium.Runtime.Environment.RunContext)

local UnreliableChannel = {}

export type Handle = {
	Name: string,
	FireFast: (self: Handle, target: any, ...any) -> (), -- client->server or server->player
}

function UnreliableChannel.Open(name: string): Handle
	assert(type(name) == "string" and #name > 0, "[Dr.UnreliableChannel] name required")
	-- Unreliable channels piggyback on the same registry so channel discovery stays single-map.
	local remote = NetworkManager.GetChannel(name)
	local isServer = RunContext.IsServer()

	local handle: Handle = {
		Name = name,
		FireFast = function(_self: Handle, target: any, ...: any)
			if isServer then
				remote:FireClient(target :: Player, ...)
			else
				remote:FireServer(...)
			end
		end,
	}
	return table.freeze(handle)
end

return table.freeze(UnreliableChannel)
