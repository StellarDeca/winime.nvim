-----== Winime 日志模块 ==-----

local logger = {}
logger._notify = true
logger._level = "INFO"
logger._max_size_bytes = 1024 * 1024 * 4
logger._log_dir = vim.fn.stdpath("data") .. "/winime"
logger._log_file = logger._log_dir .. "/winime.log"
logger.levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 }

local function upper(s)
	return (s or ""):upper()
end

--- 设置日志级别
--- @param level "ERROR" | "INFO" | "WARN" | "DEBUG"
function logger.set_level(level)
	local L = upper(level or "INFO")
	logger._level = L
end

--- 设置日志是否通知
--- @param enable boolean
function logger.set_notify(enable)
	logger._notify = enable
end

--- 获取日志事件时间
--- @return string | osdate
local function timestamp()
	return os.date("%Y-%m-%d %H:%M:%S")
end

--- 确保日志路径是否存在
--- 路径不存在自动创建
local function ensure_log_dir()
	local dir = logger._log_file:match("^(.+)/[^/]+$")
	if dir and vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
end

--- 日志通知函数
--- @param msg string
--- @param level "ERROR" | "INFO" | "WARN" | "DEBUG"
local function log_notify(msg, level)
	if logger._notify then
		vim.notify(msg, vim.log.levels[level])
	end
end

--- 序列化TSnode数据
--- @param node TSNode
--- @return string
local function format_tsnode(node)
	if not node then
		return "<NilTSNode>"
	end

	local node_type = node:type()
	local start_row, start_col, end_row, end_col = node:range()
	local node_text = require("nvim-treesitter.ts_utils").get_node_text(node, 0) or {}
	local child_count = node:child_count()

	return vim.inspect({
		node_type = node_type,
		child_count = child_count,
		node_text = node_text,
		node_range = {
			start_row = start_row,
			start_col = start_col,
			end_row = end_row,
			end_col = end_col,
		},
	}, { indent = "    " })
end

--- 格式化extra表
--- @param data any
--- @return string
local function serialize_data(data)
	if type(data) == "userdata" then
		return format_tsnode(data)
	elseif type(data) == "table" then
		--- 检查是否为UserData数组
		if vim.islist(data) then
			local result = ""
			for _, v in ipairs(data) do
				if type(v) == "userdata" then
					result = result .. format_tsnode(v) .. "\n"
				else
					result = result .. vim.inspect(v) .. "\n"
				end
			end
			return result
		else
			return vim.inspect(data, { indent = "    " })
		end
	else
		return vim.inspect(data, { indent = "    " })
	end
end

--- 日志轮转,当日志大小超过限制后,删除老旧日志,备份当前日志并创建新的日治文件
local function log_rotate()
	-- 检查日志文件是否存在
	if vim.fn.filereadable(logger._log_file) ~= 1 then
		return
	end

	-- 获取文件大小（字节）
	local stat = vim.fn.getfsize(logger._log_file)
	if stat <= logger._max_size_bytes then
		return
	end

	-- 定义旧日志文件名
	local old_log = logger._log_file .. ".old.log"

	-- 删除已存在的旧日志
	if vim.fn.filereadable(old_log) == 1 then
		vim.fn.delete(old_log)
	end

	-- 重命名当前日志为旧日志
	vim.fn.rename(logger._log_file, old_log)

	-- 创建新的空日志文件（立即写入头信息）
	vim.fn.writefile({ "# Log rotated at: \n" .. os.date() }, logger._log_file)
end

--- 写入内容到日志文件
--- @param data string
local function write_file(data)
	ensure_log_dir()
	log_rotate()

	local f = io.open(logger._log_file, "a+")
	if not f then
		vim.fn.writefile({ "# Log rotated at: \n" .. os.date() }, logger._log_file)
		return
	end
	f:write(data .. "\n")
	f:close()
end

--- 格式化行文本
--- @param level "ERROR" | "INFO" | "WARN" | "DEBUG"
--- @param msg string 日志信息
--- @param component nil | string 组件名
--- @param extra any 额外内容
local function format_log_data(level, msg, component, extra)
	local comp = component or ""
	local lvl = level
	local time = timestamp()
	local pid = tostring(vim.fn.getpid())
	local extra_s = serialize_data(extra) or ""

	return table.concat({
		time,
		lvl,
		comp,
		"(pid:" .. pid .. ")",
		"\n" .. msg .. "\n",
		"" .. extra_s,
	}, "	")
end

-- public API
--- @param level nil | "ERROR" | "INFO" | "WARN" | "DEBUG"
--- @param msg string 日志信息
--- @param component nil | string 组件名
--- @param extra any 额外内容
function logger.write_log(level, msg, component, extra)
	if level == nil then
		level = logger._level
	end

	local log_data = format_log_data(level, msg, component, extra)

	--- 保存文件内容
	write_file(log_data)

	--- 自动显示级别在WARN及以上的日志内容
	if level == "ERROR" or level == "WARN" then
		log_notify(msg, level)
	end
end

return logger
