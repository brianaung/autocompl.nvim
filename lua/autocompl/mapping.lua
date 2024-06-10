local core = require "autocompl.core"
local util = require "autocompl.util"

local M = {}

function M.bind_keys(keys)
  for key, fn in pairs(keys) do
    fn(key)
  end
end

function M.confirm(key)
  -- Default confirm key behavior
  vim.keymap.set("i", key, function()
    -- If item is selected
    if vim.fn.complete_info()["selected"] ~= -1 then
      return util.k "<C-y>"
    end
    -- If pmenu is open and nothing is selected
    if util.pumvisible() then
      return util.k "<C-n><C-y>"
    end
    -- Else, default
    return util.k(key)
  end, { expr = true })

  -- <CR> behavior if it's not used as confirm key
  if key ~= util.k "<CR>" then
    vim.keymap.set("i", "<CR>", function()
      -- If item is selected
      if vim.fn.complete_info()["selected"] ~= -1 then
        return util.k "<C-y>"
      end
      -- If pmenu is open and nothing is selected
      if util.pumvisible() then
        return util.k "<C-e><CR>"
      end
      -- Else, default
      return util.k "<CR>"
    end, { expr = true })
  end
end

function M.select_next(key)
  key = util.k(key)
  vim.keymap.set("i", key, function()
    if util.pumvisible() then
      return util.k "<C-n>"
    end
    return key
  end, { expr = true })
end

function M.select_prev(key)
  key = util.k(key)
  vim.keymap.set("i", key, function()
    if util.pumvisible() then
      return util.k "<C-p>"
    end
    return key
  end, { expr = true })
end

function M.scroll_docs_up(key)
  key = util.k(key)
  vim.keymap.set("i", key, function()
    M.scroll_docs(-4)
  end)
end

function M.scroll_docs_down(key)
  key = util.k(key)
  vim.keymap.set("i", key, function()
    M.scroll_docs(4)
  end)
end

-- https://github.com/hrsh7th/nvim-cmp/blob/main/lua/cmp/view/docs_view.lua#L130
function M.scroll_docs(delta)
  if core.info.winid then
    local info = vim.fn.getwininfo(core.info.winid)[1] or {}
    local top = info.topline or 1
    top = top + delta
    top = math.max(top, 1)
    top = math.min(top, core.info.height - info.height + 1)
    vim.schedule(function()
      vim.api.nvim_win_call(core.info.winid, function()
        vim.api.nvim_command("normal! " .. top .. "zt")
      end)
    end)
  end
end

return M
