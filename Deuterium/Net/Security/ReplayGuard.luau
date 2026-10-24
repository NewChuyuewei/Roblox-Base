--!strict
-- Dr.Net.Security.ReplayGuard
-- Rejects replays of authenticated frames: each authenticated frame carries (nonce, timestamp).
-- Window: |now - ts| <= windowSecs. Once-only: nonce is consumed on first sight.
-- Memory discipline: nonces are kept in a bounded ring per subject (no growth).

local RateLimiter = require(script.Parent.RateLimiter)

local DEFAULT_WINDOW = 60 -- seconds
local DEFAULT_RING = 64 -- nonces remembered per subject

local ReplayGuard = {}

export type NonceRing = {
	list: { string },
	set: { [string]: boolean },
	sz: number,
	last: number, -- os.time() of the last touch; drives Sweep
}

local _rings: { [string]: NonceRing } = {}

local function ringFor(key: string, size: number): NonceRing
	local r = _rings[key]
	if r == nil then
		r = { list = {}, set = {}, sz = size, last = os.time() }
		_rings[key] = r
	end
	r.last = os.time() -- touch: rings stay alive while traffic flows
	return r
end

-- Verify a frame stamped (key, nonce, ts). Rejects: stale ts, future ts, reused nonce.
function ReplayGuard.Verify(key: string, nonce: string, ts: number, windowSecs: number?, ringSize: number?): boolean
	assert(type(key) == "string" and #key > 0, "[Dr.ReplayGuard] key required")
	assert(type(nonce) == "string" and #nonce >= 8, "[Dr.ReplayGuard] nonce must be >= 8 chars")
	assert(type(ts) == "number", "[Dr.ReplayGuard] ts must be a number")

	if not RateLimiter.Allow(`replay:{key}`, 1, 30, 30) then
		return false -- global throttle even on the verification path
	end

	local window = windowSecs or DEFAULT_WINDOW
	local now = os.time()
	if math.abs(now - ts) > window then
		return false
	end

	local ring = ringFor(key, ringSize or DEFAULT_RING)
	if ring.set[nonce] then
		return false -- replay
	end

	-- consume: push into ring, evict oldest
	ring.set[nonce] = true
	table.insert(ring.list, nonce)
	if #ring.list > ring.sz then
		local oldest = table.remove(ring.list, 1)
		if oldest ~= nil then
			ring.set[oldest] = nil
		end
	end
	return true
end

function ReplayGuard.Remembered(key: string): number
	local ring = _rings[key]
	if ring == nil then
		return 0
	end
	return #ring.list
end

-- Cold-path maintenance: drop rings idle longer than `staleSeconds` (departed players).
-- Note: an attacker still spamming (already throttled to 30/s) keeps their ring alive —
-- that ring is bounded at `sz` nonces, so the abuse cost is capped by design.
function ReplayGuard.Sweep(staleSeconds: number): number
	assert(type(staleSeconds) == "number" and staleSeconds > 0, "[Dr.ReplayGuard] staleSeconds must be > 0")
	local now = os.time()
	local removed = 0
	for key, ring in _rings do
		if now - ring.last >= staleSeconds then
			_rings[key] = nil
			removed += 1
		end
	end
	return removed
end

function ReplayGuard.Reset(): ()
	_rings = {}
end

return table.freeze(ReplayGuard)
