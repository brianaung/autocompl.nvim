local lsp = require "compl.lsp"
local view = require "compl.view"

local vim = vim
local unpack = unpack

---@class compl.signature
---@field private view compl.view
---@field private lsp compl.lsp
---@field private active string
---@field public timer 'uv_timer_t'
local signature = {}

function signature:new()
	self = setmetatable({}, { __index = signature })
	self.view = view:new()
	self.lsp = lsp:new()
	self.active = nil
	self.timer = vim.uv.new_timer()
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

		-- Get active signature from response
		-- If active signature outside the range, default to 0
		local active_index = result.activeSignature or 0
		if active_index < 0 or active_index >= #result.signatures then active_index = 0 end
		local active_signature = result.signatures[active_index + 1]

		-- If new signature help is same as currently active one, do nth
		if self.active == active_signature.label then return end

		self.active = active_signature.label

		local lines = vim.lsp.util.convert_input_to_markdown_lines(active_signature.label) or {}
		if vim.tbl_isempty(lines) then return end

		self.view:stylize_markdown(lines)

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
