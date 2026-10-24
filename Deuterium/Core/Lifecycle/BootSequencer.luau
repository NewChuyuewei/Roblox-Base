--!strict
-- Dr.Core.Lifecycle.BootSequencer
-- The deterministic order the whole game boots: Collecting → Constructed → Initialized → Started.
-- One run per process; re-entry is a contract violation (this is boot, not a toggle).

local Contract = require(script.Parent.Parent.Foundation.Contract)
local Kernel = require(script.Parent.Parent.Container.Kernel)

local BootSequencer = {}

local _ran = false

function BootSequencer.Run(): boolean
	Contract.Invariant(not _ran, "BOOT.ONCE", "BootSequencer.Run must run exactly once")
	_ran = true

	-- Construct is the make-or-break gate: dependency graph errors are fatal by design.
	if not Kernel.Construct() then
		return false
	end
	Kernel.Init()
	Kernel.Start()
	return true -- providers may be partially failed; the game runs, Bulkhead isolates them
end

return table.freeze(BootSequencer)
