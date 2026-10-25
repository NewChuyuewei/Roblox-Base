--!strict
-- Dr.Net.Processing.Packet
-- The transport envelope. Binary layout (little-endian, native):
--   u16 opId | u32 payloadByteLen | payload bytes
-- Strict length prefixing + bounded read = the wire cannot make us read out of bounds.

local ErrorHandler = require(game:GetService("ReplicatedStorage").Deuterium.Core.Foundation.ErrorHandler)

local HEADER_SIZE = 6 -- u16 + u32
local MAX_PAYLOAD_BYTES = 4096 -- hard cap, W2.3 validator enforces smaller per-channel

local Packet = {}

export type Envelope = {
	opId: number,
	payload: buffer,
}

function Packet.Encode(opId: number, payload: buffer): buffer
	assert(type(opId) == "number" and opId >= 0 and opId <= 0xFFFF, "[Dr.Packet] opId must be u16")
	local payloadLen = buffer.len(payload)
	if payloadLen > MAX_PAYLOAD_BYTES then
		ErrorHandler.Raise(
			"DR.NET.PACKET.OVERSIZE",
			`payload {payloadLen}B > {MAX_PAYLOAD_BYTES}B`,
			"Dr.Packet"
		)
	end
	local out = buffer.create(HEADER_SIZE + payloadLen)
	buffer.writeu16(out, 0, opId)
	buffer.writeu32(out, 2, payloadLen)
	buffer.copy(out, HEADER_SIZE, payload, 0, payloadLen)
	return out
end

-- Returns (opId, payload) or throws on a malformed/oversized packet.
function Packet.Decode(buf: buffer): Envelope
	local len = buffer.len(buf)
	if len < HEADER_SIZE then
		ErrorHandler.Raise("DR.NET.PACKET.SHORT", `packet {len}B < header {HEADER_SIZE}B`, "Dr.Packet")
	end
	local opId = buffer.readu16(buf, 0)
	local payloadLen = buffer.readu32(buf, 2)
	if payloadLen > MAX_PAYLOAD_BYTES then
		ErrorHandler.Raise(
			"DR.NET.PACKET.OVERSIZE",
			`declared {payloadLen}B > {MAX_PAYLOAD_BYTES}B`,
			"Dr.Packet"
		)
	end
	if len - HEADER_SIZE < payloadLen then
		ErrorHandler.Raise(
			"DR.NET.PACKET.TRUNCATED",
			`payload {len - HEADER_SIZE}B < declared {payloadLen}B`,
			"Dr.Packet"
		)
	end
	local payload = buffer.create(payloadLen)
	if payloadLen > 0 then
		buffer.copy(payload, 0, buf, HEADER_SIZE, payloadLen)
	end
	return table.freeze({ opId = opId, payload = payload }) :: any
end

return table.freeze(Packet)
