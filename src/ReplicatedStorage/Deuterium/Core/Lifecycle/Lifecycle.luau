--!strict
-- Dr.Core.Lifecycle.Lifecycle
-- Typed lifecycle phases for the kernel. Zero state: a pure table of phases.
-- The state machine itself is the Kernel (already W1.4) — this module is the vocabulary.

local Contract = require(script.Parent.Parent.Foundation.Contract)

local Lifecycle = {}

export type Phase = "Collecting" | "Constructed" | "Initialized" | "Started" | "Stopped"

local ORDER: { Phase } = { "Collecting", "Constructed", "Initialized", "Started", "Stopped" }

function Lifecycle.Phases(): { Phase }
	return table.clone(ORDER) :: { Phase }
end

function Lifecycle.IsBefore(a: Phase, b: Phase): boolean
	local ia = (table.find(ORDER, a) :: number) or -1
	local ib = (table.find(ORDER, b) :: number) or -1
	Contract.Invariant(ia >= 0 and ib >= 0, "PHASE.KNOWN", "unknown phase")
	return ia < ib
end

function Lifecycle.IsKnown(phase: string): boolean
	-- table.find 就在上面几个函数里用过；手写循环是重复实现（subagent core lane）。
	return table.find(ORDER, phase) ~= nil
end

return table.freeze(Lifecycle)
