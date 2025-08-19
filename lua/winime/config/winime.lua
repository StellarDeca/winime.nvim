---- Winime 核心配置 -----

--- @class winime
--- @field winime_core winime_core
--- @field user_config user_config
--- @field input_method input_method
--- @field comment_symbols CommentSymbols
local winime = {}

--- @class winime_core
--- @field winime_version string Winime版本
--- @field nvim_version string Neovim最低版本
--- @field notify boolean 插件通知
--- @field user_language string 用户语言
--- @field grammer_analysis_mode "String" | "TreeSitter" | "Auto" 语法分析模式
--- @field method_auto_detect boolean 首次启动时自动进行输入法区域ID检测
winime.winime_core = {
	winime_version = "1.0.0",
	nvim_version = "0.10.0",
	notify = true,
	user_language = "chinese",
	grammer_analysis_mode = "Auto",
	method_auto_detect = true,
}

--- @calss language
--- @type table<string, string>
winime.language = {}

--- @class nvim_enter_method_change NeovimEnter输入法切换功能
--- @field max_retry number 最长延时执行时长,ms
--- @field nvim_enter boolean 功能开关
---
--- @class nvim_insert_mode_change Insert输入法切换功能
--- @field insert_enter boolean 进入插入模式功能开关
--- @field insert_leave boolean 离开插入模式功能开关
---
--- @class nvim_insert_input_analysis 输入分析功能,依赖InsertEnter与InsertLeave事件
--- @field max_char_cache integer 输入分析最大缓存字符数
--- @field max_postpone_time number 最长延时分析时间
--- @field input_analysis boolean 输入分析功能开关
---
--- @class nvim_insert_cursor_moved_analysis
--- @field max_postpone_time number 最长延时分析时间
--- @field cursor_moved_analysis boolean 插入模式光标功能开关
---
--- @class user_config
--- @field nvim_enter_method_change nvim_enter_method_change
--- @field nvim_insert_mode_change nvim_insert_mode_change
--- @field nvim_insert_input_analysis nvim_insert_input_analysis
--- @field nvim_insert_cursor_moved_analysis nvim_insert_cursor_moved_analysis
--- @type user_config
winime.user_config = {
	nvim_enter_method_change = {
		max_retry = 50,
		nvim_enter = true,
	},

	nvim_insert_mode_change = {
		insert_enter = true,
		insert_leave = true,
	},

	nvim_insert_input_analysis = {
		max_char_cache = 2000,
		max_postpone_time = 280,
		input_analysis = true,
	},

	nvim_insert_cursor_moved_analysis = {
		max_postpone_time = 280,
		cursor_moved_analysis = true,
	},
}

--- @class input_method
--- @field im_tool_path string im-select工具的相对路径
--- @field im_id { en: integer, other: integer }
--- @field im_candiates_id {
---		en: integer[],
---		other: integer[] } 候选输入法ID
winime.input_method = {
	im_tool_path = "lua/winime/tools/im-select.exe",
	im_id = {
		en = 1033,
		other = 2052,
	},

	im_candiates_id = {
		en = {
			1033,
			2057,
			3081,
			4105,
			5129,
			0,
		},

		other = {
			307,
			1025,
			1028,
			1031,
			1034,
			1036,
			1037,
			1038,
			1039,
			1040,
			1041,
			1042,
			1043,
			1044,
			1045,
			1046,
			1047,
			1048,
			1049,
			1050,
			1051,
			1052,
			1053,
			1054,
			1055,
			2052,
		},
	},
}

--- @class CommentSymbols
--- @field line table<string> 单行注释起始符号
--- @field block table<string, string> 多行注释起始符号
--- @field block_is_string boolean 多行注释是否视为字符串(仅仅在String分析模式生效)
---
--- @type table<string, CommentSymbols>
winime.comment_symbols = {
	-- Lua
	lua = {
		line = { "--" },
		block = {
			["--[["] = "]]",
			["--[=["] = "]=]",
			["--[==["] = "]==]",
			["--[===["] = "]===]",
		},
		block_is_string = false,
	},

	-- Python
	python = {
		line = { "#" },
		block = {
			['"""'] = '"""',
			["'''"] = "'''",
		},
		block_is_string = false,
	},

	-- C / C++ / Java / C# / Go / Rust / Swift 等 C 风格语言
	c = {
		line = { "//" },
		block = { ["/*"] = "*/" },
		block_is_string = false,
	},
	cpp = {
		line = { "//" },
		block = { ["/*"] = "*/" },
		block_is_string = false,
	},
	java = {
		line = { "//" },
		block = { ["/*"] = "*/" },
		block_is_string = false,
	},
	cs = {
		line = { "//" },
		block = { ["/*"] = "*/" },
		block_is_string = false,
	},
	go = {
		line = { "//" },
		block = { ["/*"] = "*/" },
		block_is_string = false,
	},
	rust = {
		line = { "//" },
		block = { ["/*"] = "*/" },
		block_is_string = false,
	},
	swift = {
		line = { "//" },
		block = { ["/*"] = "*/" },
		block_is_string = false,
	},

	-- JavaScript / TypeScript
	javascript = {
		line = { "//" },
		block = { ["/*"] = "*/" },
		block_is_string = false,
	},
	typescript = {
		line = { "//" },
		block = { ["/*"] = "*/" },
		block_is_string = false,
	},

	-- Shell / Bash / sh / zsh
	sh = {
		line = { "#" },
		block = {}, -- 无标准多行注释
		block_is_string = false,
	},
	bash = {
		line = { "#" },
		block = {},
		block_is_string = false,
	},
	zsh = {
		line = { "#" },
		block = {},
		block_is_string = false,
	},

	-- SQL
	sql = {
		line = { "--" },
		block = { ["/*"] = "*/" },
		block_is_string = false,
	},

	-- HTML / XML
	html = {
		line = {},
		block = { ["<!--"] = "-->" },
		block_is_string = false,
	},
	xml = {
		line = {},
		block = { ["<!--"] = "-->" },
		block_is_string = false,
	},

	-- Markdown (仅行注释 = none, 但可定义为 html comment)
	markdown = {
		line = {},
		block = { ["<!--"] = "-->" },
		block_is_string = false,
	},

	-- YAML / TOML / JSON
	yaml = {
		line = { "#" },
		block = {},
		block_is_string = false,
	},
	toml = {
		line = { "#" },
		block = {},
		block_is_string = false,
	},

	-- PHP
	php = {
		line = { "//", "#" },
		block = { ["/*"] = "*/" },
		block_is_string = false,
	},
}

return winime
