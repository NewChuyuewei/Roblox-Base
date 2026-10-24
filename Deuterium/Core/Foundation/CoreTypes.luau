--!strict
-- Dr.Core.Foundation.CoreTypes — shared core primitives. Pure types, no engine imports.

export type DrError = {
	code: string, -- stable, greppable identifier, e.g. "DR.INIT.FAILED"
	message: string, -- human-readable detail
	source: string?, -- e.g. "Provider/Name.Init"
}

export type Result = {
	ok: boolean,
	err: DrError?,
}

return table.freeze({})
