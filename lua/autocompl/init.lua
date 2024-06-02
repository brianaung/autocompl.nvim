local M = {}

M.configs = {}

M.states = {
  confirm_done = false,
}

M.keys = {
  completefunc = vim.keycode "<C-x><C-u>",
  fallback = vim.keycode "<C-x><C-n>",
}

M.setup = function()
  local success, ls = pcall(require, "luasnip")

  if not success then
    vim.notify(
      "(autocompl.nvim) Requires luasnip as a dependency to support snippet expansion."
        .. " Please check your dependencies list.",
      vim.log.levels.ERROR
    )
    return
  end

  -- Set options
  vim.opt.completeopt = { "menuone", "popup", "noselect" }
  vim.opt.shortmess:append "c"

  -- Listen to confirm key pressed event
  vim.on_key(function(key)
    if vim.fn.pumvisible() ~= 1 then
      return
    end

    if key == vim.keycode "<C-y>" or key == vim.keycode "<Space>" then
      M.states.confirm_done = true
    end
  end, 0)

  -- Enter key behavior
  -- TODO might need to refactor this if I am going to support custom keybindings
  vim.keymap.set("i", "<CR>", function()
    -- If some item is selected, confirm selection
    if vim.fn.complete_info().selected ~= -1 then
      return vim.keycode "<C-y>"
    end
    -- If pmenu is open and nothing selected, close it then newline
    if vim.fn.pumvisible() == 1 then
      return vim.keycode "<C-e><CR>"
    end
    -- Else, default
    return vim.keycode "<CR>"
  end, { expr = true })

  -- Confirm key behavior
  -- Auto confirm first item on <C-y>
  vim.keymap.set("i", "<C-y>", function()
    -- If some item is selected, confirm selection
    if vim.fn.complete_info().selected ~= -1 then
      return vim.keycode "<C-y>"
    end
    -- If pmenu is open and nothing is selected, select the first item
    if vim.fn.pumvisible() == 1 then
      return vim.keycode "<C-n><C-y>"
    end
    -- Else, default
    return vim.keycode "<C-y>"
  end, { expr = true })

  -- LS Keybindings
  vim.keymap.set({ "i", "s" }, "<C-l>", function()
    if ls.expand_or_locally_jumpable() then
      ls.expand_or_jump()
    end
  end, { silent = true })
  vim.keymap.set({ "i", "s" }, "<C-h>", function()
    if ls.locally_jumpable(-1) then
      ls.jump(-1)
    end
  end, { silent = true })

  -- Start
  M.create_autocmds()
end

M.create_autocmds = function()
  local augroup = vim.api.nvim_create_augroup("AutoCompl", {})
  local au = function(event, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, callback = callback, desc = desc })
  end
  -- Define autocommands
  au("LspAttach", M.set_completefunc, "Set completefunc if LSP client is available")
  au("InsertCharPre", M.trigger_completion, "Auto trigger completion")
  au("CompleteDonePre", M.expand_snippet, "Expand snippet completion if confirm_done")
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

M.trigger_completion = function()
  if vim.fn.pumvisible() == 1 or vim.fn.state "m" == "m" then
    return
  end

  if vim.api.nvim_buf_get_option(0, "buftype") == "" then
    local key = vim.api.nvim_get_option_value("completefunc", {}) == "" and M.keys["fallback"] or M.keys["completefunc"]
    vim.api.nvim_feedkeys(key, "m", false)
  end
end

M.expand_snippet = function()
  if not M.states.confirm_done then
    return
  end

  local completed_item = vim.v.completed_item
  local completion_item = vim.tbl_get(completed_item, "user_data", "nvim", "lsp", "completion_item")

  -- check that this is an lsp completion and is a snippet
  if not (completion_item and completed_item.kind == "Snippet") then
    return
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local col = vim.api.nvim_win_get_cursor(0)[2]
  vim.api.nvim_buf_set_text(0, row - 1, col - #completed_item.word, row - 1, col, { "" })
  vim.api.nvim_win_set_cursor(0, { row, col - vim.fn.strwidth(completed_item.word) })

  -- expand snippet
  require("luasnip").lsp_expand(vim.tbl_get(completion_item, "textEdit", "newText") or completion_item.insertText or "")

  M.states.confirm_done = false
end

return M
