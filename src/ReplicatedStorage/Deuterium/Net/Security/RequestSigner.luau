--!strict
-- Dr.Net.Security.RequestSigner
-- Frame authentication: sign (nonce, ts, payload) with a server-held secret via
-- HMAC-SHA256. The secret never crosses the wire. Verify = signature check FIRST
-- (constant-time compare), then ReplayGuard window/nonce consumption — a failed
-- signature does not burn a nonce slot.

local Hmac = require(game:GetService("ReplicatedStorage").Deuterium.Security.Crypto.Hmac)
local ReplayGuard = require(script.Parent.ReplayGuard)

local RequestSigner = {}

local function constantTimeEqual(a: string, b: string): boolean
	if #a ~= #b then
		return false
	end
	local acc = 0
	for i = 1, #a do
		acc = bit32.bxor(acc, bit32.bxor(string.byte(a, i), string.byte(b, i)))
	end
	return acc == 0
end

local function bodyOf(payload: buffer | string): string
	return if typeof(payload) == "buffer" then buffer.tostring(payload) else payload
end

function RequestSigner.Sign(secret: string, nonce: string, ts: number, payload: buffer | string): string
	assert(type(secret) == "string" and #secret >= 16, "[Dr.RequestSigner] secret must be >= 16 chars")
	assert(type(nonce) == "string" and #nonce >= 8, "[Dr.RequestSigner] nonce must be >= 8 chars")
	assert(type(ts) == "number", "[Dr.RequestSigner] ts must be a number")
	return Hmac.Sha256(secret, nonce .. "|" .. ts .. "|" .. bodyOf(payload))
end

-- Full gate: authentic signature + fresh (non-replayed) nonce inside the time window.
function RequestSigner.Verify(
	subject: string,
	secret: string,
	nonce: string,
	ts: number,
	payload: buffer | string,
	signature: string,
	windowSecs: number?
): boolean
	assert(type(subject) == "string" and #subject > 0, "[Dr.RequestSigner] subject required")
	local expected = Hmac.Sha256(secret, nonce .. "|" .. ts .. "|" .. bodyOf(payload))
	if not constantTimeEqual(expected, signature) then
		return false
	end
	return ReplayGuard.Verify(subject, nonce, ts, windowSecs)
end

return table.freeze(RequestSigner)
