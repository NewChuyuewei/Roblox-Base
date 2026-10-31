--!strict
-- Dr.Net.Core.Channel
-- Thin, typed wrapper around one RemoteEvent.
-- - Connections returned by Connect are tracked by ConnectionPool (no leaks).
-- - Fire* on server accept Player or list; on client FireServer only.
-- - No payload validation here: that is Net.Processing's job (W2.3). This layer is pure plumbing.

local NetworkManager = require(script.Parent.NetworkManager)
local ConnectionPool = require(script.Parent.ConnectionPool)
local RunContext = require(script.Parent.Parent.Parent.Runtime.Environment.RunContext)

local Channel = {}

export type Handle = {
	Name: string,
	Connect: (self: Handle, fn: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: Handle, target: any, ...any) -> (),
	FireAll: (self: Handle, ...any) -> (),
	IsServer: (self: Handle) -> boolean,
}

function Channel.Open(name: string): Handle
	assert(type(name) == "string" and #name > 0, "[Dr.Channel] channel name required")
	local remote = NetworkManager.GetChannel(name)

	local isServer = RunContext.IsServer()

	local handle: Handle = {
		Name = name,
		Connect = function(_self: Handle, fn: (...any) -> ()): RBXScriptConnection
			assert(type(fn) == "function", "[Dr.Channel] Connect expects a function")
			local conn
			if isServer then
				conn = remote.OnServerEvent:Connect(fn)
			else
				conn = remote.OnClientEvent:Connect(fn)
			end
			ConnectionPool.Give(conn)
			return conn
		end,
		Fire = function(_self: Handle, target: any, ...: any)
			if isServer then
				remote:FireClient(target :: Player, ...) -- target: Player
			else
				(remote :: RemoteEvent):FireServer(...)
			end
		end,
		FireAll = function(_self: Handle, ...: any)
			assert(isServer, "[Dr.Channel] FireAll is server-only")
			remote:FireAllClients(...)
		end,
		IsServer = function(_self: Handle): boolean
			return isServer
		end,
	}
	return table.freeze(handle)
end

return table.freeze(Channel)
