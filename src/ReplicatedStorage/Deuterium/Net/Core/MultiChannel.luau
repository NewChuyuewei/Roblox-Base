--!strict
-- Dr.Net.Core.MultiChannel
-- Fans one logical send across multiple channels with identical payload. Zero-allocation
-- on the hot path: channel list is frozen at Open time; Send is one loop over array
-- entries (pre-bound handles), no string lookup per send.

local Channel = require(script.Parent.Channel)

local MultiChannel = {}

export type Handle = {
	Names: { string },
	Send: (self: Handle, target: any, ...any) -> (), -- target only used on server
	SendToAll: (self: Handle, ...any) -> (),
}

function MultiChannel.Open(names: { string }): Handle
	assert(type(names) == "table", "[Dr.MultiChannel] names must be a table")
	assert(#names > 0, "[Dr.MultiChannel] names must not be empty")
	local channels = table.create(#names)
	for i, name in names do
		channels[i] = Channel.Open(name)
	end
	local frozenNames = table.freeze(table.clone(names))
	local frozenChannels = table.freeze(channels)

	local handle: Handle = {
		Names = frozenNames,
		Send = function(_self: Handle, target: any, ...: any)
			for _, ch in frozenChannels do
				ch:Fire(target, ...)
			end
		end,
		SendToAll = function(_self: Handle, ...: any)
			for _, ch in frozenChannels do
				ch:FireAll(...)
			end
		end,
	}
	return table.freeze(handle)
end

return table.freeze(MultiChannel)
