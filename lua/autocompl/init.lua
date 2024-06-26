local AutoCompl = {}
local M = {}

SENT = "SENT"
RECEIVED = "RECEIVED"
DONE = "DONE"

M.ns_id = vim.api.nvim_create_namespace "AutoCompl"

M.opts = {
  completion_timeout = 150,
  info_timeout = 100,
  signature_timeout = 100,
}

M.completion = {
  timer = vim.uv.new_timer(),
  status = DONE,
  responses = {},
}

M.info = {
  timer = vim.uv.new_timer(),
  status = DONE,
  responses = {},
  bufnr = nil,
  winids = {},
}

M.signature = {
  timer = vim.uv.new_timer(),
  status = DONE,
  responses = {},
  bufnr = nil,
  winids = {},
  active = nil,
}

M.au = function(event, callback, desc)
  vim.api.nvim_create_autocmd(event, {
    group = vim.api.nvim_create_augroup("AutoCompl", { clear = false }),
    callback = callback,
    desc = desc,
  })
end

-- https://github.com/folke/trouble.nvim/blob/40aad004f53ae1d1ba91bcc5c29d59f07c5f01d3/lua/trouble/util.lua#L71-L80
M.debounce = function(timer, ms, fn)
  return function(...)
    local argv = { ... }
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule_wrap(fn)(unpack(argv))
    end)
  end
end

AutoCompl.setup = function(opts)
  _G.AutoCompl = AutoCompl

  -- Assign options
  M.opts = {
    completion_timeout = opts.completion_timeout or M.opts.completion_timeout,
    info_timeout = opts.info_timeout or M.opts.info_timeout,
  }

  -- Create a permanent scratch buffer for info window
  M.info.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(M.info.bufnr, "AutoCompl:info-window")
  vim.fn.setbufvar(M.info.bufnr, "&buftype", "nofile")

  -- Create a permanent scratch buffer for signature window
  M.signature.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(M.signature.bufnr, "AutoCompl:signature-window")
  vim.fn.setbufvar(M.signature.bufnr, "&buftype", "nofile")

  -- Setup autocommands
  M.au({ "BufEnter", "LspAttach" }, M.set_completefunc, "")
  M.au("InsertCharPre", M.start_completion, "")
  M.au("CompleteChanged", M.start_info, "")
  M.au("CursorMovedI", M.start_signature, "")
  M.au("CompleteDonePre", M.on_completedonepre, "")
  M.au("InsertLeavePre", M.on_insertleavepre, "")
end

M.has_lsp_clients = function()
  local clients = vim.lsp.get_clients { bufnr = 0, method = "textDocument/completion" }
  return not vim.tbl_isempty(clients)
end

M.set_completefunc = function(e) vim.bo[e.buf].completefunc = "v:lua.AutoCompl.completefunc" end

-- On InsertCharPre, completefunc gets called twice.
-- - first invocation: findstart = 1
-- - second invocation: findstart = 0
-- On the first invocation, we make a completion request, which re-triggers completefunc ,therefore restarting the two invocations.
-- Now, for this (second) first invocation, we don't make another request anymore. We return the col where completion starts.
-- On the second invocation, we use the responses we got from the earlier request, process and return them to show in a completion list.
AutoCompl.completefunc = function(findstart, base)
  if not vim.list_contains({ SENT, RECEIVED }, M.completion.status) then
    M.completion.status = SENT
    vim.lsp.buf_request_all(0, "textDocument/completion", vim.lsp.util.make_position_params(), function(responses)
      M.completion.status = RECEIVED
      M.completion.responses = responses
      M.start_completion()
    end)
    return findstart == 1 and -3 or {}
  end
  if findstart == 1 then
    return M.findstart()
  else
    M.completion.status = DONE
    local results = M.process_lsp_responses(
      M.completion.responses,
      function(res) return vim.tbl_get(res, "items") or res end
    )
    return M.process_completion_items(results, base)
  end
end

M.findstart = function()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local line = vim.api.nvim_get_current_line()
  return vim.fn.match(line:sub(1, col), "\\k*$")
end

M.process_lsp_responses = function(responses, processor)
  local results = {}
  for client_id, response in pairs(responses) do
    if not response.err and response.result then table.insert(results, { client_id, processor(response.result) }) end
  end
  return results
end

M.start_completion = M.debounce(M.completion.timer, M.opts.completion_timeout, function()
  if vim.fn.pumvisible() ~= 0 then return end -- Pmenu is visible
  if vim.fn.mode() ~= "i" then return end -- Not in insert mode
  if vim.api.nvim_get_option_value("buftype", { buf = 0 }) ~= "" then return end -- Not a normal buffer
  if M.has_lsp_clients() then
    vim.api.nvim_feedkeys(vim.keycode "<C-x><C-u>", "m", false) -- trigger lsp
  else
    vim.api.nvim_feedkeys(vim.keycode "<C-x><C-n>", "m", false) -- trigger fallback
  end
end)

