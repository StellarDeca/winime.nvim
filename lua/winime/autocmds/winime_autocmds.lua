-----== Winime Auto Cmds ==-----

local F = {}
local Orc = {}
local Logger = require("winime.tools.logger")
local RunTime = require("winime.space.orchestrator_runtime")
local StringAutoCmdsCallback = require("winime.autocmds.string_analysis_listen")
local TreeSitterAutoCmdsCallback = require("winime.autocmds.tree_sitter_analysis_liten")
local WinimeCoreAutoCmdGroup = vim.api.nvim_create_augroup("WinimeAutoAnalysis", { clear = true })
F.winime_autocmds_group = WinimeCoreAutoCmdGroup

--[[
统一管理缓存与标志位,同时按照固定的顺序去执行功能
给每个窗口都设置一个 协调器
按照 -> TextChangedI -> CurSorMovedI 去触发事件,同时维护更新重置所有的标志位

每个事件都有自己的handler, 去延时调用业务逻辑
在handler中去调用统一的orchestrator,保证业务逻辑按照顺序执行
--]]

--- Orc立即事件回调函数表
--- @type { [string]: function }
Orc.immediate_callback = {}

--- Orc延迟事件回调函数表
--- @type { [string]: function }
Orc.schedule_callback = {}

--- 重置orc自动命令标志
function Orc.re_set_orc_flags(win)
	vim.schedule(function()
		RunTime.get_orc_cache(win).events = {}
	end)
end

--- 协调器卸载函数-执行立即执行命令后删除所有延时执行任务
function Orc.unload_orc_immediate()
	local win = vim.api.nvim_get_current_win()
	RunTime.stop_orc_timer_all(win)
end

--- 协调器缓存初始化函数-初始化协调器
--- 仅仅在协调器缓存不存在时初始化
function Orc.init_orc_cache_immediate()
	local win = vim.api.nvim_get_current_win()
	if RunTime.get_orc_cache(win) == nil then
		RunTime.init_orc_cache(win)
	end
end

--- 协调器缓存删除-停掉所有的延时任务并删除缓存
function Orc.del_orc_cache_immediate()
	local win = vim.api.nvim_get_current_win()
	RunTime.stop_orc_timer_all(win)
	RunTime.del_orc_cache(win)
end

--- 协调器任务分配函数
--- @param ev table 事件表
--- @param max_time number
--- @param opts table 参数表
function Orc.schedule_orc(ev, max_time, opts)
	local win = vim.api.nvim_get_current_win()

	--- 不存在协调器缓存则初始化
	Orc.init_orc_cache_immediate()

	--- 设置状态标记
	RunTime.get_orc_cache(win).events[ev.event] = true

	--- 执行立即执行任务
	if Orc.immediate_callback[ev.event] ~= nil then
		Orc.run_orc_immediate(ev, win, opts)
	end

	--- 执行延迟执行任务
	if Orc.schedule_callback[ev.event] ~= nil then
		local timer_key = "Orchestrator"
		RunTime.stop_orc_timer(win, timer_key)
		RunTime.set_orc_timer(win, timer_key, max_time, Orc.run_orc_schedule, { ev, win, opts })
	end

	--- 记录RunTime cache
	local runtime = Orc.immediate_callback["GetRunTime"]()
	if vim.api.nvim_get_mode() == "n" then
		Logger.write_log(nil, "RunTime Cache", "Orchestrator Schedile", runtime)
	end

	--- 清除标记状态
	Orc.re_set_orc_flags(win)
end

--- 协调器主函数-立即事件处理
--- @param ev table 事件表
--- @param win integer
--- @param opts table 参数表
function Orc.run_orc_immediate(ev, win, opts)
	--- 按照事件类型执行对应的事件函数
	local callback = Orc.immediate_callback[ev.event]
	callback(win, opts)
end

--- 协调器主函数-延迟执行
--- @param ev table 事件表
--- @param win integer
--- @param opts table 参数表
function Orc.run_orc_schedule(ev, win, opts)
	local orc_cache = RunTime.get_orc_cache(win)
	if orc_cache.busy then
		return nil
	end
	orc_cache.busy = true

	local callback = Orc.schedule_callback[ev.event]
	callback(win, opts)

	orc_cache.busy = false
end

--- 监听BUfEnter事件,自动选择TreeSitter或String分析方式
--- @param winime table winime配置表
function F.nvim_buf_enter_listen(winime)
	local analysis_mode = winime.winime_core.grammer_analysis_mode

	if analysis_mode == "String" then
		---== String 分析模式
		Orc.immediate_callback = StringAutoCmdsCallback.immediate_callback
		Orc.schedule_callback = StringAutoCmdsCallback.schedule_callback
	elseif analysis_mode == "TreeSitter" then
		---== TreeSitter 分析模式
		Orc.immediate_callback = TreeSitterAutoCmdsCallback.immediate_callback
		Orc.schedule_callback = TreeSitterAutoCmdsCallback.schedule_callback
	elseif analysis_mode == "Auto" then
		--- 监听BufEnter事件
		--- TreeSitter可用时使用TreeSitter分析
		local switch = "String"
		Orc.immediate_callback = StringAutoCmdsCallback.immediate_callback
		Orc.schedule_callback = StringAutoCmdsCallback.schedule_callback

		vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPost" }, {
			group = WinimeCoreAutoCmdGroup,
			callback = function(ev)
				local ts_parsers = require("nvim-treesitter.parsers")
				local ft = vim.bo[ev.buf].filetype
				local parser_name = ts_parsers.ft_to_lang(ft)

				if ts_parsers.has_parser(parser_name) then
					if switch ~= "TreeSitter" then
						--- 切换到TreeSitter分析
						switch = "TreeSitter"
						Orc.immediate_callback = TreeSitterAutoCmdsCallback.immediate_callback
						Orc.schedule_callback = TreeSitterAutoCmdsCallback.schedule_callback
					end
				else
					if switch ~= "String" then
						--- TreeSitter未安装或不可用
						--- 使用String分析
						switch = "String"
						Orc.immediate_callback = StringAutoCmdsCallback.immediate_callback
						Orc.schedule_callback = StringAutoCmdsCallback.schedule_callback
					end
				end
			end,
		})
	else
		vim.notify("无效的模式配置!")
	end
