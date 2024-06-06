local util = require "autocompl.util"

DONE = "lsp_request_done"
RECEIVED = "lsp_request_received"

local M = {}
M.lsp = { status = DONE, result = {} }

M.process_items = function(items, base)
  local res = vim.tbl_filter(function(item)
    -- Keep items which match (or fuzzy match) the base
    local text = item.filterText or (vim.tbl_get(item, "textEdit", "newText") or item.insertText or item.label or "")
    return (vim.startswith(text, base)) or (not vim.tbl_isempty(vim.fn.matchfuzzy({ text }, base)))
  end, items)

  table.sort(res, function(a, b)
    return (a.sortText or a.label) < (b.sortText or b.label)
  end)

  return res
end

AutoCompl = {}
AutoCompl.lspfunc = function(findstart, base)
  -- No lsp client
  if not M.has_lsp_clients() then
    return findstart == 1 and -3 or {}
  end
  if M.lsp.status ~= RECEIVED then
    if M.lsp.cancel_fn then
      M.lsp.cancel_fn()
    end
    M.lsp.cancel_fn = vim.lsp.buf_request_all(
      0,
      "textDocument/completion",
      vim.lsp.util.make_position_params(),
      function(result)
        M.lsp.result = result
        M.lsp.status = RECEIVED
        M.trigger_completion()
      end
    )
    return findstart == 1 and -3 or {}
  end
  if findstart == 1 then
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local start = vim.fn.match(line:sub(1, pos[2]), "\\k*$")
    return start
  end
  -- Important: status needs to be done whether we return words or {}
  M.lsp.status = DONE

  local words = {}
  for client_id, response in pairs(M.lsp.result) do
    if response.err or not response.result then
      return {}
    end
    local items = vim.tbl_get(response.result, "items") or response.result
    items = M.process_items(items, base)
    if type(items) ~= "table" then
      return {}
    end
    for _, item in pairs(items) do
      table.insert(words, {
        word = vim.tbl_get(item, "textEdit", "newText") or item.insertText or item.label or "",
        abbr = item.label,
        kind = vim.lsp.protocol.CompletionItemKind[item.kind] or "Unknown",
        menu = item.detail or "",
        -- info = info,
        icase = 1,
        dup = 1,
        empty = 1,
        user_data = {
          nvim = { lsp = { completion_item = item, client_id = client_id } },
        },
      })
    end
  end

  return words
end

M.timer = vim.uv.new_timer()

M.trigger_completion = util.debounce(M.timer, 150, function()
  if
    util.pumvisible() -- Pmenu is open
    or vim.fn.state "m" == "m" -- Halfway a mapping
    or vim.fn.mode() ~= "i" -- Not in insert mode
    or vim.api.nvim_get_option_value("buftype", { buf = 0 }) ~= "" -- Not a normal buffer
  then
    -- Don't trigger completion
    return
  end

  if M.has_lsp_clients() then
    M.trigger_lsp()
  else
    M.trigger_fallback()
  end
end)

M.trigger_lsp = function()
  vim.api.nvim_feedkeys(util.k "<C-x><C-u>", "m", false)
end

M.trigger_fallback = function()
  vim.api.nvim_feedkeys(util.k "<C-x><C-n>", "m", false)
end

M.set_completefunc = function(e)
  -- vim.bo[e.buf].completefunc = "v:lua.vim.lsp.omnifunc"
  vim.bo[e.buf].completefunc = "v:lua.AutoCompl.lspfunc"
end

M.has_lsp_clients = function()
  local clients = vim.lsp.get_clients { bufnr = 0, method = "textDocument/completion" }
  return not vim.tbl_isempty(clients)
end

return M
