----- 字符串工具函数 -----

local F = {}

--- 处理字符中的多重转义,将多余的转义字符替换为空格
--- @param line_text string
--- @return string
function F.remove_extra_escapes(line_text)
	local result = {}

	local i = 1
	while i <= #line_text do
		local char = line_text:sub(i, i)
		if char == "\\" then
			--- 遇见第一个转义字符时,开始多重转义处理
			local j = i
			while j <= #line_text and line_text:sub(j, j) == "\\" do
				j = j + 1
			end
			local count = j - i

			--- 对多重转义字符进行替换
			if count % 2 == 0 then
				table.insert(result, string.rep(" ", count))
			else
				table.insert(result, string.rep(" ", count - 1))
				table.insert(result, "\\")
			end

			--- 更新循环进度
			i = j
		else
			table.insert(result, char)
			i = i + 1
		end
	end
	return table.concat(result)
end

--- 删除字符串中的转义引号,传入的line_text需要经过转义去重
--- @param line_text string
--- @return string
function F.del_escape_quotes(line_text)
	local result = {}
	local i = 1
	while i <= #line_text do
		local char = line_text:sub(i, i)
		if char == "\\" then
			--- 检查是否为转义引号
			local next_char = line_text:sub(i + 1, i + 1)
			if next_char == '"' or next_char == "'" then
				--- 跳过下次循环
				table.insert(result, "\\ ")
				i = i + 1
			else
				table.insert(result, "\\")
			end
		else
			table.insert(result, char)
		end
		i = i + 1
	end
	return table.concat(result)
end

--[[
将传入字符串内的引号内的内容进行替换
--]]
--- @param line_text string
--- @return string
function F.replace_quotes_to_space(line_text)
	local parttern_1 = [["([^"]*)"]]
	local parttern_2 = [['([^']*)']]

	-- 先替换双引号字符串,再替换单引号字符串
	line_text = line_text:gsub(parttern_1, function(content)
		return string.rep(" ", #content + 2)
	end)

	line_text = line_text:gsub(parttern_2, function(content)
		return string.rep(" ", #content + 2)
	end)

	return line_text
end

--- 根据传入的待匹配符号将单行注释排除,同时避免包含导致的错误判断
--- 将单行注释替换为相同长度的空字符
--- @param line_text string
--- @param line_symbols table<string> 降序排列的单行注释符号表
--- @param overlapping table<string, { block_symbol: string, pairs: any }>
--- @return string
function F.replace_line_comment_to_space(line_text, line_symbols, overlapping)
	local function replace(space_len, replace_start_idx, text)
		local space = string.rep(" ", space_len)
		text = line_text:sub(1, replace_start_idx - 1) .. space
		return text
	end

	--[[
	左侧原则,处理最左侧的符号
	行注释符号被包含或在未闭合的引号内部则丢弃
	--]]

	local matches = {}
	for _, symbol in ipairs(line_symbols) do
		local start_pos = 1
		while start_pos <= #line_text do
			local line_s, line_e = line_text:find(symbol, start_pos, true)
			local overlapped = false
			if line_s == nil then
				break
			elseif F.in_unclosed_qutoe(line_s, line_text) then
				start_pos = line_e + 1
				goto continue
			end

			for _, contain in ipairs(overlapping[symbol]) do
				local match_s, match_e = line_text:find(contain.block_symbol, start_pos, true)
				local match_in_quote = match_s and F.in_unclosed_qutoe(match_s, line_text)
				if match_s and not match_in_quote and line_s >= match_s and line_e <= match_e then
					--- 行注释符号在块注释内部
					--- 清空符号表,跳转到右侧重新匹配
					overlapped = true
					break
				end
			end

			if overlapped then
				start_pos = line_e + 1
			else
				--- 匹配成功,这个符号已经是这个符号的最左侧符号了
				--- 结束这个符号的匹配,跳转到下一个符号
				table.insert(matches, {
					symbol = symbol,
					col = line_s - 1,
				})
				start_pos = line_e + 1
				break
			end

			::continue::
		end
	end

	if next(matches) == nil then
		return line_text
	else
		local left_item = matches[1]
		for _, match in ipairs(matches) do
			if match.col < left_item.col then
				left_item = match
			end
		end
		return replace(#line_text - left_item.col, left_item.col + 1, line_text)
	end
end

--- 判断制定字符串位置是否在未闭合的字符串(也就是单个引号的下文,只看单行)(最好经过引号配对去除,否则影响结果)
--- 边界不包含index的位置,只匹配到index的前一个符号
--- @param index integer 1基索引
--- @param line_text string
--- @return boolean 在返回True不在返回Flase
function F.in_unclosed_qutoe(index, line_text)
	local stack = nil
	local i = 1
	while i < index do
		local char = line_text:sub(i, i)
		if char == "'" or char == '"' then
			--- 查看是否为转义字符
			local last_char = line_text:sub(i - 1, i - 1)
			if last_char ~= "\\" and stack == nil then
				stack = char
			elseif last_char ~= "\\" and stack ~= nil and char == stack then
				stack = nil
			end
		end
		i = i + 1
	end
	return stack ~= nil
end

return F
