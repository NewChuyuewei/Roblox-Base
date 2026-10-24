--!strict
-- Dr.Security.Crypto.Sha256
-- Pure-Luau SHA-256 (FIPS 180-4). Zero dependencies.
-- Correctness is pinned by NIST known-answer vectors in Net/Security/SelfTest
-- (empty string + "abc" + HMAC RFC 4231). Scope: auth/startup paths only —
-- the byte-array padding allocates by design; never call this per-frame.

local Sha256 = {}

local K = {
	0x428a2f98,
	0x71374491,
	0xb5c0fbcf,
	0xe9b5dba5,
	0x3956c25b,
	0x59f111f1,
	0x923f82a4,
	0xab1c5ed5,
	0xd807aa98,
	0x12835b01,
	0x243185be,
	0x550c7dc3,
	0x72be5d74,
	0x80deb1fe,
	0x9bdc06a7,
	0xc19bf174,
	0xe49b69c1,
	0xefbe4786,
	0x0fc19dc6,
	0x240ca1cc,
	0x2de92c6f,
	0x4a7484aa,
	0x5cb0a9dc,
	0x76f988da,
	0x983e5152,
	0xa831c66d,
	0xb00327c8,
	0xbf597fc7,
	0xc6e00bf3,
	0xd5a79147,
	0x06ca6351,
	0x14292967,
	0x27b70a85,
	0x2e1b2138,
	0x4d2c6dfc,
	0x53380d13,
	0x650a7354,
	0x766a0abb,
	0x81c2c92e,
	0x92722c85,
	0xa2bfe8a1,
	0xa81a664b,
	0xc24b8b70,
	0xc76c51a3,
	0xd192e819,
	0xd6990624,
	0xf40e3585,
	0x106aa070,
	0x19a4c116,
	0x1e376c08,
	0x2748774c,
	0x34b0bcb5,
	0x391c0cb3,
	0x4ed8aa4a,
	0x5b9cca4f,
	0x682e6ff3,
	0x748f82ee,
	0x78a5636f,
	0x84c87814,
	0x8cc70208,
	0x90befffa,
	0xa4506ceb,
	0xbef9a3f7,
	0xc67178f2,
}

local function rrot(x: number, n: number): number
	return bit32.bor(bit32.rshift(x, n), bit32.lshift(x, 32 - n))
end

local function bytesToString(list: { number }): string
	local parts = table.create(#list)
	for i, v in list do
		parts[i] = string.char(v)
	end
	return table.concat(parts)
end

function Sha256.Hash(data: string): string
	local len = #data
	local bitLen = len * 8

	-- Preprocessing: [data][0x80][zeros...][64-bit big-endian bit length]
	local bytes = table.create(len + 72) :: { number }
	local n = 0
	for i = 1, len do
		n += 1
		bytes[n] = string.byte(data, i)
	end
	n += 1
	bytes[n] = 0x80
	while (n % 64) ~= 56 do
		n += 1
		bytes[n] = 0
	end
	-- Bit length as two 32-bit words (messages stay well under 2^53 bits).
	local hi = math.floor(bitLen / 4294967296)
	local lo = bitLen % 4294967296
	n += 1
	bytes[n] = bit32.rshift(hi, 24)
	n += 1
	bytes[n] = bit32.band(bit32.rshift(hi, 16), 0xFF)
	n += 1
	bytes[n] = bit32.band(bit32.rshift(hi, 8), 0xFF)
	n += 1
	bytes[n] = bit32.band(hi, 0xFF)
	n += 1
	bytes[n] = bit32.rshift(lo, 24)
	n += 1
	bytes[n] = bit32.band(bit32.rshift(lo, 16), 0xFF)
	n += 1
	bytes[n] = bit32.band(bit32.rshift(lo, 8), 0xFF)
	n += 1
	bytes[n] = bit32.band(lo, 0xFF)

	local h = {
		0x6a09e667,
		0xbb67ae85,
		0x3c6ef372,
		0xa54ff53a,
		0x510e527f,
		0x9b05688c,
		0x1f83d9ab,
		0x5be0cd19,
	}
	local W = table.create(64) :: { number }

	local blockStart = 1
	while blockStart <= n do
		-- Message schedule, first 16 words straight from the block.
		for t = 0, 15 do
			local b = blockStart + t * 4
			W[t + 1] = bit32.bor(
				bit32.lshift(bytes[b], 24),
				bit32.lshift(bytes[b + 1], 16),
				bit32.lshift(bytes[b + 2], 8),
				bytes[b + 3]
			)
		end
		-- Remaining 48 words.
		for t = 16, 63 do
			local w15 = W[t - 14] -- W[t-15]
			local w2 = W[t - 1] -- W[t-2]
			local s0 = bit32.bxor(rrot(w15, 7), rrot(w15, 18), bit32.rshift(w15, 3))
			local s1 = bit32.bxor(rrot(w2, 17), rrot(w2, 19), bit32.rshift(w2, 10))
			W[t + 1] = (W[t - 15] + s0 + W[t - 6] + s1) % 4294967296 -- W[t-16] + s0 + W[t-7] + s1
		end

		-- Compression.
		local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
		for t = 0, 63 do
			local S1 = bit32.bxor(rrot(e, 6), rrot(e, 11), rrot(e, 25))
			local ch = bit32.bxor(bit32.band(e, f), bit32.band(bit32.bnot(e), g))
			local temp1 = (hh + S1 + ch + K[t + 1] + W[t + 1]) % 4294967296
			local S0 = bit32.bxor(rrot(a, 2), rrot(a, 13), rrot(a, 22))
			local maj = bit32.bxor(bit32.band(a, b), bit32.band(a, c), bit32.band(b, c))
			local temp2 = (S0 + maj) % 4294967296
			hh = g
			g = f
			f = e
			e = (d + temp1) % 4294967296
			d = c
			c = b
			b = a
			a = (temp1 + temp2) % 4294967296
		end
		h[1] = (h[1] + a) % 4294967296
		h[2] = (h[2] + b) % 4294967296
		h[3] = (h[3] + c) % 4294967296
		h[4] = (h[4] + d) % 4294967296
		h[5] = (h[5] + e) % 4294967296
		h[6] = (h[6] + f) % 4294967296
		h[7] = (h[7] + g) % 4294967296
		h[8] = (h[8] + hh) % 4294967296

		blockStart += 64
	end

	-- Digest: 8 words, big-endian bytes.
	local out = table.create(32)
	local pos = 1
	for _, w in h do
		out[pos] = bit32.rshift(w, 24)
		out[pos + 1] = bit32.band(bit32.rshift(w, 16), 0xFF)
		out[pos + 2] = bit32.band(bit32.rshift(w, 8), 0xFF)
		out[pos + 3] = bit32.band(w, 0xFF)
		pos += 4
	end
	return bytesToString(out)
end

-- Hex rendering for tests and diagnostics.
function Sha256.ToHex(bytes: string): string
	local parts = table.create(#bytes)
	for i = 1, #bytes do
		parts[i] = string.format("%02x", string.byte(bytes, i))
	end
	return table.concat(parts)
end

return table.freeze(Sha256)
