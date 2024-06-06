local completion = require "autocompl.completion"
local mapping = require "autocompl.mapping"
local util = require "autocompl.util"

local M = {}

M.ns_id = vim.api.nvim_create_namespace "AutoCompl"

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
  util.au("CompleteDonePre", function()
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
  end, "Start auto completion with a debounce")

  util.au("CompleteDonePre", function()
    local lsp_data = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp")
    if lsp_data == nil or vim.tbl_isempty(lsp_data) then
      return
    end

    local completion_item = lsp_data.completion_item

    if completion_item then
      local edits = completion_item.additionalTextEdits
      local client_id = lsp_data.client_id
      if edits then
        local cur_pos = vim.api.nvim_win_get_cursor(0)
        local extmark_id = vim.api.nvim_buf_set_extmark(0, M.ns_id, cur_pos[1] - 1, cur_pos[2], {})

        local offset_encoding = vim.lsp.get_client_by_id(client_id).offset_encoding
        vim.lsp.util.apply_text_edits(edits, vim.api.nvim_get_current_buf(), offset_encoding)

        local extmark_data = vim.api.nvim_buf_get_extmark_by_id(0, M.ns_id, extmark_id, {})
        pcall(vim.api.nvim_buf_del_extmark, 0, M.ns_id, extmark_id)
        pcall(vim.api.nvim_win_set_cursor, 0, { extmark_data[1] + 1, extmark_data[2] })
      end
      -- vim.lsp.buf_request(0, "completionItem/resolve", completion_item, function(_, _, result)
      --   local edits = vim.tbl_get(result, "params", "additionalTextEdits") or completion_item.additionalTextEdits
      --   local client_id = result.client_id
      --   if edits then
      --     client_id = lsp_data.client_id
      --   end

      --   if edits then
      --     local cur_pos = vim.api.nvim_win_get_cursor(0)
      --     local extmark_id = vim.api.nvim_buf_set_extmark(0, M.ns_id, cur_pos[1] - 1, cur_pos[2], {})

      --     local offset_encoding = vim.lsp.get_client_by_id(client_id).offset_encoding
      --     vim.lsp.util.apply_text_edits(edits, vim.api.nvim_get_current_buf(), offset_encoding)

      --     local extmark_data = vim.api.nvim_buf_get_extmark_by_id(0, M.ns_id, extmark_id, {})
      --     pcall(vim.api.nvim_buf_del_extmark, 0, M.ns_id, extmark_id)
      --     pcall(vim.api.nvim_win_set_cursor, 0, { extmark_data[1] + 1, extmark_data[2] })
      --   end
      -- end)
    end
  end, "Start auto completion with a debounce")
end

return M
