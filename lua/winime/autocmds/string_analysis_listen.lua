-----== Winime String自动化命令 ==------

local Orc = {}
local Files = require("winime.tools.files")
local Method = require("winime.tools.method")
local RunTime = require("winime.space.string_analysis_runtime")
local CommentDetect = require("winime.apis.string_comment_detect")
local InputIntent = require("winime.apis.string_input_intent")

--- Orc立即事件回调函数表
--- @type { [string]: function }
Orc.immediate_callback = {}

--- Orc延迟事件回调函数表
--- @type { [string]: function }
Orc.schedule_callback = {}

--- 获取RunTime运行缓存数据表
Orc.immediate_callback["GetRunTime"] = function()
	return RunTime.get_runtime_cache()
end

--- Neovim Enter 事件
Orc.immediate_callback["VimEnter"] = function(win, opts)
	local retry = 0
	local stable_count = 0

	--- 延时启动加稳定性检测
	local function ensure_english()
		local current = Method.get_input_method(opts.im_tool_path)

		if current == opts.im_id.en then
			stable_count = stable_count + 1
			if stable_count >= 3 then -- 连续3次都是英文才认为成功
				return
			end
		else
			stable_count = 0
		end

		if retry < opts.max_retry then
			retry = retry + 1
			Method.change_input_method(opts.im_tool_path, opts.im_id.en)
			vim.defer_fn(ensure_english, 200)
		end
	end

	vim.defer_fn(ensure_english, 10)
end

--- Neovim CursorMoved 事件
--- @param win integer
--- @return nil
Orc.immediate_callback["CursorMoved"] = function(win, opts)
	RunTime.set_cursor_cache(win, "n")
end

--- Neovim InsertEnter 事件 -----
Orc.immediate_callback["InsertEnter"] = function(win, opts)
	if not Files.filetype_available(opts.comment_symbols) then
		return nil
	end
	--[[
	判断光标位置是否在注释块内
	初始化Runtime Symbol 表, Input 表
	更新Cursor表
	--]]
	local filetype = vim.bo.filetype
	if vim.tbl_isempty(RunTime.get_cursor_cache(win, "n")) then
		RunTime.init_cursor_cache(win, "n")
	end
	RunTime.set_cursor_cache(win, "i")
	RunTime.init_symbol_cache(win, opts.comment_symbols[filetype])

	local result = CommentDetect.comment_detect_string_analysis(win)
	RunTime.init_input_cache(win, result.grammer_state, result.grammer_info, result.grammer_position, true)

	if result.grammer_state ~= "code" then
		Method.change_input_method(opts.im_tool_path, opts.im_id.other)
	else
		Method.change_input_method(opts.im_tool_path, opts.im_id.en)
	end
end

--- Neovim TextChangedI 事件
Orc.immediate_callback["TextChangedI"] = function(win, opts)
	if not Files.filetype_available(opts.comment_symbols) then
		return nil
	end
	--[[
	延时触发分析以等待输入稳定
	同时针对连续删除操作把缓存清空后
		1.直接再次启用字符串语法分析
		2.根据语法分析语法结果进行输入法的判定
		3.重新初始化Input缓存
	针对补全需要解决:
		1.菜单候选不经确认直接输入
		2.菜单多次选择后补全(包含是否按下<C-y>来确认)
		3.直接确认补全
	--]]
	local cache = RunTime.get_input_cache(win)
	local track_char = InputIntent.track_insert_changes(win)

	--- 更新状态位标志
	cache.first_insert_enter = false
	cache.char_insert = track_char.char_insert
	cache.char_removed = track_char.char_removed
	cache.need_comment = track_char.del_beyond_history_range

	--- 更新光标位置
	RunTime.set_cursor_cache(win, "i")
end

--- Neovim Insert Leave事件
Orc.immediate_callback["InsertLeave"] = function(win, opts)
	if not Files.filetype_available(opts.comment_symbols) then
		Method.change_input_method(opts.im_tool_path, opts.im_id.en)
		return nil
	end
	--- 删除并更新状态
	RunTime.del_input_cache(win)
	RunTime.del_symbols_cache(win)

	RunTime.del_cursor_cache(win)
	RunTime.set_cursor_cache(win, "n")

	Method.change_input_method(opts.im_tool_path, opts.im_id.en)
end

--- NeedComment 事件
Orc.schedule_callback["NeedComment"] = function(win)
	local cd = CommentDetect.comment_detect_string_analysis(win)

	--- 更新input_cache语法状态
	local cache = RunTime.get_input_cache(win)
	cache.need_comment = false
	cache.grammer_state = cd.grammer_state
	cache.grammer_position = cd.grammer_position
	cache.grammer_info = cd.grammer_info
	cache.insert_enter_grammer_state = cd
end

--- MethodChanged事件
Orc.schedule_callback["MethodChangedI"] = function(win, im_tool_path, im_id)
	--- 根据语法状态统一切换输入法状态,仅仅在状态更新后进行输入法的更新
	local cache = RunTime.get_input_cache(win)
	local method_state
	if cache.grammer_state == "code" then
		method_state = "en"
	else
		method_state = "other"
	end

	if method_state ~= cache.method_state.state or not cache.method_state.in_sync then
		if method_state == "en" then
			Method.change_input_method(im_tool_path, im_id.en)
		else
			Method.change_input_method(im_tool_path, im_id.other)
		end
		cache.method_state = {
			state = method_state,
			in_sync = true,
		}
	end

	--- 重置部分状态
	cache.char_insert = false
	cache.char_removed = false
end

--- Neovim TextChangedI 事件
Orc.schedule_callback["TextChangedI"] = function(win, opts)
	if not Files.filetype_available(opts.comment_symbols) then
		return nil
	end
	local cache = RunTime.get_input_cache(win)

	--- 重判光标位置语法状态
	if cache.need_comment then
		Orc.schedule_callback["NeedComment"](win)
	end

	local input_res = InputIntent.insert_input_analysis(win, opts.max_history_len)

	--- 更新CursorMovedI标志
	RunTime.get_input_cache(win).cursor_moved = false
	if input_res.match then
		cache.skip_grammer_offset = true
	end

	--- 更新光标位置
	RunTime.set_cursor_cache(win, "i")

	--- 回调MethodChangedI
	Orc.schedule_callback["MethodChangedI"](win, opts.im_tool_path, opts.im_id)
end

--- Neovim CurSorMovedI 事件
Orc.schedule_callback["CursorMovedI"] = function(win, opts)
	if not Files.filetype_available(opts.comment_symbols) then
		return nil
	end
	local cursor_res, cursor_info = InputIntent.insert_cursor_moved_analysis(win)
	local cache = RunTime.get_input_cache(win)

	--- 更新状态
	cache.need_comment = cursor_res
	cache.cursor_moved = cursor_info.cursor_moved

	--- 更新光标位置
	RunTime.set_cursor_cache(win, "i")

	--- 重判光标位置语法状态
	if cache.need_comment then
		Orc.schedule_callback["NeedComment"](win)
	end

	--- 回调MethodChangedI
	Orc.schedule_callback["MethodChangedI"](win, opts.im_tool_path, opts.im_id)
end

return Orc
