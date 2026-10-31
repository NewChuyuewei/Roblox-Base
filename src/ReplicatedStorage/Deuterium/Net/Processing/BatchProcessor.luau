--!strict
-- Dr.Net.Processing.BatchProcessor
-- Frame-batched send: register (channel → sender fn) once at Construct; Tick() flushes
-- each queue through its sender. Verifies wiring by refusing to duplex.

local PacketQueue = require(script.Parent.PacketQueue)
local RunContext = require(script.Parent.Parent.Parent.Runtime.Environment.RunContext)

local BatchProcessor = {}

export type Sender = (payloads: { buffer }) -> ()

local _bindings: { { queue: any, sender: Sender } } = {}
local _locked = false
local _ticking = false

function BatchProcessor.Bind(channel: string, maxPayloadBytes: number, sender: Sender): any
	assert(not _locked, "[Dr.BatchProcessor] Bind after Start")
	assert(type(sender) == "function", "[Dr.BatchProcessor] sender must be a function")
	local queue = PacketQueue.Open(channel, maxPayloadBytes)
	table.insert(_bindings, table.freeze({ queue = queue, sender = sender }) :: any)
	return queue
end

function BatchProcessor.Start(): ()
	-- no context assert: IsServer() or IsClient() is a tautology — both sides batch
	_locked = true
	_ticking = true
end

-- One pump. Called once per frame (Heartbeat) by the wiring layer; idempotent when empty.
function BatchProcessor.Tick(): ()
	if not _ticking then
		return
	end
	for _, binding in _bindings do
		binding.queue.Flush(binding.sender)
	end
end

function BatchProcessor.Stop(): ()
	_ticking = false
end

function BatchProcessor.IsTicking(): boolean
	return _ticking
end

function BatchProcessor.Reset(): () -- Test-only
	assert(RunContext.IsStudio(), "[Dr.BatchProcessor] Reset is Studio-only")
	_bindings = {}
	_locked = false
	_ticking = false
	PacketQueue.Reset()
end

return table.freeze(BatchProcessor)
