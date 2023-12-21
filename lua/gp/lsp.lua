local M = {}

---@param lines string[]|nil lines of text
---@return string[]|nil snippet lines
M.extract_snippet = function(lines)
	if not lines then
		return nil
	end
	local snippet_started = false
	local snippet_lines = {}
	local non_empty_encountered = false
	for _, line in ipairs(lines) do
		local is_fence = line:match("^```")
		if is_fence and not snippet_started then
			snippet_started = true
			non_empty_encountered = true
		elseif is_fence and snippet_started then
			return snippet_lines
		elseif snippet_started then
			table.insert(snippet_lines, line)
		elseif non_empty_encountered and not is_fence then
			table.insert(snippet_lines, line)
		elseif not non_empty_encountered and line ~= "" and not is_fence then
			non_empty_encountered = true
		end
	end
	return snippet_started and snippet_lines or nil
end

---@param row integer|nil mark-indexed line number, defaults to current line
---@param col integer|nil mark-indexed column number, defaults to current column
---@param bufnr integer|nil buffer handle or 0 for current, defaults to current
---@param offset_encoding "utf-8"|"utf-16"|"utf-32"|nil defaults to `offset_encoding` of first client of `bufnr`
---@return table { textDocument = { uri = `current_file_uri` }, position = { line = `row`, character = `col`} }
---@see https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocumentPositionParams
M.make_given_position_param = function(row, col, bufnr, offset_encoding)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	row = row or vim.api.nvim_win_get_cursor(0)[1]
	col = col or vim.api.nvim_win_get_cursor(0)[2]
	local params = vim.lsp.util.make_given_range_params({ row, col }, { row, col }, bufnr, offset_encoding)
	return { textDocument = params.textDocument, position = params.range.start }
end

---@param buf integer|nil buffer handle or 0 for current, defaults to current
---@param win integer|nil window handle or 0 for current, defaults to current
---@param row integer|nil mark-indexed line number, defaults to current line
---@param col integer|nil mark-indexed column number, defaults to current column
M.hover = function(buf, win, row, col, offset_encoding)
	local params = M.make_given_position_param(row, col, buf)

	vim.lsp.buf_request_all(buf, "textDocument/hover", params, function(results)
		local contents = {}
		for _, r in pairs(results) do
			if r.result and r.result.contents then
				local lines = vim.lsp.util.convert_input_to_markdown_lines(r.result.contents)
				for _, line in ipairs(lines) do
					table.insert(contents, line)
				end
			end
		end
		if #contents == 0 then
			return
		end
		local snippet_lines = M.extract_snippet(contents) or {}
		table.insert(contents, "$$$$$$$$$$$$$$$$")
		for _, line in ipairs(snippet_lines) do
			table.insert(contents, line)
		end

		local bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)
		vim.api.nvim_win_set_buf(0, bufnr)
	end)
end

---@param row integer|nil mark-indexed line number, defaults to current line
---@param col integer|nil mark-indexed column number, defaults to current column
---@param bufnr integer|nil buffer handle or 0 for current, defaults to current
---@see https://microsoft.github.io/language-server-protocol/specifications/specification-current/#completionParams
M.completion = function(row, col, bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	row = row or vim.api.nvim_win_get_cursor(0)[1]
	col = col or vim.api.nvim_win_get_cursor(0)[2]
	local params = M.make_given_position_param(row, col, bufnr)

	vim.lsp.buf_request_all(bufnr, "textDocument/completion", params, function(results)
		local items = {}
		-- text = vim.inspect(results) .. "\n" .. "-------------------" .. "\n" .. text
		for cid, r in pairs(results) do
			for _, item in ipairs(r.result.items) do
				table.insert(items, { cid = cid, item = item })
			end
		end

		local res = vim.lsp.util.text_document_completion_list_to_complete_items(results)
		local tbuf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(tbuf, 0, -1, false, vim.split(vim.inspect(res), "\n"))
		vim.api.nvim_win_set_buf(0, tbuf)
	end)
end
return M