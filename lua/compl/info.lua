local lsp = require "compl.lsp"
local view = require "compl.view"

local vim = vim
local unpack = unpack

---@class compl.info
---@field private view compl.view
---@field private lsp compl.lsp
---@field public timer 'uv_timer_t'
---@field public timeout integer
local info = {}

function info:new(opts)
	self = setmetatable({}, { __index = info })
	self.view = view:new()
	self.lsp = lsp:new()
	self.timer = vim.uv.new_timer()
	self.timeout = opts.timeout or 100
	return self
end

---Create a permanent scratch buffer for info window.
function info:create_buf() self.view:create_buf "info-window" end

function info:start()
	self:stop()

	-- Check if completion item exists
	local completion_item = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp", "completion_item") or {}
	if vim.tbl_isempty(completion_item) then return end

	if self.lsp:is_request_done() then
		self.lsp:request_all("completionItem/resolve", completion_item, function() self:start() end)
	else
		self.lsp:set_request_done()

		local _, result = unpack(#self.lsp.results >= 1 and self.lsp.results[1] or {})
		result = result and result or completion_item

		local lines = self:get_lines(result)
		if vim.tbl_isempty(lines) then return end

		self.view:stylize_markdown(lines)

		local winopts = self:get_winopts()
		if vim.tbl_isempty(winopts) then return end

		self.view:open(winopts)
	end
end

---@param result table Completion result
---@return table # Documentation markdown lines
function info:get_lines(result)
	local documentation = type(result.documentation) == "string" and result.documentation
		or (vim.tbl_get(result.documentation or {}, "value") or "")
	local detail = result.detail or ""
	if documentation == "" and detail == "" then return {} end

	local input
	if detail == "" then
		input = documentation
	elseif documentation == "" then
		input = detail
	else
		input = detail .. "\n" .. documentation
	end

	return vim.lsp.util.convert_input_to_markdown_lines(input)
end

---@return table # Config to use when opening an info window.
function info:get_winopts()
	local pumpos = vim.fn.pum_getpos()
	if vim.tbl_isempty(pumpos) then return {} end

	local pum_left = pumpos.col - 1
	local pum_right = pumpos.col + pumpos.width + (pumpos.scrollbar and 1 or 0)
	local space_left = pum_left
	local space_right = vim.o.columns - pum_right

	-- Choose the side to open win
	local anchor, col, space = "NW", pum_right, space_right
	if space_right < space_left then
		anchor, col, space = "NE", pum_left, space_left
	end

	-- Calculate width (can grow to full space) and height
	local line_range = vim.api.nvim_buf_get_lines(self.view.bufnr, 0, -1, false)
	local width, height = vim.lsp.util._make_floating_popup_size(line_range, { max_width = space })

	return {
		relative = "editor",
		anchor = anchor,
		row = pumpos.row,
		col = col,
		width = width,
		height = height,
		focusable = false,
		style = "minimal",
		border = "none",
	}
end

function info:stop() self.view:close() end

return info
