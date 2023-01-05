local M = {}
local api = vim.api
local inspect = vim.inspect
local fn = vim.fn
local cmd = vim.cmd
local block_next_resize_event = false

local function calc_padding(win, width)
	local textwidth = 80
	width = width or api.nvim_win_get_width(win)
	local padding = (width - textwidth) / 2

	if padding < 0 then
		padding = 0
	end

	return math.floor(padding)
end

local function get_last_win()
	return fn.win_getid(fn.winnr('#'))
end

local function get_win_at(side)
	return fn.win_getid(fn.winnr(side))
end

local function padbuf_new(win)
	local padbuf = api.nvim_create_buf(false, true)

	-- add empty lines
	for i=0, api.nvim_win_get_height(win) do
		api.nvim_buf_set_lines(padbuf, i, i, false, {''})
	end

	-- buffer settings
	local opt = {scope = 'local'}
	api.nvim_set_option_value('number', false, opt)
	api.nvim_set_option_value('relativenumber', false, opt)
	api.nvim_set_option_value('cursorline', false, opt)
	api.nvim_set_option_value('cursorcolumn', false, opt)

	api.nvim_buf_set_option(padbuf, 'buftype', 'nofile')
	api.nvim_buf_set_option(padbuf, 'bufhidden', 'wipe')
	api.nvim_buf_set_option(padbuf, 'modifiable', false)
	api.nvim_buf_set_option(padbuf, 'buflisted', false)

	return padbuf
end

local function padparent_get_padwins(padparent, padwins)
	if padwins then
		return padwins
	else
		local ok
		ok, padwins = pcall(api.nvim_win_get_var, padparent, 'padwins')
		if ok then
			return padwins
		end
	end
end

local function padparent_get_width(padparent)
	local ok, padwins = pcall(api.nvim_win_get_var, padparent, 'padwins')
	local total_width = api.nvim_win_get_width(padparent)

	if ok then
		for _, padwin in pairs(padwins) do
			total_width = total_width + api.nvim_win_get_width(padwin)
		end
	end

	return total_width
end

M.get_width = padparent_get_width

function M.check()
	local ok = pcall(api.nvim_win_get_var, api.nvim_get_current_win(), 'padwins')
	return ok
end

local function padparent_avoid_displacement()
	local last_win = get_last_win()
	if not padparent_get_padwins(last_win) then
		return
	end

	local win = api.nvim_get_current_win()
	local padwin_on_left = padparent_get_padwins(get_win_at('h'))
	local padwin_on_right = padparent_get_padwins(get_win_at('l'))

	if padwin_on_left and not padwin_on_right then
		vim.cmd('wincmd x')
		api.nvim_win_set_width(win, api.nvim_win_get_width(win)+api.nvim_win_get_width(padwin_on_left[1]))
	elseif not padwin_on_left and padwin_on_right then
		vim.cmd('wincmd h')
		vim.cmd('wincmd x')
		api.nvim_win_set_width(win, api.nvim_win_get_width(win)+api.nvim_win_get_width(padwin_on_right[1]))
	end

	M.center(last_win)
end

local function padparent_set_padwins(padparent, padwins)
	api.nvim_win_set_var(padparent, 'padwins', padwins)
end

local function padwin_new(side, win)
	local org_win = api.nvim_get_current_win()
	win = win or org_win

	-- Create padwin
	if side == 1 then
		vim.cmd('vertical leftabove sb')
	elseif side == 2 then
		vim.cmd('vertical rightbelow sb')
	end
	local padwin = api.nvim_get_current_win()

	-- Setup padwin
	api.nvim_win_set_var(padwin, 'padparent', win)
	api.nvim_win_set_buf(padwin, padbuf_new(win))

	-- Go back to original window
	api.nvim_set_current_win(org_win)

	return padwin
end

local function padwin_avoid_enter()
	local win = api.nvim_get_current_win()
	local is_padwin = pcall(api.nvim_win_get_var, win, 'padparent')
	if not is_padwin then
		return
	end

	local function go_to_win_at(side, alt_side)
		local win = api.nvim_get_current_win()
		cmd('wincmd '..side)
		if win == api.nvim_get_current_win()  then
			cmd('wincmd '..alt_side)
		end
	end

	local last_win = fn.win_getid(fn.winnr('#'))
	local position_win = api.nvim_win_get_position(win)
	local position_last_win  = api.nvim_win_get_position(last_win)
	local col_win = position_win[2]
	local col_last_win = position_last_win[2]

	-- is on the left
	if col_last_win < col_win then
		go_to_win_at('l', 'h')
	else
		go_to_win_at('h', 'l')
	end

	-- TODO: avoid enter to padwin from up
end

function M.refresh(windows)
	if block_next_resize_event then
		return
	end
	assert(type(windows) == 'table')

	for _, win in pairs(windows) do
		local ok, padparent = pcall(api.nvim_win_get_var, win, 'padparent')
		if ok then
			win = padparent
		end

		local padwins = padparent_get_padwins(win)
		if padwins then
			print('refresh')
			local width = padparent_get_width(win)
			local padding = calc_padding(nil, width)

			if padding > 0 then
				M.center(win, padding, padwins)
			else
				M.offcenter(win, true)
			end
		end
	end
end

function M.center(win, padding, padwins, no_resize_event)
	win = win or api.nvim_get_current_win()
	padwins = padparent_get_padwins(win, padwins)

	if padwins then
		if #padwins == 0 then
			local width = padparent_get_width(win)
			padding = calc_padding(nil, width)
			padwins = {padwin_new(1, win), padwin_new(2, win)}
			padparent_set_padwins(win, padwins)

			-- center
			api.nvim_win_set_width(padwins[1], padding)
			api.nvim_win_set_width(win, width - (padding * 2))
			api.nvim_win_set_width(padwins[2], padding)
		else
			local width = padparent_get_width(win)
			padding = calc_padding(nil, width)
			api.nvim_win_set_width(padwins[1], padding)
			api.nvim_win_set_width(win, width - (padding * 2))
			api.nvim_win_set_width(padwins[2], padding)
		end
	else
		local width = padparent_get_width(win)
		padding = calc_padding(nil, width)
		print(padding)
		padwins = {padwin_new(1, win), padwin_new(2, win)}

		padparent_set_padwins(win, padwins)

		-- center
		api.nvim_win_set_width(padwins[1], padding)
		api.nvim_win_set_width(win, width - (padding * 2))
		api.nvim_win_set_width(padwins[2], padding)
	end

	block_next_resize_event = true
end

function M.offcenter(win, padwins, keep_var)
	win = win or api.nvim_get_current_win()
	padwins = padparent_get_padwins(win, padwins)

	if keep_var then
		padparent_set_padwins(win,  {})
	else
		api.nvim_win_del_var(win, 'padwins')
	end

	for _, padwin in pairs(padwins) do
		api.nvim_win_close(padwin, true)
	end
end

function M.setup()
	local augroup_center = api.nvim_create_augroup('Center', {clear = true})
	local autocmd = api.nvim_create_autocmd

	autocmd('WinResized', {
		group = augroup_center,
		callback = function()
			M.refresh(vim.v.event.windows)
		end
	})

	autocmd('WinNew', {
		group = augroup_center,
		callback = padparent_avoid_displacement
	})

	autocmd('WinEnter', {
		group = augroup_center,
		callback = padwin_avoid_enter
	})
end

return M
