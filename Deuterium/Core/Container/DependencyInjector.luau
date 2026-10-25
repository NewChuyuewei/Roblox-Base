--!strict
-- Dr.Core.Container.DependencyInjector
-- Pure static resolver: given the registered providers, produce an initialization
-- order that respects every declared dependency. Failures are fatal and explicit:
--  * missing dependency -> nil, "<path>" string naming the broken link
--  * dependency cycle    -> nil, cycle path string ("A -> B -> A")
-- Nothing here touches the engine, state outside its locals, or time — pure logic.

local Types = require(script.Parent.Types)

local DependencyInjector = {}

type ResolveResult = { order: { string }?, error: string? }

-- Kahn's algorithm with registration-order tie-breaking for determinism.
local function topologicalOrder(providers: { Types.Provider }): ResolveResult
	local names: { [string]: boolean } = {}
	for _, p in providers do
		names[p.Name] = true
	end

	-- Validate references first: a dependency that isn't registered is a construction error.
	for _, p in providers do
		local deps = p.Dependencies
		if deps ~= nil then
			for _, dep in deps do
				if not names[dep] then
					return {
						order = nil,
						error = `[Dr.DependencyInjector] {p.Name} depends on missing provider {dep}`,
					}
				end
			end
		end
	end

	-- outDegree = number of remaining dependencies; reverseEdge[dep] = dependents
	local outDegree: { [string]: number } = {}
	local dependents: { [string]: { string } } = {}
	for _, p in providers do
		outDegree[p.Name] = 0
		dependents[p.Name] = {}
	end
	for _, p in providers do
		local deps = p.Dependencies
		if deps ~= nil then
			for _, dep in deps do
				outDegree[p.Name] = (outDegree[p.Name] :: number) + 1
				table.insert(dependents[dep] :: { string }, p.Name)
			end
		end
	end

	-- Registration order drives determinism among ready nodes.
	local ready: { string } = {}
	for _, p in providers do
		if (outDegree[p.Name] :: number) == 0 then
			table.insert(ready, p.Name)
		end
	end

	local order: { string } = {}
	local head = 1
	while head <= #ready do
		local name = ready[head]
		head += 1
		table.insert(order, name)
		for _, dependent in dependents[name] :: { string } do
			local remaining = (outDegree[dependent] :: number) - 1
			outDegree[dependent] = remaining
			if remaining == 0 then
				table.insert(ready, dependent)
			end
		end
	end

	if #order < #providers then
		-- Cycle: recover a readable path via DFS over the unresolved subgraph.
		local state: { [string]: number } = {} -- 0=white 1=gray 2=black
		local stack: { string } = {}
		local cyclePath: string? = nil

		local function dfs(node: string): boolean
			state[node] = 1
			table.insert(stack, node)
			local provider: Types.Provider? = nil
			for _, p in providers do
				if p.Name == node then
					provider = p
					break
				end
			end
			for _, dep in ((provider and provider.Dependencies) or {}) :: { string } do
				if (outDegree[dep] :: number) <= 0 then
					continue -- resolved; not part of any remaining cycle
				end
				local s = state[dep] or 0
				if s == 1 then
					local from = table.find(stack, dep) :: number
					local path = table.create(#stack - from + 2)
					for i = from, #stack do
						table.insert(path, stack[i])
					end
					table.insert(path, dep)
					cyclePath = table.concat(path, " -> ")
					return true
				elseif s == 0 and dfs(dep) then
					return true
				end
			end
			state[node] = 2
			table.remove(stack)
			return false
		end

		for _, p in providers do
			if (outDegree[p.Name] :: number) > 0 and (state[p.Name] or 0) == 0 then
				if dfs(p.Name) then
					break
				end
			end
		end

		return { order = nil, error = `[Dr.DependencyInjector] dependency cycle: {cyclePath or "unknown"}` }
	end

	return { order = order, error = nil }
end

DependencyInjector.ResolveOrder = topologicalOrder

return table.freeze(DependencyInjector)
