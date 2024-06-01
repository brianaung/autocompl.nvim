local M = {}

local compl_keys = {
  completefunc = vim.keycode "<C-x><C-u>",
  fallback = vim.keycode "<C-x><C-n>",
}

M.setup = function()
  -- Set options
  vim.opt.completeopt = { "menuone", "popup", "noinsert" }
  vim.opt.shortmess:append "c"

  -- Set keybindings
  vim.keymap.set("i", "<CR>", function()
    return vim.fn.pumvisible() == 1 and vim.keycode "<C-e><CR>" or vim.keycode "<CR>"
  end, { expr = true })

  M.create_autocmds()
end

M.create_autocmds = function()
  local augroup = vim.api.nvim_create_augroup("AutoCompl", {})
  local au = function(event, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, callback = callback, desc = desc })
  end
  -- Define autocommands
  au("LspAttach", M.set_completefunc, "Update completefunc if LSP client is available")
  au("InsertCharPre", M.trigger_completion, "Auto trigger completion")
  au("CompleteDonePre", M.on_completion, "Process completed item")
end

M.trigger_completion = function()
  if vim.fn.pumvisible() == 1 or vim.fn.state "m" == "m" then
    return
  end

  if vim.api.nvim_buf_get_option(0, "buftype") == "" then
    local key = vim.api.nvim_get_option_value("completefunc", {}) == "" and compl_keys["fallback"]
      or compl_keys["completefunc"]
    vim.api.nvim_feedkeys(key, "m", false)
  end
end

M.on_completion = function()
  -- vim.print(vim.v.completed_item)
end

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
