--!strict
-- Dr.Net.Processing.Middleware
-- Ordered hook chain per named pipeline. Register freely during Construct;
-- Lock compiles the chain into a flat frozen array — runtime dispatch is a numeric
-- loop over pre-bound functions, no string lookup, no per-call table construction.

local ErrorHandler = require(game:GetService("ReplicatedStorage").Deuterium.Core.Foundation.ErrorHandler)

export type Handler = (payload: any) -> boolean -- false = halt chain

export type Chain = {
	Run: (payload: any) -> boolean, -- true = chain completed, false = halted
	Size: () -> number,
}

local Middleware = {}

local _pipelines: { [string]: { { order: number, seq: number, fn: Handler } } } = {}
local _compiled: { [string]: Chain } = {}
local _locked = false
local _seq = 0 -- registration counter: table.sort is NOT stable, seq preserves ties

function Middleware.Register(pipeline: string, fn: Handler, order: number?)
	assert(not _locked, "[Dr.Middleware] Register after Lock")
	assert(type(pipeline) == "string" and #pipeline > 0, "[Dr.Middleware] pipeline name required")
	assert(type(fn) == "function", "[Dr.Middleware] handler must be a function")
	local list = _pipelines[pipeline]
	if list == nil then
		list = {}
		_pipelines[pipeline] = list
	end
	_seq += 1
	table.insert(list, { order = order or 100, seq = _seq, fn = fn })
end

-- Compile a pipeline once. Deterministic: sort by order, ties keep registration order.
function Middleware.Lock(): ()
	if _locked then
		return
	end
	for name, list in _pipelines do
		table.sort(list, function(a, b)
			if a.order ~= b.order then
				return a.order < b.order
			end
			return a.seq < b.seq -- unstable sort: seq keeps registration order for ties
		end)
		local fns = table.create(#list)
		for i, entry in list do
			fns[i] = entry.fn
		end
		local frozen = table.freeze(fns)
		local size = #frozen
		_compiled[name] = table.freeze({
			Run = function(payload: any): boolean
				for i = 1, size do
					if not frozen[i](payload) then
						return false
					end
				end
				return true
			end,
			Size = function(): number
				return size
			end,
		}) :: any
	end
	_locked = true
end

-- [P0] dispatch exception path raises only for genuinely unknown pipelines.
function Middleware.Get(pipeline: string): Chain
	local chain = _compiled[pipeline]
	if chain == nil then
		ErrorHandler.Raise("DR.NET.MW.MISSING", `pipeline not compiled: {pipeline}`, "Dr.Middleware")
	end
	return chain
end

function Middleware.IsLocked(): boolean
	return _locked
end

function Middleware.Reset(): () -- Test-only (Session-state discipline)
	_pipelines = {}
	_compiled = {}
	_locked = false
end

return table.freeze(Middleware)
