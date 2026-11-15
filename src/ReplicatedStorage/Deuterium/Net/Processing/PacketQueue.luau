--!strict
-- Dr.Net.Processing.PacketQueue
-- Per-channel outbox. Push is one table write; Flush hands the batch to a consumer
-- function and clears. Hard caps reject oversize payloads BEFORE the buffer exists —
-- never allocate memory for a packet we are about to drop.

local MAX_PENDING = 64 -- per channel; beyond this we drop + count instead of RAM-growing

local PacketQueue = {}

export type Queue = {
	Push: (payload: buffer) -> boolean, -- false = dropped (cap hit or oversize)
	Flush: (consume: (payloads: { buffer }) -> ()) -> number, -- # payloads consumed
	Dropped: () -> number,
	Pending: () -> number,
}

local _queues: { [string]: { list: { buffer }, dropped: number } } = {}

function PacketQueue.Open(channel: string, maxPayloadBytes: number): Queue
	assert(type(channel) == "string" and #channel > 0, "[Dr.PacketQueue] channel name required")
	assert(
		type(maxPayloadBytes) == "number" and maxPayloadBytes > 0,
		"[Dr.PacketQueue] maxPayloadBytes must be > 0"
	)
	assert(_queues[channel] == nil, `[Dr.PacketQueue] duplicate queue: {channel}`)

	local slot = { list = {} :: { buffer }, dropped = 0 }
	_queues[channel] = slot

	return table.freeze({
		Push = function(payload: buffer): boolean
			if buffer.len(payload) > maxPayloadBytes then
				slot.dropped += 1
				return false
			end
			local list = slot.list
			local pending = #list -- measured once, reused for the append
			if pending >= MAX_PENDING then
				slot.dropped += 1
				return false
			end
			list[pending + 1] = payload
			return true
		end,
		Flush = function(consume: (payloads: { buffer }) -> ()): number
			local n = #slot.list
			if n == 0 then
				return 0
			end
			local batch = slot.list
			slot.list = table.create(8)
			consume(batch)
			return n
		end,
		Dropped = function(): number
			return slot.dropped
		end,
		Pending = function(): number
			return #slot.list
		end,
	}) :: any
end

function PacketQueue.Reset(): () -- Test-only
	_queues = {}
end

return table.freeze(PacketQueue)
