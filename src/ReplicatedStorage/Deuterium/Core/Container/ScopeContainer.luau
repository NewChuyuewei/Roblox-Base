--!strict
-- Dr.Core.Container.ScopeContainer
-- Per-extension resource domain. A Scope owns everything an extension produces
-- (connections, instances, teardown handlers) and kills it all in one Destroy().
-- This is the handle Bulkhead/ShutdownManager will hold later.

local Debug = require(game:GetService("ReplicatedStorage"):WaitForChild("Debug"))

local ScopeContainer = {}

export type TeardownTask = () -> () | RBXScriptConnection | Instance

export type Scope = {
	Tag: string,
	Give: (self: Scope, task: TeardownTask) -> TeardownTask,
	Destroy: (self: Scope) -> (),
	Alive: (self: Scope) -> boolean,
}

function ScopeContainer.New(tag: string): Scope
	assert(type(tag) == "string" and #tag > 0, "[Dr.ScopeContainer] tag must be a non-empty string")

	local tasks: { TeardownTask } = {}
	local alive = true

	local scope: Scope = {
		Tag = tag,
		Give = function(_self: Scope, task: TeardownTask): TeardownTask
			assert(alive, `[Dr.Scope:{tag}] Give after Destroy`)
			local kind = typeof(task)
			assert(
				kind == "function" or kind == "RBXScriptConnection" or kind == "Instance",
				`[Dr.Scope:{tag}] unsupported task type: {kind}`
			)
			table.insert(tasks, task)
			return task
		end,
		Destroy = function(_self: Scope): ()
			if not alive then
				return
			end
			alive = false
			-- Reverse order teardown: last registered, first released.
			for i = #tasks, 1, -1 do
				local task = tasks[i]
				local kind = typeof(task)
				local ok, err = pcall(function()
					if kind == "function" then
						(task :: () -> ())()
					elseif kind == "RBXScriptConnection" then
						(task :: RBXScriptConnection):Disconnect()
					else
						(task :: Instance):Destroy()
					end
				end)
				if not ok then
					Debug.warn(`[Dr.Scope:{tag}] teardown failed: {tostring(err)}`)
				end
			end
			table.clear(tasks)
		end,
		Alive = function(_self: Scope): boolean
			return alive
		end,
	}
	return table.freeze(scope)
end

return table.freeze(ScopeContainer)
