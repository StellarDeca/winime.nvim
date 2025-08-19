----- 注册Winime热重载与卸载指令 -----

--- 卸载winime
vim.api.nvim_create_user_command("WinimeUnload", function()
	-- 删除自动命令
	vim.api.nvim_clear_autocmds({ group = "WinimeAutoAnalysis" })

	-- 删除winime 热重载与卸载指令
	vim.api.nvim_del_user_command("WinimeUnload")
	vim.api.nvim_del_user_command("WinimeReload")

	-- 卸载winime模块文件
	for k in pairs(package.loaded) do
		if k:match("^winime") then
			package.loaded[k] = nil
		end
	end

	vim.notify("Winime unload successful", vim.log.levels.INFO)
end, { desc = "WinimeUnload" })

--- 热重载winime
vim.api.nvim_create_user_command("WinimeReload", function()
	-- 删除自动命令
	vim.api.nvim_clear_autocmds({ group = "WinimeAutoAnalysis" })

	-- 卸载winime模块文件
	for k in pairs(package.loaded) do
		if k:match("^winime") then
			package.loaded[k] = nil
		end
	end

	-- 重新加载winime
	require("winime").setup({})

	vim.notify("Winime reload successful", vim.log.levels.INFO)
end, { desc = "WinimeReload" })

--- 查看Winime支持的文件类型
vim.api.nvim_create_user_command("WinimeFileTypeAvaliable", function()
	local cfg = require("winime").winime
	local result = {}
	for ft, _ in pairs(cfg.comment_symbols) do
		table.insert(result, ft)
	end
	vim.notify(vim.inspect(result), vim.log.levels.INFO)
end, { desc = "WinimeReload" })
