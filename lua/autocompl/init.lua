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
  responses = {},
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
  util.au({ "BufEnter", "LspAttach" }, M.setup_completefunc, "Start auto completion with a debounce")
  util.au(
    "InsertCharPre",
    util.debounce(M.cmp.timer, 150, M.trigger_completion),
    "Start auto completion with a debounce"
  )
  util.au("CompleteDonePre", function()
    M.expand_snippet()
  end, "Additional text edits on after completion is done")
end

function M.setup_completefunc(e)
  vim.bo[e.buf].completefunc = "v:lua.AutoCompl.completefunc"
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

-- On InsertCharPre, completefunc gets called twice.
-- - first invocation: findstart = 1
-- - second invocation: findstart = 0
-- On the first invocation, we make a completion request, which re-triggers completefunc ,therefore restarting the two invocations.
-- Now, for this (second) first invocation, we don't make another request anymore. We return the col where completion starts.
-- On the second invocation, we use the responses we got from the earlier request, process and return them to show in a completion list.
function M.completefunc(findstart, base)
  if not vim.list_contains({ M.status_code.SENT, M.status_code.RECEIVED }, M.cmp.status) then
    M.make_completion_request()
    return findstart == 1 and -3 or {}
  end

  if findstart == 1 then
    return M.findstart()
  else
    M.cmp.status = M.status_code.COMPLETED
    return M.process_completion_response(base)
  end
end

function M.findstart()
  local _, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  return vim.fn.match(line:sub(1, col), "\\k*$")
end

function M.make_completion_request()
  M.cmp.status = M.status_code.SENT
  M.cmp.cancel_fn = vim.lsp.buf_request_all(
    0,
    "textDocument/completion",
    vim.lsp.util.make_position_params(),
    function(responses)
      M.cmp.responses = responses
      M.cmp.status = M.status_code.RECEIVED
      M.trigger_completion()
    end
  )
end

function M.process_completion_response(base)
  local words = {}
  for client_id, response in pairs(M.cmp.responses) do
    if response.err or not response.result then
      goto continue
    end
    local items = vim.tbl_get(response.result, "items") or response.result
    items = M.process_completion_items(items, base)
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

M.process_completion_items = function(items, base)
  local matched_items = {}
  for _, item in pairs(items) do
    local text = item.filterText or (vim.tbl_get(item, "textEdit", "newText") or item.insertText or item.label or "")
    -- If base only contains lower chars, do case-insensitive matching
    if not base:match "%u" then
      text = text:lower()
      base = base:lower()
    end
    -- Fuzzy pattern matching and scoring
    if vim.startswith(text, base:sub(1, 1)) then
      local score = vim.fn.matchfuzzypos({ text }, base)[3]
      if not vim.tbl_isempty(score) then
        vim.list_extend(matched_items, { { score = score[1], item = item } })
      else
        vim.list_extend(matched_items, { { score = 0, item = item } })
      end
    end
  end
  -- Sort them based on the pattern matching scores
  table.sort(matched_items, function(a, b)
    return a.score > b.score
  end)
  -- Sort again based on LSP sortText
  table.sort(matched_items, function(a, b)
    -- return (a.item.sortText or a.item.label) < (b.item.sortText or b.item.label)
    return a.item.sortText < b.item.sortText
  end)
  -- Flatten into items list
  local res = {}
  for _, item in ipairs(matched_items) do
    vim.list_extend(res, { item.item })
  end
  return res
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
