local mapping = require "autocompl.mapping"
local util = require "autocompl.util"

local M = {}
local AutoCompl = {}

M.ns_id = vim.api.nvim_create_namespace "AutoCompl"

M.status_code = {
  SENT = "lsp_request_sent",
  RECEIVED = "lsp_request_received",
  COMPLETED = "lsp_request_completed",
}

M.cmp = {
  timer = vim.uv.new_timer(),
  status = M.status_code.COMPLETED,
  result = {},
  resolved = {},
}

function AutoCompl.setup()
  _G.AutoCompl = AutoCompl
  AutoCompl.completefunc = M.completefunc

  vim.opt.completeopt = { "menuone", "noselect", "noinsert" }
  vim.opt.shortmess:append "c"

  mapping.bind_keys {
    ["<C-y>"] = mapping.confirm,
    ["<C-n>"] = mapping.select_next,
    ["<C-p>"] = mapping.select_prev,
  }

  -- Define autocommands
  util.au({ "BufEnter", "LspAttach" }, function(e)
    vim.bo[e.buf].completefunc = "v:lua.AutoCompl.completefunc"
  end, "Start auto completion with a debounce")
  util.au(
    "InsertCharPre",
    util.debounce(M.cmp.timer, 150, M.trigger_completion),
    "Start auto completion with a debounce"
  )
  util.au("CompleteDonePre", function()
    M.expand_snippet()
    M.apply_additional_text_edits()
  end, "Perform extra edits on complete done pre")

  -- On key pressed commands
  vim.on_key(function(key, _)
    if key == util.k "<BS>" then
      M.trigger_completion()
    end
  end, M.ns_id)
end

function M.trigger_completion()
  if util.pumvisible() or not util.insertmode() or not util.normalbuf() then
    return
  end
  if util.has_lsp_clients() then
    vim.api.nvim_feedkeys(util.k "<C-x><C-u>", "m", false) -- trigger lsp
  else
    vim.api.nvim_feedkeys(util.k "<C-x><C-i>", "m", false) -- trigger fallback
  end
end

function M.completefunc(findstart, base)
  if not util.has_lsp_clients() or M.cmp.status == M.status_code.SENT then
    return findstart == 1 and -3 or {}
  end
  if M.cmp.status ~= M.status_code.RECEIVED then
    M.cmp.status = M.status_code.SENT
    vim.lsp.buf_request_all(0, "textDocument/completion", vim.lsp.util.make_position_params(), function(result)
      M.cmp.status = M.status_code.RECEIVED
      M.cmp.result = result
      M.trigger_completion()
    end)
    return findstart == 1 and -3 or {}
  end
  if findstart == 1 then
    local _, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    -- TODO: calculate start from LSP response if possible
    return vim.fn.match(line:sub(1, col), "\\k*$")
  end
  -- Important: status needs to be done whether we return words or {}
  M.cmp.status = M.status_code.COMPLETED

  local words = {}
  for client_id, response in pairs(M.cmp.result) do
    if response.err or not response.result then
      goto continue
    end
    local items = vim.tbl_get(response.result, "items") or response.result
    items = M.process_items(items, base)
    if type(items) ~= "table" then
      goto continue
    end
    for _, item in pairs(items) do
      local success, info = pcall(function()
        return type(item.documentation) == "string" and item.documentation
          or (vim.tbl_get(item.documentation, "value") or "")
      end)
      table.insert(words, {
        word = vim.tbl_get(item, "textEdit", "newText") or item.insertText or item.label or "",
        abbr = item.label,
        menu = item.detail or "",
        info = success and info or "",
        kind = vim.lsp.protocol.CompletionItemKind[item.kind] or "Unknown",
        icase = 1,
        dup = 1,
        empty = 1,
        user_data = {
          nvim = { lsp = { completion_item = item, client_id = client_id } },
        },
      })
    end
    ::continue::
  end

  return words
end

M.process_items = function(items, base)
  local res = {}
  for _, item in pairs(items) do
    local text = item.filterText or (vim.tbl_get(item, "textEdit", "newText") or item.insertText or item.label or "")

    if not base:match "%u" then
      text = text:lower()
      base = base:lower()
    end

    if vim.startswith(text, base:sub(1, 1)) then
      local score = vim.fn.matchfuzzypos({ text }, base)[3]
      if not vim.tbl_isempty(score) then
        vim.list_extend(res, { { score = score[1], item = item } })
      else
        vim.list_extend(res, { { score = 0, item = item } })
      end
    end
  end

  table.sort(res, function(a, b)
    return a.score > b.score
  end)

  table.sort(res, function(a, b)
    return (a.item.sortText or a.item.label) < (b.item.sortText or b.item.label)
  end)

  local ret = {}
  for _, item in ipairs(res) do
    vim.list_extend(ret, { item.item })
  end

  return ret
end

M.apply_additional_text_edits = function()
  local lsp_data = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp") or {}
  if vim.tbl_isempty(lsp_data) then
    return
  end

  local completion_item = lsp_data.completion_item or {}
  if vim.tbl_isempty(completion_item) then
    return
  end

  vim.lsp.buf_request_all(0, "completionItem/resolve", completion_item, function(result)
    M.cmp.resolved = result
  end)

  local res = {}
  for client_id, response in pairs(M.cmp.resolved) do
    if not response.err and response.result then
      vim.list_extend(res, { { edits = response.result.additionalTextEdits, client_id = client_id } })
    end
  end
  local edits, client_id
  if #res >= 1 then
    edits = res[1].edits or {}
    client_id = res[1].client_id or 0
  else
    edits = completion_item.additionalTextEdits or {}
    client_id = lsp_data.client_id or 0
  end

  if vim.tbl_isempty(edits) then
    return
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local extmark_id = vim.api.nvim_buf_set_extmark(0, M.ns_id, row - 1, col, {})
  local offset_encoding = vim.lsp.get_client_by_id(client_id).offset_encoding
  vim.lsp.util.apply_text_edits(edits, vim.api.nvim_get_current_buf(), offset_encoding)
  local extmark_row, extmark_col = unpack(vim.api.nvim_buf_get_extmark_by_id(0, M.ns_id, extmark_id, {}))
  pcall(vim.api.nvim_buf_del_extmark, 0, M.ns_id, extmark_id)
  pcall(vim.api.nvim_win_set_cursor, 0, { extmark_row + 1, extmark_col })
end

M.expand_snippet = function()
  local completion_item = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp", "completion_item") or {}
  -- not a lsp completion or not a snippet
  if vim.tbl_isempty(completion_item) or completion_item.kind ~= 15 then
    return
  end

  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_text(0, row - 1, col - #vim.v.completed_item.word, row - 1, col, { "" })
  vim.api.nvim_win_set_cursor(0, { row, col - vim.fn.strwidth(vim.v.completed_item.word) })
  vim.snippet.expand(vim.tbl_get(completion_item, "textEdit", "newText") or completion_item.insertText or "")
end

return AutoCompl
