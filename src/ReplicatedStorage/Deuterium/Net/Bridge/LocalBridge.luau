--!strict
-- Dr.Net.Bridge.LocalBridge
-- In-memory direct channel: no RemoteEvent at all. Same handle shape as the real
-- bridges — used for Studio selftests, local mode (host = client), and hotwiring
-- simulations. No replication, no ordering guarantees beyond call sequence.

local LocalBridge = {}

export type Handle = {
	Name: string,
	Connect: (self: Handle, fn: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: Handle, target: any, ...any) -> (),
	FireAll: (self: Handle, ...any) -> (),
}

-- BindableEvent gives us a friendly in-memory signal; we never replicate it.
local function makeBindable(name: string): BindableEvent
	local b = Instance.new("BindableEvent")
	b.Name = name
	return b
end

function LocalBridge.Open(name: string): Handle
	assert(type(name) == "string" and #name > 0, "[Dr.LocalBridge] name required")
	local bindable = makeBindable(`Local:{name}`)

	local handle: Handle = {
		Name = name,
		Connect = function(_self: Handle, fn: (...any) -> ()): RBXScriptConnection
			assert(type(fn) == "function", "[Dr.LocalBridge] Connect expects fn")
			return bindable.Event:Connect(fn)
		end,
		Fire = function(_self: Handle, _target: any, ...: any)
			bindable:Fire(...)
		end,
		FireAll = function(_self: Handle, ...: any)
			bindable:Fire(...)
		end,
	}
	return table.freeze(handle)
end

return table.freeze(LocalBridge)
