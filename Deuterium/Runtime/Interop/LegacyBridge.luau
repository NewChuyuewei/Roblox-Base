--!strict
-- Dr.Runtime.Interop.LegacyBridge
-- Safe, observable adapter for pre-Deuterium legacy systems (Commander, F3X, DAWX...).
-- We never edit legacy code; we wrap it. Every touchpoint is pcall-guarded.

local LegacyBridge = {}

-- Safely require a legacy ModuleScript. Diagnostic-friendly: returns
-- (true, module) or (false, errorString) instead of throwing through callers.
function LegacyBridge.SafeRequire(module: Instance): (boolean, unknown)
	if not module:IsA("ModuleScript") then
		return false, `[Dr.LegacyBridge] not a ModuleScript: {module:GetFullName()}`
	end
	local ok, result = pcall(require, module)
	if not ok then
		return false, `[Dr.LegacyBridge] require failed: {module:GetFullName()} -> {tostring(result)}`
	end
	return true, result
end

-- Call a function captured from a legacy module without letting it crash the caller.
function LegacyBridge.TryCall(fn: (...any) -> ...any, ...: any): (boolean, any)
	local results = table.pack(pcall(fn, ...))
	local ok = results[1] == true
	if ok then
		return true, results[2]
	end
	return false, results[2]
end

return table.freeze(LegacyBridge)
