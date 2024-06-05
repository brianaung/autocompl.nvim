local util = require "autocompl.util"

local keys = {
  completefunc = vim.keycode "<C-x><C-u>",
  fallback = vim.keycode "<C-x><C-n>",
}

local M = {}

M.timer = vim.uv.new_timer()

M.trigger = util.debounce(M.timer, 100, function()
  if
    util.pumvisible()
    or vim.fn.state "m" == "m"
    or vim.fn.mode() ~= "i"
    or vim.api.nvim_buf_get_option(0, "buftype") ~= ""
  then
    return
  end

  local key = vim.api.nvim_get_option_value("completefunc", {}) == "" and keys["fallback"] or keys["completefunc"]
  vim.api.nvim_feedkeys(util.k(key), "m", false)
end)

M.set_completefunc = function(e)
  local bufnr = e.buf
  local c = vim.lsp.get_client_by_id(e.data.client_id)

  if c.server_capabilities.completionProvider then
    vim.bo[bufnr].completefunc = "v:lua.vim.lsp.omnifunc"
  else
    vim.bo[bufnr].completefunc = ""
  end
end

return M
