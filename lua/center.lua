local M = {}
local api = vim.api
local inspect = vim.inspect
local block_next_resize_event = false

local function calc_padding(win, width)
	local textwidth = 80
	width = width or api.nvim_win_get_width(win)
	local padding = (textwidth - width) / 2

	if padding < 0 then
		padding = 0
	end

	return math.floor(padding)
end

local function padbuf_new(win)
	local padbuf = api.nvim_create_buf(false, true)

	-- add empty lines
	for i=0, api.nvim_win_get_heigth(win) do
		api.nvim_buf_set_text(padbuf, i, 1, i, 1, '')
	end

	-- buffer settings
	local opt = {scope = 'local'}
	api.nvim_set_option('number', false, opt)
	api.nvim_set_option('relativenumber', false, opt)
	api.nvim_set_option('cursorline', false, opt)
	api.nvim_set_option('cursorcolumn', false, opt)

	api.nvim_buf_set_option(padbuf, 'buftype', 'nofile')
	api.nvim_buf_set_option(padbuf, 'bufhidden', 'wipe')
	api.nvim_buf_set_option(padbuf, 'nomodifiable', false)
	api.nvim_buf_set_option(padbuf, 'nobuflisted', false)

	return padbuf
end

local function padparent_get_padwins(padparent, padwins)
	if padwins then
		return
	else
		local ok
		ok, padwins = api.nvim_win_get_var(padparent, 'padwins')
		if ok then
			return padwins
		end
	end
end

local function padparent_get_width(padparent)
	local ok, padwins = api.nvim_win_get_var(padparent, 'padwins')
	local total_width = api.nvim_win_get_width(padparent)

	if ok then
		for _, padwin in pairs(padwins) do
			total_width = total_width + api.nvim_win_get_width(padwin)
		end
	end
end

local function padwin_new(side, win)
	local org_win = api.nvim_get_current_win()
	win = win or org_win

	-- Create padwin
	if side == 1 then
		api.nvim_cmd('vertical leftabove sb')
	elseif side == 2 then
		api.nvim_cmd('vertical rightbelow sb')
	end
	local padwin = api.nvim_get_current_win()

	-- Setup padwin
	api.nvim_win_set_var(padwin, 'padparent', win)
	api.nvim_win_set_buf(padwin, padbuf_new(win))

	local padwins = padparent_get_padwins(win) or {}
	padwins[side] = padwin
	api.nvim_win_set_var(win, 'padwins', padwins)

	-- Go back to original window
	api.nvim_set_current_win(org_win)

	return padwin
end

local function padwin_avoid_enter()
	local win = api.nvim_get_current_win()
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

function M.setup()
	local augroup_center = api.nvim_create_augroup({force = true})
	local autocmd = api.nvim_create_autocmd

	autocmd('WinResized', {
		group = augroup_center,
		callback = function()
			M.refresh(vim.v.event.windows)
		end
	})

	autocmd('WinNew', {
		group = augroup_center,
		callback = avoid_displace
	})

	autocmd('WinEnter', {
		group = augroup_center,
		callback = padwin_avoid_enter
	})
end

return M
