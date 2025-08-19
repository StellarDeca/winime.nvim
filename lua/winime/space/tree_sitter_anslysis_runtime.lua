-----== Winime String Analysis运行数据管理 ==------

local F = {}

--[[
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
	runtime.ts_cache[winid] = {
		root_node: TSNode
		file_ticked: integer
		grammer_state: "code" | "comment"
		grammer_range: nil | {
			start_row: integer,
			start_col: integer,
			end_row: integer,
			end_col: integer
		}

=====================================================================================
	runtime.method_cache[winid] = {
		state: "en" | "other"
		in_sync: boolean
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
--- @class containing_symbols
--- @field block_symbol string
--- @field pairs { start_symbol: string, end_symbol: string }
---
--- @class cache
--- @field block_is_string boolean
--- @field symbols (line_symbols | block_start_symbols | block_end_symbols)[]
--- @field containing { [string]: containing_symbols[] }
---
--- @type table<integer, cache>
runtime.symbol_cache = {}

--- @class ts_cache
--- @field root_node TSNode
--- @field file_ticked integer
--- @field grammer_state "code" | "comment"
--- @field grammer_range nil | {
--- 	start_row: integer,
--- 	start_col: integer,
--- 	end_row: integer,
--- 	end_col: integer }
---
--- @type table<integer, ts_cache>
runtime.ts_cache = {}

--- @class method_cache
--- @field state "en" | "other"
--- @field in_sync boolean
---
--- @type table<integer, method_cache>
runtime.method_cache = {}

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
		symbols = sym,
		block_is_string = symbols.block_is_string,
		containing = {},
	}

	--- 初始化重叠符号表
	local cache = runtime.symbol_cache[win]
	local ot = cache.containing
	for _, l_sym in ipairs(symbols.line) do
		if not ot[l_sym] then
			ot[l_sym] = {}
		end

		for s_sym, e_sym in pairs(symbols.block) do
			local ss = s_sym:find(l_sym, 1, true)
			local es = e_sym:find(l_sym, 1, true)
			if ss then
				table.insert(ot[l_sym], {
					block_symbol = s_sym,
					pairs = {
						start_symbol = s_sym,
						end_symbol = e_sym,
					},
				})
			end

			if es then
				table.insert(ot[l_sym], {
					block_symbol = e_sym,
					pairs = {
						start_symbol = s_sym,
						end_symbol = e_sym,
					},
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

--- 初始化TS_cache表
--- @param win integer
--- @param file_ticked integer
--- @param root TSNode
--- @param in_comment boolean
--- @param grammer_range nil | {
--- 	start_row: integer,
--- 	start_col: integer,
--- 	end_row: integer,
--- 	end_col: integer }
--- @return nil
function F.init_ts_cache(win, file_ticked, root, in_comment, grammer_range)
	local grammer_state
	if in_comment then
		grammer_state = "comment"
	else
		grammer_state = "code"
	end

	runtime.ts_cache[win] = {
		root_node = root,
		file_ticked = file_ticked,
		grammer_state = grammer_state,
		grammer_range = grammer_range,
	}
end

--- 获取ts_cache缓存表
--- @param win integer
function F.get_ts_cache(win)
	return runtime.ts_cache[win]
end

--- 删除ts_cache缓存
--- @param win integer
function F.del_ts_cache(win)
	runtime.ts_cache[win] = nil
end

--- 初始化Method_cache表
--- @param win integer
--- @param in_comment boolean
--- @param in_sync boolean
--- @return nil
function F.init_method_cache(win, in_comment, in_sync)
	local state
	if in_comment then
		state = "other"
	else
		state = "en"
	end

	runtime.method_cache[win] = {
		state = state,
		in_sync = in_sync,
	}
end

--- 获取Method_cache
--- @param win integer
function F.get_method_cache(win)
	return runtime.method_cache[win]
end

--- 设置method_cache状态
--- 当in_sync为nil时,自动更新state与in_sync属性
--- @param win integer
--- @param in_comment boolean
--- @param in_sync boolean | nil
--- @return nil
function F.set_method_cache(win, in_comment, in_sync)
	local state
	if in_comment then
		state = "other"
	else
		state = "en"
	end
	local cache = F.get_method_cache(win)

	if in_sync == nil then
		if state ~= cache.state then
			cache.state = state
			cache.in_sync = false
		end
	else
		cache.state = state
		cache.in_sync = in_sync
	end
end

--- 删除method_cache缓存
--- @param win integer
--- @return nil
function F.del_method_cache(win)
	runtime.method_cache[win] = nil
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
