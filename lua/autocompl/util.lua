local M = {}

M.has_lsp_clients = function()
  local clients = vim.lsp.get_clients { bufnr = 0, method = "textDocument/completion" }
  return not vim.tbl_isempty(clients)
end

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

M.insertmode = function()
  return vim.fn.mode() == "i"
end

M.normalbuf = function()
  return vim.api.nvim_get_option_value("buftype", { buf = 0 }) == ""
end

return M
