local completion = require "autocompl.completion"
local mapping = require "autocompl.mapping"
local util = require "autocompl.util"

local M = {}

M.setup = function()
  vim.opt.completeopt = { "menuone", "noselect", "noinsert" }
  vim.opt.shortmess:append "c"

  mapping.bind_keys {
    ["<C-y>"] = mapping.confirm,
    ["<C-n>"] = mapping.select_next,
    ["<C-p>"] = mapping.select_prev,
  }

  -- Define autocommands
  util.au("LspAttach", completion.set_completefunc, "Set completefunc if LSP client is available")
  util.au("InsertCharPre", completion.trigger_completion, "Start auto completion with a debounce")
  util.au("CompleteDonePre", function()
    local completion_item = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp", "completion_item") or {}

    -- do nth it's not a lsp completion or not a snippet
    if vim.tbl_isempty(completion_item) or completion_item.kind ~= 15 then
      return
    end

    local row = vim.api.nvim_win_get_cursor(0)[1]
    local col = vim.api.nvim_win_get_cursor(0)[2]
    vim.api.nvim_buf_set_text(0, row - 1, col - #vim.v.completed_item.word, row - 1, col, { "" })
    vim.api.nvim_win_set_cursor(0, { row, col - vim.fn.strwidth(vim.v.completed_item.word) })

    vim.snippet.expand(vim.tbl_get(completion_item, "textEdit", "newText") or completion_item.insertText or "")
  end, "Start auto completion with a debounce")
end

return M
