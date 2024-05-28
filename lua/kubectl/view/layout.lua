local hl = require("kubectl.view.highlight")
local M = {}
local api = vim.api

local function set_buf_options(buf, win, filetype, syntax)
	api.nvim_set_option_value("filetype", filetype, { buf = buf })
	api.nvim_set_option_value("syntax", syntax, { buf = buf })
	api.nvim_set_option_value("bufhidden", "wipe", { scope = "local" })
	api.nvim_set_option_value("cursorline", true, { win = win })
	api.nvim_set_option_value("modified", false, { buf = buf })

	-- TODO: How do we handle long text?
	-- api.nvim_set_option_value("wrap", true, { scope = "local" })
	-- api.nvim_set_option_value("linebreak", true, { scope = "local" })

	-- TODO: Is this neaded?
	-- vim.wo[win].winhighlight = "Normal:Normal"
	-- TODO: Need to workout how to reuse single buffer with this setting, or not
	-- api.nvim_set_option_value("modifiable", false, { buf = buf })
end

function M.main_layout(buf, filetype, syntax)
	if not syntax then
		syntax = filetype
	end
	local win = api.nvim_get_current_win()
	set_buf_options(buf, win, filetype, syntax)
	hl.set_highlighting()
end

function M.float_layout(buf, filetype, title, syntax)
	if not syntax then
		syntax = filetype
	end
	local width = vim.o.columns - 20
	local height = 40
	local row = 5
	local col = 10

	local win = api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "minimal",
		width = math.floor(width),
		height = math.floor(height),
		row = row,
		border = "rounded",
		col = col,
		title = filetype .. " - " .. (title or ""),
	})

	set_buf_options(buf, win, filetype, syntax)
	hl.set_highlighting()
end

return M
