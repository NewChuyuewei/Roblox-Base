--!strict
-- Dr.Net.Security.SelfTest — W2.3 acceptance: rate limit, replay window, validator,
-- and crypto KATs (SHA-256 NIST + HMAC RFC 4231). Command bar:
--   require(game.ReplicatedStorage.Deuterium.Net.Security.SelfTest).RunAll()

local Debug = require(script.Parent.Parent.Parent.Parent.Debug)
local ErrorHandler = require(script.Parent.Parent.Parent.Core.Foundation.ErrorHandler)

local RunContext = require(script.Parent.Parent.Parent.Runtime.Environment.RunContext)
local Sha256 = require(script.Parent.Parent.Parent.Security.Crypto.Sha256)
local Hmac = require(script.Parent.Parent.Parent.Security.Crypto.Hmac)
local RateLimiter = require(script.Parent.RateLimiter)
local ReplayGuard = require(script.Parent.ReplayGuard)
local PacketValidator = require(script.Parent.PacketValidator)
local RequestSigner = require(script.Parent.RequestSigner)
local Packet = require(script.Parent.Parent.Processing.Packet)

local SelfTest = {}

local function check(name: string, fn: () -> ()): (boolean, string)
	local err: unknown = nil
	local ok = xpcall(fn, function(e)
		err = ErrorHandler.Render(e)
	end)
	return ok, if ok then name else (name .. " -> " .. tostring(err))
end

local function expect(cond: boolean, what: string)
	assert(cond, what)
end

