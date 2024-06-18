local M = {}
local AutoCompl = {}

SENT = "SENT"
RECEIVED = "RECEIVED"
DONE = "DONE"

M.ns_id = vim.api.nvim_create_namespace "AutoCompl"

M.completion = {
  timer = vim.uv.new_timer(),
  status = DONE,
  responses = {},
}

M.info = {
  timer = vim.uv.new_timer(),
  bufnr = nil,
  winids = {},
}

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

M.au = function(event, callback, desc)
  vim.api.nvim_create_autocmd(event, {
    group = vim.api.nvim_create_augroup("AutoCompl", { clear = false }),
    callback = callback,
    desc = desc,
  })
end

AutoCompl.setup = function()
  _G.AutoCompl = AutoCompl

  vim.opt.completeopt = { "menuone", "noselect", "noinsert" }
  vim.opt.shortmess:append "c"

  M.setup_keymaps {
    confirm = "<C-y>",
    select_next = "<C-n>",
    select_prev = "<C-p>",
    snippet_jump_next = "<C-k>",
    snippet_jump_prev = "<C-j>",
  }

  -- Create a permanent scratch buffer for info window
  M.info.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(M.info.bufnr, "AutoCompl:info-window")
  vim.fn.setbufvar(M.info.bufnr, "&buftype", "nofile")

  M.au({ "BufEnter", "LspAttach" }, M.setup_completefunc, "")
  M.au("InsertCharPre", M.completion_start, "")
  M.au("CompleteChanged", M.info_start, "")
  M.au("CompleteDonePre", M.on_completedonepre, "")
end

M.setup_completefunc = function(e) vim.bo[e.buf].completefunc = "v:lua.AutoCompl.completefunc" end

M.completion_start = M.debounce(M.completion.timer, 100, function()
  if vim.fn.pumvisible() ~= 0 then return end -- Pmenu is visible
  if vim.fn.mode() ~= "i" then return end -- Not in insert mode
  if vim.api.nvim_get_option_value("buftype", { buf = 0 }) ~= "" then return end -- Not a normal buffer
  if M.has_lsp_clients() then
    vim.api.nvim_feedkeys(vim.keycode "<C-x><C-u>", "m", false) -- trigger lsp
  else
    vim.api.nvim_feedkeys(vim.keycode "<C-x><C-n>", "m", false) -- trigger fallback
  end
end)

-- On InsertCharPre, completefunc gets called twice.
-- - first invocation: findstart = 1
-- - second invocation: findstart = 0
-- On the first invocation, we make a completion request, which re-triggers completefunc ,therefore restarting the two invocations.
-- Now, for this (second) first invocation, we don't make another request anymore. We return the col where completion starts.
-- On the second invocation, we use the responses we got from the earlier request, process and return them to show in a completion list.
AutoCompl.completefunc = function(findstart, base)
  if not vim.list_contains({ SENT, RECEIVED }, M.completion.status) then
    M.completion_make_request()
    return findstart == 1 and -3 or {}
  end
  if findstart == 1 then
    return M.completion_findstart()
  else
    M.completion.status = DONE
    return M.completion_process_responses(base, M.completion.responses)
  end
end

M.completion_make_request = function()
  M.completion.status = SENT
  vim.lsp.buf_request_all(0, "textDocument/completion", vim.lsp.util.make_position_params(), function(responses)
    M.completion.status = RECEIVED
    M.completion.responses = responses
    M.completion_start()
  end)
end

M.completion_findstart = function()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local line = vim.api.nvim_get_current_line()
  -- TODO implement findstart using lsp
  return vim.fn.match(line:sub(1, col), "\\k*$")
end

M.completion_process_responses = function(base, responses)
  local words = {}
  for client_id, response in pairs(responses) do
    if response.err or not response.result then goto continue end
    local items = vim.tbl_get(response.result, "items") or response.result
    items = M.completion_process_items(items, base)
    if vim.tbl_isempty(items) then goto continue end
    vim.list_extend(words, M.completion_get_words(items, client_id))
    ::continue::
  end
  return words
end

-- TODO improve completion item matching algorithm, and better fuzzy search
M.completion_process_items = function(items, base)
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
      end
    end
  end
  -- Sort them based on the pattern matching scores
  table.sort(matched_items, function(a, b) return a.score > b.score end)
  -- Sort again based on LSP sortText
  table.sort(
    matched_items,
    function(a, b) return (a.item.sortText or a.item.label) < (b.item.sortText or b.item.label) end
  )
  -- Flatten into items list
  local res = {}
  for _, item in ipairs(matched_items) do
    vim.list_extend(res, { item.item })
  end
  return res
end

M.completion_get_words = function(items, client_id)
  local words = {}
  for _, item in pairs(items) do
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
  return words
