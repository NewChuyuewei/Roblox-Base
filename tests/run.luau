--!nocheck
-- headless 测试入口 —— CI 的 test 阶段跑这个。
--
-- 三类 suite：
--   selftest —— 装载一组模块后跑它们的 SelfTest.RunAll()
--   checks   —— 装载一组模块后跑内联断言（用于还没有 SelfTest 的模块）
--   sweep    —— **全量装载巡检**：把挂载树里每个模块都装载一遍，报告
--                "不加引擎桩能装几个 / 加桩能装几个 / 谁装不上、为什么"
--
-- 引擎相关的 SelfTest 会被明确列为 SKIP 并给出理由（它们需要 game，只能在 Studio 跑）。
-- **SKIP 不是通过** —— 这里如实打印数量，免得"CI 绿"被误读成"全部都测了"。
--
-- 运行：lune run tests/run.luau

local Loader = require("../scripts/lune-loader")
local process = require("@lune/process")

local RS = "src/ReplicatedStorage"

local SUITES = {
	{
		name = "Dr.Diagnostics.Logging",
		kind = "selftest",
		dir = RS .. "/Deuterium/Diagnostics/Logging",
		order = { "StructuredLog", "LogSink", "Logger", "Debug", "SelfTest" },
	},
	{
		-- 认证范围的第一批 headless 测试。这些文件用三级上跳 require
		-- （script.Parent.Parent.Parent.Core.Foundation.ErrorHandler），
		-- loader v1 无法解析 —— 所以它们此前**从未被任何环境执行过**。
		name = "certified: Dr.Core.Foundation + Dr.Types.Contract",
		kind = "checks",
		modules = {
			RS .. "/Deuterium/Core/Foundation/CoreTypes.luau",
			RS .. "/Deuterium/Core/Foundation/ErrorHandler.luau",
			RS .. "/Deuterium/Core/Foundation/Contract.luau",
			RS .. "/Deuterium/Types/Contract/Interface.luau",
		},
		run = function(m)
			local failures = {}
			local function expect(cond, what)
				if not cond then
					table.insert(failures, what)
				end
			end

			local ErrorHandler, Contract, Interface = m.ErrorHandler, m.Contract, m.Interface

			-- ErrorHandler
			expect(ErrorHandler.IsDrError(ErrorHandler.New("DR.T", "m")), "New 产出的就是 DrError")
			expect(not ErrorHandler.IsDrError("naked string"), "字符串不是 DrError")
			expect(table.isfrozen(ErrorHandler.New("DR.T", "m")), "DrError 冻结")
			expect(ErrorHandler.Render("plain") == "plain", "字符串原样透传")
			expect(ErrorHandler.Render(ErrorHandler.New("DR.T", "m", "Src")) == "[DR.T] m @ Src", "Render 格式")
			expect(ErrorHandler.Render(ErrorHandler.New("DR.T", "m")) == "[DR.T] m @ ?", "Render 无 source 用 ?")
			expect(ErrorHandler.Normalize("boom", "DR.FALLBACK").code == "DR.FALLBACK", "外来错误套 fallback code")
			local r = ErrorHandler.Try(function()
				error("x")
			end, "DR.TRY")
			expect(r.ok == false and r.err ~= nil, "Try 捕获并结构化")
			expect(ErrorHandler.Try(function() end, "DR.TRY").ok == true, "Try 成功路径")

			-- Contract
			expect(pcall(Contract.Precondition, true, "C", "m") == true, "前置条件通过时不抛")
			expect(pcall(Contract.Precondition, false, "C", "m") == false, "前置条件失败时抛")
			expect(pcall(Contract.Invariant, false, "C", "m") == false, "不变量失败时抛")
			expect(pcall(Contract.IsA, "s", "string", "C") == true, "IsA 匹配")
			expect(pcall(Contract.IsA, 1, "string", "C") == false, "IsA 不匹配时抛")
			-- R26 回归：伪类型 "Instance" 必须认得实例（旧实现用 type()，对实例恒为
			-- "userdata"，于是 ModuleLoader/HotReload 的 Contract.IsA(x,"Instance") 必然抛错）。
			-- 用一个带 ClassName 的表即可验证该分支，不需要引擎。
			expect(pcall(Contract.IsA, { ClassName = "Folder" }, "Instance", "C") == true, "伪类型 Instance 认实例")
			expect(pcall(Contract.IsA, "not-an-instance", "Instance", "C") == false, "非实例不得通过 Instance 判定")

			-- Interface.Conform（三级上跳 require 真的解析成功了，才可能跑到这里）
			local spec = { Name = "string", Init = "function" }
			expect(Interface.Conform("t", { Name = "ok", Init = function() end }, spec) == true, "形状匹配")
			expect(pcall(Interface.Conform, "t", { Name = "ok" }, spec) == false, "缺字段必须抛")
			expect(
				pcall(Interface.Conform, "t", { Name = "ok", Init = function() end, Extra = 1 }, spec) == true,
				"多字段当前不报错（已知行为）"
			)
			expect(pcall(Interface.Conform, "t", "not a table", spec) == false, "值不是表必须抛")
			expect(pcall(Interface.Conform, "t", {}, { Name = "string" }) == false, "全缺字段必须抛")

			if #failures > 0 then
				for _, f in failures do
					print(`  断言失败: {f}`)
				end
			end
			return #failures == 0, `{#failures} 条断言失败`
		end,
	},
	{
		-- 这两个模块此前同样从未被执行过：它们的 Load() 里直接 game:GetService(...)
		-- loader v3 的虚拟节点提供 WaitForChild/IsA，并支持可选引擎桩，于是可以真跑。
		name = "Dr.Core.Lifecycle.Configuration + Dr.Runtime.Environment.FeatureFlags",
		kind = "checks",
		engineStub = true,
		modules = {
			RS .. "/Deuterium/Runtime/Environment/FeatureFlags.luau",
			RS .. "/Deuterium/Core/Lifecycle/Configuration.luau",
		},
		run = function(m)
			local failures = {}
			local function expect(cond, what)
				if not cond then
					table.insert(failures, what)
				end
			end
			local Configuration, FeatureFlags = m.Configuration, m.FeatureFlags

			-- Configuration：Load 之前读 section 必须失败（断言式保护）
			expect(pcall(Configuration.Section, "FeatureFlags") == false, "Load 之前 Section 必须报错")
			expect(Configuration.IsLoaded() == false, "初始未加载")

			Configuration.Load()
			expect(Configuration.IsLoaded() == true, "Load 后为已加载")
			local names = Configuration.SectionNames()
			expect(#names >= 1, `SectionNames 非空（得到 {#names}）`)
			local found = false
			for _, n in names do
				if n == "FeatureFlags" then
					found = true
				end
			end
			expect(found, "清单里有 FeatureFlags 段")
			expect(type(Configuration.Section("FeatureFlags")) == "table", "段读出来是 table")
			expect(pcall(Configuration.Section, "NoSuchSection") == false, "未知段必须报错")
			expect(pcall(Configuration.Load) == false, "重复 Load 必须报错（锁）")

			-- FeatureFlags：从 Configs 树批量定义
			FeatureFlags.LoadFromConfig()
			expect(FeatureFlags.Get("Dr.Security.StrictSchema") == true, "StrictSchema 默认 true")
			local snap = FeatureFlags.Snapshot()
			expect(type(snap["Dr.Diagnostics.StructuredLogs"]) == "boolean", "StructuredLogs 是布尔")
			expect(pcall(FeatureFlags.Get, "No.Such.Flag") == false, "未知 flag 读取必须报错")
			FeatureFlags.Lock()
			expect(FeatureFlags.IsLocked() == true, "Lock 之后为已锁")
			expect(pcall(FeatureFlags.Define, "Late.Flag", true) == false, "Lock 之后 Define 必须报错")
			expect(pcall(FeatureFlags.LoadFromConfig) == false, "Lock 之后重复加载必须报错")

			if #failures > 0 then
				for _, f in failures do
					print(`  断言失败: {f}`)
				end
			end
			return #failures == 0, `{#failures} 条断言失败`
		end,
	},
	{
		-- 回归：TestSuite 曾因多余的 `_self` 首参而**永远无法注册用例**（Suite.Define 必抛），
		-- 整套 TestKit 是死的。这里直接验证“用例真的注册上了”。
		name = "Testing.TestKit: Suite.Define + Assert（曾经完全无法注册用例）",
		kind = "checks",
		modules = {
			RS .. "/Deuterium/Testing/Assert.luau",
			RS .. "/Deuterium/Testing/TestSuite.luau",
		},
		run = function(m)
			local failures = {}
			local function expect(cond, what)
				if not cond then
					table.insert(failures, what)
				end
			end
			local Assert, Suite = m.Assert, m.TestSuite

			local suite = Suite.Define("Probe", function(t)
				t.Test("case one", function() end)
				t.Test("case two", function() end)
			end)
			expect(suite.name == "Probe", "套件名保留")
			expect(#suite.cases == 2, `两个用例都注册上了（实到 {#suite.cases}）`)
			expect(suite.cases[1].name == "case one", "用例名未被参数错位污染")
			expect(pcall(Suite.Define, "Bad", function(t)
				t.Test("", function() end)
			end) == false, "空用例名必报错")

			expect(pcall(Assert.IsTrue, true, "x") == true, "IsTrue 通过")
			expect(pcall(Assert.IsTrue, false, "x") == false, "IsTrue 失败必抛")
			expect(pcall(Assert.Equal, 1, 1, "x") == true, "Equal 相等通过")
			expect(pcall(Assert.Equal, 1, 2, "x") == false, "Equal 不等必抛")
			expect(pcall(Assert.Throws, function()
				error("boom")
			end, "boom", "x") == true, "Throws 命中")

			if #failures > 0 then
				for _, f in failures do
					print(`  断言失败: {f}`)
				end
			end
			return #failures == 0, `{#failures} 条断言失败`
		end,
	},
	{
		-- 以前加密模块的唯一正确性证据在 Net/Security/SelfTest 里，而那个套件因 require game
		-- 被登记为 SKIP —— 也就是说 SHA-256/HMAC 从未被任何环境验证过。
		name = "Security.Crypto: NIST / RFC 4231 已知答案",
		kind = "checks",
		modules = {
			RS .. "/Deuterium/Security/Crypto/Sha256.luau",
			RS .. "/Deuterium/Security/Crypto/Hmac.luau",
		},
		run = function(m)
			local failures = {}
			local function expect(cond, what)
				if not cond then
					table.insert(failures, what)
				end
			end
			local Sha256, Hmac = m.Sha256, m.Hmac
			expect(
				Sha256.ToHex(Sha256.Hash("")) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
				"sha256(\"\") NIST 向量"
			)
			expect(
				Sha256.ToHex(Sha256.Hash("abc")) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
				"sha256(\"abc\") NIST 向量"
			)
			expect(#Sha256.Hash("anything") == 32, "摘要 32 字节")
			expect(
				Sha256.ToHex(Hmac.Sha256(string.rep("\11", 20), "Hi There"))
					== "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
				"RFC 4231 TC2 向量"
			)
			if #failures > 0 then
				for _, f in failures do
					print(`  断言失败: {f}`)
				end
			end
			return #failures == 0, `{#failures} 条断言失败`
		end,
	},
	{
		-- 含两个回归用例：
		--  ① Compressor：65–130 字节纯重复段往返（修复前 MAX_EXPAND_FACTOR=32 → Decode 拒收自己 Encode 的输出）
		--  ② Serializer：字符串长度前缀被截断（修复前抛裸的 buffer 越界）
		name = "Net codec: Compressor 往返 + Serializer 往返/截断",
		kind = "checks",
		modules = {
			RS .. "/Deuterium/Net/Processing/Compressor.luau",
			RS .. "/Deuterium/Net/Processing/Serializer.luau",
		},
		run = function(m)
			local failures = {}
			local function expect(cond, what)
				if not cond then
					table.insert(failures, what)
				end
			end
			local Compressor, Serializer = m.Compressor, m.Serializer

			local function runRoundTrip(n, fill)
				local src = buffer.create(n)
				for i = 0, n - 1 do
					buffer.writeu8(src, i, fill)
				end
				local dec = Compressor.Decode(Compressor.Encode(src))
				return buffer.len(dec) == n and (n == 0 or buffer.readu8(dec, 0) == fill)
			end
			expect(runRoundTrip(130, 0), "回归：130 字节纯重复段往返")
			expect(runRoundTrip(65, 7), "回归：65 字节纯重复段往返")
			expect(runRoundTrip(1, 3), "1 字节往返")
			expect(runRoundTrip(0, 0), "空缓冲往返")
			expect(runRoundTrip(200, 9), "200 字节（超出单次 run 上限）往返")

			local mixed = buffer.fromstring(string.rep("a", 100) .. "bcd" .. string.rep("x", 40))
			local back = Compressor.Decode(Compressor.Encode(mixed))
			expect(buffer.tostring(back) == buffer.tostring(mixed), "重复段 + 字面量混合往返")

			local schema = {
				name = "probe",
				fields = {
					{ name = "id", type = "u32" },
					{ name = "flag", type = "bool" },
					{ name = "label", type = "string" },
					{ name = "score", type = "f64" },
				},
			}
			local packed = Serializer.Pack(schema, { id = 42, flag = true, label = "hello", score = 1.5 })
			local out = Serializer.Unpack(schema, packed)
			expect(out.id == 42 and out.flag == true and out.label == "hello" and out.score == 1.5, "Serializer 往返一致")

			-- ② 长度前缀截断：4 字节 u32 + 长度前缀的前 2 字节
			local schema2 = {
				name = "probe2",
				fields = { { name = "id", type = "u32" }, { name = "label", type = "string" } },
			}
			local full = Serializer.Pack(schema2, { id = 7, label = "hello" })
			local cut = buffer.create(6)
			for i = 0, 5 do
				buffer.writeu8(cut, i, buffer.readu8(full, i))
			end
			local okCut, errCut = pcall(Serializer.Unpack, schema2, cut)
			expect(not okCut, "截断缓冲必须抛错")
			-- 结构化错误是 DrError（冻结表），不是字符串：tostring 只会得到 "table: 0x..."。
			-- 要断言 code 与 message 两个字段。
			local code = if type(errCut) == "table" then tostring((errCut :: any).code) else tostring(errCut)
			local msg = if type(errCut) == "table" then tostring((errCut :: any).message) else tostring(errCut)
			expect(code == "DR.NET.SER.TRUNC", `回归：截断应报 DR.NET.SER.TRUNC（实到 {code}）`)
			expect(
				string.find(msg, "truncated length prefix", 1, true) ~= nil,
				`回归：消息应说明是长度前缀截断（实到 {msg}）`
			)

			if #failures > 0 then
				for _, f in failures do
					print(`  断言失败: {f}`)
				end
			end
			return #failures == 0, `{#failures} 条断言失败`
		end,
	},
	{
		-- 这些 SelfTest 原先全部被登记为 SKIP（它们 require game）。现在用 Studio 桩
		-- （engineStub + studio=true）**真正执行**它们，逐条报告成败与原因。
		name = "引擎绑定的 SelfTest（Studio 桩下尝试执行）",
		kind = "engine",
	},
	{
		name = "全量装载巡检（每个第一方模块都试着装载一次）",
		kind = "sweep",
	},
}

-- 需要 game、只能在 Studio 跑的 SelfTest（此处只登记，不跑）
local ENGINE_BOUND = {
	"src/ReplicatedStorage/Deuterium/Core/Container/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Core/Lifecycle/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Core/Reflection/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Net/Core/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Net/Processing/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Net/Security/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Runtime/Environment/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Runtime/Interop/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Runtime/Platform/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Testing/SelfTest.luau",
}

local function relPath(p)
	-- 注意：Luau 没有 string.replace（第一次写这里时踩了，sweep 一打印失败清单就崩）
	return (string.gsub(p, RS .. "/", ""))
end

local function runSweep()
	-- 两遍：不加桩（能装几个）vs 加桩（引擎依赖被遮蔽后能装几个）。
	-- 差额本身就是有价值的指标：加载期就碰引擎的模块有几个。
	local THIRD_PARTY = { "Scribe/", "QuickZone/" }
	local function pass(engineStub)
		Loader.reset()
		local mods = {}
		for _, p in Loader.listModules() do
			local third = false
			for _, prefix in THIRD_PARTY do
				if string.find(p, prefix, 1, true) ~= nil then
					third = true
				end
			end
			if not third then
				table.insert(mods, p)
			end
		end
		local ok, bad = 0, {}
		for _, path in mods do
			local fine, err = pcall(Loader.load, path, { engineStub = engineStub })
			if fine then
				ok += 1
			else
				table.insert(bad, { path, tostring(err) })
			end
		end
		return #mods, ok, bad
	end

	local total, plainOk, plainBad = pass(false)
	local _, stubOk, stubBad = pass(true)

	print(`  模块总数 {total}`)
	print(`  不加引擎桩可装载: {plainOk}  (失败 {#plainBad})`)
	print(`  加引擎桩可装载:   {stubOk}  (失败 {#stubBad})`)
	if #plainBad > 0 then
		print("  不加桩失败清单（= 加载期依赖引擎的模块，CI 无法装载它们）:")
		for _, e in plainBad do
			print(`    {relPath(e[1])}  ->  {string.sub(e[2], 1, 110)}`)
		end
	end
	if #stubBad > 0 then
		print("  加桩仍失败（真问题，必须修）:")
		for _, e in stubBad do
			print(`    {relPath(e[1])}  ->  {string.sub(e[2], 1, 110)}`)
		end
	end
	-- 关键：不加桩的装载数就是 R29 的哨兵 —— 新增代码若把引擎依赖放到加载期，
	-- 这里会立刻变红。以前它只被**打印**、没被断言，等于哨兵不响。
	if #plainBad > 0 then
		return false, `不加引擎桩有 {#plainBad} 个模块装不上（有代码把引擎依赖放到了加载期）`
	end
	return #stubBad == 0, `加桩仍有 {#stubBad} 个模块装不上`
end

print(("="):rep(72))
print("headless 测试（Lune + 虚拟实例树 loader）")
print(("="):rep(72))

local passed, failed = 0, 0
for _, suite in SUITES do
	if suite.kind == "sweep" then
		print(`--- {suite.name}`)
		local ok, good, detail = pcall(runSweep)
		if ok and good == true then
			passed += 1
			print(`[PASS] {suite.name}`)
		else
			failed += 1
			print(`[FAIL] {suite.name} —— {if ok then tostring(detail) else "抛错: " .. tostring(good)}`)
		end
	elseif suite.kind == "engine" then
		Loader.reset()
		local ran, okCount = 0, 0
		local problems = {}
		for _, path in ENGINE_BOUND do
			local okLoad, mod = pcall(Loader.load, path, { engineStub = true, studio = true })
			if not okLoad or mod == nil or type(mod.RunAll) ~= "function" then
				table.insert(problems, { path, "装载失败: " .. string.sub(tostring(mod), 1, 120) })
				continue
			end
			ran += 1
			local okRun, res = pcall(mod.RunAll)
			if okRun and res == true then
				okCount += 1
			else
				table.insert(problems, { path, if okRun then "RunAll() 返回 false" else "RunAll() 抛错: " .. string.sub(tostring(res), 1, 120) })
			end
		end
		print(string.format("  实际执行 %d/%d · 通过 %d · 失败 %d", ran, #ENGINE_BOUND, okCount, #problems))
		for _, p in problems do
			print(`    {p[1]}: {p[2]}`)
		end
		if #problems == 0 and ran > 0 then
			passed += 1
			print(`[PASS] {suite.name}`)
		else
			failed += 1
			print(string.format("[FAIL] %s —— %d 条失败，%d 条装不上", suite.name, #problems, #ENGINE_BOUND - ran))
		end
	elseif suite.kind == "selftest" then
		local okLoad, loaded = pcall(function()
			return Loader.chain(suite.dir, suite.order)
		end)
		if not okLoad then
			failed += 1
			print(`[FAIL] {suite.name} —— 加载失败: {tostring(loaded)}`)
			continue
		end
		local selfTest = loaded.SelfTest
		if selfTest == nil or type(selfTest.RunAll) ~= "function" then
			failed += 1
			print(`[FAIL] {suite.name} —— 没有 SelfTest.RunAll`)
			continue
		end
		local okRun, result = pcall(selfTest.RunAll)
		if okRun and result == true then
			passed += 1
			print(`[PASS] {suite.name}`)
		else
			failed += 1
			print(`[FAIL] {suite.name} —— RunAll()={tostring(result)}`)
		end
	else
		local byName = {}
		local opts = { engineStub = suite.engineStub == true }
		local okLoad, err = pcall(function()
			for _, path in suite.modules do
				local name = string.match(path, "([^/]+)%.luau$")
				byName[name] = Loader.load(path, opts)
			end
		end)
		if not okLoad then
			failed += 1
			print(`[FAIL] {suite.name} —— 加载失败: {tostring(err)}`)
			continue
		end
		local okRun, good, detail = pcall(suite.run, byName)
		if okRun and good == true then
			passed += 1
			print(`[PASS] {suite.name}`)
		else
			failed += 1
			print(`[FAIL] {suite.name} —— {if okRun then tostring(detail) else "抛错: " .. tostring(good)}`)
		end
	end
end

print(("="):rep(72))
print(`结果：PASS {passed} · FAIL {failed} · SKIP 0（引擎绑定的 {#ENGINE_BOUND} 个已由 Studio 桩执行）`)
if #ENGINE_BOUND > 0 then
	print("")
	print("以下 SelfTest 曾因 require game 被登记为 SKIP；现在已由 Studio 桩（rbx-stub）执行：")
	for _, path in ENGINE_BOUND do
		print(`  SKIP  {path}`)
	end
	print("它们已计入上面的 PASS/FAIL。剩余的真实覆盖缺口是：桩不模拟引擎交互语义，所以只覆盖逻辑与数据流。")
end
print(("="):rep(72))

if failed > 0 or passed == 0 then
	process.exit(1)
end
