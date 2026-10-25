--!strict
-- Dr.Security.Crypto.Hmac
-- HMAC-SHA256 (RFC 2104) over the pure-Luau SHA-256.
-- Key rules: >64-byte keys are hashed first; ipad/opad are 64 bytes each.
-- Scope: auth paths; allocates ~128 bytes of pads per call by design.

local Sha256 = require(script.Parent.Sha256)

local Hmac = {}

function Hmac.Sha256(key: string, message: string): string
	assert(type(key) == "string", "[Dr.Hmac] key must be a string")
	assert(type(message) == "string", "[Dr.Hmac] message must be a string")

	if #key > 64 then
		key = Sha256.Hash(key)
	end

	local ipadParts = table.create(64)
	local opadParts = table.create(64)
	for i = 1, 64 do
		local kb = if i <= #key then string.byte(key, i) else 0
		ipadParts[i] = string.char(bit32.bxor(kb, 0x36))
		opadParts[i] = string.char(bit32.bxor(kb, 0x5c))
	end
	local inner = Sha256.Hash(table.concat(ipadParts) .. message)
	return Sha256.Hash(table.concat(opadParts) .. inner)
end

return table.freeze(Hmac)
