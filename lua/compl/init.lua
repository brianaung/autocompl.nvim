local completion = require "compl.completion"
local info = require "compl.info"
local lib = require "compl.lib"
local signature = require "compl.signature"

local ns_id = vim.api.nvim_create_namespace "Compl"

local compl = {}

function compl.setup(opts)
	opts = opts or {}

	compl.completion = completion:new(opts.completion or {})
	compl.info = info:new(opts.info or {})
	compl.signature = signature:new(opts.signature or {})

	compl.info:create_buf()
	compl.signature:create_buf()

	_G.Compl = {}
	_G.Compl.completefunc = function(findstart, base) return compl.completion:completefunc(findstart, base) end

	lib.au(
		{ "BufEnter", "LspAttach" },
		function(e) vim.bo[e.buf].completefunc = "v:lua.Compl.completefunc" end,
		"Set complete-function."
	)
	lib.au(
		"InsertCharPre",
		lib.debounce(compl.completion.timer, compl.completion.timeout, function() compl.completion:start() end),
		"Trigger completion."
	)
	lib.au(
		"CompleteChanged",
		lib.debounce(compl.info.timer, compl.info.timeout, function() compl.info:start() end),
		"Trigger info window."
	)
	lib.au(
		"CursorMovedI",
		lib.debounce(compl.signature.timer, compl.signature.timeout, function() compl.signature:start() end),
		"Trigger signature help."
	)
	lib.au("CompleteDonePre", function()
		compl.completion:expand_snippet()
		compl.completion:apply_additional_text_edits(ns_id)
	end, "")
	lib.au("InsertLeavePre", function()
		compl.info:stop()
		compl.signature:stop()
	end, "")
end

return compl
