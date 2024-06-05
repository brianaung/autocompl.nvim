local M = {}

M.k = function(key)
  return vim.api.nvim_replace_termcodes(key, true, false, true)
end

M.au = function(event, callback, desc)
  vim.api.nvim_create_autocmd(event, {
    group = vim.api.nvim_create_augroup("AutoCompl", { clear = false }),
    callback = callback,
    desc = desc,
  })
end

-- https://github.com/folke/trouble.nvim/blob/40aad004f53ae1d1ba91bcc5c29d59f07c5f01d3/lua/trouble/util.lua#L71-L80
M.debounce = function(timer, ms, fn)
  return function(...)
    local argv = { ... }
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule_wrap(fn)(unpack(argv))
    end)
  end
end

M.pumvisible = function()
  return vim.fn.pumvisible() > 0
end

return M