function SelfTest.RunAll(): boolean
	assert(RunContext.IsStudio(), "[Dr.SelfTest.Security] Studio-only")
	local failures = 0
	local function record(label: string, ok: boolean, msg: string)
		if ok then
			Debug.print("[Dr.SelfTest.Security] PASS", label)
		else
			failures += 1
			Debug.warn("[Dr.SelfTest.Security] FAIL", msg)
		end
	end

	local tests = {
		{
			name = "rate limiter: cap enforced, rate 0 never refills",
			fn = function()
				RateLimiter.Reset()
				local key = "W23.cap"
				expect(RateLimiter.Allow(key, 1, 3, 0), "1st")
				expect(RateLimiter.Allow(key, 1, 3, 0), "2nd")
				expect(RateLimiter.Allow(key, 1, 3, 0), "3rd")
				expect(not RateLimiter.Allow(key, 1, 3, 0), "4th rejected")
				expect(not RateLimiter.Allow(key, 1, 3, 0), "still rejected (rate 0)")
				local snap = RateLimiter.Snapshot(key)
				expect(snap ~= nil and (snap :: any).cap == 3, "snapshot shape")
			end,
		},
		{
			name = "rate limiter: refills over time",
			fn = function()
				RateLimiter.Reset()
				local t = 100 -- injected clock: no real sleeping, no dependence on timer granularity
				RateLimiter.SetClock(function()
					return t
				end)
				local key = "W23.refill"
				expect(RateLimiter.Allow(key, 1, 1, 10000), "drain the single token")
				expect(not RateLimiter.Allow(key, 1, 1, 10000), "empty right after")
				t += 0.02 -- 20ms at 10000/s = 200 tokens worth, capped at 1
				expect(RateLimiter.Allow(key, 1, 1, 10000), "refilled")
				expect(not RateLimiter.Allow(key, 1, 1, 10000), "refill is capped at 1 token")
			end,
		},
		{
			name = "replay guard: fresh ok / replay no / stale no / future no",
			fn = function()
				RateLimiter.Reset()
				ReplayGuard.Reset()
				local now = os.time()
				expect(ReplayGuard.Verify("W23.sub", "nonceAAAA1", now), "fresh accepted")
				expect(not ReplayGuard.Verify("W23.sub", "nonceAAAA1", now), "replay rejected")
				expect(not ReplayGuard.Verify("W23.sub", "nonceBBBB2", now - 3600), "stale rejected")
				expect(not ReplayGuard.Verify("W23.sub", "nonceCCCC3", now + 3600), "future rejected")
			end,
		},
		{
			name = "replay guard: ring eviction re-admits oldest nonce",
			fn = function()
				RateLimiter.Reset()
				ReplayGuard.Reset()
				local now = os.time()
				for i = 1, 6 do
					expect(
						ReplayGuard.Verify("W23.ring", string.format("nonce%04d", i), now, nil, 4),
						`nonce {i} accepted`
					)
				end
				-- ring size 4 → nonces 1,2 evicted; resubmitting 1 is accepted again.
				expect(ReplayGuard.Remembered("W23.ring") == 4, "ring stays at its size")
				expect(not ReplayGuard.Verify("W23.ring", "nonce0006", now, nil, 4), "newest still remembered")
				expect(not ReplayGuard.Verify("W23.ring", "nonce0003", now, nil, 4), "oldest survivor remembered")
				expect(ReplayGuard.Verify("W23.ring", "nonce0001", now, nil, 4), "evicted nonce re-admitted")
				-- re-admitting 1 evicted 3 (the oldest), so 3 is accepted again — and evicts 4 in turn.
				expect(ReplayGuard.Verify("W23.ring", "nonce0003", now, nil, 4), "wraparound evicts oldest")
				expect(not ReplayGuard.Verify("W23.ring", "nonce0005", now, nil, 4), "5 not evicted yet")
				expect(ReplayGuard.Remembered("W23.ring") == 4, "ring still at its size")
			end,
		},
		{
			name = "packet validator: ok / oversize / garbage",
			fn = function()
				local inner = buffer.create(4)
				buffer.writeu32(inner, 0, 0xDEADBEEF)
				local env = Packet.Encode(7, inner)
				local ok = PacketValidator.Check(env, 512)
				expect((ok :: any).ok, "valid envelope passes")
				expect((ok :: any).opId == 7, "opId surfaced")
				local big = Packet.Encode(7, buffer.create(2048)) -- >512 maxBytes, but legal at encode
				expect(not (PacketValidator.Check(big, 512) :: any).ok, "oversize rejected")
				local junk = buffer.create(4) -- shorter than a header
				expect(not (PacketValidator.Check(junk, 512) :: any).ok, "garbage rejected")
			end,
		},
		{
			name = "sha256: NIST known-answer vectors",
			fn = function()
				expect(
					Sha256.ToHex(Sha256.Hash(""))
						== "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
					"empty-string vector"
				)
				expect(
					Sha256.ToHex(Sha256.Hash("abc"))
						== "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
					"abc vector"
				)
				expect(#Sha256.Hash("anything") == 32, "digest is 32 bytes")
			end,
		},
		{
			name = "hmac: RFC 4231 test case 2 (key 0x0b x20, 'Hi There')",
			fn = function()
				local key = string.rep("\11", 20)
				local mac = Hmac.Sha256(key, "Hi There")
				expect(
					Sha256.ToHex(mac) == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
					"RFC 4231 TC2 vector"
				)
			end,
		},
		{
			name = "request signer: sign/verify, tamper, wrong sig, replay",
			fn = function()
				RateLimiter.Reset()
				ReplayGuard.Reset()
				local secret = "unit-test-secret-0123456789"
				local payload = buffer.create(8)
				buffer.writeu32(payload, 0, 1)
				buffer.writeu32(payload, 4, 2)
				local nonce = "nonceXYZ99"
				local ts = os.time()

				local sig = RequestSigner.Sign(secret, nonce, ts, payload)
				expect(#sig == 32, "signature is 32 bytes")
				expect(
					RequestSigner.Verify("W23.sign", secret, nonce, ts, payload, sig),
					"authentic frame accepted"
				)

				-- Tampered payload, same signature → reject.
				local tampered = buffer.create(8)
				buffer.writeu32(tampered, 0, 999)
				buffer.writeu32(tampered, 4, 2)
				expect(
					not RequestSigner.Verify("W23.sign", secret, nonce, ts, tampered, sig),
					"tampered payload rejected"
				)

				-- Wrong signature → reject (and does not consume the nonce).
				expect(
					not RequestSigner.Verify("W23.sign2", secret, nonce, ts, payload, string.rep("\0", 32)),
					"wrong signature rejected"
				)

				-- Replay of the already-consumed frame → reject.
				expect(
					not RequestSigner.Verify("W23.sign", secret, nonce, ts, payload, sig),
					"replayed frame rejected"
				)

				-- Fresh frame with a new nonce → accepted.
				local nonce2 = "nonceXYZ9A"
				local sig2 = RequestSigner.Sign(secret, nonce2, ts, payload)
				expect(
					RequestSigner.Verify("W23.sign", secret, nonce2, ts, payload, sig2),
					"fresh frame accepted"
				)
			end,
		},
		{
			name = "rate limiter sweep removes idle buckets",
			fn = function()
				RateLimiter.Reset()
				local t = 100
				RateLimiter.SetClock(function()
					return t
				end)
				RateLimiter.Allow("W23.sweepA", 1, 1, 0)
				RateLimiter.Allow("W23.sweepB", 1, 1, 0)
				local fresh = RateLimiter.Sweep(60)
				expect(fresh == 0, "fresh buckets survive")
				t += 0.1
				local removed = RateLimiter.Sweep(0.05)
				expect(removed >= 2, "idle buckets removed")
				expect(RateLimiter.Snapshot("W23.sweepA") == nil, "bucket gone")
			end,
		},
		{
			name = "replay guard sweep removes idle rings",
			fn = function()
				RateLimiter.Reset()
				ReplayGuard.Reset()
				local now = 1000
				ReplayGuard.SetClock(function()
					return now
				end)
				expect(ReplayGuard.Verify("W23.sweepR", "nonceSWEEP1", now), "ring created")
				expect(ReplayGuard.Sweep(60) == 0, "fresh ring survives")
				expect(ReplayGuard.Remembered("W23.sweepR") == 1, "ring alive")
				now += 2 -- idle past the 1s stale window
				local removed = ReplayGuard.Sweep(1)
				expect(removed >= 1, "idle ring removed")
				expect(ReplayGuard.Remembered("W23.sweepR") == 0, "ring gone")
			end,
		},
	}

	for _, entry in tests do
		local ok, msg = check(entry.name, entry.fn)
		-- a case may have swapped a clock (and may have failed before restoring it)
		RateLimiter.SetClock(nil)
		ReplayGuard.SetClock(nil)
		record(entry.name, ok, msg)
	end

	Debug.print(("[Dr.SelfTest.Security] %d/%d passed"):format(#tests - failures, #tests))
	return failures == 0
end

return SelfTest
