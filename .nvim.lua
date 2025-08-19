return {
	library = {
		vimruntime = true,
		runtime = true,
		"plenary.nvim",
		{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
	},

	integrations = {
		cmp = true,
		lspconfig = true,
	},
}
