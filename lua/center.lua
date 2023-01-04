local M = {}
local api = vim.api
local inspect = vim.inspect

local function calc_padding(win, width)
	local textwidth = 80
	width = width or api.nvim_win_get_width(win)
	local padding = (textwidth - width) / 2

	if padding < 0 then
		padding = 0
	end

	return math.floor(padding)
end

local function get_padwins(padwins)
	if padwins then
		return
	else
		local ok
		ok, padwins = api.nvim_win_get_var(win, 'padwins')
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

local function M.refresh(windows)
end

return M
