----- String 分析判断当前窗口内的光标位置是否在注释块内部 -----

local F = {}
local Logger = require("winime.tools.logger")
local RunTime = require("winime.space.string_analysis_runtime")
local StringTools = require("winime.tools.string")

--[[
在文件语法错误的情况下,使用字符串匹配注释块
单行注释块分析
严格限制光标位置在注释块内,同时排除注释符号相互包含导致的错误判断
--]]
--- @param win integer
--- @return {
--- 	grammer_state: "line" | "code",
--- 	grammer_position: {
--- 	row: integer,
--- 	col: integer },
--- 	grammer_info: nil | {
--- 	symbol: string,
--- 	complete: true,
--- 	pairs: nil } }, table matches
function F.comment_detect_line(win)
	local symbols = RunTime.get_symbol_cache(win)

	-- 获取光标位置
	local cursor = vim.api.nvim_win_get_cursor(win)
	local row = (cursor[1] - 1 < 0) and 0 or cursor[1] - 1
	local col = cursor[2]

	-- 检查光标位置是否在注释内部
	-- 同时排除引号字符串,防止符号在字符串内部
	local bufnr = vim.api.nvim_win_get_buf(win)
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

	--- 先进行转义符号去重,再进行转义引号的删除,在进行闭合引号内容的删除
	line = StringTools.replace_quotes_to_space(StringTools.del_escape_quotes(StringTools.remove_extra_escapes(line)))

	local result = {
		grammer_state = "code",
		grammer_info = nil,
		grammer_position = {
			row = row,
			col = col,
		},
	}
	local matches = {}
	for _, symbol in ipairs(symbols.lines) do
		local start_pos = 1
		while start_pos <= #line do
			--[[
			循环匹配符号,若行注释符号包含在块注释符号内部则丢弃这部分匹配结果,更新起始位置向更右侧匹配
			直到无匹配项终止匹配
			--]]
			local s, e = line:find(symbol.symbol, start_pos, true)
			local overlapped = false
			if s == nil then
				break
			elseif StringTools.in_unclosed_qutoe(s, line) then
				start_pos = e + 1
				goto continue
			end

			for _, contain in ipairs(symbols.containing[symbol.symbol]) do
				local b_s, b_e = line:find(contain.block_symbol, s, true)
				local b_in_quote = b_s and StringTools.in_unclosed_qutoe(b_s, line)
				if b_s and not b_in_quote and s >= b_s and e <= b_e then
					--- 行注释符号在块注释内部
					--- 清空符号表,跳转到右侧重新匹配
					overlapped = true
					break
				end
			end

			--- 查看是否重叠
			if overlapped then
				start_pos = e + 1
			else
				--- 此种注释符号已经找到最左侧符号
				--- 注释符号加入候选表
				--- 结束本次符号查找,进入下一个符号的查找
				table.insert(matches, {
					grammer_state = "line",
					grammer_position = {
						row = row,
						col = s - 1,
					},
					grammer_info = {
						symbol = symbol.symbol,
						complete = true,
						pairs = nil,
					},
				})
				start_pos = e + 1
				break
			end

			::continue::
		end
	end

	--- 最左原则,返回最左侧的符号
	if next(matches) == nil then
		return result, {}
	else
		local left_item = matches[1]
		for _, match in ipairs(matches) do
			if match.grammer_position.col < left_item.grammer_position.col then
				left_item = match
			end
		end
		--- 严格判断光标位置与最左侧符号位置
		if col > left_item.grammer_position.col then
			return left_item, matches
		else
			return result, matches
		end
	end
end

