local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

local _wez_cc_viewer_cache = nil
local function find_wez_cc_viewer()
	if _wez_cc_viewer_cache then
		return _wez_cc_viewer_cache
	end
	local ok, stdout = wezterm.run_child_process({
		os.getenv("SHELL") or "/bin/zsh", "-lic", "which wez-cc-viewer",
	})
	if ok and stdout then
		local path = stdout:gsub("%s+$", "")
		if path ~= "" then
			_wez_cc_viewer_cache = path
			return path
		end
	end
	return nil
end

function M.notify(title, message)
	wezterm.run_child_process({
		"osascript",
		"-e",
		string.format(
			'display notification %q with title %q sound name "Glass"',
			message,
			title
		),
	})
end

local STATUS_ICON = { idle = "⚫", running = "🔵", unknown = "?" }
local cache = { result = {}, timestamp = 0 }
local CACHE_TTL = 3

-- Track previous agent info per pane_id for completion detection
local prev_agents = {} -- pane_id -> agent info table

-- Walk ppid chain to find a claude ancestor pid
local function find_claude_ancestor(pid, procs, claude_pids)
	local visited = {}
	local current = pid
	while current and current > 1 and not visited[current] do
		visited[current] = true
		if claude_pids[current] then
			return current
		end
		local info = procs[current]
		if not info then
			break
		end
		current = info.ppid
	end
	return nil
end

-- Detect agent status for a single pane; returns status string or nil
local function detect_pane_agent(p, procs, claude_pids, claude_status)
	local ok_info, fg_info = pcall(function()
		return p:get_foreground_process_info()
	end)
	local fg_pid = ok_info and fg_info and fg_info.pid

	if fg_pid and procs[fg_pid] then
		local cpid = find_claude_ancestor(fg_pid, procs, claude_pids)
		return cpid and (claude_status[cpid] or "idle") or nil
	end

	local proc_path = p:get_foreground_process_name() or ""
	local proc_name = proc_path:match("([^/]+)$") or proc_path

	if proc_name:find("claude") then
		return "idle"
	end

	for pid, info in pairs(procs) do
		if info.name == proc_name or info.fullpath == proc_path then
			local cpid = find_claude_ancestor(pid, procs, claude_pids)
			if cpid then
				return claude_status[cpid] or "idle"
			end
		end
	end
	return nil
end

--- Scan all panes for running agents. Results are cached for CACHE_TTL seconds.
function M.scan()
	local now = os.time()
	if now - cache.timestamp < CACHE_TTL then
		return cache.result
	end

	local ok, stdout = wezterm.run_child_process({ "ps", "-eo", "pid,ppid,comm" })
	local procs = {}
	local children = {}
	local claude_pids = {}
	if ok and stdout then
		for line in stdout:gmatch("[^\n]+") do
			local pid_s, ppid_s, comm = line:match("(%d+)%s+(%d+)%s+(.+)")
			if pid_s then
				local pid = tonumber(pid_s)
				local ppid = tonumber(ppid_s)
				local name = comm:gsub("^%s+", ""):gsub("%s+$", "")
				local basename = name:match("([^/]+)$") or name
				procs[pid] = { ppid = ppid, name = basename, fullpath = name }
				if not children[ppid] then
					children[ppid] = {}
				end
				table.insert(children[ppid], pid)
				if basename:find("claude") then
					claude_pids[pid] = true
				end
			end
		end
	end

	-- Claude Code spawns caffeinate while running and kills it when idle.
	local claude_status = {}
	for cpid in pairs(claude_pids) do
		local is_active = false
		for _, child_pid in ipairs(children[cpid] or {}) do
			if procs[child_pid].name == "caffeinate" then
				is_active = true
				break
			end
		end
		claude_status[cpid] = is_active and "running" or "idle"
	end

	local agents = {}
	for _, mux_win in ipairs(wezterm.mux.all_windows()) do
		local workspace = mux_win:get_workspace()
		for _, tab in ipairs(mux_win:tabs()) do
			for _, p in ipairs(tab:panes()) do
				local status = detect_pane_agent(p, procs, claude_pids, claude_status)
				if status then
					local cwd = p:get_current_working_dir()
					local dir = cwd and cwd.file_path or "unknown"
					table.insert(agents, {
						workspace = workspace,
						pane_id = p:pane_id(),
						project = dir:match("([^/]+)$") or dir,
						dir = dir,
						status = status,
					})
				end
			end
		end
	end

	-- Detect agents that completed: running->idle or running->gone
	local completed = {}
	local current_agents = {}
	for _, a in ipairs(agents) do
		current_agents[a.pane_id] = a
		local prev = prev_agents[a.pane_id]
		if prev and prev.status == "running" and a.status == "idle" then
			table.insert(completed, a)
		end
	end
	-- Check for agents that were running but disappeared entirely
	for pane_id, prev in pairs(prev_agents) do
		if prev.status == "running" and not current_agents[pane_id] then
			table.insert(completed, prev)
		end
	end
	prev_agents = current_agents

	-- Log scan results for debugging
	local statuses = {}
	for _, a in ipairs(agents) do
		table.insert(statuses, a.project .. "=" .. a.status)
	end
	if #agents > 0 then
		wezterm.log_info("agent scan: " .. table.concat(statuses, ", "))
	end
	for _, a in ipairs(completed) do
		wezterm.log_info("agent completed: " .. a.project .. " [" .. a.workspace .. "]")
		M.notify("Agent Complete", a.project .. " [" .. a.workspace .. "]")
	end

	cache.result = agents
	cache.timestamp = now
	return agents, completed
