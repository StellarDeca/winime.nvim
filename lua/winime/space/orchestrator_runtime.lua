-----== Winime AutoCmds 协调器运行数据 ==-----

local F = {}

--[[
=====================================================================================
	runtime.orchestrator_cache[winid]: {
		----- 协调器标志数据 -----
		events: {
			event: boolean
			...
		}

		timer: {
			timer_key: nil | integer
			..
		}

-------------------------------------------------------------------------------------
		--- 协调器状态标志
		busy: boolean
	}
--]]

local runtime = {}

--- @class orc_cache
--- @field events { [string]: boolean }
--- @field timer { [string]: integer }
--- @field busy boolean
---
--- @type table<integer, orc_cache>
runtime.orchestrator_cache = {}

--- 初始化orc缓存表
--- @param win integer
--- @return nil
function F.init_orc_cache(win)
	runtime.orchestrator_cache[win] = {
		events = {},
		timer = {},
		busy = false,
	}
end

--- 获取orc缓存表
--- @param win integer
function F.get_orc_cache(win)
	local cache = runtime.orchestrator_cache[win]
	if not cache then
		F.init_orc_cache(win)
	end
	return runtime.orchestrator_cache[win]
end

--- 设定orc的timer
--- @param win integer
--- @param key string
--- @param max_time number
--- @param callback function
--- @param args table | nil
--- @return nil
function F.set_orc_timer(win, key, max_time, callback, args)
	local t_cache = runtime.orchestrator_cache[win].timer
	t_cache[key] = vim.fn.timer_start(max_time, function()
		args = args or {}
		callback(unpack(args))
	end)
end

--- 停止orc的timer
--- @param win integer
--- @param key string
--- @return nil
function F.stop_orc_timer(win, key)
	local timer_id = runtime.orchestrator_cache[win].timer[key]
	if timer_id and #vim.fn.timer_info(timer_id) then
		vim.fn.timer_stop(timer_id)
	end
end

--- 停止orc的timer
--- @param win integer
--- @return nil
function F.stop_orc_timer_all(win)
	local timer_ids = runtime.orchestrator_cache[win].timer
	for _, id in pairs(timer_ids) do
		if id and #vim.fn.timer_info(id) then
			vim.fn.timer_stop(id)
		end
	end
end

--- 清除orc的timer
--- @param win integer
--- @param key string
--- @return nil
function F.del_orc_timer(win, key)
	runtime.orchestrator_cache[win].timer[key] = nil
end

--- 清除orc缓存
--- @param win integer
function F.del_orc_cache(win)
	runtime.orchestrator_cache[win] = nil
end

return F
