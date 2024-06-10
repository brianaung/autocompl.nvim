local core = require "autocompl.core"
local mapping = require "autocompl.mapping"
local util = require "autocompl.util"

local AutoCompl = {}

AutoCompl.opts = {
  debounce_timeout = 150,
  request_timeout = 1000,
  keys = {
    ["<C-y>"] = mapping.confirm,
    ["<C-n>"] = mapping.select_next,
    ["<C-p>"] = mapping.select_prev,
    ["<C-u>"] = mapping.scroll_docs_up,
    ["<C-d>"] = mapping.scroll_docs_down,
  },
  info_border = "none",
  info_max_height = 25,
  info_max_width = 80,
  completeopt = { "menuone", "noselect", "noinsert" },
  hide_completion_messages = true,
}

function AutoCompl.setup()
  _G.AutoCompl = AutoCompl
  AutoCompl.completefunc = core.completefunc

  vim.opt.completeopt = AutoCompl.opts.completeopt
  if AutoCompl.opts.hide_completion_messages then
    vim.opt.shortmess:append "c"
  end

  -- Create a permanent scratch buffer for info window
  core.info.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(core.info.bufnr, "AutoCompl:info-window")
  vim.fn.setbufvar(core.info.bufnr, "&buftype", "nofile")

  mapping.bind_keys(AutoCompl.opts.keys)

  -- Define autocommands
  util.au({ "BufEnter", "LspAttach" }, core.setup_completefunc, "")
  util.au("InsertCharPre", util.debounce(core.cmp.timer, AutoCompl.opts.debounce_timeout, core.trigger_completion), "")
  util.au("CompleteChanged", util.debounce(core.info.timer, AutoCompl.opts.debounce_timeout, core.trigger_info), "")
  util.au("CompleteDonePre", core.on_completedonepre, "")
end

return AutoCompl
