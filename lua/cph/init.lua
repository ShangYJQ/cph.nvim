local M = {}
local config = require("cph.config")
local runner = require("cph.runner")

function M.toggle()
	runner.toggle()
end

function M.setup(opts)
	config.setup(opts)
	runner.setup()
end

return M
