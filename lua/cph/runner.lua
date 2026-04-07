---@class CPHtest
---@field std_input string
---@field std_output string
---@field real_output string
---@field time_limit integer
---@field mem_limit integer
---@field passed string
---@field selected boolean


local M = {}

local highlight_ns = vim.api.nvim_create_namespace("cph-runner-highlight")
local decor_ns = vim.api.nvim_create_namespace("cph-runner-decor")
local popup_group = vim.api.nvim_create_augroup("CphRunnerPopup", { clear = true })

---@type integer
local buf = nil
local win = nil
local edit_buf = nil
local edit_win = nil
local edit_sync_pending = false


local lines = {}
local selected_test_rows = {}
local selected_test_indexes = {}
local selected_count = 0


---@type CPHtest[]
local tests = {}

---@type integer
local current = 1
---@type integer
local current_test_row = 1
---@type integer
local current_test_end_row = 1
---@type string
local file_path = ""
---@type string
local ui_file_path = ""
local in_create_ui = false
local in_tests_ui = false

local group = vim.api.nvim_create_augroup("MyPluginTrackSource", { clear = true })

local function get_config()
	return require("cph.config").get()
end

local function get_tests_path()
	return vim.fn.fnamemodify(file_path, ":h")
		.. "/.cph/"
		.. vim.fn.fnamemodify(file_path, ":t")
		.. ".json"
end

local function cph_exits()
	return vim.uv.fs_stat(get_tests_path()) ~= nil
end

local function write_tests()
	local cph_dir = vim.fn.fnamemodify(get_tests_path(), ":h")
	local persisted = {}

	for _, test in ipairs(tests) do
		persisted[#persisted + 1] = {
			std_input = test.std_input,
			std_output = test.std_output,
			time_limit = test.time_limit,
			mem_limit = test.mem_limit,
			selected = test.selected,
		}
	end

	vim.fn.mkdir(cph_dir, "p")
	vim.fn.writefile({ vim.json.encode(persisted) }, get_tests_path())
end

local function rebuild_selected_state()
	selected_count = 0
	selected_test_indexes = {}

	for i, test in ipairs(tests) do
		if test.selected then
			selected_count = selected_count + 1
			selected_test_indexes[#selected_test_indexes + 1] = i
		end
	end
end

local function creat_tests()
	tests = {
		{
			std_input = "",
			std_output = "",
			real_output = "",
			time_limit = get_config().run.time_limit,
			mem_limit = get_config().run.memory_limit,
			passed = "",
			selected = false,
		},
	}
	selected_count = 0
	selected_test_indexes = {}

	write_tests()
end

local function del_test(i)
	table.remove(tests, i)
	rebuild_selected_state()
end

local function add_test()
	tests[#tests + 1] = {
		std_input = "",
		std_output = "",
		real_output = "",
		time_limit = get_config().run.time_limit,
		mem_limit = get_config().run.memory_limit,
		passed = "",
		selected = false,
	}
	write_tests()
	M.refresh()
end

local function align_line(left, right, width)
	local pad = width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right)
	return left .. string.rep(" ", math.max(1, pad)) .. right
end

local function escape_statusline(text)
	return text:gsub("%%", "%%%%")
end

local function split_text(text)
	if text == "" then
		return { "" }
	end

	return vim.split(text, "\n", { plain = true, trimempty = false })
end

local function join_lines(input_lines)
	return table.concat(input_lines, "\n")
end