--[[
语法不完整情况下,多行文本注释符号解析(如果字符串符号与多行文本符号一致,则默认认为就是多行注释)
--]]
--- @param win integer
--- @return {
--- 	grammer_state: "block" | "code",
--- 	grammer_position: {
--- 	row: integer,
--- 	col: integer },
--- 	grammer_info: nil | {
--- 	symbol: string,
--- 	complete: true,
--- 	pairs: {
--- 	start_symbol: string,
--- 	end_symbol: string } } }, table matches
function F.comment_detect_block(win)
	local cache = RunTime.get_symbol_cache(win)
	local lines = {}
	local blocks = cache.blocks

	-- 获取光标位置
	local cursor = vim.api.nvim_win_get_cursor(win)
	local row = (cursor[1] - 1 < 0) and 0 or cursor[1] - 1
	local col = cursor[2]
	local buf = vim.api.nvim_win_get_buf(win)

	local result = {
		grammer_state = "code",
		grammer_info = nil,
		grammer_position = { row = row, col = col },
	}
	if cache.block_is_string then
		return result, {}
	end

	--[[
	创建数据表,使用单栈匹配多行注释符号
	matches 结果表
	stack 单栈
	--]]
	--- @type table | nil
	local stack = nil
	local matches = {}

	--- 创建字符串单栈表
	--- @type table<string>
	for _, sym in ipairs(cache.lines) do
		table.insert(lines, sym.symbol)
	end

	--[[
	逐行按照字符匹配
		根据栈的状态顺序匹配起始与终止符号
		注意栈为单栈,只会为nil空栈或者为table表示匹配到符号
		栈中的符号一定为起始注释符号

		栈空则按照顺序匹配符号
		- 匹配到起始符号:
			1.进行入栈操作
			2.跳转到栈不空的处理
		- 匹配到终止符号
			1.记录匹配结果(孤立的结束符号)
			2.跳转到栈空处理
		- 匹配失败
			1.跳转到下一行按照栈空处理

		栈不空则尝试匹配栈中符号对应的终止符号
		- 若匹配成功:
			1.记录匹配结果
			2.进行出栈操作
			3.跳转到栈空处理
		- 若匹配失败
			1.跳转到下一行按照栈不空处理
	--]]
	--- 逐行遍历整个文件
	--- 文件行数1基

	local max_line_num = vim.api.nvim_buf_line_count(buf)
	local line_texts = vim.api.nvim_buf_get_lines(buf, 0, max_line_num, false)
	for l_num, line_text in ipairs(line_texts) do
		-- 单行内循环匹配符号,处理栈空与栈不空
		local start_pos = 1
		while start_pos < #line_text do
			if stack == nil then
				--- 栈空,按照顺序匹配符号
				--- 对行内容进行预处理,进行转义符号的去重,转义引号的删除,引号对的删除

				local new_line = StringTools.replace_quotes_to_space(
					StringTools.del_escape_quotes(StringTools.remove_extra_escapes(line_text))
				)
				local code_matches = {}
				for _, symbol in ipairs(blocks) do
					--- 排除单行注释符号的干扰
					new_line = StringTools.replace_line_comment_to_space(new_line, lines, cache.containing)
					local s, e = new_line:find(symbol.symbol, start_pos, true)

					if s and e and symbol.is_start and not StringTools.in_unclosed_qutoe(s, new_line) then
						-- 匹配到起始符号,记录位置信息,进行入栈操作
						table.insert(code_matches, {
							symbol_type = "start",
							symbol = symbol.symbol,
							pairs = symbol.pairs,
							complete = false,
							position = {
								row = (l_num - 1 < 0) and 0 or l_num - 1,
								col = s - 1,
							},
							range = {
								--- 匹配到起始符号,暂时仅仅记录起始范围
								start_row = (l_num - 1 < 0) and 0 or l_num - 1,
								start_col = s - 1,
								end_row = nil,
								end_col = nil,
							},
						})
					elseif s and e and not symbol.is_start and not StringTools.in_unclosed_qutoe(s, new_line) then
						-- 匹配到孤立的结束符号
						table.insert(code_matches, {
							symbol_type = "end",
							complete = false,
							symbol = symbol.symbol,
							pairs = symbol.pairs,
							position = {
								row = l_num,
								col = s - 1,
							},
							range = {
								start_row = 0,
								start_col = 0,
								end_row = (l_num - 1 < 0) and 0 or l_num - 1,
								end_col = e - 1,
							},
						})
					end
				end

				--- 最左侧原则
				if next(code_matches) == nil then
					-- 都匹配不到,则跳转至下一行处理
					break
				else
					local left_item = code_matches[1]
					for _, match in ipairs(code_matches) do
						if left_item.position.col >= match.position.col then
							left_item = match
						end
					end
					--- 判断符号的性质
					if left_item.symbol_type == "start" then
						stack = left_item
						-- 更新未匹配的范围
						-- 跳出符号匹配循环,进入下一次while栈不空的处理
						start_pos = left_item.range.start_col + #left_item.symbol + 1 + 1
					else
						table.insert(matches, left_item)
						-- 更新未匹配的范围,并跳转到下一次while循环按照栈空处理
						start_pos = left_item.range.end_col + 1 + 1
					end
				end
			end
			--- 栈不空处理
			if stack ~= nil then
				--- 尝试匹配栈中元素对应的终止符号
				--- 在注释块内不需要判断是否在未闭合的引号内
				local s, e = line_text:find(stack.pairs.end_symbol, start_pos, true)

				if s and e then
					-- 匹配到对应的终止符号
					table.insert(matches, {
						symbol_type = "complete symbol",
						complete = true,
						symbol = stack.pairs.start_symbol,
						pairs = stack.pairs,
						position = stack.position,
						range = {
							start_row = stack.range.start_row,
							start_col = stack.range.start_col,
							end_row = (l_num - 1 < 0) and 0 or l_num - 1,
							end_col = e - 1,
						},
					})
					stack = nil
					start_pos = e + 1
				else
					-- 匹配不到结束符号则跳到下一行处理
					break
				end
			end
		end
	end

	--[[
	匹配整个文件后发现栈不空:
		1.记录孤立的起始符号
	--]]
	if stack ~= nil then
		local last_col_num = #vim.api.nvim_buf_get_lines(buf, max_line_num - 1, max_line_num, false)[1] - 1
		table.insert(matches, {
			symbol_type = "start",
			complete = false,
			symbol = stack.pairs.start_symbol,
			pairs = stack.pairs,
			position = stack.position,
			range = {
				start_row = stack.range.start_row,
				start_col = stack.range.start_col,
				end_row = (max_line_num - 1 < 0) and 0 or max_line_num - 1,
				end_col = (last_col_num - 1 < 0) and 0 or last_col_num - 1,
			},
		})
	end

	--[[
	开始对注释块进行分析,确认光标是否在注释块内
		对marches结果列表进行排序,孤立的 > 成对的, 再按照行号升序排列
	--]]
	table.sort(matches, function(a, b)
		if a.complete ~= b.complete then
			return not a.complete
		else
			return a.range.start_row < b.range.start_row
		end
	end)

	--- 判断光标是否在注释块内
	for _, block in ipairs(matches) do
		local range = block.range
		if row > range.start_row and row < range.end_row then
			result.grammer_state = "block"
			result.grammer_position = block.position
			result.grammer_info = {
				symbol = block.symbol,
				complete = block.complete,
				pairs = block.pairs,
			}
			return result, matches
		elseif row == range.start_row and col > range.start_col then -- 严格限制光标位置在注释块内,所以光标不能在起始符号的第一个字符前
			result.grammer_state = "block"
			result.grammer_position = block.position
			result.grammer_info = {
				symbol = block.symbol,
				complete = block.complete,
				pairs = block.pairs,
			}
			return result, matches
		elseif row == range.end_row and col <= range.end_col then
			result.grammer_state = "block"
			result.grammer_position = block.position
			result.grammer_info = {
				symbol = block.symbol,
				complete = block.complete,
				pairs = block.pairs,
			}
			return result, matches
		end
	end

	return result, matches
end

--[[
纯字符串注释符号分析
优先判断块注释,再判断行注释
--]]
--- @param win integer
--- @return {
--- 	grammer_state: "code" | "line" | "block",
--- 	grammer_position: {
--- 	row: integer,
--- 	col: integer },
--- 	grammer_info: nil | {
--- 	symbol: string,
--- 	complete: boolean,
--- 	pairs: nil | {
--- 	start_symbol: string,
--- 	end_symbol:string } } }
function F.comment_detect_string_analysis(win)
	local res, matches = F.comment_detect_block(win)


	if res.grammer_state == "code" then
		res, matches = F.comment_detect_line(win)
	end
	Logger.write_log(nil, "Comment Matches", "String Analysis", matches)
	return res
end

return F
