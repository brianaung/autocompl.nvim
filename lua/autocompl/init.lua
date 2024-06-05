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
end

return M
