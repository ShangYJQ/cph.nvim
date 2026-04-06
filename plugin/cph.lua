vim.api.nvim_create_user_command("ToggleCPH", function()
	require("cph").toggle()
end, {})
