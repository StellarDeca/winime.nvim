local Tools = {}

--- 输入法命令
--- @param tool_path string
--- @param tar_id integer | nil
--- @return vim.SystemCompleted
function Tools.im_cmd(tool_path, tar_id)
	local res
	if tar_id == nil then
		res = vim.system({ tool_path }, { text = true }):wait(50)
	else
		res = vim.system({ tool_path, tostring(tar_id) }, { text = true }):wait(50)
	end
	return res
end

--- 获取当前的输入法区域ID
--- @param tool_path string
--- @return integer | nil
function Tools.get_input_method(tool_path)
	local res = Tools.im_cmd(tool_path, nil)
	if res.code == 0 and res.stderr == "" then
		local result = res.stdout:gsub("%s+$", "")
		return tonumber(result)
	else
		return nil
	end
end

--- 切换到制定的输入法
--- @param tool_path string
--- @param tar_id integer
--- @return boolean
function Tools.change_input_method(tool_path, tar_id)
	local old_id = Tools.get_input_method(tool_path)

	if old_id == tar_id then
		return true
	else
		Tools.im_cmd(tool_path, tar_id)
		local new_id = Tools.get_input_method(tool_path)

		if old_id == nil or new_id == nil then
			return false
		else
			return old_id == new_id
		end
	end
end

--- 判断im-select工具存在性
--- @param tool_path string
--- @return boolean
function Tools.check_im_tool_exists(tool_path)
	if vim.fn.executable(tool_path) == 0 then
		return false
	else
		return true
	end
end

return Tools
