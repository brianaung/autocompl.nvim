local vim = vim
local unpack = unpack

local lib = {}

---Wrapped a function into a debounced function that will gets called after a set timeout.
---
---@see https://github.com/folke/trouble.nvim/blob/40aad004f53ae1d1ba91bcc5c29d59f07c5f01d3/lua/trouble/util.lua#L71-L80
---
---@param timer 'uv_timer_t'
---@param ms integer Timeout
---@param fn function A callable function that will be fired after a timeout
---@return function # A debounced wrapped callable function
function lib.debounce(timer, ms, fn)
	return function(...)
		local argv = { ... }
		timer:start(ms, 0, function()
			timer:stop()
			vim.schedule_wrap(fn)(unpack(argv))
		end)
	end
end

---Creates an |autocommand| event handler, defined by `callback`.
---
---@param event string | table Event(s) that will trigger the callback
---@param fn function | string Function to call when the event(s) is triggered
---@param desc string Description for documentation and/or troubleshooting
function lib.au(event, fn, desc)
	vim.api.nvim_create_autocmd(event, {
		group = vim.api.nvim_create_augroup("AutoCompl", { clear = false }),
		callback = fn,
		desc = desc,
	})
end

return lib
