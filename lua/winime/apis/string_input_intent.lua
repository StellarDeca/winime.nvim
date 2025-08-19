---- 通过缓存机制实现对与特定符号的输入进行判断,同时兼容光标移动的打断 -----

local F = {}
local StringTools = require("winime.tools.string")
local RunTime = require("winime.space.string_analysis_runtime")

--[[
获取输入的字符
通过光标位置的变化来获取输入的字符(包括正常输入,字符的删除,换行)
但注意再使用补全时,再补全菜单中进行候选时,也会导致输入字符
所以要排除着这种情况之后再调用此函数
同时当缓存表中的元素长度不支持删除后,需重新使用CommentDetect区判断
--]]
--- @param win integer
--- @return {
--- 	del_beyond_history_range: boolean,
--- 	char_removed: boolean,
--- 	char_insert: boolean }
function F.track_insert_changes(win)
	local cursor_cache = RunTime.get_cursor_cache(win)
	local buf = vim.api.nvim_win_get_buf(win)
	local cache = RunTime.get_input_cache(win)
	local history = cache.input_history
	local cursor = vim.api.nvim_win_get_cursor(win)

	if cache == nil then
		return {
			del_beyond_history_range = true,
			char_insert = false,
			char_removed = false,
		}
	end

	--- 获取光标位置,同时判断是否是刚刚进入Insert模式
	local o_r, o_c
	local n_r, n_c = (cursor[1] - 1 < 0) and 0 or cursor[1] - 1, cursor[2]
	if cache.first_insert_enter then
		--- 比较当前所在行与normal的缓存行是否相同判断是否存在跨行插入
		if n_r == cursor_cache.normal.row then
			o_r = cursor_cache.normal.row
			o_c = cursor_cache.normal.col
		else
			o_r = cursor_cache.current.row
			o_c = cursor_cache.current.col
		end
	else
		o_r, o_c = cursor_cache.insert.row, cursor_cache.insert.col
	end

	--- 字符插入,光标位置后移,下移
	local result = {
		del_beyond_history_range = false,
		char_insert = false,
		char_removed = false,
	}
	if (n_r > o_r) or (n_r == o_r and n_c > o_c) then
		local texts = vim.api.nvim_buf_get_text(buf, o_r, o_c, n_r, n_c, {})
		local total_lines = #texts

		for line_idx, line_text in ipairs(texts) do
			local start_col = (line_idx == 1) and o_c or 0
			local current_col = start_col
			local current_row = o_r + line_idx - 1

			for char_idx = 1, #line_text, 1 do
				local char = line_text:sub(char_idx, char_idx)
				table.insert(history, {
					char = char,
					row = current_row,
					col = current_col,
				})
				current_col = current_col + 1
			end

			if line_idx ~= total_lines then
				table.insert(history, {
					char = "\n",
					row = current_row,
					col = current_col,
				})
			end
		end

		result.char_insert = true
	elseif (n_r < o_r) or (n_r == o_r and n_c < o_c) then
		--- 字符删除,光标位置上移,前移
		--- 注意当缓存输入表中长度不足以删除时,需要等待重新判断光标当前语法位置
		--- 删除时应当倒叙删除,从old -> new 删除

		local function in_range(r, c, s_r, s_c, e_r, e_c)
			if s_r == e_r then
				if r == s_r and c >= s_c and c <= e_c then
					return true
				else
					return false
				end
			else
				if r > s_r and r < e_r then
					return true
				elseif r == s_r and c >= s_c then
					return true
				elseif r == e_r and c <= e_c then
					return true
				else
					return false
				end
			end
		end

		while true do
			if #history <= 0 then
				result.del_beyond_history_range = true
				break
			end
			local removed = history[#history]
			if in_range(removed.row, removed.col, n_r, n_c, o_r, o_c) then
				table.remove(history)
			else
				break
			end
		end

		result.char_removed = true
	else
		-- 光标位置未发生变化,不做处理
	end

	return result
end

--[[
检查当前缓存表的长度,如果超出设定的最大长度,则删除缓存中前30%的数据
--]]
--- @param win integer
--- @param max_history_len integer
--- @return nil
function F.trim_insert_history(win, max_history_len)
	local cache = RunTime.get_input_cache(win).input_history
	if #cache >= max_history_len then
		local del_num = math.floor(max_history_len * 0.3)
		for _ = 1, del_num, 1 do
			table.remove(cache, 1)
		end
	end
end

--[[
将字符链表还原为行字符串,并根据当前所处模式进行匹配
	光标位于代码块内,此时匹配单行注释符号与块注释起始符号
		匹配成功后进入匹配行注释,块注释模式

	光标位于单行注释内,匹配换行符
		匹配成功后进入匹配代码块模式
		
	光标位于块注释内,匹配块注释结束符号
		匹配成功后进入代码块匹配模式
返回匹配是否成功以及当前的语法状态信息
	失败:语法信息为缓存的语法信息
	成功:语法信息为成功后的语法信息
当删除字符时,也应当从InsertEnter缓存位置重新判断当前位置的语法,而不能继续使用缓存
--]]
--- @param win integer
--- @param max_history_len integer 最长输入缓存字符数
--- @return {
--- 	match: boolean,
--- 	grammer_state: "block" | "code" | "line",
--- 	grammer_position : {
--- 	row: integer,
--- 	col: integer },
--- 	grammer_info: nil | {
--- 	symbol: string,
--- 	pairs: nil | {
--- 	start_symbol: string,
--- 	end_symbol: string } } }
function F.insert_input_analysis(win, max_history_len)
	local cache = RunTime.get_input_cache(win)
	local symbols = RunTime.get_symbol_cache(win)
	local history = cache.input_history

	if cache == nil then
		return {
			match = false,
			grammer_state = "code",
			grammer_position = {
				row = 0,
				col = 0,
			},
			grammer_info = nil,
		}
	elseif #history <= 0 then
		return {
			match = false,
			grammer_state = cache.grammer_state,
			grammer_position = cache.grammer_position,
			grammer_info = cache.grammer_info,
		}
	end

	--[[
	分析输入缓存策略：
	1. 当 char_removed = true or cursor_moved = true：
	   - 回退当前语法状态为 insert_enter_grammer_state；
	   - 清除 input_analysis_tail；
	   - 从 input_history 头部重新分析；
	2. 当 char_removed = false 且 input_analysis_tail 存在：
	   - 从 grammer_position 的位置末尾向后扫描,避免重复分析
	   - 确保多字符注释或字符串结构不被截断；
	3. 如果 input_analysis_tail 无效或丢失，则默认从头分析。
	--]]

	local start_input_history_idx = 1 -- 1基
	if cache.char_removed or cache.cursor_moved then
		--- 回退语法状态,从起始分析input_history
		cache.grammer_info = cache.insert_enter_grammer_state.grammer_info
		cache.grammer_state = cache.insert_enter_grammer_state.grammer_state
		cache.grammer_position = cache.insert_enter_grammer_state.grammer_position
		start_input_history_idx = 1
	else
		if cache.input_analysis_tail == nil then
			--- 从起始开始分析
			start_input_history_idx = 1
		else
			--- 从index位置向前寻找,从grammer_position的符号位置末尾开始向后分析
			--- 没找到上一行则说明tail缓存无效,回退语法状态从起始开始分析
			local grammer_start = false
			local tar_r, tar_c = cache.grammer_position.row, cache.grammer_position.col

			if cache.grammer_state ~= "code" and cache.grammer_info and cache.skip_grammer_offset then
				tar_c = tar_c + #cache.grammer_info.symbol
			end

			if history[cache.input_analysis_tail.index + 1] ~= nil then
				for i = cache.input_analysis_tail.index + 1, 1, -1 do
					local r, c = history[i].row, history[i].col
					if r == tar_r and c == tar_c then
						grammer_start = true
						start_input_history_idx = i
						break
					end
				end
			else
				--- 输入缓存不变但是依旧触发了没有moved模式的缓存分析
				--- 此时回退语法状态,从头开始分析
				grammer_start = false
			end

			if not grammer_start then
				--- 回退语法状态,从起始分析input_history
				cache.grammer_info = cache.insert_enter_grammer_state.grammer_info
				cache.grammer_state = cache.insert_enter_grammer_state.grammer_state
				cache.grammer_position = cache.insert_enter_grammer_state.grammer_position
				start_input_history_idx = 1
			end
		end
	end
	--- 更新分析坐标记录
	local end_item = history[#history]
	cache.input_analysis_tail = {
		row = end_item.row,
		col = end_item.col,
		index = #history, -- 1基
	}

	--- start_input_history_idx开始到#input_history开始拼接分析文本
	--- @type table<integer, string>
	local line_texts = {}
	local l = {}
	local line_rows = {} -- 每一行文本在buf中的行号,0基
	local line_cols = {} -- 每一行文本的第一个字符在buf中的列号,0基
	for i = start_input_history_idx, #history, 1 do
		local char = history[i]
		if #l == 0 then
			table.insert(line_rows, char.row)
			table.insert(line_cols, char.col)
		end

		if char.char ~= "\n" then
			table.insert(l, char.char)
		else
			--- 先进行转义符号去重,再进行转义引号的删除,在进行闭合引号内容的删除
			local l_text = StringTools.replace_quotes_to_space(
				StringTools.del_escape_quotes(StringTools.remove_extra_escapes(table.concat(l)))
			)

			table.insert(line_texts, l_text)
			l = {}
		end
	end
	--- 对最后一行进行处理
	local l_text = StringTools.replace_quotes_to_space(
		StringTools.del_escape_quotes(StringTools.remove_extra_escapes(table.concat(l)))
	)
	table.insert(line_texts, l_text)

	--- 揣摩输入意图
	--- 循环匹配符号,当匹配到最后一行时结束循环
	local result = {
		match = false,
		grammer_state = cache.grammer_state,
		grammer_info = cache.grammer_info,
		grammer_position = cache.grammer_position,
	}
	for l_idx, line_text in ipairs(line_texts) do
		local start_pos = 1
		while true do
			if cache.grammer_state == "code" then
				--[[
				在代码块内,尝试匹配所有的注释符号,同时替换闭合引号内容为空格
				匹配成功后进入注释状态
				匹配注释符号,同时避免未闭合的字符串的影响	
				同时保证左侧符号优先
				--]]
				local code_matches = {}
				for _, symbol in ipairs(symbols.symbols) do
					local code_start_pos = start_pos
					while code_start_pos <= #line_text do
						local s, e = line_text:find(symbol.symbol, code_start_pos, true)
						local overlapped = false

						if s == nil then
							break
						elseif StringTools.in_unclosed_qutoe(s, line_text) then
							code_start_pos = e + 1
							goto continue
						end

						--- 匹配到注释块符号,判断行注释块是否重叠块注释符号
						if symbol.type == "line" then
							for _, block_symbol in ipairs(symbols.containing[symbol.symbol]) do
								local b_s, b_e = line_text:find(block_symbol.block_symbol, start_pos, true)
								local b_in_quote = b_s and StringTools.in_unclosed_qutoe(b_s, line_text)
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
									match_pos = {
										s = s,
										e = e,
									},
									match = true,
									grammer_state = "code",
									grammer_info = nil,
										row = line_rows[l_idx],
										grammer_position = {
										col = line_cols[l_idx] + e,
									},
								})
							else
								table.insert(code_matches, {
									match_pos = {
										s = s,
										e = e,
									},
									match = true,
									grammer_state = symbol.type,
									grammer_position = {
										row = line_rows[l_idx],
										col = line_cols[l_idx] + s - 1,
									},
									grammer_info = {
										symbol = symbol.symbol,
										pairs = symbol.pairs,
										complete = symbol.type == "line",
									},
								})
							end
							break
						end

						::continue::
					end
				end

				--- 左侧原则
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
					result.match = left_item.match
					result.grammer_state = left_item.grammer_state
					result.grammer_position = left_item.grammer_position
					result.grammer_info = left_item.grammer_info
					start_pos = left_item.match_pos.e + 1
				end
			else
				--- 在注释块内,区分行注释与块注释,匹配不同的符号
				if cache.grammer_state == "line" then
					--[[
					当块注释包含行注释时,减少误判要判断接下来是否紧挨着输入了块注释符号
					同时由于检测预备延迟,必须先检测后续输入是否将当前的行注释输入为了块注释
					行注释内匹配\n换行符
					但是合并后的行字符串不包含\n,所以检测是否存在下一行
					由于分析文本并不包含之前的行注释符号,还需要对行文本进行拼接
					--]]
					local matches = {}
					local line_symbol = cache.grammer_info.symbol
					local new_line = cache.grammer_info.symbol .. line_text
					for _, ot in ipairs(symbols.containing[line_symbol]) do
						--[[
						从本行起始开始匹配
						当进入行注释模式时,行注释符号一定为最左侧符号
						随之可能的输入符号也一定是最左侧符号
						但是对于所有的符号组,找出所有符号组匹配结果中最左侧的那个,判断这个结果与行注释符号的位置
						行注释符号被包含:
							行注释符号被补全为块注释符号 -> 进入块注释模式
						行注释符号在块注释符号的左侧:
							行注释内的包含块注释符号 -> 跳过,仍然保持行注释状态
						行注释符号在块注释符号右侧:
							不存在这种情况
						--]]
						local line_start_pos = 1
						while line_start_pos <= #line_text do
							local b_s, b_e = new_line:find(ot.block_symbol, start_pos, true)
							if b_s == nil then
								break
							elseif b_s and StringTools.in_unclosed_qutoe(b_s, line_text) then
								line_start_pos = b_e + 1
								goto continue
							end

							--- 转换索引到相对于buf的0基索引
							local start_col = cache.grammer_position.col + 1
							local end_col = start_col + #line_symbol - 1

							local b_satrt_col = line_cols[l_idx] + b_s - #line_symbol - 1
							local b_end_col = line_cols[l_idx] + b_e - #line_symbol - 1

							if b_satrt_col <= start_col and b_end_col >= end_col then
								--- 匹配到行注释补全的块注释符号,记录结果
								--- 区分块注释起始于结束符号
								if ot.block_symbol == ot.pairs.start_symbol then
									table.insert(matches, {
										match_pos = {
											s = b_s,
											e = b_e,
										},
										grammer_match = true,
										grammer_state = "block",
										grammer_position = {
											row = line_rows[l_idx],
											-- 修正拼接偏移
											col = line_cols[l_idx] + b_s - #line_symbol - 1,
										},
										grammer_info = {
											complete = false,
											symbol = ot.block_symbol,
											pairs = ot.pairs,
										},
									})
								else
									table.insert(matches, {
										match_pos = {
											s = b_s,
											e = b_e,
										},
										match = true,
										grammer_state = "code",
										grammer_info = nil,
										grammer_position = {
											row = line_rows[l_idx],
											col = line_cols[l_idx] + b_e - #line_symbol,
										},
									})
								end

								break
							else
								--- 匹配到结果,但不是符号补全
								line_start_pos = b_e + 1
							end
							::continue::
						end
					end

					--- 左侧优先
					if #matches == 0 then
						--- 未匹配到符号,不做处理
					else
						local left_item = matches[1]
						for _, match in ipairs(matches) do
							if left_item.match_pos.e > match.match_pos.e then
								left_item = match
							end
						end

						--- 计入到块注释,立即更新缓存
						--- 同时更新result表
						result.match = true
						result.grammer_state = left_item.grammer_state
						result.grammer_position = left_item.grammer_position
						result.grammer_info = left_item.grammer_info

						cache.grammer_state = left_item.grammer_state
						cache.grammer_position = left_item.grammer_position
						cache.grammer_info = left_item.grammer_info

						start_pos = left_item.match_pos.e + 1
						break
					end

					if cache.grammer_state == "line" then
						--- 未匹配到相同前缀的块注释符号,则说明在行注释内
						local current_row = cache.grammer_position.row
						local current_idx = nil
						for i, row in ipairs(line_rows) do
							if row == current_row then
								current_idx = i
								break
							end
						end

						if line_texts[current_idx + 1] ~= nil then
							--- 单行注释的下一行存在,则跳出单行注释并匹配下一行
							result.match = true
							result.grammer_state = "code"
							result.grammer_info = nil
							result.grammer_position = {
								row = line_rows[l_idx],
								col = line_cols[l_idx] + #line_text - 1,
							}
							start_pos = #line_text
						else
							--- 单行注释下一行不存在,结束本行匹配
							break
						end
					else
						--- 单行注释符号匹配到完整的块注释符号,跳转到下一次行内循环
						--- 但是会被break打断,所以else不会被触发
					end
				else
					--[[
					在块注释内,先判断在不在完整的块注释内
					在完整的块注释内不进行分析
					在不完整的块注释内:
						只有起始注释符号:匹配注释结束符号,匹配成功则进入代码块状态匹配注释符号
						只有结束注释符号:匹配起始注释符号,匹配成功后进入完整注释块模式,不进行任何匹配
					跳出到代码块内时,起始坐标rammer_position必须是块注释结尾符号的最后的下一个字符
					--]]
					if
						not cache.grammer_info.complete
						and cache.grammer_info.symbol == cache.grammer_info.pairs.start_symbol
					then
						--- 不完整起始注释块
						local s, e = line_text:find(cache.grammer_info.pairs.end_symbol, start_pos, true)
						if s and e then
							result.match = true
							result.grammer_state = "code"
							result.grammer_info = nil
							result.grammer_position = {
								row = line_rows[l_idx],
								col = line_cols[l_idx] + e,
							}
							start_pos = e + 1
						else
							--- 未匹配到结束符号,跳转到下一行
							break
						end
					elseif not cache.grammer_info.complete then
						--- 不完整的结尾注释块
						local s, e = line_text:find(cache.grammer_info.pairs.start_symbol, start_pos, true)
						if s and e then
							result.match = true
							result.grammer_state = "block"
							result.grammer_position = {
								row = line_rows[l_idx],
								col = line_cols[l_idx] + e,
							}
							result.grammer_info = {
								symbol = cache.grammer_info.pairs.start_symbol,
								complete = true,
								pairs = cache.grammer_info.pairs,
							}
							start_pos = e + 1
						else
							--- 未匹配到起始符号,跳转到下一行处理
							break
						end
					else
						--- 完整的注释块内,不做处理
						break
					end
				end
			end

			--- 匹配成功则更新注释符号,并允许跳过已经分析的注释符号
			if result.match then
				cache.grammer_state = result.grammer_state
				cache.grammer_position = result.grammer_position
				cache.grammer_info = result.grammer_info
			else
				--- 所有符号都匹配不到,状态未发生改变,跳转到下一行
				break
			end
		end
	end

	--- 当匹配结果在块注释内,且block_is_string = true
	--- 修正状态为代码状态
	if symbols.block_is_string and result.grammer_state == "block" then
		-- 如果块注释被标记为字符串内容，将状态修正为代码状态
		result.match = true
		result.grammer_state = "code"
		result.grammer_info = nil
		-- result.grammer_position 保持不变

		-- 同时更新缓存状态
		cache.grammer_state = "code"
		cache.grammer_info = nil
		-- cache.grammer_position 保持不变
	end

	--- 最后检查缓存长度是否超出最大长度
	F.trim_insert_history(win, max_history_len)

	return result
