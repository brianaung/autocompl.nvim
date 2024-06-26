# autocompl.nvim
(WIP) A minimal and dependency-free auto-completion plugin built on top of vim's builtin ins-completion mechanism.

### Features
- Async automatic LSP completion, with a fallback to buffer text.
- Info window for more completion item documentation.
- Signature helps.
- Snippet expansion and jump support.
- Apply additional text edits (e.g. auto-imports).

### Roadmap
- [ ] Fuzzy matching capabilities.

### Installation
##### Using [lazy.nvim](https://github.com/folke/lazy.nvim):
```lua
{
  "brianaung/autocompl.nvim",
  opts = {
    -- Default options.
    -- completion_timeout = 150, -- completion menu debounced timeout
    -- info_timeout = 150, -- info window debounced timeout
  },
}
```

### Recommended VIM Options
```lua
-- A combination of ins-completion options for better experience. See `:h completeopt`
vim.opt.completeopt = { "menuone", "noselect", "noinsert" }

-- Hide the ins-completion-menu messages. See `:h shm-c`
vim.opt.shortmess:append "c"
```

### Custom Keymaps
By default, this plugin follows ins-completion mappings (See `:h ins-completion-menu`, `:h popupmenu-keys`). However, they can be easily remapped.

Below are some recipes using the `vim.keymap.set()` interface. See `:h vim.keymap.set()`.

##### Accept completion using `<CR>`
```lua
vim.keymap.set("i", "<CR>", function()
  if vim.fn.complete_info()["selected"] ~= -1 then return "<C-y>" end
  if vim.fn.pumvisible() ~= 0 then return "<C-e><CR>" end
  return "<CR>"
end, { expr = true })
```

##### Change selection using `<Tab>` and `<Shift-Tab>`
```lua
vim.keymap.set("i", "<Tab>", function()
  if vim.fn.pumvisible() ~= 0 then return "<C-n>" end
  return "<Tab>"
end, { expr = true })

vim.keymap.set("i", "<S-Tab>", function()
  if vim.fn.pumvisible() ~= 0 then return "<C-p>" end
  return "<S-Tab>"
end, { expr = true })
```

##### Snippet jumps
```lua
vim.keymap.set({ "i", "s" }, "<C-k>", function()
  if vim.snippet.active { direction = 1 } then
    return "<cmd>lua vim.snippet.jump(1)<cr>"
  end
end, { expr = true })

vim.keymap.set({ "i", "s" }, "<C-j>", function()
  if vim.snippet.active { direction = -1 } then
    return "<cmd>lua vim.snippet.jump(-1)<cr>"
  end
end, { expr = true })
```

### ~Similar~ Better alternatives
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- [mini.completion](https://github.com/echasnovski/mini.completion)
- [coq_nvim](https://github.com/ms-jpq/coq_nvim)