local function append_text_lines(target, text)
	for _, line in ipairs(split_text(text or "")) do
		target[#target + 1] = line
	end
end

local function set_winbar(content)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.wo[win].winbar = content
	end
end

local function clear_winbar()
	set_winbar("")
end

local function set_tests_winbar(selected_count)
	local title = "File: " .. vim.fn.fnamemodify(file_path, ":t")
	local summary = string.format("%d selected", selected_count)
	set_winbar(
		"%#CphTitle#" .. escape_statusline(title)
		.. "%="
		.. "%#CphSelected#" .. escape_statusline(summary)
		.. "%*"
	)
end

local function close_edit_popup()
	if edit_win and vim.api.nvim_win_is_valid(edit_win) then
		vim.api.nvim_win_close(edit_win, true)
	end

	edit_win = nil
	edit_buf = nil
	edit_sync_pending = false
end

local function sync_edit_popup(field, close_after_save)
	if not (edit_buf and vim.api.nvim_buf_is_valid(edit_buf)) then
		return
	end

	local test = tests[current]
	if not test then
		close_edit_popup()
		return
	end

	test[field] = join_lines(vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false))
	write_tests()
	M.refresh()
	if close_after_save then
		close_edit_popup()
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_set_current_win(win)
		end
	elseif edit_win and vim.api.nvim_win_is_valid(edit_win) then
		vim.api.nvim_set_current_win(edit_win)
	end
end

local function open_edit_popup(field, title)
	if not in_tests_ui or #tests == 0 then
		return
	end

	local test = tests[current]
	if not test then
		return
	end

	close_edit_popup()

	local content_lines = split_text(test[field] or "")
	local width = math.max(40, math.min(vim.o.columns - 8, 80))
	local height = math.max(8, math.min(vim.o.lines - 6, #content_lines + 2))

	edit_buf = vim.api.nvim_create_buf(false, true)
	vim.b[edit_buf].cph_popup = true
	vim.bo[edit_buf].buftype = "nofile"
	vim.bo[edit_buf].bufhidden = "wipe"
	vim.bo[edit_buf].swapfile = false
	vim.bo[edit_buf].filetype = "text"

	vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, content_lines)

	edit_win = vim.api.nvim_open_win(edit_buf, true, {
		relative = "editor",
		row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " " .. title .. " ",
		title_pos = "center",
	})

	vim.wo[edit_win].wrap = false
	vim.wo[edit_win].number = false
	vim.wo[edit_win].relativenumber = false
	vim.wo[edit_win].signcolumn = "no"

	vim.keymap.set("n", "q", close_edit_popup, { buffer = edit_buf, silent = true })
	vim.keymap.set("n", "<Esc>", close_edit_popup, { buffer = edit_buf, silent = true })

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = popup_group,
		buffer = edit_buf,
		once = true,
		callback = function()
			edit_win = nil
			edit_buf = nil
		end,
	})

	vim.api.nvim_buf_attach(edit_buf, false, {
		on_lines = function()
			if edit_sync_pending then
				return
			end

			edit_sync_pending = true
			vim.schedule(function()
				edit_sync_pending = false
				sync_edit_popup(field, false)
			end)
		end,
	})

	vim.cmd("startinsert")
end