end

--[[
在插入模式中移动光标位置时,判断光标位置是否超出了input_history的缓存范围
超出范围:
	查看是否可以进行反撤销,即尝试从removed_history中去恢复被删除的input_history
	恢复失败
		需重新使用CommentDetect去判断
	恢复成功
		正常退出
未超出范围
	将光标位置之后位置的input_history内容删除
之后调用Analysis分析
同时分析是否进行了字符删除或者插入,如果进行了字符删除或者插入,那么删除缓存直接全部作废清空
同时维护cursor_moved标志,将cursor_moved置为true
--]]
--- @param win integer
--- @return boolean need_comment_detect, {
--- 	cursor_moved: boolean,
---		moved_beyond_history_range: boolean,
---		reason: string } result
--- true表示需要重新计算当前语法位置
function F.insert_cursor_moved_analysis(win)
	local cache = RunTime.get_input_cache(win)
	if cache == nil then
		return true, {
			cursor_moved = false,
			moved_beyond_history_range = true,
			reason = "empty_cache",
		}
	end

	if cache.char_insert or cache.char_removed then
		cache.input_history = {}
		cache.removed_input_history = {}
		return true,
			{
				cursor_moved = false,
				moved_beyond_history_range = true,
				reason = "char_insert_or_removed",
			}
	end

	local cursor_cache = RunTime.get_cursor_cache(win)
	local input_history = cache.input_history
	local removed_history = cache.removed_input_history
	local cursor = vim.api.nvim_win_get_cursor(win)
	local n_r, n_c = math.max(0, cursor[1] - 1), cursor[2]
	local o_r, o_c
	if cache.first_insert_enter then
		-- 如果是第一次进入插入模式，使用normal模式下的光标位置
		o_r, o_c = cursor_cache.normal.row, cursor_cache.normal.col
	else
		o_r, o_c = cursor_cache.insert.row, cursor_cache.insert.col
	end

	local function cmp_pos(r1, c1, r2, c2)
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

	local result = {
		cursor_moved = false,
		moved_beyond_history_range = false,
		reason = nil,
	}

	-- 空历史，无法基于历史恢复，需重算
	if #input_history <= 0 then
		cache.removed_input_history = {}

		result.cursor_moved = true
		result.moved_beyond_history_range = false
		result.reason = "empty_history"
		return true, result
	end

	--- 判断光标移动方向
	local moved = cmp_pos(n_r, n_c, o_r, o_c)
	local history_last = input_history[#input_history]

	if moved == 0 or cmp_pos(n_r, n_c, history_last.row, history_last.col + 1) == 0 then
		--- 光标未移动或光标位置处在input_history的待输入字符位置
		result.reason = "Cursor not moved"
		return false, result
	elseif moved < 0 then
		--- 光标左移,前移
		--- 判断光标位置是否超出了input_history的缓存范围
		local history_first = input_history[1] -- 最左上侧元素
		if cmp_pos(n_r, n_c, history_first.row, history_first.col) < 0 then
			--- 超出input_history缓存范围,恢复失败
			cache.input_history = {}
			cache.removed_input_history = {}

			result.cursor_moved = true
			result.moved_beyond_history_range = true
			result.reason = "Beyond input history range"
			return true, result
		else
			while #input_history > 0 do
				local last = input_history[#input_history]
				if cmp_pos(last.row, last.col, n_r, n_c) >= 0 then
					--- 光标右侧(包含光标位置)的item进行删除
					table.insert(removed_history, table.remove(input_history))
				else
					--- 光标左侧保留,退出循环
					break
				end
			end

			cache.input_history = input_history
			cache.removed_input_history = removed_history

			result.moved_beyond_history_range = false
			result.reason = "Cursor moved in input history range"
			return false, result
		end
	else
		--- 光标右移
		--- 尝试从removed_history中恢复
		local history_first = input_history[1] -- 最右下侧元素
		if cmp_pos(n_r, n_c, history_first.row, history_first.col) <= 0 then
			--- 超出removed_history范围
			cache.input_history = {}
			cache.removed_input_history = {}

			result.cursor_moved = true
			result.moved_beyond_history_range = true
			result.reason = "Beyond removed history range"
			return true, result
		else
			--- 恢复被删除的input_history
			while #removed_history > 0 do
				local last = removed_history[#removed_history]
				--- 光标左侧位置均被回复,不包含光标位置
				if cmp_pos(last.row, last.col, n_r, n_c) < 0 then
					table.insert(input_history, table.remove(removed_history))
				else
					break
				end
			end

			cache.input_history = input_history
			cache.removed_input_history = removed_history

			result.moved_beyond_history_range = false
			result.reason = "Cursor moved in removed history range"
			return false, result
		end
	end
end

return F
