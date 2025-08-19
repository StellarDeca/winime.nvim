-----== 使用 TreeSitter 判断光标位置是否在注释块内 ==-----

local F = {}
local Logger = require("winime.tools.logger")
local RunTime = require("winime.space.tree_sitter_anslysis_runtime")
local StringTools = require("winime.tools.string")

function F.cmp_pos(r1, c1, r2, c2)
	--- 判断给定的r1, c1是否在r2,c2范围内
	--- 范围左面返回-1,范围右面返回1,相等返回0
	if r1 < r2 then
		return -1
	end
	if r1 > r2 then
		return 1
	end
	if c1 < c2 then
		return -1
	end
	if c1 > c2 then
		return 1
	end
	return 0
end

--- Error Node 字符串分析规则
--- @param win integer
--- @param error_node TSNode
--- @return {
--- 	start_row: integer,
--- 	start_col: integer,
--- 	end_row: integer,
--- 	end_col: integer }[]
function F.error_node_string_analysis(win, error_node)
	--[[
	使用栈进行Error节点内的注释符号分析
	初始状态为code状态,只匹配最外层的行注释与块注释
	--]]

	--[[
	对node_text按行存储
	--]]
	local bufnr = vim.api.nvim_win_get_buf(win)
	local lines = vim.split(vim.treesitter.get_node_text(error_node, bufnr), "\n", { plain = true })
	local symbols = RunTime.get_symbol_cache(win)

	--- 对字符串进行转义,引号的去重
	local sr, sc, _, _ = error_node:range()
	local line_rows = {}
	local line_cols = {}
	local result_l = {}
	for i, l in ipairs(lines) do
		local line_text =
			StringTools.replace_quotes_to_space(StringTools.del_escape_quotes(StringTools.remove_extra_escapes(l)))

		if i == 1 then
			table.insert(line_cols, sc)
		else
			table.insert(line_cols, 0)
		end

		table.insert(line_rows, sr + i - 1)
		table.insert(result_l, line_text)
	end

	--- 使用单栈处理嵌套符号
	local matches = {}
	local stack = nil

	--- 逐行分析文本
	for idx, line in ipairs(result_l) do
		local start_pos = 1
		while start_pos <= #line do
			--- 标记匹配是否成功
			local match_mark = false

			if stack == nil then
				--- 栈空,同时匹配起始符号与结束符号
				-- 匹配符号选取最左侧符号,同时排除重叠符号
				local code_matches = {}
				for _, symbol in ipairs(symbols.symbols) do
					local code_start_pos = start_pos
					while code_start_pos <= #line do
						local s, e = line:find(symbol.symbol, code_start_pos, true)
						local overlapped = false

						if s == nil then
							break
						elseif StringTools.in_unclosed_qutoe(s, line) then
							code_start_pos = e + 1
							goto continue
						end

						--- 匹配到注释块符号,判断行注释块是否重叠块注释符号
						if symbol.type == "line" then
							for _, block_symbol in ipairs(symbols.containing[symbol.symbol]) do
								local b_s, b_e = line:find(block_symbol.block_symbol, start_pos, true)
								local b_in_quote = b_s and StringTools.in_unclosed_qutoe(b_s, line)
								if b_s and not b_in_quote and s >= b_s and e <= b_e then
									--- 行注释符号重叠块注释符号
									code_start_pos = e + 1
									overlapped = true
									break
								end
							end
						end

						if overlapped then
							code_start_pos = e + 1
						else
							--- 此种注释符号已经找到最左侧符号
							--- 注释符号加入候选表
							--- 结束本次符号查找,进入下一个符号的查找
							--- 当匹配到孤立的结束符号时,代码状态仍保持code不变,位置变为块注释结尾位置
							if symbol.type == "block" and not symbol.is_start then
								table.insert(code_matches, {
									symbol = symbol,
									match_pos = {
										s = s,
										e = e,
									},
									grammer_range = {
										start_row = 0,
										start_col = 0,
										end_row = line_rows[idx],
										end_col = line_cols[idx] + e,
									},
								})
							else
								table.insert(code_matches, {
									symbol = symbol,
									match_pos = {
										s = s,
										e = e,
									},
									grammer_range = {
										start_row = line_rows[idx],
										start_col = line_cols[idx] + s - 1,
										end_row = 0,
										end_col = 0,
									},
								})
							end
							break
						end
						::continue::
					end
				end
				--- 左侧原则,选出匹配结果中最左侧的匹配项
				if #code_matches == 0 then
					--- 所有符号都匹配不到,跳转到下一行处理
					start_pos = 1
					break
				else
					local left_item = code_matches[1]
					for _, match in ipairs(code_matches) do
						if left_item.match_pos.e > match.match_pos.e then
							left_item = match
						end
					end

					local result = {
						symbol = left_item.symbol,
					}
					if left_item.symbol.type == "line" then
						result.grammer_range = {
							start_row = left_item.grammer_range.start_row,
							start_col = left_item.grammer_range.start_col,
							end_row = left_item.grammer_range.start_row,
							end_col = math.max(0, #line),
						}
						table.insert(matches, result)
						break
					elseif left_item.symbol.is_start then
						result.grammer_range = left_item.grammer_range
						stack = result
					else
						result.grammer_range = left_item.grammer_range
						table.insert(matches, result)
					end

					--- 更新匹配状态
					match_mark = true
					start_pos = left_item.match_pos.e + 1
				end
			else
				--- 栈不空,匹配起始符号对应的结束符号
				local s, e = line:find(stack.symbol.pairs.end_symbol, start_pos, true)
				if s and e then
					local s_r = stack.grammer_range
					table.insert(matches, {
						symbol = stack.symbol,
						match_pos = { s = s, e = e },
						grammer_range = {
							start_row = s_r.start_row,
							start_col = s_r.start_col,
							end_row = line_rows[idx],
							end_col = line_cols[idx] + e,
						},
					})

					stack = nil
					match_mark = true
					start_pos = e + 1
				end
			end

			--- 匹配整行后,无匹配符号则跳到下一行
			if not match_mark then
				break
			end
		end
	end
	--- 处理栈不空的孤立起始符号
	if stack ~= nil then
		local s_r = stack.grammer_range
		local max_line_num = vim.api.nvim_buf_line_count(bufnr)
		local last_col_num = #vim.api.nvim_buf_get_lines(bufnr, max_line_num - 1, max_line_num, false)[1] - 1
		table.insert(matches, {
			symbol = stack.symbol,
			match_pos = stack.match_pos,
			grammer_range = {
				start_row = s_r.start_row,
				start_col = s_r.start_col,
				end_row = math.max(0, max_line_num - 1),
				end_col = math.max(0, last_col_num - 1),
			},
		})
	end

	local result = {}
	for _, c in ipairs(matches) do
		table.insert(result, c.grammer_range)
	end
	return result
end

--- Comment Node 分析
--- @param comment_node TSNode
--- @return {
--- 	start_row: integer,
--- 	start_col: integer,
--- 	end_row: integer,
--- 	end_col: integer } grammer_range
function F.comment_node_analysis(comment_node)
	local sr, sc, er, ec = comment_node:range()
	return {
		start_row = sr,
		start_col = sc,
		end_row = er,
		end_col = ec,
	}
end

--- 判断光标是否在给定的范围内
--- @param win integer
--- @param comment_range {
--- 	start_row: integer,
--- 	start_col: integer,
--- 	end_row: integer,
--- 	end_col: integer }[]
--- @return boolean in_comment, nil | {
--- 	start_row: integer,
--- 	start_col: integer,
--- 	end_row: integer,
--- 	end_col: integer } grammer_range
function F.cursor_in_comment_range(win, comment_range)
	--- 匹配成功后整理并判断光标位置是否在注释范围内
	local cursor = vim.api.nvim_win_get_cursor(win)
	local row, col = math.max(0, cursor[1] - 1), cursor[2]
	for _, range in ipairs(comment_range) do
		if
			F.cmp_pos(row, col, range.start_row, range.start_col) > 0
			and F.cmp_pos(row, col, range.end_row, range.end_col) <= 0
		then
			return true, range
		end
	end
	return false, nil
end

--- 对文件语法树进行分析,判断光标位置是否在注释块内
--- @param win integer
--- @param root_node nil | TSNode
--- @return boolean in_comment, TSNode root_node, nil | {
---		start_row: integer,
---		start_col: integer,
---		end_row: integer,
---		end_col: integer } grammer_range
function F.comment_detect_tree_sitter_analysis(win, root_node)
	--[[
	遍历语法树,找到完整的注释跟节点以及Error根节点
	并判断光标是否在注释范围之内
	--]]

	if root_node == nil then
		local bufnr = vim.api.nvim_win_get_buf(win)
		local parser = require("nvim-treesitter.parsers").get_parser(bufnr)
		local trees = parser:parse()
		root_node = trees[1]:root()
	end

	local comment_nodes = {}
	local error_nodes = {}
	local ranges = {}

	--- 递归遍历语法树,查找comment节点与error节点的根节点
	--- 从根部开始遍历,第一个符合要求的节点就是根节点
	--- @param node TSNode
	local function tree_walk(node)
		local typ = string.lower(node:type())
		if typ and typ:find("error", 1, true) ~= nil then
			table.insert(error_nodes, node)
			return nil
		elseif type and typ:find("comment", 1, true) ~= nil then
			table.insert(comment_nodes, node)
			return nil
		end

		for i = 0, node:child_count() - 1, 1 do
			local child = node:child(i)
			if child then
				tree_walk(child)
			else
				return nil
			end
		end
	end

	tree_walk(root_node)

	--- 获取comment节点,error节点的注释范围信息
	if not vim.tbl_isempty(error_nodes) then
		for _, e in ipairs(error_nodes) do
			vim.list_extend(ranges, F.error_node_string_analysis(win, e))
		end
		Logger.write_log(nil, "Error Nodes", "TS Analysis", comment_nodes)
	end

	if not vim.tbl_isempty(comment_nodes) then
		for _, c in ipairs(comment_nodes) do
			table.insert(ranges, F.comment_node_analysis(c))
		end

		Logger.write_log(nil, "Comment Nodes", "TS Analysis", comment_nodes)
	end

	local in_comment, grammer_range = F.cursor_in_comment_range(win, ranges)

	return in_comment, root_node, grammer_range
end

return F
