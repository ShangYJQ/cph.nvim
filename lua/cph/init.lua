local M = {}

local config = require("cph.config")
local highlights = require("cph.highlights")
local runner = require("cph.runner")

highlights.setup()

function M.toggle()
	runner.toggle()
end

function M.setup(opts)
	config.setup(opts)
	highlights.setup()
	runner.setup()
end

return M
