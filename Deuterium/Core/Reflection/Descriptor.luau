--!strict
-- Dr.Core.Reflection.Descriptor
-- Captures the static shape of a module/provider table as a frozen snapshot.
-- Frozen + sorted = diffable, cacheable, and safe to hand to diagnostics.

local Descriptor = {}

export type Entry = {
	name: string,
	kind: string, -- "function" | "table" | ...
}

export type ModuleDescriptor = {
	name: string,
	exports: { Entry },
	frozen: boolean,
}

-- Build (and freeze) a descriptor for any table-like export surface.
function Descriptor.Of(name: string, target: any): ModuleDescriptor
	assert(type(name) == "string" and #name > 0, "[Dr.Descriptor] name required")
	assert(type(target) == "table", "[Dr.Descriptor] target must be a table")

	local exports: { Entry } = {}
	for key, value in target do
		if type(key) == "string" then
			table.insert(exports, table.freeze({ name = key, kind = typeof(value) }))
		end
	end
	table.sort(exports, function(a, b)
		return a.name < b.name
	end)

	return table.freeze({
		name = name,
		exports = table.freeze(exports),
		frozen = table.isfrozen(target),
	})
end

return table.freeze(Descriptor)
