local util = require "autocompl.util"

local M = {}

M.bind_keys = function(keys)
  for key, fn in pairs(keys) do
    fn(key)
  end
end

M.confirm = function(key)
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

M.select_next = function(key)
  key = util.k(key)
  vim.keymap.set("i", key, function()
    if util.pumvisible() then
      return util.k "<C-n>"
    end
    return key
  end, { expr = true })
end

M.select_prev = function(key)
  key = util.k(key)
  vim.keymap.set("i", key, function()
    if util.pumvisible() then
      return util.k "<C-p>"
    end
    return key
  end, { expr = true })
end

return M
