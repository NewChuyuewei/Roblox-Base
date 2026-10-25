--!strict
-- Dr.Core.Reflection.Inspector
-- Answers questions about module shape, using Descriptor snapshots.
-- Pure functions over already-built descriptors; zero engine contact.

local Descriptor = require(script.Parent.Descriptor)

local Inspector = {}

-- Does the export surface contain this member name?
function Inspector.Has(descriptor: Descriptor.ModuleDescriptor, memberName: string): boolean
	for _, entry in descriptor.exports do
		if entry.name == memberName then
			return true
		end
	end
	return false
end

-- What kind is a member, or nil if absent?
function Inspector.KindOf(descriptor: Descriptor.ModuleDescriptor, memberName: string): string?
	for _, entry in descriptor.exports do
		if entry.name == memberName then
			return entry.kind
		end
	end
	return nil
end

-- Sorted member names (stable across sessions).
function Inspector.List(descriptor: Descriptor.ModuleDescriptor): { string }
	local out = table.create(#descriptor.exports)
	for i, entry in descriptor.exports do
		out[i] = entry.name
	end
	return table.freeze(out)
end

-- Count of exported members.
function Inspector.Count(descriptor: Descriptor.ModuleDescriptor): number
	return #descriptor.exports
end

return table.freeze(Inspector)
