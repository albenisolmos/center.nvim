local M = {}
local vim = vim
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local first_centering = false
local _padwins = {}
local block_refresh = false
local DEFAULT_SETTINGS = {
	autocentering = false,
	win_width = 80,
	on_padding_buf = function(buf, win) end,
	debug = false,
}
M.DEFAULT_SETTINGS = DEFAULT_SETTINGS
M.settings = DEFAULT_SETTINGS

local function set_settings(opts)
	M.settings = vim.tbl_deep_extend("force", M.settings, opts)
	vim.validate({
		autocenter = { M.settings.autocentering, "boolean" },
		win_width = { M.settings.win_width, "number" },
		on_padding_buf = { M.settings.on_padding_buf, "function" },
		debug = { M.settings.debug, "boolean" },
	})
end

local function create_padbuf(win)
	local padbuf = api.nvim_create_buf(false, true)
	local opt = {}

	api.nvim_set_option_value("relativenumber", false, opt)
	api.nvim_set_option_value("number", false, opt)
	api.nvim_set_option_value("cursorline", false, opt)
	api.nvim_set_option_value("cursorcolumn", false, opt)
	api.nvim_buf_set_option(padbuf, "buftype", "nofile")
	api.nvim_buf_set_option(padbuf, "bufhidden", "wipe")
	api.nvim_buf_set_option(padbuf, "modifiable", false)
	api.nvim_buf_set_option(padbuf, "buflisted", false)

	if type(M.settings.on_padding_buf) == "function" then
		M.settings.on_padding_buf(padbuf, win)
	end

	return padbuf
end

local function create_padwin(side, win)
	local org_win = api.nvim_get_current_win()
	win = win or org_win
	api.nvim_set_current_win(win)

	-- Create padwins
	if side == 1 then
		cmd("vertical leftabove sb")
	elseif side == 2 then
		cmd("vertical rightbelow sb")
	end
	local padwin = api.nvim_get_current_win()

	-- Setup padwin
	api.nvim_win_set_var(padwin, "padparent", win)
	api.nvim_win_set_buf(padwin, create_padbuf(padwin))

	-- TODO: there is any posibility to set up this with lua?
	cmd([[setlocal fillchars=eob:\ ,vert:\ ]])
	cmd([[setglobal fillchars=vert:\ ]])

	-- Go back to original window
	api.nvim_set_current_win(win)

	return padwin
end

local function is_padwin(win)
	return pcall(api.nvim_win_get_var, win, "padparent")
end

local function avoid_enter_padwin()
	local win = api.nvim_get_current_win()

	if not is_padwin(win) then
		return
	end

	local function go_to_win_at(side, alt_side)
		local cur_win = api.nvim_get_current_win()
		cmd("wincmd " .. side)

		if cur_win == api.nvim_get_current_win() then
			cmd("wincmd " .. alt_side)
		end
	end

	local last_win = fn.win_getid(fn.winnr("#"))
	local position_win = api.nvim_win_get_position(win)
	local position_last_win = api.nvim_win_get_position(last_win)
	local col_win = position_win[2]
	local col_last_win = position_last_win[2]

	-- is on the left
	if col_last_win < col_win then
		go_to_win_at("l", "h")
	else
		go_to_win_at("h", "l")
	end
end

local function get_padwins()
	return _padwins
end

local function set_padwins(padwins)
	_padwins = padwins
end

local function is_splitted_vertically()
	local wins = api.nvim_tabpage_list_wins(0)
	local i = 0

	for _, win in pairs(wins) do
		local row = api.nvim_win_get_position(win)[1]

		if is_padwin(win) == false and row == 0 and i == 1 then
			return true
		end

		i = i + 1
	end
end

local function update_width(padparent, padwins, width, padding)
	api.nvim_win_set_width(padwins[1], padding)
	api.nvim_win_set_width(padparent, width - (padding * 2))
	api.nvim_win_set_width(padwins[2], padding)
end

local function get_avaliable_width()
	local wins = api.nvim_tabpage_list_wins(0)
	local width = 0

	for _, win in pairs(wins) do
		local row = api.nvim_win_get_position(win)[1]

		if row == 0 then
			width = width + api.nvim_win_get_width(win)
		end
	end

	return width
end

local function calc_padding()
	local width = get_avaliable_width()

	local textwidth = M.settings.win_width
	local padding = (width - textwidth) / 2

	if padding < 0 then
		padding = 0
	end

	return math.ceil(padding)
end

local function create_padwins(padparent)
	local padwins = { create_padwin(1, padparent), create_padwin(2, padparent) }
	set_padwins(padwins)
	return padwins
end

local function add_autocommands()
	local augroup_center = api.nvim_create_augroup("Center", { clear = true })
	local autocmd = api.nvim_create_autocmd

	autocmd("WinResized", {
		group = augroup_center,
		callback = function()
			M.refresh(vim.v.event.windows)
		end,
	})

	autocmd({ "WinEnter", "VimEnter" }, {
		group = augroup_center,
		callback = avoid_enter_padwin,
	})

	autocmd("WinClosed", {
		group = augroup_center,
		callback = function()
			-- If theres more than one tab, dont quit
			if #api.nvim_list_tabpages() > 1 then
				return
			end

			local wins = api.nvim_tabpage_list_wins(0)
			local i = #wins

			for _, win in pairs(wins) do
				if is_padwin(win) then
					i = i - 1
				end
			end

			if i == 1 then
				cmd("qa!")
			end
		end,
	})
end

local function remove_autocommands()
	api.nvim_del_augroup_by_name("Center")
end

function M.refresh(windows)
	if block_refresh then
		return
	end
	assert(type(windows) == "table")

	local padwins = get_padwins()
	local padding = calc_padding()

	if is_splitted_vertically() then
		M.offcenter()
	elseif padding > 0 then
		M.center()
	elseif #padwins == 0 and padding == 0 then
		return
	else
		M.offcenter()
	end
end

function M.center(win, padding, padwins)
	block_refresh = true

	--  Check for the first centering for attach autocommand
	if first_centering == false then
		add_autocommands()
		first_centering = true
	end

	win = win or api.nvim_get_current_win()
	local wins = api.nvim_tabpage_list_wins(0)

	-- Get first win that is not padwin
	for _, w in pairs(wins) do
		if not is_padwin(w) then
			win = w
			break
		end
	end

	padwins = get_padwins()
	local width = get_avaliable_width()
	padding = padding or calc_padding()

	if not padwins or #padwins == 0 then
		-- if there is not enough space to center then don't center
		if padding == 0 then
			return
		end

		padwins = create_padwins(win)
		update_width(win, padwins, width, padding)
	else
		update_width(win, padwins, width, padding)
	end

	block_refresh = false
end

function M.offcenter(win, padwins)
	block_refresh = true
	win = win or api.nvim_get_current_win()
	padwins = padwins or get_padwins()

	if not padwins or #padwins == 0 then
		block_refresh = false
		return
	end

	api.nvim_win_close(padwins[1], true)
	api.nvim_win_close(padwins[2], true)
	set_padwins({})

	block_refresh = false
end

function M.setup(opts)
	local command = api.nvim_create_user_command

	set_settings(opts)

	command("Center", function(props)
		for _, arg in pairs(props.fargs) do
			if arg == "on" then
				M.center()
			elseif arg == "off" then
				remove_autocommands()
				M.offcenter()
			end
		end
	end, { nargs = 1 })

	if M.settings.autocentering == true then
		M.center()
	end
end

return M
