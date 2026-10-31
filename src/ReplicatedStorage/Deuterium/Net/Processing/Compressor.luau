--!strict
-- Dr.Net.Processing.Compressor
-- Minimal run-length encoding on raw buffers. Honest scope: RLE only, no LZ/Huffman.
-- The compression contract is: decode(encode(x)) == x, ALWAYS, with hard expansion caps
-- so a hostile/corrupt payload cannot blow up memory (zip-bomb defense is a hard invariant).

-- 本格式的最大膨胀比是**推出来的**，不是拍的：编码器把最多 130 个相同字节压成 2 个字节
-- （flag + 长度），所以 1 字节编码最坏解出 130 字节 → 上限为 130/2 = **65×**。
-- 旧值 32 会让 Decode 拒收 Encode 自己的输出：任何 65–130 字节的连续重复段（例如 130 个 0）
-- 编码成 2 字节后，outCap = 2×32 = 64 < 130 → 抛 “expansion cap exceeded”。
-- 修复依据与复现：独立复审（subagent, net lane）2026-10-25。
local MAX_EXPAND_FACTOR = 65 -- decoded size may not exceed 65x the encoded size
local MAX_DECODE_BYTES = 1048576 -- absolute ceiling 1 MiB after expansion

local Compressor = {}

-- Format: [u8 flag][u8 value] pairs, flag: high bit 1 = run of (low7+3) repeats of value,
-- high bit 0 = literal run of (low7+1) raw bytes following.
function Compressor.Encode(src: buffer): buffer
	local len = buffer.len(src)
	-- Worst-case output for pure literals: ceil(len/128)*2 + len; allocate generously.
	local out = buffer.create(len * 2 + 16)
	local w = 0
	local i = 0
	while i < len do
		-- try run
		local v = buffer.readu8(src, i)
		local run = 1
		while i + run < len and buffer.readu8(src, i + run) == v and run < 130 do
			run += 1
		end
		if run >= 3 then
			buffer.writeu8(out, w, 0x80 + (run - 3))
			buffer.writeu8(out, w + 1, v)
			w += 2
			i += run
		else
			-- literal block up to 128 bytes
			local litStart = i
			local litLen = 0
			while i < len and litLen < 128 do
				local lv = buffer.readu8(src, i)
				local lookRun = 1
				while i + lookRun < len and buffer.readu8(src, i + lookRun) == lv and lookRun < 3 do
					lookRun += 1
				end
				if lookRun >= 3 then
					break
				end
				i += 1
				litLen += 1
			end
			buffer.writeu8(out, w, litLen - 1)
			w += 1
			buffer.copy(out, w, src, litStart, litLen)
			w += litLen
		end
	end
	local trimmed = buffer.create(w)
	buffer.copy(trimmed, 0, out, 0, w)
	return trimmed
end

function Compressor.Decode(src: buffer): buffer
	local len = buffer.len(src)
	local outCap = math.min(len * MAX_EXPAND_FACTOR, MAX_DECODE_BYTES)
	local out = buffer.create(outCap)
	local w = 0
	local i = 0
	while i < len do
		local flag = buffer.readu8(src, i)
		i += 1
		if flag >= 0x80 then
			-- run
			if i >= len then
				error("[Dr.Compressor] truncated run header", 0)
			end
			local v = buffer.readu8(src, i)
			i += 1
			local run = (flag - 0x80) + 3
			if w + run > outCap then
				error("[Dr.Compressor] expansion cap exceeded", 0)
			end
			for _ = 1, run do
				buffer.writeu8(out, w, v)
				w += 1
			end
		else
			local litLen = flag + 1
			if i + litLen > len then
				error("[Dr.Compressor] truncated literal", 0)
			end
			if w + litLen > outCap then
				error("[Dr.Compressor] expansion cap exceeded", 0)
			end
			buffer.copy(out, w, src, i, litLen)
			w += litLen
			i += litLen
		end
	end
	local trimmed = buffer.create(w)
	buffer.copy(trimmed, 0, out, 0, w)
	return trimmed
end

return table.freeze(Compressor)
