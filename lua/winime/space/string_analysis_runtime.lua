-----== Winime String Analysis运行数据管理 ==------

local F = {}

--[[
String Analysis 运行数据表
=====================================================================================
	runtime.symbol_cache: {
		---- 表都按照符号长度降序排列 ----

		-- 注释符号是否认为是字符串
		block_is_string: boolean

-------------------------------------------------------------------------------------
		-- 全体符号表
		symbols = {
			[index] = {
				symbol: string
				type: "line" | "block"
				is_start: boolean
				pairs: nil | {
					start_symbol: string,
					end_stmbol: string
				}
			}
		}

-------------------------------------------------------------------------------------
		-- 行注释符号表
		lines = {
			[index] = {
				symbol: string
				type: "line"
				is_start: boolean
				pairs: nil | {
					start_symbol: string,
					end_stmbol: string
				}
			}
		}
		
-------------------------------------------------------------------------------------
		-- 块注释符号表,起始终止均包含
		blocks = {
			[index] = {
				symbol: string
				type: "block"
				is_start: boolean
				pairs: nil | {
					start_symbol: string,
					end_stmbol: string
				}
			}
		}

-------------------------------------------------------------------------------------
		--- 起始符号表
		starts = {
			[index] = {
				symbol: string
				type: "line" | "block"
				is_start: boolean
				pairs: nil | {
					start_symbol: string,
					end_stmbol: string
				}
			}
		}

-------------------------------------------------------------------------------------
		--- 包含符号表,记录符号之间的包含关系（包含起始符号和终止符号）
		containing = {
			[line_symbol: string] = {
				block_symbol: string,
				pairs: {
					start_symbol: string,
					end_stmbol: string
				}
			}
		}

=====================================================================================
	runtime.input_cache[winid] = {
		--- 用户行为状态标志	
		char_insert: boolean
		char_removed: boolean
		cursor_moved: boolean
		need_comment boolean

		--- 语法状态标志
		first_insert_enter: boolean -- 首次进入Insert模式
		skip_grammer_offset boolean -- 是否跳过特定语法符号开头

-------------------------------------------------------------------------------------
		--- 输入法状态信息
		method_state: {
			state: "en" | "other"
			in_sync: boolean  -- 输入法缓存是否被真实的进行了切换
		}

-------------------------------------------------------------------------------------
		--- 语法状态信息
		grammer_state: "line" | "block" | "code"

		grammer_info: nil | {
			-- 如果comment_type == "block"
			symbol: string -- 注释块符号
			complete: boolean -- 块注释符号是否闭合
			pairs: {
					start_symbol -- 注释块起始符号
					end_symbol -- 注释块终止符号
				}
			}
		}

		grammer_position: {  -- 语法坐标位置,为注释符号起始位置或代码光标位置
			row: integer,
			col: integer
		}	

		insert_enter_grammer_state: {
			grammer_state: grammer_state,
			grammer_info: grammer_info
			grammer_position: {
				row: integer,
				col: integer
			}	
		}
-------------------------------------------------------------------------------------
		--- 用户输入缓存信息

		input_analysis_tail: nil | {
			-- 记录Input_history的分析的终点位置,下次分析的起点位置
			row: integer  -- 0基
			col: integer  -- 0基
			index: integer -- 上次分析位置在input_history中的索引,1基
		}	

		input_history: {
			--
			使用链表记录用户输入
			每个节点仅仅存放一个字符(特殊按键符号视为一个字符)
			char为输入的字符
			row, col 表示这个字符在文件中的行数与列数,从0开始计数

			获取插入的字符,只需要先判断光标位置,判断是否进行了退格,换行等
			再根据当前的光标位置去获取到输入的字符
			--
	
			{ char = string, row = integer, col = integer }
			...
		}

		removed_input_history: {
			{ char = string, row = integer, col = integer }
			...
		}
	}

=====================================================================================
	光标位置缓存表,只记录Cursor的最后一次位置
	runtime.cursor_cache = [winid] = {
		normal = { row, col }
		insert= { row, col }
		current = { row, col }
	}

--]]

local runtime = {}

