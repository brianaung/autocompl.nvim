local M = {}

function M.setup()
	vim.api.nvim_create_autocmd({ "InsertCharPre" }, {
		callback = function()
			if vim.fn.pumvisible() == 1 or vim.fn.state "m" == "m" then
				return
			end

			if vim.api.nvim_buf_get_option(0, "buftype") == "" then
				local key = vim.keycode "<C-x><C-o>"
				vim.api.nvim_feedkeys(key, "m", false)
			end
		end,
	})

	vim.opt.completeopt = { "menuone", "noinsert" }
	vim.opt.shortmess:append "c"
end

return M
