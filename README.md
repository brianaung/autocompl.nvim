# autocompl.nvim
(WIP) A minimal auto completion plugin built on top of Vim's builtin insert-completion mechanism.

### Current roadmap
- [x] Automatic code completion.
- [x] Native LSP completion source with a fallback.
    - [x] Native LSP.
    - [x] Buffer fallback
- [x] Basic fuzzy match.
- [x] Basic snippet expansion
- [x] Additional (synchronous) text edits (e.g. automatic imports).
- [ ] Info preview window.
- [ ] Expose configuration options.
    - [x] Custom keymappings.
    - [ ] Completion debounce waiting time.
    - [ ] Additional text edits request max blocking timeout.
    - [ ] Enable/disable info window.
    - [ ] Custom fallback completion.
    - [ ] Custom snippet expansion.

#### Known bugs
- [ ] Certain keymaps like `<C-n>` and `<C-p>` does not work when setting as confirm key.

### Future roadmap
- [ ] Signature help.
- [ ] More advanced fuzzy match.
- [ ] Advanced snippet expansion.
    - [ ] Support custom snippet expand function
    - [ ] Keymaps to jump around like luasnip
- [ ] Better highlighting

### ~Similar~ Better alternatives
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- [mini.completion](https://github.com/echasnovski/mini.completion)
- [coq_nvim](https://github.com/ms-jpq/coq_nvim)
