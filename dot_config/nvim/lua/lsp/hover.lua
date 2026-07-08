-- Hover表示の調整
-- 0.12 の hover はコールバック内で直接 open_floating_preview を呼ぶため
-- handlers での差し替えが効かず、ここが唯一のフック地点。
-- 先頭の ``` フェンス行は conceal で空行として float の行数を浪費し、
-- 高さがカーソル周辺の空きでクランプされると署名が隠れる。
-- フェンスを剥がして裸の散文にすると署名内の _ や * が markdown 強調として
-- conceal され署名が壊れるため、インデント式コードブロック (raw 扱い) に変換して
-- 署名を1行目に出す。
if not vim.g.lsp_hover_preview_wrapped then
	vim.g.lsp_hover_preview_wrapped = true

	local original_open_floating_preview = vim.lsp.util.open_floating_preview
	vim.lsp.util.open_floating_preview = function(contents, syntax, opts, ...)
		if
			opts
			and opts.focus_id == "textDocument/hover"
			and type(contents) == "table"
			and type(contents[1]) == "string"
			and contents[1]:match("^```")
		then
			local converted = {}
			local closed = false
			for i, line in ipairs(contents) do
				if i == 1 then
					-- 開始フェンスを捨てる
				elseif not closed and line:match("^```%s*$") then
					closed = true
				elseif not closed then
					converted[#converted + 1] = "    " .. line
				else
					converted[#converted + 1] = line
				end
			end
			contents = converted
		end
		return original_open_floating_preview(contents, syntax, opts, ...)
	end
end
