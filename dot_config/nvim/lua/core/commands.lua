-- カスタムコマンド定義

-- 置換コマンド
vim.api.nvim_create_user_command("Sed", function(opt)
	local args = opt.args
	local words = vim.split(args, " ")
	if #words >= 2 then
		local old = words[1]
		local new = words[2]
		vim.cmd(string.format("%%s/%s/%s/g", old, new))
	end
end, {
	nargs = "*",
	complete = "file",
})

-- パスコピーコマンド
local function strip_uri_scheme(path)
	return path:gsub("^[%a][%w+.-]*://", "")
end

local function line_suffix(opt)
	if opt.range == 0 then
		return ""
	end

	if opt.line1 == opt.line2 then
		return string.format("#L%d", opt.line1)
	end

	return string.format("#L%d-L%d", opt.line1, opt.line2)
end

local function copy_path(kind, opt)
	local path
	if kind == "full" then
		path = strip_uri_scheme(vim.fn.expand("%:p"))
	elseif kind == "relative" then
		local full_path = strip_uri_scheme(vim.fn.expand("%:p"))
		local cwd = vim.fn.getcwd()
		local prefix = cwd .. "/"
		path = vim.startswith(full_path, prefix) and full_path:sub(#prefix + 1) or full_path
	elseif kind == "filename" then
		path = strip_uri_scheme(vim.fn.expand("%:t"))
	end

	path = path .. line_suffix(opt)
	vim.fn.setreg("*", path)
	vim.notify("Copied path: " .. path)
end

vim.api.nvim_create_user_command("Cfp", function(opt)
	copy_path("full", opt)
end, { range = true, desc = "Copy the full path of the current file to the clipboard" })

vim.api.nvim_create_user_command("Crp", function(opt)
	copy_path("relative", opt)
end, { range = true, desc = "Copy the relative path of the current file to the clipboard" })

vim.api.nvim_create_user_command("Cfn", function(opt)
	copy_path("filename", opt)
end, { range = true, desc = "Copy the file name of the current file to the clipboard" })

-- LSP制御コマンド
vim.api.nvim_create_user_command("Nonts", function()
	for _, client in ipairs(vim.lsp.get_clients({ name = "ts_ls" })) do
		client:stop()
	end
end, { desc = "Stop TypeScript LSP server" })

vim.api.nvim_create_user_command("Nondeno", function()
	for _, client in ipairs(vim.lsp.get_clients({ name = "denols" })) do
		client:stop()
	end
end, { desc = "Stop Deno LSP server" })

-- Copilot制御コマンド
vim.api.nvim_create_user_command("Ghcd", function()
	vim.cmd("Copilot disable")
	vim.notify("Copilot disabled")
end, { desc = "Disable GitHub Copilot" })

vim.api.nvim_create_user_command("Ghcn", function()
	vim.cmd("Copilot enable")
	vim.notify("Copilot enabled")
end, { desc = "Enable GitHub Copilot" })

vim.api.nvim_create_user_command("CopilotToggle", function()
	local copilot_status = vim.fn["copilot#Enabled"]()
	if copilot_status == 1 then
		vim.cmd("Copilot disable")
		vim.notify("Copilot disabled")
	else
		vim.cmd("Copilot enable")
		vim.notify("Copilot enabled")
	end
end, { desc = "Toggle GitHub Copilot" })

-- フォーマットコマンド
vim.api.nvim_create_user_command("Fmt", function(args)
	local range = nil
	if args.count ~= -1 then
		local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
		range = {
			start = { args.line1, 0 },
			["end"] = { args.line2, end_line:len() },
		}
	end
	require("conform").format({ async = true, lsp_fallback = true, range = range })
end, { range = true, desc = "Format code" })

-- NotePush: git add, commit, push を一括実行
vim.api.nvim_create_user_command("NotePush", function()
	local Snacks = require("snacks")
	local buf_dir = vim.fn.expand("%:p:h")
	local root_result = vim.system({ "git", "-C", buf_dir, "rev-parse", "--show-toplevel" }, { text = true }):wait()
	local git_root = vim.trim(root_result.stdout or "")

	if root_result.code ~= 0 or git_root == "" then
		vim.notify("Not a git repository", vim.log.levels.ERROR)
		return
	end

	Snacks.input({ prompt = "Type 'yes' to push: " }, function(value)
		if value == "yes" then
			-- auto-saveを一時的に無効化
			local auto_save_enabled = vim.g.auto_save
			vim.g.auto_save = 0

			local steps = {
				{ "git", "-C", git_root, "add", "." },
				{ "git", "-C", git_root, "commit", "-m", "note update" },
				{ "git", "-C", git_root, "push" },
			}
			local output = {}

			local function restore_auto_save()
				vim.defer_fn(function()
					vim.g.auto_save = auto_save_enabled
				end, 100)
			end

			local function run_step(index)
				local cmd = steps[index]
				if not cmd then
					restore_auto_save()
					vim.notify("Push complete: " .. git_root, vim.log.levels.INFO)
					return
				end

				vim.system(cmd, { text = true }, function(result)
					vim.schedule(function()
						if result.stdout and result.stdout ~= "" then
							for line in result.stdout:gmatch("[^\r\n]+") do
								table.insert(output, line)
							end
						end
						if result.stderr and result.stderr ~= "" then
							for line in result.stderr:gmatch("[^\r\n]+") do
								table.insert(output, "ERROR: " .. line)
							end
						end

						if result.code ~= 0 then
							restore_auto_save()
							vim.notify("Push failed (code: " .. result.code .. ")", vim.log.levels.ERROR)
							if #output > 0 then
								vim.notify(table.concat(output, "\n"), vim.log.levels.ERROR)
							end
							return
						end

						run_step(index + 1)
					end)
				end)
			end

			run_step(1)
		else
			vim.notify("Cancelled", vim.log.levels.WARN)
		end
	end)
end, { desc = "git add, commit, push を一括実行" })