local function apply_decorations()
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return
	end

	vim.api.nvim_buf_clear_namespace(buf, decor_ns, 0, -1)

	if #lines == 0 then
		return
	end

	for i, line in ipairs(lines) do
		local row = i - 1
		local function add_decoration(hl_group, col_start, col_end, priority)
			col_start = math.max(0, col_start)
			if col_end < 0 then
				col_end = #line
			end
			col_end = math.max(col_start, math.min(col_end, #line))

			vim.api.nvim_buf_set_extmark(buf, decor_ns, row, col_start, {
				end_col = col_end,
				hl_group = hl_group,
				priority = priority,
			})
		end

		if line:match("^  Test %d+") then
			add_decoration("CphHeading", 0, -1)
			if selected_test_rows[i] then
				add_decoration("CphSelectedBlock", 0, 2, 200)
			end

			if line:sub(-1) == ">" then
				add_decoration("CphAccent", #line - 1, #line, 200)
			end
		elseif line == "std_input: " or line == "std_output: " or line == "real_output: " then
			add_decoration("CphLabel", 0, -1)
		elseif not in_tests_ui and line ~= "" then
			add_decoration("CphMuted", 0, -1)
		end
	end
end

local function get_tests()
	local tests_path = get_tests_path()
	local content = table.concat(vim.fn.readfile(tests_path), "\n")
	local decoded = vim.json.decode(content) or {}

	tests = {}
	for _, test in ipairs(decoded) do
		test.real_output = test.real_output or ""
		test.passed = test.passed or ""
		test.selected = test.selected or false
		tests[#tests + 1] = test
	end

	rebuild_selected_state()
end

local function set_tests_ui()
	local width = win and vim.api.nvim_win_is_valid(win)
		and vim.api.nvim_win_get_width(win)
		or get_config().window.width

	lines = {}
	selected_test_rows = {}
	current_test_row = 1
	current_test_end_row = 1
	for i, test in ipairs(tests) do
		local test_start_row = #lines + 1
		if i == current then
			current_test_row = test_start_row
		end
		selected_test_rows[test_start_row] = test.selected
		lines[#lines + 1] = align_line("  Test " .. tostring(i), ">", width)
		lines[#lines + 1] = "std_input: "
		append_text_lines(lines, test.std_input)
		lines[#lines + 1] = "std_output: "
		append_text_lines(lines, test.std_output)
		if test.real_output ~= "" then
			lines[#lines + 1] = "real_output: "
			append_text_lines(lines, test.real_output)
		end
		if i == current then
			current_test_end_row = #lines
		end
	end

	set_tests_winbar(selected_count)
end

local function toggle_selected()
	if not in_tests_ui or #tests == 0 then
		return
	end

	local test = tests[current]
	if not test then
		return
	end

	test.selected = not test.selected
	if test.selected then
		selected_count = selected_count + 1
		selected_test_indexes[#selected_test_indexes + 1] = current
		table.sort(selected_test_indexes)
	else
		selected_count = math.max(0, selected_count - 1)
		for i = #selected_test_indexes, 1, -1 do
			if selected_test_indexes[i] == current then
				table.remove(selected_test_indexes, i)
				break
			end
		end
	end

	selected_test_rows[current_test_row] = test.selected
	set_tests_winbar(selected_count)
	apply_decorations()
	vim.cmd("redrawstatus")
	write_tests()
end

local function focus_current_test()
	if #tests == 0 then
		return
	end

	if not (win and vim.api.nvim_win_is_valid(win)) then
		return
	end

	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return
	end

	local row = current_test_row
	local end_row = current_test_end_row
	local height = math.max(1, vim.api.nvim_win_get_height(win))
	local block_height = end_row - row + 1

	vim.api.nvim_buf_clear_namespace(buf, highlight_ns, 0, -1)
	for line = row, end_row do
		vim.api.nvim_buf_set_extmark(buf, highlight_ns, line - 1, 0, {
			line_hl_group = "CphCurrentTest",
		})
	end

	pcall(vim.api.nvim_win_set_cursor, win, { row, 0 })
	pcall(vim.api.nvim_win_call, win, function()
		local view = vim.fn.winsaveview()
		local topline = view.topline
		local bottomline = topline + height - 1
		local target_topline = topline

		if block_height <= height then
			if row < topline then
				target_topline = row
			elseif end_row > bottomline then
				target_topline = end_row - height + 1
			end
		else
			if row < topline or row > bottomline then
				target_topline = row
			end
		end

		vim.fn.winrestview({
			lnum = row,
			col = 0,
			topline = math.max(1, target_topline),
			leftcol = 0,
		})
	end)
end

local function refresh_tests_ui()
	get_tests()

	if #tests == 0 then
		current = 1
		current_test_row = 1
		current_test_end_row = 1
	else
		current = math.max(1, math.min(current, #tests))
	end

	set_tests_ui()

	if #tests == 0 then
		return
	end
	vim.schedule(function()
		focus_current_test()
	end)
end

local function set_creat_ui()
	clear_winbar()
	lines = (function()
		local prompts = {
			"File: " .. vim.fn.fnamemodify(file_path, ":t"),
			"当前文件还没有创建 cph",
			"按下 c 创建",
		}
		local width = win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_width(win) or
			get_config().window.width
		local height = win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_height(win) or #prompts
		local centered = {}
		local top_pad = math.max(1, math.floor(height * 0.2))

		for _ = 1, top_pad do
			centered[#centered + 1] = ""
		end

		for _, line in ipairs(prompts) do
			local left_pad = math.max(0, math.floor((width - vim.fn.strdisplaywidth(line)) / 2))
			centered[#centered + 1] = string.rep(" ", left_pad) .. line
		end

		return centered
	end)()
end


local function set_welcome()
	clear_winbar()
	lines = (function()
		local art = {
			"  _____ ____  _   _ ",
			" / ____|  _ \\| | | |",
			"| |    | |_) | |_| |",
			"| |    |  __/|  _  |",
			"| |____| |   | | | |",
			" \\_____|_|   |_| |_|",
		}
		local width = win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_width(win) or
			get_config().window.width
		local height = win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_height(win) or #art
		local centered = {}
		local top_pad = math.max(0, math.floor((height - #art) / 2))

		for _ = 1, top_pad do
			centered[#centered + 1] = ""
		end

		for _, line in ipairs(art) do
			local left_pad = math.max(0, math.floor((width - vim.fn.strdisplaywidth(line)) / 2))
			centered[#centered + 1] = string.rep(" ", left_pad) .. line
		end

		return centered
	end)()
end

local function build_lines()
	lines = {}
	local type = vim.uv.fs_stat(file_path)

	if not type or type.type == "directory" then
		ui_file_path = file_path
		in_create_ui = false
		in_tests_ui  = false
		set_welcome()
	else
		if ui_file_path ~= file_path then
			ui_file_path = file_path
			in_create_ui = false
			in_tests_ui = false
		end

		if in_tests_ui or cph_exits() then
			in_create_ui = false
			in_tests_ui = true
			refresh_tests_ui()
		else
			in_tests_ui = false
			in_create_ui = true
			set_creat_ui()
		end
	end
end

local function map_multi(modes, lhs_list, rhs, opts)
	if type(lhs_list) == "string" then
		lhs_list = { lhs_list }
	end

	for _, lhs in ipairs(lhs_list) do
		vim.keymap.set(modes, lhs, rhs, opts)
	end
end


local function set_keymaps()
	vim.keymap.set("n", "q", function()
		M.close()
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "<CR>", function()
		local line = vim.api.nvim_get_current_line()
		vim.notify("selected: " .. line)
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "c", function()
		if in_create_ui then
			creat_tests()
			M.refresh()
		end
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "a", function()
		if in_tests_ui then
			add_test()
		end
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "<Space>", function()
		toggle_selected()
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "i", function()
		open_edit_popup("std_input", "Edit std_input")
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "o", function()
		open_edit_popup("std_output", "Edit std_output")
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "d", function()
		if in_tests_ui then
			if #selected_test_indexes == 0 then
				del_test(current)
				write_tests()
				M.refresh()
				return
			end
			for i = #selected_test_indexes, 1, -1 do
				del_test(selected_test_indexes[i])
			end
			write_tests()
			M.refresh()
		end
	end, { buffer = buf, silent = true })

	map_multi("n", { "j", "<Down>" }, M.next_test, { buffer = buf, silent = true })
	map_multi("n", { "k", "<Up>" }, M.last_test, { buffer = buf, silent = true })
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

	set_keymaps()
end

function M.render()
	ensure_buf()

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_clear_namespace(buf, highlight_ns, 0, -1)
	vim.api.nvim_buf_clear_namespace(buf, decor_ns, 0, -1)
	build_lines()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	apply_decorations()
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
	vim.wo[win].fillchars = "eob: "

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
	if in_tests_ui and current < #tests then
		current = current + 1
		M.render()
	end
end

function M.last_test()
	if in_tests_ui and current > 1 then
		current = current - 1
		M.render()
	end
end

function M.setup()
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "TabEnter" }, {
		group = group,
		callback = function(args)
			if vim.b[args.buf].cph_popup then
				return
			end
			if buf ~= args.buf then
				file_path = vim.api.nvim_buf_get_name(args.buf)
				M.refresh()
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
		group = group,
		callback = function(args)
			if vim.b[args.buf].cph_popup then
				return
			end
			if vim.api.nvim_buf_get_name(args.buf) == file_path then
				local win_ = vim.api.nvim_get_current_win()
				file_path = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win_))
				M.refresh()
			end
		end,
	})
end

return M
