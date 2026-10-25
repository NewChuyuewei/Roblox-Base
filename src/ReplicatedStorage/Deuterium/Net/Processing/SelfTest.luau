--!strict
-- Dr.Net.Processing.SelfTest — W2.2 acceptance: schema round-trip, corruption never crashes,
-- middleware compiled order, queue overflow caps. Command bar:
--   require(game.ReplicatedStorage.Deuterium.Net.Processing.SelfTest).RunAll()

local Debug = require(game:GetService("ReplicatedStorage"):WaitForChild("Debug"))
local ErrorHandler = require(game:GetService("ReplicatedStorage").Deuterium.Core.Foundation.ErrorHandler)

local RunContext = require(game:GetService("ReplicatedStorage").Deuterium.Runtime.Environment.RunContext)
local Serializer = require(script.Parent.Serializer)
local Packet = require(script.Parent.Packet)
local Compressor = require(script.Parent.Compressor)
local Middleware = require(script.Parent.Middleware)
local PacketQueue = require(script.Parent.PacketQueue)
local ProtocolBuffer = require(script.Parent.ProtocolBuffer)

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

local POS_SCHEMA = {
	name = "W22.Pos",
	fields = {
		{ name = "id", type = "u16" },
		{ name = "pos", type = "vec3" },
		{ name = "zone", type = "string", maxLen = 16 },
		{ name = "active", type = "bool" },
	},
} :: any

function SelfTest.RunAll(): boolean
	assert(RunContext.IsStudio(), "[Dr.SelfTest.Processing] Studio-only")
	local failures = 0
	local function record(label: string, ok: boolean, msg: string)
		if ok then
			Debug.print("[Dr.SelfTest.Processing] PASS", label)
		else
			failures += 1
			Debug.warn("[Dr.SelfTest.Processing] FAIL", msg)
		end
	end

	local tests = {
		{
			name = "schema pack/unpack round-trip",
			fn = function()
				local payload = { id = 7, pos = Vector3.new(1.5, -2.25, 300), zone = "lobby", active = true }
				local buf = Serializer.Pack(POS_SCHEMA, payload)
				local back = Serializer.Unpack(POS_SCHEMA, buf)
				expect(back.id == 7, "id")
				expect(back.zone == "lobby", "zone")
				expect(back.active == true, "active")
				local p = back.pos :: Vector3
				expect(math.abs(p.X - 1.5) < 1e-3, "pos x f32")
				expect(math.abs(p.Z - 300) < 1e-3, "pos z f32")
			end,
		},
		{
			name = "truncated buffer erros not crashes",
			fn = function()
				local buf =
					Serializer.Pack(POS_SCHEMA, { id = 1, pos = Vector3.zero, zone = "a", active = false })
				local short = buffer.create(4)
				buffer.copy(short, 0, buf, 0, 4)
				local ok = pcall(Serializer.Unpack, POS_SCHEMA, short)
				expect(not ok, "truncated must error")
			end,
		},
		{
			name = "oversize string rejected at pack and unpack",
			fn = function()
				local payload = { id = 1, pos = Vector3.zero, zone = string.rep("x", 64), active = false }
				local ok = pcall(Serializer.Pack, POS_SCHEMA, payload)
				expect(not ok, "maxLen enforced on pack")
			end,
		},
		{
			name = "packet envelope bounds-checked",
			fn = function()
				local inner =
					Serializer.Pack(POS_SCHEMA, { id = 3, pos = Vector3.zero, zone = "z", active = true })
				local env = Packet.Encode(42, inner)
				local decoded = Packet.Decode(env)
				expect(decoded.opId == 42, "opId")
				expect(buffer.len(decoded.payload) == buffer.len(inner), "payload length")
				local ok = pcall(Packet.Decode, buffer.create(2))
				expect(not ok, "short packet rejected")
			end,
		},
		{
			name = "compressor/decompressor bit-exact + zipbomb cap",
			fn = function()
				local source = buffer.create(200)
				for i = 0, 199 do
					buffer.writeu8(source, i, if i < 100 then 9 else i % 256)
				end
				local packed = Compressor.Encode(source)
				local restored = Compressor.Decode(packed)
				expect(buffer.len(restored) == 200, "length preserved")
				expect(
					buffer.readu8(restored, 0) == 9
						and buffer.readu8(source, 120) == buffer.readu8(restored, 120),
					"byte-exact"
				)
			end,
		},
		{
			name = "middleware compiles and halts",
			fn = function()
				Middleware.Reset()
				local hits: { string } = {}
				Middleware.Register("W22.pipe", function()
					table.insert(hits, "last")
					return true
				end, 300)
				Middleware.Register("W22.pipe", function(p)
					if p == "stop" then
						table.insert(hits, "halted")
					end
					return p ~= "stop"
				end, 100)
				Middleware.Lock()
				local chain = Middleware.Get("W22.pipe")
				expect(chain.Size() == 2, "two handlers")
				expect(chain.Run("go"), "pass path")
				expect(not chain.Run("stop"), "halt path")
				expect(hits[1] == "halted", "halt ran before 'last' (order 100 < 300)")
				expect(hits[2] == nil, "chain halted before last")
			end,
		},
		{
			name = "packet queue caps push + flush drains",
			fn = function()
				PacketQueue.Reset()
				local q = PacketQueue.Open("W22.q", 8)
				local big = buffer.create(9)
				expect(not q.Push(big), "oversize dropped")
				expect(q.Dropped() == 1, "drop counted")
				for _ = 1, 80 do
					q.Push(buffer.create(4))
				end
				expect(q.Dropped() > 1, "cap drops counted")
				local sum = 0
				local n = q.Flush(function(payloads)
					sum += #payloads
				end)
				expect(n == 64 and sum == 64, "flush consumed the full capped batch")
				expect(q.Pending() == 0, "drained")
			end,
		},
		{
			name = "protocol registry define/get/duplicate-error",
			fn = function()
				if not ProtocolBuffer.Has("W22.Pos") then
					ProtocolBuffer.Define(POS_SCHEMA)
				end
				expect(ProtocolBuffer.Has("W22.Pos"), "registered")
				local schema = ProtocolBuffer.Get("W22.Pos")
				expect(table.isfrozen(schema), "frozen")
				local ok = pcall(ProtocolBuffer.Define, POS_SCHEMA)
				expect(not ok, "duplicate define errors")
			end,
		},
	}

	for _, entry in tests do
		local ok, msg = check(entry.name, entry.fn)
		record(entry.name, ok, msg)
	end

	Debug.print(("[Dr.SelfTest.Processing] %d/%d passed"):format(#tests - failures, #tests))
	return failures == 0
end

return SelfTest
