--!nocheck
-- P1.W3 failure proof: this file must make the dependency gate fail. Reverted in the next commit.
local RunService = game:GetService("RunService")
local Impl = require(script.Parent.Host.Impl)
local Other = require(script.Parent.Parent.Tin.Host.Impl)

return { RunService, Impl, Other }
