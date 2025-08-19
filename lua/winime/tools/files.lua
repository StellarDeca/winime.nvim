local F = {}

--- 查看当前文件类型是否可用
--- @param ft_available table<string, any>
--- @return boolean
--- 文件可用时返回true
function F.filetype_available(ft_available)
	local filetype = vim.bo.filetype
	for ft, _ in pairs(ft_available) do
		if ft == filetype then
			return true
		end
	end
	return false
end

--- 排除制定类型的文件
--- @param ft_deny table<string>
--- @return boolean
--- 文件被排除时返回true
function F.filetype_deny(ft_deny)
	local filetype = vim.bo.filetype
	for _, ft in ipairs(ft_deny) do
		if ft == filetype then
			return true
		end
	end
	return false
end

--- 读取l并运行lua文件,返回lua文件的返回值
--- @param cache_path string 缓存路径
--- @return table
function F.read_lua_file(cache_path)
	local flag, res = pcall(dofile, cache_path)
	if flag and type(res) == "table" then
		return res
	else
		return {}
	end
end

--- 写入保存lua文件
--- @param cache_path string 缓存路径
--- @param data table 插件配置表
--- @return nil
function F.save_lua_file(cache_path, data)
	-- 确保缓存路径存在
	vim.fn.mkdir(vim.fn.fnamemodify(cache_path, ":h"), "p")
	local f = io.open(cache_path, "w")
	if f then
		f:write("return " .. vim.inspect(data))
		f:close()
	end
end

return F
