local lsp = require "compl.lsp"

local vim = vim
local unpack = unpack

---@class compl.completion
---@field private lsp compl.lsp
---@field public timer 'uv_timer_t'
---@field public timeout integer
local completion = {}

function completion:new(opts)
	self = setmetatable({}, { __index = completion })
	self.lsp = lsp:new()
	self.timer = vim.uv.new_timer()
	self.timeout = opts.timeout or 100
	return self
end

---Starts ins-completion mode. Triggers user defined completion (LSP) if there are active LSP clients with completion support, otherwise
---fallbacks to current buffer keywords completion.
function completion:start()
	if
		vim.fn.pumvisible() ~= 0 -- Popup menu is visible
		or vim.fn.mode() ~= "i" -- Not in insert mode
		or vim.api.nvim_get_option_value("buftype", { buf = 0 }) ~= "" -- Not a normal buffer
	then
		return
	end

	if self.lsp:has_clients() then
		vim.api.nvim_feedkeys(vim.keycode "<C-x><C-u>", "m", false) -- trigger lsp
	else
		vim.api.nvim_feedkeys(vim.keycode "<C-x><C-n>", "m", false) -- trigger fallback
	end
end

---Finds LSP completions.
---
---This function gets called twice.
---- first invocation: findstart = 1, base = empty
---- second invocation: findstart = 0, base = text located in the first call
---On the first invocation, it makes a request to get completion items, and re-triggers completefunc ,thereby resetting completefunc calls.
---Now, for this call (it is still in first invocation), no more request are made, and it returns the start of completion.
---Then, on the second invocation, it uses the responses from the earlier request, to process and return the a list of matching words to complete.
---
---@param findstart integer Defines the way the function is called: 1 = find the start of text to be completed, 2 = find the actuall matches
---@param base string The text with which matches should match; the text that was located in the first call (can be empty)
---@return integer|table # A list of matching words
function completion:completefunc(findstart, base)
	if self.lsp:is_request_done() then
		self.lsp:request_all(
			"textDocument/completion",
			vim.lsp.util.make_position_params(),
			function() self:start() end
		)
		return findstart == 1 and -3 or {}
	end
	if findstart == 1 then
		return self:findstart()
	else
		self.lsp:set_request_done()
		local words = self:process_matches(base)
		return words
	end
end

---Returns the start of the text to be completed.
---
---@return integer
function completion:findstart()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	local line = vim.api.nvim_get_current_line()
	return vim.fn.match(line:sub(1, col), "\\k*$")
end

---@param base string Text to be matched
---@return table # A list of matching words
function completion:process_matches(base)
	local words = {}
	for _, result in ipairs(self.lsp.results) do
		local client_id, items = unpack(result)
		items = items.items or items
		if vim.tbl_isempty(items) then goto continue end

		-- Filter items
		local matched_items = {}
		for _, item in pairs(items) do
			local text = item.filterText
				or (vim.tbl_get(item, "textEdit", "newText") or item.insertText or item.label or "")
			if vim.startswith(text, base:sub(1, 1)) then vim.list_extend(matched_items, { item }) end
		end

		table.sort(matched_items, function(a, b) return (a.sortText or a.label) < (b.sortText or b.label) end)

		-- Construct the table of items for the pmenu content
		for _, item in pairs(matched_items) do
			table.insert(words, {
				word = vim.tbl_get(item, "textEdit", "newText") or item.insertText or item.label or "",
				abbr = item.label,
				kind = vim.lsp.protocol.CompletionItemKind[item.kind] or "Unknown",
				icase = 1,
				dup = 1,
				empty = 1,
				user_data = {
					nvim = { lsp = { completion_item = item, client_id = client_id } },
				},
			})
		end
		::continue::
	end
	return words
end

---Replace and expands completed text if it is a snippet.
function completion:expand_snippet()
	local completion_item = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp", "completion_item") or {}
	-- not a lsp completion or not a snippet
	if vim.tbl_isempty(completion_item) or completion_item.kind ~= 15 then return end
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	vim.api.nvim_buf_set_text(0, row - 1, col - #vim.v.completed_item.word, row - 1, col, { "" })
	vim.api.nvim_win_set_cursor(0, { row, col - vim.fn.strwidth(vim.v.completed_item.word) })
	vim.snippet.expand(vim.tbl_get(completion_item, "textEdit", "newText") or completion_item.insertText or "")
end

---@param ns_id integer
function completion:apply_additional_text_edits(ns_id)
	local lsp_data = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp") or {}
	local completion_item = lsp_data.completion_item or {}
	if vim.tbl_isempty(completion_item) then return end

	local results = self.lsp.resolved_results
	local result = #results >= 1 and results[1] or {}

	-- use info from resolved item if available, otherwise just use the original completion item
	local item, client_id
	if vim.tbl_isempty(result) then
		client_id, item = lsp_data.client_id, completion_item
	else
		client_id, item = unpack(result)
	end
	client_id = client_id or 0

	-- apply edits if there's any
	local edits = item.additionalTextEdits or {}
	if vim.tbl_isempty(edits) then return end

	-- https://github.com/echasnovski/mini.completion/blob/main/lua/mini/completion.lua#L889
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local extmark_id = vim.api.nvim_buf_set_extmark(0, ns_id, row - 1, col, {})
	local offset_encoding = vim.lsp.get_client_by_id(client_id).offset_encoding
	vim.lsp.util.apply_text_edits(edits, vim.api.nvim_get_current_buf(), offset_encoding)
	local extmark_row, extmark_col = unpack(vim.api.nvim_buf_get_extmark_by_id(0, ns_id, extmark_id, {}))
	pcall(vim.api.nvim_buf_del_extmark, 0, ns_id, extmark_id)
	pcall(vim.api.nvim_win_set_cursor, 0, { extmark_row + 1, extmark_col })
end

return completion
