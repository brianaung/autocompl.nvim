local lsp = require "compl.lsp"
local view = require "compl.view"

local vim = vim
local unpack = unpack
local ns_id = vim.api.nvim_create_namespace "Compl:signature-help"

---@class compl.signature
---@field private view compl.view
---@field private lsp compl.lsp
---@field private active string
---@field public timer 'uv_timer_t'
---@field public timeout integer
local signature = {}

function signature:new(opts)
	self = setmetatable({}, { __index = signature })
	self.view = view:new()
	self.lsp = lsp:new()
	self.active = nil
	self.timer = vim.uv.new_timer()
	self.timeout = opts.timeout or 100
	return self
end

---Create a permanent scratch buffer for signature help window.
function signature:create_buf() self.view:create_buf "signature-window" end

function signature:start()
	if self.lsp:is_request_done() then
		self.lsp:request_all(
			"textDocument/signatureHelp",
			vim.lsp.util.make_position_params(),
			function() self:start() end
		)
	else
		self.lsp:set_request_done()

		local _, result = unpack(self.lsp.results[1] or {})
		if not result or not result.signatures or vim.tbl_isempty(result.signatures) then
			self:stop()
			return
		end

		-- https://github.com/echasnovski/mini.completion/blob/main/lua/mini/completion.lua#L1131
		local signature_id = result.activeSignature or 0
		if signature_id < 0 or signature_id >= #result.signatures then signature_id = 0 end
		local active_signature = result.signatures[signature_id + 1]

		local param_id = active_signature.activeParameter or result.activeParameter or 0
		if param_id < 0 or param_id >= #active_signature.parameters then param_id = 0 end
		local active_param = active_signature.parameters[param_id + 1]

		-- Get the highlight range of active param
		local hl_range = {}
		local first, last
		if type(active_param.label) == "string" then
			first, last = active_signature.label:find(vim.pesc(active_param.label))
			-- Make zero-indexed and end-exclusive
			if first then first = first - 1 end
		elseif type(active_param.label) == "table" then
			first, last = unpack(active_param.label)
		end
		if first and last then hl_range = { first, last } end

		-- Convert input into markdown lines, then configures them in its view's buffer
		local lines = vim.lsp.util.convert_input_to_markdown_lines(active_signature.label) or {}
		if vim.tbl_isempty(lines) then return end
		self.view:stylize_markdown(lines)

		-- Highlight active param in current signature help window
		if not vim.tbl_isempty(hl_range) then
			vim.api.nvim_buf_clear_namespace(self.view.bufnr, ns_id, 0, -1)
			vim.api.nvim_buf_add_highlight(self.view.bufnr, ns_id, "PmenuSel", 0, hl_range[1], hl_range[2])
		end

		-- If new signature help is same as currently active one, don't open a new window
		if self.active == active_signature.label then return end
		self.active = active_signature.label

		local winopts = self:get_winopts()
		if vim.tbl_isempty(winopts) then return end
		self.view:open(winopts)
	end
end

---@return table # Configs for when opening signature help window
function signature:get_winopts()
	local winline = vim.fn.winline()
	local space_top = winline - 1

	local bufpos = vim.api.nvim_win_get_cursor(0)
	bufpos[1] = bufpos[1] - 1

	-- Calculate width (can grow to full space) and height
	local line_range = vim.api.nvim_buf_get_lines(self.view.bufnr, 0, -1, false)
	local width, height = vim.lsp.util._make_floating_popup_size(line_range)

	-- TODO find a better placement for signature help window
	local anchor = "SW" -- stay above
	if height > space_top then
		anchor = "NW" -- stay below
	end

	return {
		relative = "win",
		bufpos = bufpos,
		anchor = anchor,
		col = 0,
		width = width,
		height = height,
		focusable = false,
		style = "minimal",
		border = "none",
	}
end

function signature:stop()
	self.view:close()
	self.active = nil
end

return signature
