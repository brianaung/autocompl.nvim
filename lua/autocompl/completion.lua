local util = require "autocompl.util"

DONE = "lsp_request_done"
RECEIVED = "lsp_request_received"

local M = {}

M.lsp = { status = DONE, result = {}, resolved = {} }
M.ns_id = vim.api.nvim_create_namespace "AutoCompl"

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
    -- TODO find a better way to cancel pending requests, and also cleaning up result table
    -- if M.lsp.cancel_fn then
    --   M.lsp.cancel_fn()
    -- end
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
      local success, info = pcall(function()
        return type(item.documentation) == "string" and item.documentation
          or (vim.tbl_get(item.documentation, "value") or "")
      end)
      table.insert(words, {
        word = vim.tbl_get(item, "textEdit", "newText") or item.insertText or item.label or "",
        abbr = item.label,
        kind = vim.lsp.protocol.CompletionItemKind[item.kind] or "Unknown",
        menu = item.detail or "",
        info = success and info or "",
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
  -- vim.api.nvim_feedkeys(util.k "<C-x><C-n>", "m", false)
  vim.api.nvim_feedkeys(util.k "<C-x><C-i>", "m", false)
end

M.set_completefunc = function(e)
  -- vim.bo[e.buf].completefunc = "v:lua.vim.lsp.omnifunc"
  vim.bo[e.buf].completefunc = "v:lua.AutoCompl.lspfunc"
end

M.has_lsp_clients = function()
  local clients = vim.lsp.get_clients { bufnr = 0, method = "textDocument/completion" }
  return not vim.tbl_isempty(clients)
end

M.apply_additional_text_edits = function()
  local lsp_data = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp")
  if lsp_data == nil or vim.tbl_isempty(lsp_data) then
    return
  end

  local completion_item = lsp_data.completion_item

  if completion_item then
    vim.lsp.buf_request_all(0, "completionItem/resolve", completion_item, function(result)
      M.lsp.resolved = result
    end)
    local res = {}
    for client_id, response in pairs(M.lsp.resolved) do
      if not response.err and response.result then
        vim.list_extend(res, { edits = response.result.additionalTextEdits, client_id = client_id })
      end
    end
    local edits, client_id
    if #res >= 1 then
      edits = res[1].edits
      client_id = res[1].client_id or 0
    else
      edits = completion_item.additionalTextEdits
      client_id = lsp_data.client_id or 0
    end

    if edits then
      local cur_pos = vim.api.nvim_win_get_cursor(0)
      local extmark_id = vim.api.nvim_buf_set_extmark(0, M.ns_id, cur_pos[1] - 1, cur_pos[2], {})

      local offset_encoding = vim.lsp.get_client_by_id(client_id).offset_encoding
      vim.lsp.util.apply_text_edits(edits, vim.api.nvim_get_current_buf(), offset_encoding)

      local extmark_data = vim.api.nvim_buf_get_extmark_by_id(0, M.ns_id, extmark_id, {})
      pcall(vim.api.nvim_buf_del_extmark, 0, M.ns_id, extmark_id)
      pcall(vim.api.nvim_win_set_cursor, 0, { extmark_data[1] + 1, extmark_data[2] })
    end
  end
end

M.expand_snippet = function()
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
end

return M
