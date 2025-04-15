# 🎯 center.nvim
like other plugins, center.nvim place your view at center and dinamically refresh the center if there's any size change, nothing more.
![center.nvim example](https://github.com/user-attachments/assets/102c202a-ff10-473d-902a-f355854deb40)

## Settings
Some settings you can do:
```lua
-- default settings
require("center").setup {
	autocentering = false, -- if true, it will automatically centered when you enter in nvim
	win_width = 80, -- is good idea to keep the same value of 'textwidth'
	on_padding_buf = function(buf, win) end, -- if you might want to add something on the padding space of center
}
```

## Commands
- `:Center on`: center the view if possible
- `:Center off`: turn off centering on the view

## Known issues
- Centering is disabled when there's is more than one tab
- Centering is disabled when there's a horizontal splitted window
- Some glitches still
