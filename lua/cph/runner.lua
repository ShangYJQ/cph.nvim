---@class CPHtest
---@field std_input string
---@field std_output string
---@field real_output string
---@field time_limit integer
---@field mem_limit integer


local M = {


}

---@type integer
local buf = nil
local win = nil


local lines = {}


---@type CPHtest[]
local tests = {}
---@type integer
local current = 1
---@type string
local file_path = ""

local group = vim.api.nvim_create_augroup("MyPluginTrackSource", { clear = true })

local function get_config()
	return require("cph.config").get()
end

local function get_tests()

end


local function set_welcome()

end

local function build_lines()
	local config = get_config()

	local type = vim.uv.fs_stat(file_path)

	if type == "directory" then

	end
	lines = {
		file_path,
		vim.fn.fnamemodify(file_path, ":f"),
		vim.fn.fnamemodify(file_path, ":e"),
		config.compile["cpp"].compiler
	}
end


local function ensure_buf()
	if buf and vim.api.nvim_buf_is_valid(buf) then
		return buf
	end

	buf = vim.api.nvim_create_buf(false, true)

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "cph-tree"

	vim.keymap.set("n", "q", function()
		M.close()
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "<CR>", function()
		local line = vim.api.nvim_get_current_line()
		vim.notify("selected: " .. line)
	end, { buffer = buf, silent = true })
end

function M.render()
	ensure_buf()

	vim.bo[buf].modifiable = true
	build_lines()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
end

function M.refresh()
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_set_width(win, get_config().window.width)
		M.render()
	end
end

function M.open()
	local config = get_config();
	file_path = vim.api.nvim_buf_get_name(0)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
		M.refresh()
		return
	end

	ensure_buf()

	win = vim.api.nvim_open_win(buf, true, {
		split = config.window.dir,
		win = -1,
	})

	vim.api.nvim_win_set_width(win, get_config().window.width)

	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	vim.wo[win].winfixwidth = true
	vim.wo[win].statuscolumn = ""

	M.render()
end

function M.close()
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	win = nil
end

function M.toggle()
	if win and vim.api.nvim_win_is_valid(win) then
		M.close()
	else
		M.open()
	end
end

function M.next_test()
	if current < #tests then
		current = current + 1
	end
end

function M.last_test()
	if current > 2 then
		current = current - 1
	end
end

function M.setup()
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "TabEnter" }, {
		group = group,
		callback = function(args)
			if buf ~= args.buf then
				file_path = vim.api.nvim_buf_get_name(args.buf)
				M.refresh()
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
		group = group,
		callback = function(args)
			if vim.api.nvim_buf_get_name(args.buf) == file_path then
				local win_ = vim.api.nvim_get_current_win()
				file_path = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win_))
				M.refresh()
			end
		end,
	})
end

return M