end

----- 在进入 Neovim 时将输入法切换到英文 -----
--- @param max_retry number 最大重试次数
--- @param im_id { en: integer, other: integer } 输入法区域ID
--- @param im_tool_path string im-select工具路径
--- @return nil
function F.nvim_enter_listen(max_retry, im_id, im_tool_path)
	vim.api.nvim_create_autocmd("VimEnter", {
		group = WinimeCoreAutoCmdGroup,
		callback = function(ev)
			Orc.schedule_orc(ev, 0, {
				max_retry = max_retry,
				im_id = im_id,
				im_tool_path = im_tool_path,
			})
		end,
	})
end

----- 监听 Neovim的 Normal CursorMoved 事件 -----
--- 在进入Insert模式之前更新Cursor位置,Insert模式内移动光标则不会触发此自动命令
--- @return nil
function F.nvim_normal_cursor_moved_listen()
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = WinimeCoreAutoCmdGroup,
		callback = function(ev)
			Orc.schedule_orc(ev, 0, {})
		end,
	})
end

----- 监听 Neovim 的 InsertEnter 事件 -----
--- @param comment_symbols table<string, {
--- line: table<string>,
--- block: table<string, string>,
--- block_is_string: boolean }>
--- @param im_id { en: integer, other: integer } 输入法区域ID表
--- @param im_tool_path string im-selsect工具路径
--- @return nil
function F.nvim_insert_enter_listen(comment_symbols, im_id, im_tool_path)
	vim.api.nvim_create_autocmd("InsertEnter", {
		group = WinimeCoreAutoCmdGroup,
		callback = function(ev)
			Orc.schedule_orc(ev, 0, {
				comment_symbols = comment_symbols,
				im_id = im_id,
				im_tool_path = im_tool_path,
			})
		end,
	})
end

----- 监听 Neovim TextChangedI 模式,同时针对补全做特殊处理 -----
--- @param comment_symbols table<string, {
--- line: table<string>,
--- block: table<string, string>,
--- block_is_string: boolean,
--- line_nodes: string[],
--- block_nodes: string[] }>
--- @param max_history_len integer 最长输入缓存字符数
--- @param max_time number 最长延时执行时间
--- @param im_id { en: integer, other: integer } 输入法区域ID
--- @param im_tool_path string im-select工具路径
--- @return nil
function F.nvim_insert_input_analysis_listen(comment_symbols, max_history_len, max_time, im_id, im_tool_path)
	vim.api.nvim_create_autocmd({ "TextChangedI" }, {
		group = WinimeCoreAutoCmdGroup,
		callback = function(ev)
			--- 设置延迟执行输入语法分析
			Orc.schedule_orc(ev, max_time, {
				comment_symbols = comment_symbols,
				max_history_len = max_history_len,
				im_id = im_id,
				im_tool_path = im_tool_path,
			})
		end,
	})
end

----- 监听 CursorMovedI 模式事件 -----
--- 在insert模式内移动光标触发,判断光标位置是否超出了input_history的缓存范围
--- @param comment_symbols table<string, {
--- line: table<string>,
--- block: table<string, string>,
--- block_is_string: boolean,
--- line_nodes: string[],
--- block_nodes: string[] }>
--- @param max_time number
--- @param im_id { en: integer, other: integer } 输入法区域ID
--- @param im_tool_path string im-select工具路径
--- @return nil
function F.nvim_insert_cursor_moved_liten(comment_symbols, max_time, im_id, im_tool_path)
	vim.api.nvim_create_autocmd("CursorMovedI", {
		group = WinimeCoreAutoCmdGroup,
		callback = function(ev)
			Orc.schedule_orc(ev, max_time, {
				comment_symbols = comment_symbols,
				im_id = im_id,
				im_tool_path = im_tool_path,
			})
		end,
	})
end

----- 监听 Neovim Insert 模式退出事件 -----
--- 退出Insert模式时将输入法切换到英文,并清除缓存,同时更新cursor缓存
--- @param comment_symbols table<string, {
--- line: table<string>,
--- block: table<string, string>,
--- block_is_string: boolean,
--- line_nodes: string[],
--- block_nodes: string[] }>
--- @param im_id { en: integer, other: integer } 输入法区域ID
--- @param im_tool_path string im-select工具路径
function F.nvim_insert_leave_listen(comment_symbols, im_id, im_tool_path)
	vim.api.nvim_create_autocmd("InsertLeave", {
		group = WinimeCoreAutoCmdGroup,
		callback = function(ev)
			Orc.schedule_orc(ev, 0, {
				comment_symbols = comment_symbols,
				im_id = im_id,
				im_tool_path = im_tool_path,
			})

			--- 卸载协调器
			Orc.del_orc_cache_immediate()
		end,
	})
end

return F
