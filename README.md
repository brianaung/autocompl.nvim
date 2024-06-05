# autocompl.nvim
(WIP) A minimal auto completion plugin builtin on top of Vim's builtin insert-completion mechanism.

### Current roadmap
- [x] Automatic code completion.
- [x] Native LSP completion source with a fallback.
    - [x] Native LSP.
    - [x] Buffer fallback
- [x] Custom keymappings.
- [x] Snippet expansion.
- [ ] Info preview window.
- [ ] Additional text edits (e.g. automatic imports).

#### Known bugs
- [x] Keep completion suggestion window when deleting text
    - Fixed: had to rewrite my own lsp complete_func since vim.lsp.omnifunc uses vim.fn.complete() which [disappear when pressing <BS>](https://github.com/neovim/neovim/pull/24661#issuecomment-1764712654).
- [ ] Certain keymaps like `<C-n>` and `<C-p>` does not work when setting as confirm key.

### Future roadmap
- [ ] Fuzzy search.
- [ ] Signature help.
- [ ] Builtin snippet expansion (no extra dependencies).

### ~Similar~ Better alternatives
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- [mini.completion](https://github.com/echasnovski/mini.completion)
