# autocompl.nvim
(WIP) A minimal auto completion plugin built on top of Vim's builtin insert-completion mechanism.

### Current roadmap
- [x] Automatic code completion.
- [x] Native LSP completion source with a fallback.
    - [x] Native LSP.
    - [x] Buffer fallback
- [x] Custom keymappings.
- [x] Basic fuzzy match.
- [x] Basic snippet expansion
- [x] Additional text edits (e.g. automatic imports).
- [ ] Info preview window.

#### Known bugs
- [x] Keep completion suggestion window when deleting text
    - Fixed: implemented a custom LSP completefunc, since vim.lsp.omnifunc uses vim.fn.complete() which [disappear when pressing backspace.](https://github.com/neovim/neovim/pull/24661#issuecomment-1764712654).
- [x] Completion not showing up when using in buffers with multiple clients attached.
    - Fixed: Process items for all clients.
- [x] Some language servers returning incorrect completion items on first character.
    - Fixed: Improved process_items function with better match scoring.
- [ ] Certain keymaps like `<C-n>` and `<C-p>` does not work when setting as confirm key.

### Future roadmap
- [ ] More advanced fuzzy match.
- [ ] Signature help.
- [ ] Advanced snippet expansion.
    - [ ] Support custom snippet expand function
    - [ ] Keymaps to jump around like luasnip

### ~Similar~ Better alternatives
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- [mini.completion](https://github.com/echasnovski/mini.completion)
- [coq_nvim](https://github.com/ms-jpq/coq_nvim)
