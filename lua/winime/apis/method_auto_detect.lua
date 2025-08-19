-----== 自动在 MethodID 表中查找可用的 Method ID ==-----

local F = {}
local Method = require("winime.tools.method")

--- 自动检测输入法区域ID
--- @param im_candidates_id {
---		en: integer[],
---		other: integer[] } 候选输入法ID
--- @param im_tool_path string
--- @return boolean successful, {
--- 	en: integer,
--- 	other: integer } im_id
function F.auto_get_input_method(im_tool_path, im_candidates_id, language)
	----- 自动探测英文、第二语言输入法(英文输入法最后一定可以探测到0,除非系统不是Windows) -----
	local function get_input_method(im_candidates_ids)
		for _, im_id in ipairs(im_candidates_ids) do
			Method.change_input_method(im_tool_path, im_id)
			if Method.get_input_method(im_tool_path) == im_id then
				return im_id
			end
		end
		return nil
	end

	local english_im_id = get_input_method(im_candidates_id.en)
	local other_im_id = get_input_method(im_candidates_id.other)

	if english_im_id and other_im_id then
		return true, {
			en = english_im_id,
			other = other_im_id,
		}
	else
		return false, {}
	end
end

return F
