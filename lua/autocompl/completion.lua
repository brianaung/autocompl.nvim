local util = require "autocompl.util"

SENT = "lsp_request_sent"
DONE = "lsp_request_done"
RECEIVED = "lsp_request_received"

local M = {}
M.lsp = { status = DONE, result = {} }

M.process_items = function(items, base)
  local res = vim.tbl_filter(function(item)
    -- Keep items which match the base and are not snippets
    local text = item.filterText or (vim.tbl_get(item, "textEdit", "newText") or item.insertText or item.label or "")
    return vim.startswith(text, base) and item.kind ~= 15
  end, items)

  table.sort(res, function(a, b)
    return (a.sortText or a.label) < (b.sortText or b.label)
  end)

  return res
end

AutoCompl = {}
AutoCompl.lspfunc = function(findstart, base)
  -- No lsp client or request has been sent
  if not M.has_lsp_clients() or M.lsp.status == SENT then
    return findstart == 1 and -3 or {}
  end
  if M.lsp.status ~= RECEIVED then
    M.lsp.status = SENT
    vim.lsp.buf_request_all(0, "textDocument/completion", vim.lsp.util.make_position_params(), function(results)
      for client_id, response in pairs(results) do
        if response.err or not response.result then
          return {}
        end
        local items = vim.tbl_get(response.result, "items") or response.result
        if type(items) ~= "table" then
          return {}
        end
        items = M.process_items(items, base)
        for _, item in pairs(response.result.items) do
          table.insert(M.lsp.result, {
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
      M.lsp.status = RECEIVED
      M.trigger_completion()
    end)
    return findstart == 1 and -3 or {}
  end
  if findstart == 1 then
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local start = vim.fn.match(line:sub(1, pos[2]), "\\k*$")
    return start
  end
  local words = M.lsp.result
  M.lsp.result = {}
  M.lsp.status = DONE
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
