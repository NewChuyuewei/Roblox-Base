--!strict
-- Dr.Core.Foundation.CoreTypes — shared core primitives. Pure types, no engine imports.
--
-- CERTIFIED (DAL C) — 需求基线：docs/cert/req/CORETYPES.md（HLR/LLR 与本文件注解双向可查；
-- 追溯矩阵 docs/cert/TRACE.md 由 scripts/cert-trace-check.luau 生成）。

-- LLR-CORETYPES-001
export type DrError = {
	code: string, -- stable, greppable identifier, e.g. "DR.INIT.FAILED"
	message: string, -- human-readable detail
	source: string?, -- e.g. "Provider/Name.Init"
}

-- LLR-CORETYPES-002
export type Result = {
	ok: boolean,
	err: DrError?,
}

return table.freeze({})
