local M = {}

M.states = {
  confirm_done = false,
}

M.keys = {
  completefunc = vim.keycode "<C-x><C-u>",
  fallback = vim.keycode "<C-x><C-n>",
}

M.visible = function()
  return vim.fn.pumvisible() ~= 0
end

M.setup = function(opts)
  local success, ls = pcall(require, "luasnip")
  if not success then
    -- TODO: add proper error message with vim.notify
    return
  end

  opts = (not vim.tbl_isempty(opts)) and opts
    or {
      keys = {
        ["<C-y>"] = M.mapping.confirm,
        ["<C-n>"] = M.mapping.select_next,
        ["<C-p>"] = M.mapping.select_prev,
        -- LS bindings
        ["<C-l>"] = M.mapping(function()
          if ls.expand_or_locally_jumpable() then
            ls.expand_or_jump()
          end
        end, { "i", "s" }, { silent = true }),
        ["<C-h>"] = M.mapping(function()
          if ls.locally_jumpable(-1) then
            ls.jump(-1)
          end
        end, { "i", "s" }, { silent = true }),
      },
    }

  -- Set options
  vim.opt.completeopt = { "menuone", "popup", "noselect", "noinsert" }
  vim.opt.shortmess:append "c"
  M.bind_keys(opts.keys)

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
  if M.visible() or vim.fn.state "m" == "m" then
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

M.bind_keys = function(keys)
  for key, fn in pairs(keys) do
    fn(key)
  end
end

M.mapping = setmetatable({}, {
  __call = function(_, invoke, modes, opts)
    -- if type(invoke) == "function" then
    -- end
    return function(key)
      vim.keymap.set(modes, key, invoke, opts)
    end
  end,
})

-- TODO: fix some mappings like <C-n> or <C-p> that does not work as confirm key
M.mapping.confirm = function(key)
  key = vim.keycode(key)

  -- Listen to confirm key pressed event
  vim.on_key(function(pressed_key)
    if not M.visible() then
      return
    end
    if pressed_key == key or pressed_key == vim.keycode "<Space>" then
      M.states.confirm_done = true
    end
  end)

  -- Default confirm key behavior
  vim.keymap.set("i", key, function()
    -- If some item is selected, confirm selection
    if vim.fn.complete_info().selected ~= -1 then
      return vim.keycode "<C-y>"
    end
    -- If pmenu is open and nothing is selected, select the first item
    if M.visible() then
      return vim.keycode "<C-n><C-y>"
    end
    -- Else, default
    return key
  end, { expr = true })

  -- Special <CR> behavior if it's not a default confirm key
  if key ~= vim.keycode "<CR>" then
    vim.keymap.set("i", "<CR>", function()
      -- If some item is selected, confirm selection
      if vim.fn.complete_info().selected ~= -1 then
        return vim.keycode "<C-y>"
      end
      -- If pmenu is open and nothing selected, close it then newline
      if M.visible() then
        return vim.keycode "<C-e><CR>"
      end
      -- Else, default
      return vim.keycode "<CR>"
    end, { expr = true })
  end
end

M.mapping.select_next = function(key)
  key = vim.keycode(key)
  vim.keymap.set("i", key, function()
    if M.visible() then
      return vim.keycode "<C-n>"
    end
    return key
  end, { expr = true })
end

M.mapping.select_prev = function(key)
  key = vim.keycode(key)
  vim.keymap.set("i", key, function()
    if M.visible() then
      return vim.keycode "<C-p>"
    end
    return key
  end, { expr = true })
end

return M
