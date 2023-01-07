local M = {}
local api = vim.api
local inspect = vim.inspect
local fn = vim.fn
local cmd = vim.cmd
local block_next_resize_event = false
local block_next_win_new_event = false

local function calc_padding(width)
	local textwidth = 70
	width = width or api.nvim_win_get_width(0)
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
	--api.nvim_buf_set_option(padbuf, 'modifiable', false)
	api.nvim_buf_set_option(padbuf, 'modifiable', true)
	api.nvim_buf_set_option(padbuf, 'buflisted', false)

	return padbuf
end

local function padwin_new(side, win)
	block_next_win_new_event = true
	local org_win = api.nvim_get_current_win()
	win = win or org_win
	api.nvim_set_current_win(win)

	-- Create padwinwins
	if side == 1 then
		cmd('vertical leftabove sb')
	elseif side == 2 then
		cmd('vertical rightbelow sb')
	end
	local padwin = api.nvim_get_current_win()

	-- Setup padwin
	api.nvim_win_set_var(padwin, 'padparent', win)
	api.nvim_win_set_buf(padwin, padbuf_new(win))

	-- Go back to original window
	api.nvim_set_current_win(org_win)

	block_next_win_new_event = false
	return padwin
end

local function padwin_avoid_enter()
	local win = api.nvim_get_current_win()
	local is_padwin = pcall(api.nvim_win_get_var, win, 'padparent')
	if not is_padwin then
		return
	end

	local function go_to_win_at(side, alt_side)
		local cur_win = api.nvim_get_current_win()
		cmd('wincmd '..side)
		if cur_win == api.nvim_get_current_win() then
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

local function padparent_set_width(padparent, padwins, width, padding)
	api.nvim_win_set_width(padwins[1], padding)
	api.nvim_win_set_width(padparent, width - (padding * 2))
	api.nvim_win_set_width(padwins[2], padding)
end

local function padparent_calc_padding(padparent, width)
	width = width or padparent_get_width(padparent)
	return calc_padding(width)
end

local function padparent_avoid_displacement()
	local last_win = get_last_win()
	if block_next_win_new_event or not padparent_get_padwins(last_win) then
		return
	end

	local win = api.nvim_get_current_win()
	local padwin_on_left = padparent_get_padwins(get_win_at('h'))
	local padwin_on_right = padparent_get_padwins(get_win_at('l'))

	if padwin_on_left and not padwin_on_right then
		cmd('wincmd x')
		api.nvim_win_set_width(win, api.nvim_win_get_width(win) + (padwin_on_left[1] and api.nvim_win_get_width(padwin_on_left[1]) or 0))
	elseif not padwin_on_left and padwin_on_right then
		cmd('wincmd h')
		cmd('wincmd x')
		api.nvim_win_set_width(win,
			api.nvim_win_get_width(win) + (padwin_on_right[1] and api.nvim_win_get_width(padwin_on_right[1]) or 0))
	end
end

local function padparent_set_padwins(padparent, padwins)
	api.nvim_win_set_var(padparent, 'padwins', padwins)
end

local function padparent_add_padding(padparent)
	vim.o.winfixwidth = true
	local padwins = {padwin_new(1, padparent), padwin_new(2, padparent)}
	vim.o.winfixwidth = false

	padparent_set_padwins(padparent, padwins)

	return padwins
end

function M.check()
	local win = api.nvim_get_current_win()
	local ok = pcall(api.nvim_win_get_var, win, 'padwins')
	print(win, ok)
	return ok
end

function M.refresh(windows)
	if block_next_resize_event then
		block_next_resize_event = false
		return
	end
	assert(type(windows) == 'table')

	for _, win in pairs(windows) do
		local ok, padparent = pcall(api.nvim_win_get_var, win, 'padparent')
		if ok then
			win = padparent
		end

		if vim.g.disable_refresh then
			return
		end
		local padwins = padparent_get_padwins(win)
		if padwins then
			local padding = padparent_calc_padding(win)

			if padding > 0 then
				M.center(win, padding, padwins)
				block_next_resize_event = true
			else
				M.offcenter(win, padwins, true)
				block_next_resize_event = true
			end
		end
	end
end
local function padparent_fix_position(win, col_win)
	local org_win = api.nvim_get_current_win()
	local new_col_win = api.nvim_win_get_position(win)[2]
	local function excess_cells(cell1, cell2)
		local ret = math.abs(cell2 - cell1)
		return ret
	end

	api.nvim_set_current_win(win)
	if col_win < new_col_win then
		print(string.format('wincmd %d%s | col%d newcol%d', excess_cells(col_win, new_col_win), '>', col_win, new_col_win))
		cmd('wincmd 2l')
		cmd(string.format('wincmd %d%s', excess_cells(col_win, new_col_win), '<'))
	elseif col_win > new_col_win then
		print(string.format('wincmd %d%s | col%d newcol%d', excess_cells(col_win, new_col_win), '<', col_win, new_col_win))
		cmd('wincmd 2h')
		cmd(string.format('wincmd %d%s', excess_cells(col_win, new_col_win), '>'))
	end

	api.nvim_set_current_win(org_win)
end

function M.center(win, padding, padwins)
	win = win or api.nvim_get_current_win()
	padwins = padparent_get_padwins(win, padwins)
	local width = padparent_get_width(win)
	padding = padparent_calc_padding(win, width)

	if padwins then
		if #padwins == 0 then
			local col_win = api.nvim_win_get_position(win)[2]
			padwins = padparent_add_padding(win)

			-- center
			padparent_fix_position(win, col_win)
			padparent_set_width(win, padwins, width, padding)
		else
			padparent_set_width(win, padwins, width, padding)
		end
	else
		-- if there is not enough space to center then don't center, just convert win to a padparent without padding
		if padding == 0 then
			padparent_set_padwins(win, {})
			return
		end

		-- center
		padwins = padparent_add_padding(win)
		padparent_set_width(win, padwins, width, padding)
	end
end

function M.offcenter(win, padwins, keep_var)
	win = win or api.nvim_get_current_win()
	padwins = padparent_get_padwins(win, padwins)

	-- BUG: Why is offcenter called several times with #padwins == 0
	if #padwins == 0 then
		return
	end

	local w0 = padparent_get_width(win)
	local col_win = api.nvim_win_get_position(padwins[1])[2]

	api.nvim_win_close(padwins[1], true)
	api.nvim_win_close(padwins[2], true)
	padparent_fix_position(win, col_win)
	api.nvim_win_set_width(win, w0)

	if keep_var then
		padparent_set_padwins(win, {})
	else
		api.nvim_win_del_var(win, 'padwins')
	end
end

function M.setup()
	local augroup_center = api.nvim_create_augroup('Center', {clear = true})
	local autocmd = api.nvim_create_autocmd

	autocmd('WinResized', {
		group = augroup_center,
		callback = function()
			for _,win in pairs(vim.v.event.windows) do
				api.nvim_buf_set_lines(api.nvim_win_get_buf(win), 1,2, false, {tostring(api.nvim_win_get_position(win)[2])})
			end
			M.refresh(vim.v.event.windows)
		end
	})

	autocmd('WinNew', {
		group = augroup_center,
		callback = function()
			cmd('enew')
			padparent_avoid_displacement()
		end
	})

	autocmd('WinEnter', {
		group = augroup_center,
		callback = padwin_avoid_enter
	})
end

return M
