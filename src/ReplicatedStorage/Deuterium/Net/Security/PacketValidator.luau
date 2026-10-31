--!strict
-- Dr.Net.Security.PacketValidator
-- Structural sanity check fire-walled at the channel edge: any syntactically corrupt
-- packet is rejected BEFORE it can reach the app's schema layer. Defensive by default.

local Packet = require(script.Parent.Parent.Processing.Packet)

local PacketValidator = {}

export type Verdict = {
	ok: boolean,
	reason: string?,
	payload: buffer?, -- decoded payload buffer, set iff ok
	opId: number?, -- envelope op id, set iff ok
}

-- Structural check on an encoded envelope. Never throws; verdict is a frozen table.
function PacketValidator.Check(buf: buffer, maxBytes: number): Verdict
	assert(type(maxBytes) == "number" and maxBytes > 0, "[Dr.PacketValidator] maxBytes must be > 0")
	local size = buffer.len(buf)
	if size > maxBytes then
		return table.freeze({ ok = false, reason = `oversize {size}B > {maxBytes}B` }) :: any
	end

	-- 每包验证都在热路径上：不要为此分配匿名闭包（P0 规约）。
	-- Packet.Decode 的签名就是 (buf)，可以直接交给 pcall。
	local ok, envelope = pcall(Packet.Decode, buf)
	if not ok then
		return table.freeze({ ok = false, reason = `malformed: {tostring(envelope)}` }) :: any
	end

	return table.freeze({
		ok = true,
		reason = nil,
		payload = envelope.payload,
		opId = envelope.opId,
	}) :: any
end

return table.freeze(PacketValidator)
