local M = {}

---@class CphRunOpts
---@field time_limit integer
---@field memory_limit integer

---@class CphWindowOpts
---@field width integer
---@field dir string
---@field height integer

---@class CphCompileOpt
---@field compiler string
---@field arg? string

---@class CphOpts
---@field window CphWindowOpts
---@field compile table<string, CphCompileOpt>
---@field run CphRunOpts

---@type CphOpts
local default_opts = {
	window = {
		width = 100,
		height = 80,
		dir = "left",
	},
	compile = {
		cpp = {
			compiler = "clang++",
			arg = "-O2",
		},
	},
	run = {
		time_limit = 2000,
		memory_limit = 2048,
	},
}

---@type CphOpts
M.opts = vim.deepcopy(default_opts)

---@param opts? CphOpts
function M.setup(opts)
	opts = opts or {}

	local merged = vim.tbl_deep_extend("force", vim.deepcopy(default_opts), opts)
	if opts.compile ~= nil then
		merged.compile = opts.compile
	end

	for filetype, item in pairs(merged.compile) do
		if type(filetype) ~= "string" then
			error("cph.setup(): compile keys must be filetype strings")
		end

		vim.validate({
			compiler = { item.compiler, "string" },
			arg = { item.arg, "string", true },
		})
	end

	vim.validate({
		window = { merged.window, "table" },
		compile = { merged.compile, "table" },
		run = { merged.run, "table" },
	})

	vim.validate({
		time_limit = { merged.run.time_limit, "number" },
		memory_limit = { merged.run.memory_limit, "number" },
	})

	M.opts = merged
end

function M.get()
	return M.opts
end

return M
