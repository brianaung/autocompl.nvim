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
- [ ] Info preview window.
- [ ] Additional text edits (e.g. automatic imports).

#### Known bugs
- [x] Keep completion suggestion window when deleting text
    - Fixed: had to rewrite my own lsp complete_func since vim.lsp.omnifunc uses vim.fn.complete() which [disappear when pressing backspace.](https://github.com/neovim/neovim/pull/24661#issuecomment-1764712654).
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
