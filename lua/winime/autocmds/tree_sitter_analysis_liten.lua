-----== Winime TreeSitter 自动化命令 ==------

local Orc = {}
local Files = require("winime.tools.files")
local Method = require("winime.tools.method")
local RunTime = require("winime.space.tree_sitter_anslysis_runtime")
local CommentDetect = require("winime.apis.tree_sitter_comment_detect")

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
	初始化Runtime symbols 表 ts 表 method 表
	--]]
	local filetype = vim.bo.filetype
	local bufnr = vim.api.nvim_win_get_buf(win)
	if vim.tbl_isempty(RunTime.get_cursor_cache(win, "n")) then
		RunTime.init_cursor_cache(win, "n")
	end
	RunTime.set_cursor_cache(win, "i")
	RunTime.init_symbol_cache(win, opts.comment_symbols[filetype])

	local in_comment, root_node, grammer_range = CommentDetect.comment_detect_tree_sitter_analysis(win, nil)

	RunTime.init_ts_cache(win, vim.api.nvim_buf_get_changedtick(bufnr), root_node, in_comment, grammer_range)
	RunTime.init_method_cache(win, in_comment, true)

	if in_comment then
		Method.change_input_method(opts.im_tool_path, opts.im_id.other)
	else
		Method.change_input_method(opts.im_tool_path, opts.im_id.en)
	end
end

--- Neovim Insert Leave事件
Orc.immediate_callback["InsertLeave"] = function(win, opts)
	if not Files.filetype_available(opts.comment_symbols) then
		Method.change_input_method(opts.im_tool_path, opts.im_id.en)
		return nil
	end

	--- 删除并更新状态
	RunTime.del_ts_cache(win)
	RunTime.del_method_cache(win)
	RunTime.del_cursor_cache(win)
	RunTime.del_symbols_cache(win)

	RunTime.set_cursor_cache(win, "n")

	Method.change_input_method(opts.im_tool_path, opts.im_id.en)
end

--- NeedComment 事件
Orc.schedule_callback["NeedComment"] = function(win)
	local in_comment, root_node, grammer_range = CommentDetect.comment_detect_tree_sitter_analysis(win, nil)

	--- 更新ts_cache 与 method_cache
	local ts_cache = RunTime.get_ts_cache(win)
	local grammer_state
	if in_comment then
		grammer_state = "comment"
	else
		grammer_state = "code"
	end
	ts_cache.grammer_state = grammer_state
	ts_cache.root_node = root_node
	ts_cache.grammer_range = grammer_range

	RunTime.set_method_cache(win, in_comment, nil)
end

--- MethodChanged事件
Orc.schedule_callback["MethodChangedI"] = function(win, im_tool_path, im_id)
	--- 根据语法状态统一切换输入法状态,仅仅在状态更新后进行输入法的更新
	local ts_cache = RunTime.get_ts_cache(win)
	local method_cache = RunTime.get_method_cache(win)

	local method_state
	if ts_cache.grammer_state == "code" then
		method_state = "en"
	else
		method_state = "other"
	end

	if not method_cache.in_sync then
		if method_state == "en" then
			Method.change_input_method(im_tool_path, im_id.en)
		else
			Method.change_input_method(im_tool_path, im_id.other)
		end

		method_cache = {
			state = method_state,
			in_sync = true,
		}
	end
end

--- Neovim TextChangedI 事件
Orc.schedule_callback["TextChangedI"] = function(win, opts)
	if not Files.filetype_available(opts.comment_symbols) then
		return nil
	end

	--- 判断文件是否进行了更改
	--- 文件未进行更改则直接使用已有的comennt_matches
	local ts_cache = RunTime.get_ts_cache(win)
	local bufnr = vim.api.nvim_win_get_buf(win)
	local buf_changed_tick = vim.api.nvim_buf_get_changedtick(bufnr)

	if buf_changed_tick == ts_cache.file_ticked then
		local in_comment, root_node, grammer_range =
			CommentDetect.comment_detect_tree_sitter_analysis(win, ts_cache.root_node)

		--- 更新状态
		local grammer_state
		if in_comment then
			grammer_state = "comment"
		else
			grammer_state = "code"
		end
		ts_cache.grammer_state = grammer_state
		ts_cache.root_node = root_node
		ts_cache.grammer_range = grammer_range

		RunTime.set_method_cache(win, in_comment, nil)
	else
		Orc.schedule_callback["NeedComment"](win)
		ts_cache.file_ticked = buf_changed_tick
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

	--[[
	判断光标位置是否移出注释块
		1.移出: 判断文件内容变化,尝试使用缓存数据
		2.未移除,只更新光标位置,不做改动
	--]]

	--- 更新光标位置
	RunTime.set_cursor_cache(win, "i")
	local ts_cache = RunTime.get_ts_cache(win)
	local range = ts_cache.grammer_range
	local cursor = RunTime.get_cursor_cache(win, "i").current
	local row, col = cursor.row, cursor.col

	if
		range
		and CommentDetect.cmp_pos(row, col, range.start_row, range.start_col) > 0
		and CommentDetect.cmp_pos(row, col, range.start_row, range.end_col) <= 0
	then
		--- 仍在注释范围内,保持不变
	else
		local bufnr = vim.api.nvim_win_get_buf(win)
		local buf_changed_tick = vim.api.nvim_buf_get_changedtick(bufnr)

		if buf_changed_tick == ts_cache.file_ticked then
			local in_comment, root_node, grammer_range =
				CommentDetect.comment_detect_tree_sitter_analysis(win, ts_cache.root_node)

			--- 更新状态
			local grammer_state
			if in_comment then
				grammer_state = "comment"
			else
				grammer_state = "code"
			end
			ts_cache.grammer_state = grammer_state
			ts_cache.root_node = root_node
			ts_cache.grammer_range = grammer_range

			RunTime.set_method_cache(win, in_comment, nil)
		else
			Orc.schedule_callback["NeedComment"](win)
			ts_cache.file_ticked = buf_changed_tick
		end
	end

	--- 回调MethodChangedI
	Orc.schedule_callback["MethodChangedI"](win, opts.im_tool_path, opts.im_id)
end

return Orc
