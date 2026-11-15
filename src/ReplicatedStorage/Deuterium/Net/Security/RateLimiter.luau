--!strict
-- Dr.Net.Security.RateLimiter
-- Token bucket per subject. Hot path is allocation-free: one hash read + in-place decrement.

local RateLimiter = {}

export type Bucket = {
	cap: number,
	rate: number, -- tokens per second
	tokens: number,
	last: number, -- clock reading at the last refill
}

local _buckets: { [string]: Bucket } = {}

local function systemClock(): number
	return os.clock()
end

-- Time source. Production always uses os.clock; tests swap it via SetClock so that
-- refill and sweep behaviour can be asserted without sleeping.
local _now: () -> number = systemClock

local function refill(bucket: Bucket)
	local now = _now()
	local elapsed = now - bucket.last
	if elapsed > 0 then
		bucket.tokens = math.min(bucket.cap, bucket.tokens + elapsed * bucket.rate)
		bucket.last = now
	end
end

-- One bucket key per subject (player id, request kind...). Create-if-missing.
function RateLimiter.Allow(key: string, cost: number?, cap: number?, ratePerSec: number?): boolean
	assert(type(key) == "string" and #key > 0, "[Dr.RateLimiter] key must be non-empty string")
	local bucket = _buckets[key]
	if bucket == nil then
		local c = cap or 10
		bucket = {
			cap = c,
			rate = ratePerSec or 10,
			tokens = c,
			last = _now(),
		}
		_buckets[key] = bucket
	end
	refill(bucket)
	local c = cost or 1
	if bucket.tokens >= c then
		bucket.tokens -= c
		return true
	end
	return false
end

function RateLimiter.Snapshot(key: string): { tokens: number, cap: number, rate: number }?
	local bucket = _buckets[key]
	if bucket == nil then
		return nil
	end
	return table.freeze({ tokens = bucket.tokens, cap = bucket.cap, rate = bucket.rate })
end

-- Cold-path maintenance: drop buckets idle longer than `staleSeconds` (departed players).
-- Call from PlayerRemoving or a periodic janitor; never from a hot path.
function RateLimiter.Sweep(staleSeconds: number): number
	assert(type(staleSeconds) == "number" and staleSeconds > 0, "[Dr.RateLimiter] staleSeconds must be > 0")
	local now = _now()
	local removed = 0
	for key, bucket in _buckets do
		if now - bucket.last >= staleSeconds then
			_buckets[key] = nil
			removed += 1
		end
	end
	return removed
end

function RateLimiter.SetClock(clock: (() -> number)?): () -- Test-only; nil restores os.clock
	_now = clock or systemClock
end

function RateLimiter.Reset(): () -- Test-only
	_buckets = {}
end

return table.freeze(RateLimiter)
