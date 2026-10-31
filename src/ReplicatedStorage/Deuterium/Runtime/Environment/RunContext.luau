--!strict
-- Dr.Runtime.Environment.RunContext
-- Snapshot of "where am I running" taken once at require time.
-- Engine state cannot change mid-session, so caching is the philosophy:
-- callers get zero per-call cost ([P0] safe getters), never re-query RunService.
-- All probes are pcall-guarded: RunService APIs must never crash module init.

local RuntimeTypes = require(script.Parent.Parent.RuntimeTypes)

-- 探测改为**懒执行一次并缓存**。为什么：原来在 require 时直接 game:GetService("RunService")，
-- 使整个 Environment/Platform/Interop/Net 栈在 headless 下**根本无法装载**（实测 12 个模块
-- 卡在这一行），于是它们永远进不了 CI。
-- 契约不变：仍然是“会话内只算一次 + getter 零开销读取”；只是在首次 getter 时才探测。
-- 无引擎时全部保持 false（与旧实现里 pcall 失败的行为一致）。
local _probed = false
local isServer: boolean = false
local isStudio: boolean = false
local isRunMode: boolean = false
local side: RuntimeTypes.Side = "Client"
local runKind: RuntimeTypes.RunKind = "Production"

local function probe(fn: () -> boolean): boolean
	local ok, result = pcall(fn)
	return ok and result == true
end

local function probeOnce(): ()
	if _probed then
		return
	end
	_probed = true
	local ok, RunService = pcall(function()
		return game:GetService("RunService")
	end)
	if not ok or RunService == nil then
		return -- headless：保持默认值
	end
	isServer = probe(function()
		return RunService:IsServer()
	end)
	isStudio = probe(function()
		return RunService:IsStudio()
	end)
	isRunMode = probe(function()
		return RunService:IsRunMode()
	end)
	side = if isServer then "Server" else "Client"
	runKind = if not isStudio then "Production" elseif isRunMode then "StudioPlay" else "StudioEdit"
end

local RunContext = {}

-- [P0] cached read（首次调用时才探测一次）
function RunContext.IsServer(): boolean
	probeOnce()
	return isServer
end

function RunContext.IsClient(): boolean
	probeOnce()
	return not isServer
end

function RunContext.IsStudio(): boolean
	probeOnce()
	return isStudio
end

function RunContext.GetSide(): RuntimeTypes.Side
	probeOnce()
	return side
end

function RunContext.GetRunKind(): RuntimeTypes.RunKind
	probeOnce()
	return runKind
end

function RunContext.IsProduction(): boolean
	probeOnce()
	return runKind == "Production"
end

-- 测试用：清掉探测缓存（headless 下切换桩环境时用）
function RunContext.ResetProbe(): ()
	_probed = false
end

return table.freeze(RunContext)
