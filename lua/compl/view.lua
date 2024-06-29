local vim = vim

---@class compl.view
---@field public bufnr integer
---@field public winids table
local view = {}

function view:new()
	self = setmetatable({}, { __index = view })
	self.bufnr = 0
	self.winids = {}
	return self
end

---Creates a permanent scratch buffer.
---
---@param name string Buffer name to set
function view:create_buf(name)
	self.bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(self.bufnr, "Compl:" .. name)
	vim.fn.setbufvar(self.bufnr, "&buftype", "nofile")
end

function view:stylize_markdown(lines) vim.lsp.util.stylize_markdown(self.bufnr, lines) end

function view:open(configs)
	table.insert(self.winids, vim.api.nvim_open_win(self.bufnr, false, configs))
end

function view:close()
	for idx, winid in ipairs(self.winids) do
		if pcall(vim.api.nvim_win_close, winid, false) then self.winids[idx] = nil end
	end
end

return view
