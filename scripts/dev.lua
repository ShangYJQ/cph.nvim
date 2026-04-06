local root = vim.fn.getcwd()

vim.opt.rtp:prepend(root)
local function reload()
	for name in pairs(package.loaded) do
		if name == "cph" or name:match("^cph%.") then
			package.loaded[name] = nil
		end
	end
	return require("cph")
end

vim.g.mapleader = ' '

local config = {
	compile = {

		cpp = {
			compiler = "g++"
		},
		c = {
			compiler = "clang"
		}

	},

	run = {
		timeout = 1991,
	}

}

vim.api.nvim_create_user_command("DevReload", function()
	reload().setup(config)
	vim.notify("cph reloaded")
end, {})

reload().setup(config)

vim.keymap.set("n", "<leader>r", "<cmd>DevReload<CR>")
vim.keymap.set("n", "<leader>o", "<cmd>ToggleCPH<CR>")
