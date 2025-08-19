----- Winime 入口文件 ----

local M = {}
local Files = require("winime.tools.files")
local Logger = require("winime.tools.logger")
local AutoCmds = require("winime.autocmds.winime_autocmds")

----------------
-- Winime 工具函数
----------------

--- 合并用户配置与Winime配置
--- @param opts table 用户配置
function M.mearge_user_config(opts)
	local cfg = require("winime.config.winime")
	opts = opts or {}

	local res = vim.tbl_deep_extend("force", {}, cfg, opts)

	-- 加载语言选项
	res.language = require("winime.language." .. res.winime_core.user_language)

	-- 配置im-select工具完整路径
	local plugin_path = vim.api.nvim_get_runtime_file("lua/winime/init.lua", false)[1]
	local root_path = vim.fn.fnamemodify(plugin_path, ":p:h:h:h")
	local tool_path = res.input_method.im_tool_path
	res.input_method.im_tool_path = vim.fn.expand(root_path .. "/" .. tool_path)

	return res
end

--- 读取配置缓存
--- 进行初始化设置与缓存保存
--- @param opts table
--- @return table
function M.init_config(opts)
	--- 查看是否存在配置缓存
	local result

	-- 缓存路径
	local cache_path = vim.fn.stdpath("data")
	local user_cfg_path = cache_path .. "/winime/user_config.lua"
	local winime_cfg_path = cache_path .. "/winime/winime_config.lua"

	-- 读取缓存
	local user_cfg = Files.read_lua_file(user_cfg_path)
	local winime_cfg = Files.read_lua_file(winime_cfg_path)

	-- 判断是否需要重新配置
	local need_reconfig = vim.tbl_isempty(user_cfg) or vim.tbl_isempty(winime_cfg) or not vim.deep_equal(opts, user_cfg)
	if need_reconfig then
		--- 合并配置并保存文件
		result = M.mearge_user_config(opts)
	else
		result = winime_cfg
	end

	-- 查看Neovim版本是否符合要求
	if not vim.version.ge(vim.version(), result.winime_core.nvim_version) then
		vim.notify(result.language.nvim_version_slow, vim.log.levels.WARN)
	end

	local need_autostart = result.winime_core.method_auto_detect or vim.tbl_isempty(result.input_method.im_id)
	if need_autostart then
		vim.notify(result.language.method_auto_detect_start, vim.log.levels.WARN)

		result.winime_core.method_auto_detect = false
		local AutoStart = require("winime.apis.method_auto_detect")
		local res, im_id =
			AutoStart.auto_get_input_method(result.input_method.im_tool_path, result.input_method.im_candiates_id)

		if res then
			vim.notify(result.language.method_auto_detect_success, vim.log.levels.WARN)
			result.input_method.im_id = im_id
		else
			vim.notify(result.language.method_auto_detect_error, vim.log.levels.ERROR)
		end
	end

	-- 仅在必要时保存配置
	if need_reconfig or need_autostart then
		Files.save_lua_file(winime_cfg_path, result)
		Files.save_lua_file(user_cfg_path, opts)
	end

	return result
end

------=========-------
--- 初始化Winime
------=========-------

--- @param opts table 用户配置表
--- @return nil
function M.setup(opts)
	local winime = M.init_config(opts)
	M.winime = winime

	--- 记录winime启动
	Logger.set_level("INFO")
	Logger.set_notify(winime.winime_core.notify)
	Logger.write_log(nil, "Winime Enter", "Winime init.lua")

	--- 启用自动命令
	local uc = winime.user_config

	-- 根据配置选择分析工具
	AutoCmds.nvim_buf_enter_listen(winime)

	--- CursorMoved 事件监听
	AutoCmds.nvim_normal_cursor_moved_listen()

	if uc.nvim_enter_method_change.nvim_enter then
		-- VimEnter 事件监听
		AutoCmds.nvim_enter_listen(
			uc.nvim_enter_method_change.max_retry,
			winime.input_method.im_id,
			winime.input_method.im_tool_path
		)
	end

	if uc.nvim_insert_mode_change.insert_enter then
		-- InsertEnter 事件监听
		AutoCmds.nvim_insert_enter_listen(
			winime.comment_symbols,
			winime.input_method.im_id,
			winime.input_method.im_tool_path
		)
	end

	if uc.nvim_insert_mode_change.insert_leave then
		--- InsertLeave事件
		AutoCmds.nvim_insert_leave_listen(
			winime.comment_symbols,
			winime.input_method.im_id,
			winime.input_method.im_tool_path
		)
	end

	if uc.nvim_insert_input_analysis.input_analysis then
		--- TextChangedI 事件处理
		AutoCmds.nvim_insert_input_analysis_listen(
			winime.comment_symbols,
			uc.nvim_insert_input_analysis.max_char_cache,
			uc.nvim_insert_input_analysis.max_postpone_time,
			winime.input_method.im_id,
			winime.input_method.im_tool_path
		)
	end

	if uc.nvim_insert_cursor_moved_analysis.cursor_moved_analysis then
		--- CursorMovedI 事件处理
		AutoCmds.nvim_insert_cursor_moved_liten(
			winime.comment_symbols,
			uc.nvim_insert_cursor_moved_analysis.max_postpone_time,
			winime.input_method.im_id,
			winime.input_method.im_tool_path
		)
	end

	require("nvim-treesitter")
end

return M
