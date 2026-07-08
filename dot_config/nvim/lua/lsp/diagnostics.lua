-- Diagnostic設定

vim.diagnostic.config({
	virtual_text = false,
	signs = true,
	underline = true,
	update_in_insert = false,
	severity_sort = true,
	float = {
		border = "rounded",
		source = true,
		format = function(diagnostic)
			local message = diagnostic.message
			local code = diagnostic.code or ""
			local source = diagnostic.source or ""

			-- biomeのルールにドキュメントURLを追加
			if source == "biome" and type(code) == "string" and code:match("/") then
				local url = "https://biomejs.dev/linter/rules/"
					.. code:match("[^/]+$")
						:gsub("(%u)", function(c)
							return "-" .. c:lower()
						end)
						:gsub("^-", "")
				return string.format("%s [%s]\n📖 %s", message, code, url)
			end

			-- TypeScriptエラーコードにドキュメントURLを追加
			if (source == "typescript" or source == "ts") and code then
				local url = "https://typescript.tv/errors/#ts" .. code
				return string.format("%s [TS%s]\n📖 %s", message, code, url)
			end

			if code ~= "" then
				return string.format("%s [%s]", message, code)
			end

			return message
		end,
	},
})
