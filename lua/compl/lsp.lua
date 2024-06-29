local vim = vim

local SENT = "SENT"
local RECEIVED = "RECEIVED"
local DONE = "DONE"

---@class compl.lsp
---@field private status 'SENT'|'RECEIVED'|'DONE'
---@field public results table { client_id, result } pairs from LSP responses
---@field public resolved_results table { client_id, result } pairs from "resolved" LSP responses
local lsp = {}

function lsp:new()
	self = setmetatable({}, { __index = lsp })
	self.status = DONE
	self.results = {}
	self.resolved_results = {}
	return self
end

---Check whether the current buffer has LSP clients that supports "textDocument/completion" method
---
---@return boolean
function lsp:has_clients()
	local clients = vim.lsp.get_clients { bufnr = 0, method = "textDocument/completion" }
	return not vim.tbl_isempty(clients)
end

---Sends an async request to all active clients attached to current buffer, process
---responses into { client_id, result } pairs, and then execute the callback if available
---
---@param method string LSP method name
---@param params table|nil Parameters to send to the server
---@param handler function|nil An optional function to call after all requests are done
function lsp:request_all(method, params, handler)
	self.status = SENT
	vim.lsp.buf_request_all(0, method, params, function(responses)
		self.status = RECEIVED
		self.results = {}
		for client_id, response in pairs(responses) do
			if not response.err and response.result then table.insert(self.results, { client_id, response.result }) end
		end
		if handler then handler() end
	end)
end

---@return boolean
function lsp:is_request_done() return self.status == DONE end

function lsp:set_request_done() self.status = DONE end

return lsp
