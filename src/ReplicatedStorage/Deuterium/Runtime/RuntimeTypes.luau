--!strict
-- Dr.Runtime shared types. Pure type module: no engine imports allowed here.

export type Side = "Server" | "Client"

-- StudioEdit = edit mode (scripts mostly idle), StudioPlay = F5 play solo / F8 run, Production = live game.
export type RunKind = "StudioEdit" | "StudioPlay" | "Production"

export type EngineInfo = {
	version: string,
	studio: boolean,
}

export type FeatureFlagDef = {
	name: string,
	default: boolean,
	studioOverride: boolean?, -- forced value while running inside Studio
}

-- Opaque self-handle for Platform.InstanceTracker: never reach into it,
-- pass it back to Release. The tracked instance is retrievable for diagnostics.
export type TrackHandle = {
	Instance: Instance,
}

return table.freeze({})