M.process_completion_items = function(results, base)
  local words = {}
  for _, result in ipairs(results) do
    local client_id, items = unpack(result)
    if vim.tbl_isempty(items) then goto continue end
    -- Filter items
    local matched_items = {}
    for _, item in pairs(items) do
      local text = item.filterText or (vim.tbl_get(item, "textEdit", "newText") or item.insertText or item.label or "")
      if vim.startswith(text, base:sub(1, 1)) then vim.list_extend(matched_items, { item }) end
    end
    table.sort(matched_items, function(a, b) return (a.sortText or a.label) < (b.sortText or b.label) end)
    -- Construct the table of items for the pmenu content
    for _, item in pairs(matched_items) do
      table.insert(words, {
        word = vim.tbl_get(item, "textEdit", "newText") or item.insertText or item.label or "",
        abbr = item.label,
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

M.stop_info = function()
  for idx, winid in ipairs(M.info.winids) do
    if pcall(vim.api.nvim_win_close, winid, false) then M.info.winids[idx] = nil end
  end
end

M.start_info = M.debounce(M.info.timer, M.opts.info_timeout, function()
  M.stop_info()
  -- Check whether to trigger another info window
  if not M.has_lsp_clients() then return end
  if vim.fn.pumvisible() == 0 then return end -- Pmenu is not visible
  if vim.fn.mode() ~= "i" then return end -- Not in insert mode
  if vim.fn.complete_info()["selected"] == -1 then return end -- No items is selected
  -- Check if completion item exists
  local lsp_data = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp") or {}
  local _, completion_item = lsp_data.client_id or 0, lsp_data.completion_item or {}
  if vim.tbl_isempty(completion_item) then return end
  -- Make a request if not made already
  if not vim.list_contains({ SENT, RECEIVED }, M.info.status) then
    M.info.status = SENT
    vim.lsp.buf_request_all(0, "completionItem/resolve", completion_item, function(responses)
      M.info.status = RECEIVED
      M.info.responses = responses
      M.start_info()
    end)
  else
    -- Process resolved items
    M.info.status = DONE
    local results = M.process_lsp_responses(M.info.responses, function(res) return res end)
    local _, result = unpack(#results >= 1 and results[1] or {})
    result = result and result or completion_item
    M.info_window_open(result)
  end
end)

-- Adapted from:
-- https://github.com/echasnovski/mini.completion/blob/main/lua/mini/completion.lua#L911
-- https://github.com/hrsh7th/nvim-cmp/blob/main/lua/cmp/view/docs_view.lua#L77
M.info_window_open = function(res)
  -- Get info string
  local documentation = res.documentation or {}
  local info = type(res.documentation or {}) == "string" and documentation
    or (vim.tbl_get(documentation, "value") or "")
  local detail = res.detail or ""
  if info == "" and detail == "" then return end
  local input
  if detail == "" then
    input = info
  elseif info == "" then
    input = detail
  else
    input = detail .. "\n" .. info
  end
  -- Set markdown lines in info window buffer
  local lines = vim.lsp.util.convert_input_to_markdown_lines(input) or {}
  vim.lsp.util.stylize_markdown(M.info.bufnr, lines)
  if vim.tbl_isempty(lines) then return end
  -- Open window
  local win_opts = M.info_get_win_opts()
  if vim.tbl_isempty(win_opts) then return end
  -- Keep winids for later cleanup
  table.insert(M.info.winids, vim.api.nvim_open_win(M.info.bufnr, false, win_opts))
end

M.info_get_win_opts = function()
  -- Get positions relative pmenu
  local pumpos = vim.fn.pum_getpos()
  if vim.tbl_isempty(pumpos) then return {} end
  local pum_left = pumpos.col - 1
  local pum_right = pumpos.col + pumpos.width + (pumpos.scrollbar and 1 or 0)
  local space_left = pum_left
  local space_right = vim.o.columns - pum_right
  -- Choose the side to open win
  local anchor, col, space
  if space_left <= space_right then
    anchor, col, space = "NW", pum_right, space_right
  else
    anchor, col, space = "NE", pum_left, space_left
  end
  -- Calculate width (can grow to full space) and height
  local width, height = vim.lsp.util._make_floating_popup_size(vim.api.nvim_buf_get_lines(M.info.bufnr, 0, -1, false), {
    max_width = space,
    max_height = 80,
  })
  return {
    relative = "editor",
    anchor = anchor,
    row = pumpos.row,
    col = col,
    width = width,
    height = height,
    focusable = false,
    style = "minimal",
    border = "none",
  }
end

M.stop_signature = function()
  M.signature.active = nil
  for idx, winid in ipairs(M.signature.winids) do
    if pcall(vim.api.nvim_win_close, winid, false) then M.signature.winids[idx] = nil end
  end
end

M.start_signature = M.debounce(M.signature.timer, M.opts.signature_timeout, function()
  if not M.has_lsp_clients() then return end
  if vim.fn.mode() ~= "i" then return end -- Not in insert mode

  -- Make a request if not made already
  if not vim.list_contains({ SENT, RECEIVED }, M.signature.status) then
    M.signature.status = SENT
    vim.lsp.buf_request_all(0, "textDocument/signatureHelp", vim.lsp.util.make_position_params(), function(responses)
      M.signature.status = RECEIVED
      M.signature.responses = responses
      M.start_signature()
    end)
  else
    -- Process signature responses
    M.signature.status = DONE
    local results = M.process_lsp_responses(M.signature.responses, function(res) return res end)
    local _, result = unpack(results[1] or {})

    -- No signature help available, stop any active signature help windows and return
    if not result or not result.signatures or vim.tbl_isempty(result.signatures) then
      M.stop_signature()
      return
    end

    -- Get active signature from response
    -- If active signature outside the range, default to 0
    local active_signature = result.activeSignature or 0
    if active_signature < 0 or active_signature >= #result.signatures then active_signature = 0 end
    local signature = result.signatures[active_signature + 1]

    -- If new signature help is same as currently active one, do nth
    if M.signature.active == signature.label then return end

    M.signature.active = signature.label

    local lines = vim.lsp.util.convert_input_to_markdown_lines(signature.label) or {}
    if vim.tbl_isempty(lines) then return end
    vim.lsp.util.stylize_markdown(M.signature.bufnr, lines)

    -- Open window
    local win_opts = M.signature_get_win_opts()
    if vim.tbl_isempty(win_opts) then return end
    -- Keep winids for later cleanup
    table.insert(M.signature.winids, vim.api.nvim_open_win(M.signature.bufnr, false, win_opts))
  end
end)

M.signature_get_win_opts = function()
  local winline = vim.fn.winline()
  local space_top = winline - 1
  local space_bottom = vim.api.nvim_win_get_height(0) - winline

  local bufpos = vim.api.nvim_win_get_cursor(0)
  bufpos[1] = bufpos[1] - 1

  -- Calculate width (can grow to full space) and height
  local width, height =
    vim.lsp.util._make_floating_popup_size(vim.api.nvim_buf_get_lines(M.signature.bufnr, 0, -1, false))

  -- TODO find a better placement for signature help window
  local anchor
  if height <= space_top then
    anchor = "SW" -- show above
  else
    anchor = "NW" -- show below
  end

  return {
    relative = "win",
    bufpos = bufpos,
    anchor = anchor,
    col = 0,
    width = width,
    height = height,
    focusable = false,
    style = "minimal",
    border = "none",
  }
end

M.expand_snippet = function()
  local completion_item = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp", "completion_item") or {}
  -- not a lsp completion or not a snippet
  if vim.tbl_isempty(completion_item) or completion_item.kind ~= 15 then return end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_text(0, row - 1, col - #vim.v.completed_item.word, row - 1, col, { "" })
  vim.api.nvim_win_set_cursor(0, { row, col - vim.fn.strwidth(vim.v.completed_item.word) })
  vim.snippet.expand(vim.tbl_get(completion_item, "textEdit", "newText") or completion_item.insertText or "")
end

M.apply_additional_text_edits = function()
  local lsp_data = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp") or {}
  local completion_item = lsp_data.completion_item or {}
  if vim.tbl_isempty(completion_item) then return end
  -- make a synchronous request to get resolved info
  -- local responses = vim.lsp.buf_request_sync(0, "completionItem/resolve", completion_item, 1000)
  local results = M.process_lsp_responses(M.info.responses, function(res) return res end)
  local result = #results >= 1 and results[1] or {}
  -- use info from resolved item if available, otherwise just use the original completion item
  local item, client_id
  if vim.tbl_isempty(result) then
    client_id, item = lsp_data.client_id, completion_item
  else
    client_id, item = unpack(result)
  end
  client_id = client_id or 0
  -- apply edits if there's any
  local edits = item.additionalTextEdits or {}
  if vim.tbl_isempty(edits) then return end
  -- https://github.com/echasnovski/mini.completion/blob/main/lua/mini/completion.lua#L889
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local extmark_id = vim.api.nvim_buf_set_extmark(0, M.ns_id, row - 1, col, {})
  local offset_encoding = vim.lsp.get_client_by_id(client_id).offset_encoding
  vim.lsp.util.apply_text_edits(edits, vim.api.nvim_get_current_buf(), offset_encoding)
  local extmark_row, extmark_col = unpack(vim.api.nvim_buf_get_extmark_by_id(0, M.ns_id, extmark_id, {}))
  pcall(vim.api.nvim_buf_del_extmark, 0, M.ns_id, extmark_id)
  pcall(vim.api.nvim_win_set_cursor, 0, { extmark_row + 1, extmark_col })
end

M.on_completedonepre = function()
  M.expand_snippet()
  M.apply_additional_text_edits()
end

M.on_insertleavepre = function()
  M.stop_info()
  M.stop_signature()
end

return AutoCompl