--- @class line_symbols
--- @field symbol string
--- @field type "line"
--- @field is_start true
--- @field pairs nil
---
--- @class block_start_symbols
--- @field symbol string
--- @field type "block"
--- @field is_start true
--- @field pairs { start_symbol: string, end_symbol: string }
---
--- @class block_end_symbols
--- @field symbol string
--- @field type "block"
--- @field is_start false
--- @field pairs { start_symbol: string, end_symbol: string }
---
--- @class containing_symbols
--- @field block_symbol string
--- @field pairs { start_symbol: string, end_symbol: string }
---
--- @class cache
--- @field block_is_string boolean
--- @field symbols (line_symbols | block_start_symbols | block_end_symbols)[]
--- @field lines line_symbols[]
--- @field blocks (block_start_symbols | block_end_symbols)[]
--- @field starts (line_symbols | block_start_symbols)[]
--- @field containing { [string]: containing_symbols[] }
---
--- @type table<integer, cache>
runtime.symbol_cache = {}

--- @class input
--- @field char_removed boolean
--- @field char_insert boolean
--- @field cursor_moved boolean
--- @field need_comment boolean
--- @field first_insert_enter boolean
--- @field skip_grammer_offset boolean
---
--- @field method_state { state: "en" | "other", in_sync: boolean }
---
--- @field grammer_state "code" | "line" | "block"
--- @field grammer_position { row: integer, col: integer }
--- @field grammer_info nil | {
--- 	symbol: string,
--- 	complete: boolean,
--- 	pairs: nil | {
--- 	start_symbol: string,
--- 	end_symbol: string } }
--- @field insert_enter_grammer_state {
--- 	grammer_state: "code" | "line" | "block",
---  	grammer_position: { row: integer, col: integer },
---  	grammer_info:  nil | {
--- 	symbol: string,
--- 	complete: boolean,
--- 	pairs: nil | {
--- 	start_symbol: string,
--- 	end_symbol: string } } }
---
--- @field input_analysis_tail nil | {
--- 	row: integer,
--- 	col: integer,
--- 	index: integer }
--- @field input_history {
--- 	char: string,
--- 	row: integer,
--- 	col: integer, }
--- @field removed_input_history {
--- 	char: string,
--- 	row: integer,
--- 	col: integer, }
---
--- @type table<integer, input>
runtime.input_cache = {}

--- @class mode_cursor
--- @field row integer
--- @field col integer
---
--- @class cursor
--- @field normal nil | mode_cursor
--- @field insert nil | mode_cursor
--- @field current mode_cursor
---
--- @type table<integer, cursor>
runtime.cursor_cache = {}

--- 获取symbols缓存表
--- @param win integer
function F.get_symbol_cache(win)
	return runtime.symbol_cache[win]
end

--- 初始化symbols缓存数据表
--- @param win integer
--- @param symbols { line: table<string>, block: table<string, string>, block_is_string: boolean }
--- @return nil
function F.init_symbol_cache(win, symbols)
	--- 初始化缓存
	local sym = {}
	for _, l_sym in ipairs(symbols.line) do
		table.insert(sym, {
			symbol = l_sym,
			type = "line",
			is_start = true,
			pairs = nil,
		})
	end
	for s_sym, e_sym in pairs(symbols.block) do
		table.insert(sym, {
			symbol = s_sym,
			type = "block",
			is_start = true,
			pairs = {
				start_symbol = s_sym,
				end_symbol = e_sym,
			},
		})
		table.insert(sym, {
			symbol = e_sym,
			type = "block",
			is_start = false,
			pairs = {
				start_symbol = s_sym,
				end_symbol = e_sym,
			},
		})
	end
	table.sort(sym, function(a, b)
		return #a.symbol > #b.symbol
	end)

	runtime.symbol_cache[win] = {
		block_is_string = symbols.block_is_string,
		symbols = sym,
		lines = {},
		blocks = {},
		starts = {},
		containing = {},
	}

	--- 分类存放数据表
	local cache = runtime.symbol_cache[win]
	for _, symbol in ipairs(sym) do
		if symbol.type == "line" then
			table.insert(cache.lines, symbol)
			table.insert(cache.starts, symbol)
		elseif symbol.type == "block" and symbol.is_start then
			table.insert(cache.blocks, symbol)
			table.insert(cache.starts, symbol)
		else
			table.insert(cache.blocks, symbol)
		end
	end

	--- 初始化重叠符号表
	local ot = cache.containing
	for _, l_sym in ipairs(symbols.line) do
		if not ot[l_sym] then
			ot[l_sym] = {}
		end

		for _, block_sym in ipairs(cache.blocks) do
			local s, e = block_sym.symbol:find(l_sym, 1, true)
			if s and e then
				table.insert(ot[l_sym], {
					block_symbol = block_sym.symbol,
					pairs = block_sym.pairs,
				})
			end
		end

		table.sort(ot[l_sym], function(a, b)
			return #a.block_symbol > #b.block_symbol
		end)
	end
