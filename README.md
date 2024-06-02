# autocompl.nvim

### Goal of this project (in order of importance)
To support:
- [x] Automatic code completion.
- [x] Different completion sources:
    - [x] Native LSP.
    - [x] Current buffer text (as fallback).
- [x] Snippet expansion.
- [ ] Info preview window.

#### Bug fixes
- [ ] Keep completion suggestion window when deleting text

### Future roadmap
- [ ] Fuzzy search.

### Maybe(s)

#### Custom keybindings support
I will be focusing on other features since this is more for personal use and I don't need the ability to set custom keybindings.
And most people should also just use Vim's "idiomatic" completion bindings (See `:h ins-completion`) since they are superior to the popular `<Tab>` and/or `<Enter>` completions bindings in my opinion.

### ~Similar~ Better alternatives
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- [mini.completion](https://github.com/echasnovski/mini.completion)
