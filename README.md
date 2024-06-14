# autocompl.nvim
A minimal and dependency-free auto-completion plugin built on top of Vim's builtin insert-completion mechanism.

### Features
- Async automatic LSP completion, with a fallback to buffer text.
- Info window for more completion item documentation.
- Snippet expansion and jump support.
- Fuzzy matching capabilities.
- Apply additional text edits (e.g. auto-imports).

### WIP
- [ ] More configuration options (keymaps, debounced timeouts, etc.)
- [ ] Signature help window.
- [ ] Improve highlighting (fuzzy matched chars, different info, etc.).

### Known bugs
- [ ] Certain keymaps like `<C-n>` and `<C-p>` does not work when setting as confirm key.

### ~Similar~ Better alternatives
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- [mini.completion](https://github.com/echasnovski/mini.completion)
- [coq_nvim](https://github.com/ms-jpq/coq_nvim)