end

--- 清除symbols缓存
--- @param win integer
--- @return nil
function F.del_symbols_cache(win)
	runtime.symbol_cache[win] = nil
end

--- 获取input_cache[winid]
--- @param win integer
function F.get_input_cache(win)
	return runtime.input_cache[win]
end

--- 初始化input_cache,这个函数将会在InsertEnter时被调用
--- @param win integer
--- @param grammer_state "line" | "block" | "code"
--- @param grammer_info nil | { symbol: string, complete: boolean, pairs: nil | { start_symbol: string, end_symbol: string } }
--- @param grammer_position { row: integer, col: integer }
--- @param method_in_sync boolean
--- @return nil
function F.init_input_cache(win, grammer_state, grammer_info, grammer_position, method_in_sync)
	local method_state
	if grammer_state == "code" then
		method_state = "en"
	else
		method_state = "other"
	end

	runtime.input_cache[win] = {
		char_insert = false,
		char_removed = false,
		cursor_moved = false,
		need_comment = false,
		first_insert_enter = true,
		skip_grammer_offset = false,

		method_state = {
			state = method_state,
			in_sync = method_in_sync,
		},

		grammer_state = grammer_state,
		grammer_position = grammer_position,
		grammer_info = grammer_info,
		insert_enter_grammer_state = {
			grammer_state = grammer_state,
			grammer_info = grammer_info,
			grammer_position = grammer_position,
		},

		input_history = {},
		input_analysis_tail = nil,
		removed_input_history = {},
	}
end

--- 清除input缓存
--- @param win integer
--- @return nil
function F.del_input_cache(win)
	runtime.input_cache[win] = nil
end

--- 获取cursor缓存表,未初始化则自动初始化
--- @param win integer
--- @param mode nil | "n" | "i" 当 Neovim 的nvim_get_mode方法不准确时,强制制定当前模式
function F.get_cursor_cache(win, mode)
	local cache = runtime.cursor_cache[win]
	if not cache then
		F.init_cursor_cache(win, mode)
	end
	return runtime.cursor_cache[win]
end

--- 初始化cursor缓存表
--- @param win integer
--- @param mode nil | "n" | "i" 当 Neovim 的nvim_get_mode方法不准确时,强制制定当前模式
--- @return nil
function F.init_cursor_cache(win, mode)
	local cursor = vim.api.nvim_win_get_cursor(win)
	local cursor_pos = {
		row = (cursor[1] - 1 < 0) and 0 or cursor[1] - 1,
		col = cursor[2],
	}
	if mode == nil then
		mode = vim.api.nvim_get_mode().mode
	end

	runtime.cursor_cache[win] = {
		current = cursor_pos,
	}
	local cache = runtime.cursor_cache[win]
	if mode == "n" then
		cache.normal = cursor_pos
	elseif mode == "i" then
		cache.insert = cursor_pos
	end
end

--- 设置cursor缓存表,未初始化则自动初始化
--- @param win integer
--- @param mode nil | "n" | "i" 当 Neovim 的nvim_get_mode方法不准确时,强制制定当前模式
--- @return nil
function F.set_cursor_cache(win, mode)
	local cache = F.get_cursor_cache(win, mode)

	local cursor = vim.api.nvim_win_get_cursor(win)
	local cursor_pos = {
		row = (cursor[1] - 1 < 0) and 0 or cursor[1] - 1,
		col = cursor[2],
	}
	if mode == nil then
		mode = vim.api.nvim_get_mode().mode
	end

	cache.current = cursor_pos
	if mode == "n" then
		cache.normal = cursor_pos
	elseif mode == "i" then
		cache.insert = cursor_pos
	end
end

--- 清除cursor缓存
--- @param win integer
--- @return nil
function F.del_cursor_cache(win)
	runtime.cursor_cache[win] = nil
end

--- 获取runtime缓存
function F.get_runtime_cache()
	return runtime
end

return F