end

M.lsp_get_resolved_result = function(responses)
  local results = {}
  for resolved_client_id, response in pairs(responses) do
    if not response.err and response.result then table.insert(results, { resolved_client_id, response.result }) end
  end
  return #results >= 1 and results[1] or {}
end

M.info_close = function()
  for idx, winid in ipairs(M.info.winids) do
    if pcall(vim.api.nvim_win_close, winid, false) then M.info.winids[idx] = nil end
  end
end

M.info_start = M.debounce(M.info.timer, 100, function()
  M.info_close()
  -- Check whether to trigger another info window
  if vim.fn.pumvisible() == 0 then return end -- Pmenu is not visible
  if vim.fn.mode() ~= "i" then return end -- Not in insert mode
  if vim.fn.complete_info()["selected"] == -1 then return end -- No items is selected
  -- Make resolved info request
  local lsp_data = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp") or {}
  local _, completion_item = lsp_data.client_id or 0, lsp_data.completion_item or {}
  if vim.tbl_isempty(completion_item) then return end
  vim.lsp.buf_request_all(0, "completionItem/resolve", completion_item, function(responses)
    local _, res = unpack(M.lsp_get_resolved_result(responses))
    res = res and res or completion_item
    M.info_window_open(res)
  end)
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
  -- Open window ==========
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

M.on_completedonepre = function()
  M.info_close()
  M.expand_snippet()
  M.apply_additional_text_edits()
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
  local responses = vim.lsp.buf_request_sync(0, "completionItem/resolve", completion_item, 1000)
  local res = M.lsp_get_resolved_result(responses)
  -- use info from resolved item if available, otherwise just use the original completion item
  local item, client_id
  if vim.tbl_isempty(res) then
    client_id, item = lsp_data.client_id, completion_item
  else
    client_id, item = unpack(res)
  end
  client_id = client_id or 0
  -- apply edits if there's any
  local edits = item.additionalTextEdits or {}
  if vim.tbl_isempty(edits) then return end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local extmark_id = vim.api.nvim_buf_set_extmark(0, M.ns_id, row - 1, col, {})
  local offset_encoding = vim.lsp.get_client_by_id(client_id).offset_encoding
  vim.lsp.util.apply_text_edits(edits, vim.api.nvim_get_current_buf(), offset_encoding)
  local extmark_row, extmark_col = unpack(vim.api.nvim_buf_get_extmark_by_id(0, M.ns_id, extmark_id, {}))
  pcall(vim.api.nvim_buf_del_extmark, 0, M.ns_id, extmark_id)
  pcall(vim.api.nvim_win_set_cursor, 0, { extmark_row + 1, extmark_col })
end

M.has_lsp_clients = function()
  local clients = vim.lsp.get_clients { bufnr = 0, method = "textDocument/completion" }
  return not vim.tbl_isempty(clients)
end

M.setup_keymaps = function(keys)
  local k = {
    ["confirm"] = function(key)
      vim.keymap.set("i", key, function()
        if vim.fn.complete_info()["selected"] ~= -1 then return "<C-y>" end
        if vim.fn.pumvisible() ~= 0 then return "<C-n><C-y>" end
        return key
      end, { expr = true })
      if key ~= "<CR>" then
        vim.keymap.set("i", "<CR>", function()
          if vim.fn.complete_info()["selected"] ~= -1 then return "<C-y>" end
          if vim.fn.pumvisible() ~= 0 then return "<C-e><CR>" end
          return "<CR>"
        end, { expr = true })
      end
    end,
    ["select_next"] = function(key)
      vim.keymap.set("i", key, function()
        if vim.fn.pumvisible() ~= 0 then return "<C-n>" end
        return key
      end, { expr = true })
    end,
    ["select_prev"] = function(key)
      vim.keymap.set("i", key, function()
        if vim.fn.pumvisible() ~= 0 then return "<C-p>" end
        return key
      end, { expr = true })
    end,
    ["snippet_jump_next"] = function(key)
      vim.keymap.set({ "i", "s" }, key, function()
        if vim.snippet.active { direction = 1 } then
          return "<cmd>lua vim.snippet.jump(1)<cr>"
        else
          -- TODO fallback to default? but it make typing experience bad sometimes
        end
      end, { expr = true })
    end,
    ["snippet_jump_prev"] = function(key)
      vim.keymap.set({ "i", "s" }, key, function()
        if vim.snippet.active { direction = -1 } then
          return "<cmd>lua vim.snippet.jump(-1)<cr>"
        else
          -- TODO fallback to default? but it make typing experience bad sometimes
        end
      end, { expr = true })
    end,
  }

  for cmd, key in pairs(keys) do
    k[cmd](key)
  end
end

return AutoCompl
