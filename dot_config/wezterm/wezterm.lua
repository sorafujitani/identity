local wezterm = require("wezterm")
local config = wezterm.config_builder()
local act = wezterm.action
local agent = require("agent")

-- Helper function to run a command in an overlay pane
local function spawn_overlay_pane(command)
	return wezterm.action_callback(function(window, pane)
		local new_pane = pane:split({
			direction = "Bottom",
			args = { os.getenv("SHELL") or "/bin/zsh", "-ic", command },
		})
		window:perform_action(act.TogglePaneZoomState, new_pane)
	end)
end

config.automatically_reload_config = true
config.hyperlink_rules = wezterm.default_hyperlink_rules()

-- herdr の prefix (ctrl+a) と競合するため無効化
-- config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 2001 }

config.font_size = 14.0
config.font = wezterm.font("Hack Nerd Font", { weight = "Regular", stretch = "Normal", style = "Normal" })

config.color_scheme = "Ef-Night"
local scheme = wezterm.color.get_builtin_schemes()[config.color_scheme]
-- 透過で壁紙の暖色が透けて黄味がかって見えるため、背景を blue 寄りに補正
scheme.background = "#000812"

wezterm.on("update-right-status", function(window)
	local agents = agent.scan()
	local running = 0
	for _, a in ipairs(agents) do
		if a.status == "running" then
			running = running + 1
		end
	end

	local status_parts = {}
	if #agents > 0 then
		local icon = running > 0 and "🔵" or "⚫"
		table.insert(status_parts, { Foreground = { Color = scheme.foreground } })
		table.insert(status_parts, { Text = string.format(" %s %d/%d ", icon, running, #agents) })
	end
	table.insert(status_parts, { Text = window:active_workspace() .. " " })

	window:set_right_status(wezterm.format(status_parts))
end)

wezterm.on("user-var-changed", function(window, pane, name, value)
	wezterm.log_info("user-var-changed: " .. name .. " = " .. tostring(value))
	if name == "switch_workspace" then
		window:perform_action(act.SwitchToWorkspace({ name = value }), pane)
	end
end)

config.use_ime = true

-- herdr が cmd 修飾キー (cmd+arrows, cmd+ctrl+arrows) を受け取れるように
-- kitty keyboard protocol の要求を許可する
config.enable_kitty_keyboard = true

-- レンダリング最適化 (Apple Silicon / macOS Sonoma 前提)
config.front_end = "WebGpu"
-- webgpu_power_preference: Apple Silicon は GPU adapter が単一のため no-op。
-- 明示しても挙動は変わらない (旧コメントの "LowPower は throttle 原因" は
-- Intel + dGPU 時代の話で M 系 Mac には当てはまらない) ため削除。
config.max_fps = 120
-- animation_fps は cursor blink 等のアニメーションだけでなく、
-- render scheduler の tick rate にも紐づく。低くしすぎると damage flush が
-- 間延びして「待つと描画される」現象を起こす。max_fps と整合させて 60 にする。
config.animation_fps = 60
-- 背景透過は毎フレーム alpha compositing を伴う。中程度のコスト。
config.window_background_opacity = 0.92
-- macos_window_background_blur は Window Server が per-frame で Gaussian blur を
-- 再計算するため、大量出力時の最大のボトルネック。0 にすると体感が劇的に向上する。
-- 美観を取り戻したくなったら 10〜20 程度に戻す (ただし render 遅延と引き換え)。
config.macos_window_background_blur = 0

-- マウスホイール1ノッチあたり3行スクロール
-- (scroll_wheel_ratio という設定は存在しないため mouse_bindings で実現)
config.mouse_bindings = {
	{
		event = { Down = { streak = 1, button = { WheelUp = 1 } } },
		mods = "NONE",
		action = act.ScrollByLine(-3),
	},
	{
		event = { Down = { streak = 1, button = { WheelDown = 1 } } },
		mods = "NONE",
		action = act.ScrollByLine(3),
	},
}

config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = false
config.window_decorations = "RESIZE"
config.show_new_tab_button_in_tab_bar = false

config.command_palette_bg_color = scheme.background
config.command_palette_fg_color = scheme.foreground
config.command_palette_font_size = 18.0

config.colors = {
	background = scheme.background,
	tab_bar = {
		inactive_tab_edge = "none",
		background = scheme.background,
	},
}

wezterm.on("format-tab-title", function(tab)
	local background = scheme.background
	local foreground = scheme.foreground

	if tab.is_active then
		foreground = scheme.brights[8]
	end

	return {
		{ Background = { Color = background } },
		{ Foreground = { Color = foreground } },
	}
end)

-- Launcher choices
local launcher_choices = {
	{ label = "Neovim", command = "nvim", icon = "md_file_edit" },
	{ label = "Lazygit", command = "lazygit", icon = "md_git" },
	{ label = "Zsh", command = "zsh", icon = "md_console" },
	-- 描画停止問題の切り分け用 minimal zsh
	-- (~/.config/zsh-diag/.zshrc を使用、本番 plugin を一切ロードしない)
	{
		label = "Zsh (diag, minimal)",
		command = "ZDOTDIR=$HOME/.config/zsh-diag exec zsh",
		icon = "md_bug",
	},
}

config.keys = {
	{ key = "p", mods = "CMD|SHIFT", action = act.ActivateCommandPalette },
	{ key = "r", mods = "CMD|SHIFT", action = act.ReloadConfiguration },
	{ key = "w", mods = "CMD", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = ",", mods = "CMD", action = act({ SplitVertical = { domain = "CurrentPaneDomain" } }) },
	{ key = ".", mods = "CMD", action = act({ SplitHorizontal = { domain = "CurrentPaneDomain" } }) },
	{ key = "LeftArrow", mods = "SHIFT", action = act.ActivatePaneDirection("Left") },
	{ key = "RightArrow", mods = "SHIFT", action = act.ActivatePaneDirection("Right") },
	{ key = "UpArrow", mods = "SHIFT", action = act.ActivatePaneDirection("Up") },
	{ key = "DownArrow", mods = "SHIFT", action = act.ActivatePaneDirection("Down") },
	-- herdr の pane 移動 (cmd+arrows) と競合するため無効化
	-- { key = "LeftArrow", mods = "CMD", action = act.SwitchWorkspaceRelative(-1) },
	-- { key = "RightArrow", mods = "CMD", action = act.SwitchWorkspaceRelative(1) },
	{ key = "9", mods = "ALT", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },
	{ key = "Enter", mods = "SHIFT", action = act.SendString("\n") },
	-- ctrl+n は herdr の pane zoom (keys.zoom) に割り当てているため、
	-- WezTerm では奪わずに herdr へ届かせる
	-- { key = "n", mods = "CTRL", action = act.TogglePaneZoomState },
	-- leader 無効化に伴い LEADER 系バインドも無効化 (launcher / agent dashboard は
	-- command palette (cmd+shift+p) から引き続き利用可能)
	-- {
	-- 	key = "l",
	-- 	mods = "LEADER",
	-- 	action = act.InputSelector({
	-- 		title = "Launcher",
	-- 		choices = (function()
	-- 			local choices = {}
	-- 			for _, item in ipairs(launcher_choices) do
	-- 				table.insert(choices, { label = item.label })
	-- 			end
	-- 			return choices
	-- 		end)(),
	-- 		action = wezterm.action_callback(function(window, pane, _id, label)
	-- 			if not label then
	-- 				return
	-- 			end
	-- 			for _, item in ipairs(launcher_choices) do
	-- 				if item.label == label then
	-- 					local new_pane = pane:split({
	-- 						direction = "Bottom",
	-- 						args = { os.getenv("SHELL") or "/bin/zsh", "-ic", item.command },
	-- 					})
	-- 					window:perform_action(act.TogglePaneZoomState, new_pane)
	-- 					return
	-- 				end
	-- 			end
	-- 		end),
	-- 	}),
	-- },
	-- {
	-- 	key = "a",
	-- 	mods = "LEADER",
	-- 	action = agent.tui_dashboard_action(),
	-- },
}

wezterm.on("augment-command-palette", function()
	local entries = agent.palette_entries()
	for _, item in ipairs(launcher_choices) do
		table.insert(entries, {
			brief = "Overlay: " .. item.label,
			icon = item.icon,
			action = spawn_overlay_pane(item.command),
		})
	end
	return entries
end)

return config
