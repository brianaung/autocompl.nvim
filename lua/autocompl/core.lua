local util = require "autocompl.util"

local M = {}

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
  cancel_fn = nil,
  cancel_resolved_fn = nil,
}

M.info = {
  timer = vim.uv.new_timer(),
  winid = nil,
  event = nil,
  height = 0,
}

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
  -- TODO implement findstart using lsp
  return vim.fn.match(line:sub(1, col), "\\k*$")
end

function M.make_completion_request()
  M.cmp.status = M.status_code.SENT
  if M.cmp.cancel_fn then
    pcall(M.cmp.cancel_fn)
    M.cmp.cancel_fn = nil
  end
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
        -- menu = item.detail or "",
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

function M.process_completion_items(items, base)
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
    return (a.item.sortText or a.item.label) < (b.item.sortText or b.item.label)
    -- return a.item.sortText < b.item.sortText
  end)
  -- Flatten into items list
  local res = {}
  for _, item in ipairs(matched_items) do
    vim.list_extend(res, { item.item })
  end
  return res
end

function M.on_completedonepre()
  M.close_infowindow()
  M.expand_snippet()
  M.apply_additional_text_edits()
end

function M.trigger_info()
  M.close_infowindow()

  if not util.pumvisible() or not util.insertmode() then
    return
  end

  -- Adapted from: https://github.com/echasnovski/mini.completion/blob/main/lua/mini/completion.lua#L911
  M.make_resolved_request(function(res)
    -- Get resolved info ==========
    local documentation = res.item.documentation or {}
    local success, info = pcall(function()
      return type(documentation) == "string" and documentation or (vim.tbl_get(documentation, "value") or "")
    end)
    if not success then
      return
    end
    -- Set lines in info window buffer ==========
    local lines = vim.lsp.util.convert_input_to_markdown_lines(info) or {}
    vim.lsp.util.stylize_markdown(M.info.bufnr, lines)
    if vim.tbl_isempty(lines) then
      return
    end
    -- Get info window options ==========
    local lines_wrap = {}
    for _, l in pairs(lines) do
      vim.list_extend(lines_wrap, M.wrap_line(l, AutoCompl.opts.info_max_width))
    end
    local height = math.min(#lines_wrap, AutoCompl.opts.info_max_height)
    M.info.height = height
    -- Width is a maximum width of the first `height` wrapped lines truncated to
    -- maximum width
    local width = 0
    local l_width
    for i, l in ipairs(lines_wrap) do
      l_width = vim.fn.strdisplaywidth(l)
      if i <= height and width < l_width then
        width = l_width
      end
    end
    width = math.min(width, AutoCompl.opts.info_max_width)

    local event = vim.fn.pum_getpos()
    local left_to_pum = event.col - 1
    local right_to_pum = event.col + event.width + (event.scrollbar and 1 or 0)
    local border_offset = AutoCompl.opts.info_border == "none" and 0 or 2
    local space_left = left_to_pum - border_offset
    local space_right = vim.o.columns - right_to_pum - border_offset
    -- Decide side at which info window will be displayed
    local anchor, col, space
    if width <= space_right or space_left <= space_right then
      anchor, col, space = "NW", right_to_pum, space_right
    else
      anchor, col, space = "NE", left_to_pum, space_left
    end

    if space < AutoCompl.opts.info_max_width then
      width = math.min(width, space)
    end
    -- Open window ==========
    M.info.winid = vim.api.nvim_open_win(M.info.bufnr, false, {
      relative = "editor",
      anchor = anchor,
      row = event.row,
      col = col,
      width = width,
      height = height,
      focusable = false,
      style = "minimal",
      border = AutoCompl.opts.info_border,
    })
  end, true)
end

function M.make_resolved_request(processor, async)
  local lsp_data = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp") or {}
  local client_id, completion_item = lsp_data.client_id or 0, lsp_data.completion_item or {}
  if vim.tbl_isempty(completion_item) then
    return
  end

  if async then
    if M.cmp.cancel_resolved_fn then
      pcall(M.cmp.cancel_resolved_fn)
      M.cmp.cancel_resolved_fn = nil
    end
    M.cmp.cancel_resolved_fn = vim.lsp.buf_request_all(0, "completionItem/resolve", completion_item, function(responses)
      local res = {}
      for resolved_client_id, response in pairs(responses) do
        if not response.err and response.result then
          vim.list_extend(res, { { client_id = resolved_client_id, item = response.result } })
        end
      end
      if #res >= 1 then
        processor(res[1])
      else
        processor { client_id = client_id, item = completion_item }
      end
    end)
  else
    local responses =
      vim.lsp.buf_request_sync(0, "completionItem/resolve", completion_item, AutoCompl.opts.request_timeout)
    local res = {}
    for resolved_client_id, response in pairs(responses) do
      if not response.err and response.result then
        vim.list_extend(res, { { client_id = resolved_client_id, item = response.result } })
      end
    end
    if #res >= 1 then
      processor(res[1])
    else
      processor { client_id = client_id, item = completion_item }
    end
  end
end

-- `additionalTextEdits` can come from either completion_item or from "resolved" completion_item.
-- When getting the "resolved" item, the request needs to be *synchronous* because:
-- - 1. you won't be able to access the responses value outside the request since you need to "await" for the request to finish.
-- - 2. and if you try to apply text edits inside the async request callback, vim's undo/redo after applying edits can get messed up.
-- (Making the request on every CompleteChanged event somewhat works, and I need to make that request for info window anyway. However, if you try to
-- very quickly select and complete an item, the `additionalTextEdits` value might not be what you expects.)
function M.apply_additional_text_edits()
  M.make_resolved_request(function(res)
    local edits = res.item.additionalTextEdits or {}
    local client_id = res.client_id or 0
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
  end, false)
end

function M.expand_snippet()
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

function M.close_infowindow()
  if M.info.winid then
    pcall(vim.api.nvim_win_close, M.info.winid, false)
    M.info.winid = nil
  end
end

-- https://github.com/echasnovski/mini.completion/blob/main/lua/mini/completion.lua#L1343
function M.wrap_line(l, width)
  local res = {}

  local success, width_id = true, nil
  -- Use `strdisplaywidth()` to account for multibyte characters
  while success and vim.fn.strdisplaywidth(l) > width do
    -- Simulate wrap by looking at breaking character from end of current break
    -- Use `pcall()` to handle complicated multibyte characters (like Chinese)
    -- for which even `strdisplaywidth()` seems to return incorrect values.
    success, width_id = pcall(vim.str_byteindex, l, width)

    if success then
      local break_match = vim.fn.match(l:sub(1, width_id):reverse(), "[- \t.,;:!?]")
      -- If no breaking character found, wrap at whole width
      local break_id = width_id - (break_match < 0 and 0 or break_match)
      table.insert(res, l:sub(1, break_id))
      l = l:sub(break_id + 1)
    end
  end
  table.insert(res, l)

  return res
end

return M