end

--- Return cached agents without triggering a new scan.
function M.cached()
	return cache.result
end

--- Return a wezterm action that opens the agent dashboard InputSelector.
function M.dashboard_action()
	return wezterm.action_callback(function(window, pane)
		cache.timestamp = 0
		local agents = M.scan()
		if #agents == 0 then
			window:toast_notification("wezterm", "No running agents", nil, 3000)
			return
		end

		local choices = {}
		for _, a in ipairs(agents) do
			local icon = STATUS_ICON[a.status] or "?"
			table.insert(choices, {
				label = string.format("%s %s [%s]  %s", icon, a.project, a.workspace, a.dir),
				id = a.workspace,
			})
		end

		window:perform_action(act.InputSelector({
			title = string.format("Running Agents (%d)", #agents),
			choices = choices,
			action = wezterm.action_callback(function(win, p, id)
				if id then
					win:perform_action(act.SwitchToWorkspace({ name = id }), p)
				end
			end),
		}), pane)
	end)
end

--- Return command palette entries for augment-command-palette.
function M.palette_entries()
	local ok, result = pcall(M.scan)
	local agents = ok and result or cache.result
	local running_count = 0
	for _, a in ipairs(agents) do
		if a.status == "running" then
			running_count = running_count + 1
		end
	end

	local dashboard_label = #agents == 0 and "wez-cc-viewer"
		or string.format("wez-cc-viewer (%d agents, %d running)", #agents, running_count)

	local entries = {
		{
			brief = dashboard_label,
			icon = "md_robot",
			action = M.dashboard_action(),
		},
		{
			brief = "Agent: Test Notification",
			icon = "md_bell",
			action = wezterm.action_callback(function()
				M.notify("Agent Complete", "Test notification")
			end),
		},
	}
	for _, a in ipairs(agents) do
		local icon = STATUS_ICON[a.status] or "?"
		table.insert(entries, {
			brief = string.format("Agent %s %s [%s]", icon, a.project, a.workspace),
			icon = "md_robot",
			action = wezterm.action_callback(function(win, p)
				win:perform_action(act.SwitchToWorkspace({ name = a.workspace }), p)
			end),
		})
	end
	return entries
end

--- Return a wezterm action that opens the TUI dashboard in an overlay pane.
function M.tui_dashboard_action()
	return wezterm.action_callback(function(window, pane)
		local wez_cc_viewer = find_wez_cc_viewer()
		if not wez_cc_viewer then
			window:toast_notification("wezterm", "wez-cc-viewer not found in PATH", nil, 3000)
			return
		end
		local new_pane = pane:split({
			direction = "Bottom",
			args = { wez_cc_viewer },
		})
		window:perform_action(act.TogglePaneZoomState, new_pane)
	end)
end

return M
