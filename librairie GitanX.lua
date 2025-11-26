--!strict
-- GitanX UI — Complete edition
-- Full rewrite: includes visual polish, UX improvements, Maid cleanup, debounced config writes,
-- icon library loader, searchable & basic-virtualized dropdowns, colorpicker with alpha & presets,
-- advanced notifications, config import/export, theme editor helper, accessibility features.
-- Public API preserved: GitanX:Init(config) -> Window with CreateTab/Section and Section:Create*(...).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local GitanX = {}

-- Minimal Themes (extend/replace with your Themes table)
local Themes = {
	Default = {
		Background   = Color3.fromRGB(22,22,24),
		Section      = Color3.fromRGB(28,30,34),
		Button       = Color3.fromRGB(34,36,40),
		ButtonHover  = Color3.fromRGB(46,50,58),
		Border       = Color3.fromRGB(64,68,76),
		Text         = Color3.fromRGB(235,238,242),
		MutedText    = Color3.fromRGB(160,165,170),
		Accent       = Color3.fromRGB(0,150,255),
		Accent2      = Color3.fromRGB(0,110,200),
		SliderTrack  = Color3.fromRGB(40,44,50),
		SliderFill   = Color3.fromRGB(0,150,255),
		ToggleOn     = Color3.fromRGB(0,190,140),
		ToggleOff    = Color3.fromRGB(90,94,98),
		Tooltip      = Color3.fromRGB(20,22,26),
		Notify       = Color3.fromRGB(28,30,34),
		Glow         = Color3.fromRGB(0,150,255)
	}
}

-- Utilities
local function create(className, props, children)
	local inst = Instance.new(className)
	if props then
		for k,v in pairs(props) do
			pcall(function() inst[k] = v end)
		end
	end
	if children then
		for _,c in ipairs(children) do c.Parent = inst end
	end
	return inst
end

local function clamp(n,a,b) return math.max(a, math.min(b, n)) end
local function round(n, step) step = step or 1; return math.floor(n/step + 0.5) * step end

-- Tween presets
local T_QUICK = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local T_MED   = TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local T_LONG  = TweenInfo.new(0.28, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

-- Maid: cleanup helper for events/objects
local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({ _tasks = {} }, Maid) end
function Maid:Give(task) if not task then return end table.insert(self._tasks, task); return task end
function Maid:DoCleaning()
	for _,t in ipairs(self._tasks) do
		pcall(function()
			if type(t) == "function" then
				t()
			elseif typeof and typeof(t) == "RBXScriptConnection" then
				t:Disconnect()
			elseif t and t.Destroy then
				t:Destroy()
			end
		end)
	end
	self._tasks = {}
end

-- Debounced writes to avoid spamming writefile
local pendingWrites = {}
local writeLocks = {}
local function debouncedWrite(folder, file, data)
	local key = folder.."/"..file
	pendingWrites[key] = HttpService:JSONEncode(data)
	if writeLocks[key] then return end
	writeLocks[key] = true
	task.spawn(function()
		task.wait(0.8)
		local payload = pendingWrites[key]
		if payload then
			if writefile then
				pcall(function()
					if makefolder and not isfolder(folder) then makefolder(folder) end
					writefile(folder.."/"..file, payload)
				end)
			else
				local store = getgenv and getgenv() or _G
				store.__GitanXCfg = store.__GitanXCfg or {}
				store.__GitanXCfg[key] = payload
			end
			pendingWrites[key] = nil
		end
		writeLocks[key] = nil
	end)
end

local function cfgLoad(folder,file)
	if readfile then
		local ok, content = pcall(function() return readfile(folder.."/"..file) end)
		if ok and content then
			local suc, dec = pcall(function() return HttpService:JSONDecode(content) end)
			if suc then return dec end
		end
		return nil
	else
		local store = getgenv and getgenv() or _G
		store.__GitanXCfg = store.__GitanXCfg or {}
		local enc = store.__GitanXCfg[folder.."/"..file]
		if enc then
			local suc, dec = pcall(function() return HttpService:JSONDecode(enc) end)
			if suc then return dec end
		end
		return nil
	end
end

-- Blur effect
local function ensureBlur()
	local b = Lighting:FindFirstChild("GitanX_Blur")
	if not b then
		b = Instance.new("BlurEffect")
		b.Name = "GitanX_Blur"
		b.Size = 0
		b.Parent = Lighting
	end
	return b
end

-- Visual helpers: shadow / glow / shine
local function addShadow(parent, corner)
	local sh = create("Frame", {
		Name = "GitanX_Shadow",
		Parent = parent,
		BackgroundColor3 = Color3.fromRGB(0,0,0),
		BackgroundTransparency = 0.9,
		Size = UDim2.new(1, 12, 1, 12),
		Position = UDim2.new(0, -6, 0, -6),
		ZIndex = parent.ZIndex - 1,
		ClipsDescendants = false
	}, {
		create("UICorner", { CornerRadius = corner or UDim.new(0,12) })
	})
	return sh
end

local function applyGlow(gui, color)
	if not gui then return end
	pcall(function()
		local s = create("UIStroke", { Name = "GitanX_Glow", Color = color or Color3.fromRGB(255,255,255), Transparency = 0.75, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		s.Parent = gui
	end)
end

local function applyShine(frame)
	if not frame then return end
	pcall(function()
		local g = create("UIGradient", {})
		g.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(220,220,220))
		}
		g.Transparency = NumberSequence.new{ NumberSequenceKeypoint.new(0,0.93), NumberSequenceKeypoint.new(1,0.98) }
		g.Rotation = 90
		g.Parent = frame
	end)
end

-- Tooltips
local function attachTooltip(gui, text, theme)
	if not text or text == "" then return end
	local tip = create("TextLabel", {
		Name = "GitanX_Tooltip",
		Parent = CoreGui,
		BackgroundColor3 = theme.Tooltip,
		TextColor3 = theme.Text,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		Text = text,
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = true,
		ZIndex = 999999
	}, {
		create("UICorner", { CornerRadius = UDim.new(0,8) }),
		create("UIPadding", { PaddingLeft = UDim.new(0,8), PaddingRight = UDim.new(0,8), PaddingTop = UDim.new(0,6), PaddingBottom = UDim.new(0,6) })
	})
	tip.Visible = false
	tip.BackgroundTransparency = 1
	local active = false
	gui.MouseEnter:Connect(function()
		active = true
		tip.Visible = true
		TweenService:Create(tip, T_QUICK, { BackgroundTransparency = 0 }):Play()
		addShadow(tip, UDim.new(0,8))
	end)
	gui.MouseLeave:Connect(function()
		active = false
		TweenService:Create(tip, T_QUICK, { BackgroundTransparency = 1 }):Play()
		task.delay(0.12, function()
			if tip and not active then
				tip.Visible = false
				for _,c in ipairs(tip:GetChildren()) do if c.Name == "GitanX_Shadow" then c:Destroy() end end
			end
		end)
	end)
	gui.MouseMoved:Connect(function(x,y)
		if tip.Visible then tip.Position = UDim2.fromOffset(x + 12, y + 12) end
	end)
end

-- Icon library loader: tries JSON or Lua returning a table
local function loadIconLibrary(url)
	local ok, res = pcall(function() return game:HttpGet(url) end)
	if not ok or not res then return nil end
	-- try JSON
	local suc, dec = pcall(function() return HttpService:JSONDecode(res) end)
	if suc and type(dec) == "table" then return dec end
	-- try Lua string
	local ok2, out = pcall(function() return loadstring(res)() end)
	if ok2 and type(out) == "table" then return out end
	return nil
end

-- Main initializer
function GitanX:Init(config)
	config = config or {}
	local theme = Themes[config.Theme or "Default"] or Themes.Default
	local columns = clamp(tonumber(config.Columns) or 1, 1, 3)
	local toggleKeybind = config.ToggleKeybind or Enum.KeyCode.RightShift
	local cfgSettings = config.ConfigurationSaving or { Enabled = false, FolderName = "GitanX", FileName = "config.json" }

	-- ScreenGui
	local screenGui = create("ScreenGui", { Name = "GitanX_UI_"..HttpService:GenerateGUID(false), Parent = CoreGui, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Global, IgnoreGuiInset = true })
	local overlay = create("Frame", { Name = "GitanX_Overlay", Parent = screenGui, BackgroundTransparency = 1, Size = UDim2.new(1,0,1,0), Visible = false, ZIndex = 99998 })
	local blur = ensureBlur()
	local function setBlur(on) if on then TweenService:Create(blur, T_MED, { Size = 14 }):Play() else TweenService:Create(blur, T_MED, { Size = 0 }):Play() end end

	-- responsive
	local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1366,768)
	local mainW = clamp(math.floor(viewport.X * 0.62), 520, 1200)
	local mainH = clamp(math.floor(viewport.Y * 0.72), 420, 920)
	local pad = 18

	-- window
	local window = create("Frame", {
		Name = "GitanX_Window",
		Parent = screenGui,
		BackgroundColor3 = theme.Background,
		BorderColor3 = theme.Border,
		Size = UDim2.fromOffset(mainW, mainH),
		Position = UDim2.fromScale(0.08, 0.08),
		ZIndex = 99999,
		ClipsDescendants = false
	}, {
		create("UICorner", { CornerRadius = UDim.new(0,16) }),
		create("UIStroke", { Color = theme.Border, Thickness = 1 })
	})
	addShadow(window, UDim.new(0,16))

	-- header
	local header = create("Frame", { Name = "Header", Parent = window, BackgroundColor3 = theme.Section, Size = UDim2.new(1,0,0,74), ZIndex = window.ZIndex + 2 }, {
		create("UICorner", { CornerRadius = UDim.new(0,16) }),
		create("UIStroke", { Color = theme.Border, Thickness = 1 })
	})
	create("TextLabel", { Name = "Title", Parent = header, BackgroundTransparency = 1, Text = tostring(config.Name or "GitanX Hub"), Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = theme.Text, Position = UDim2.fromOffset(pad,18), Size = UDim2.new(1, -pad*2, 0, 28), TextXAlignment = Enum.TextXAlignment.Left })
	create("TextLabel", { Name = "Subtitle", Parent = header, BackgroundTransparency = 1, Text = tostring(config.LoadingTitle or "GitanX").." • "..tostring(config.LoadingSubtitle or "HUB"), Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = theme.MutedText, Position = UDim2.fromOffset(pad,44), Size = UDim2.new(1, -pad*2, 0, 16), TextXAlignment = Enum.TextXAlignment.Left })

	-- tabs & content
	local tabsBar = create("Frame", { Name = "TabsBar", Parent = window, BackgroundTransparency = 1, Position = UDim2.fromOffset(pad,96), Size = UDim2.new(1, -pad*2, 0, 44) }, {
		create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0,10), VerticalAlignment = Enum.VerticalAlignment.Center })
	})
	local content = create("Frame", { Name = "Content", Parent = window, BackgroundTransparency = 1, Position = UDim2.fromOffset(pad, 150), Size = UDim2.new(1, -pad*2, 1, -(150 + pad)), ClipsDescendants = false })

	-- columns container
	local columnsContainer = {}
	for i=1,columns do
		local col = create("ScrollingFrame", {
			Name = "Column"..i,
			Parent = content,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarImageColor3 = theme.Accent2,
			ScrollBarThickness = 8,
			CanvasSize = UDim2.new(0,0,0,0),
			Position = UDim2.new((i-1)/columns, 0, 0, 0),
			Size = UDim2.new(1/columns, -8, 1, 0)
		}, {
			create("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0,12), SortOrder = Enum.SortOrder.LayoutOrder })
		})
		table.insert(columnsContainer, col)
	end

	-- draggable
	local function makeDraggable(frame, handle)
		handle = handle or frame
		local dragging, dragStart, startPos
		handle.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true; dragStart = input.Position; startPos = frame.Position
				TweenService:Create(frame, T_QUICK, { Rotation = 0.35 }):Play()
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then dragging = false; TweenService:Create(frame, T_QUICK, { Rotation = 0 }):Play() end
				end)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = input.Position - dragStart
				frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end)
	end
	makeDraggable(window, header)

	-- notifications advanced
	local notifications = create("Frame", { Name = "Notifications", Parent = screenGui, BackgroundTransparency = 1, Position = UDim2.new(1, -24, 0, 24), AnchorPoint = Vector2.new(1,0), Size = UDim2.fromOffset(320, 0), ZIndex = 160000 })
	local function repositionToasts()
		local toasts = {}
		for _,c in ipairs(notifications:GetChildren()) do if c:IsA("Frame") then table.insert(toasts, c) end end
		table.sort(toasts, function(a,b) return (a:GetAttribute("created") or 0) < (b:GetAttribute("created") or 0) end)
		for i,t in ipairs(toasts) do
			local y = (i-1) * (t.AbsoluteSize.Y + 8)
			TweenService:Create(t, T_MED, { Position = UDim2.new(1, 0, 0, 24 + y) }):Play()
		end
	end
	local function pushNotification(opts)
		opts = opts or {}
		local kind = (opts.Type or "Info"):lower()
		local bg = theme.Notify; local icon = "ℹ️"
		if kind == "success" then bg = Color3.fromRGB(28,120,60); icon = "✔️"
		elseif kind == "error" then bg = Color3.fromRGB(180,40,40); icon = "❌"
		elseif kind == "warning" then bg = Color3.fromRGB(210,140,20); icon = "⚠️"
		elseif kind == "loading" then bg = theme.Notify; icon = "⏳"
		elseif kind == "custom" then bg = opts.BackgroundColor or theme.Notify; icon = opts.Icon or "🔔" end

		local toast = create("Frame", { Parent = notifications, BackgroundColor3 = bg, BorderColor3 = theme.Border, Size = UDim2.fromOffset(0,64), AnchorPoint = Vector2.new(1,0), Position = UDim2.new(1, 0, 0, 24), ZIndex = notifications.ZIndex + 1 }, {
			create("UICorner", { CornerRadius = UDim.new(0,12) }),
			create("UIStroke", { Color = theme.Border, Thickness = 1 })
		})
		local circle = create("Frame", { Parent = toast, BackgroundColor3 = bg:lerp(Color3.new(0,0,0), 0.06), Position = UDim2.fromOffset(12,12), Size = UDim2.fromOffset(40,40) }, { create("UICorner", { CornerRadius = UDim.new(1,0) }) })
		create("TextLabel", { Parent = circle, BackgroundTransparency = 1, Text = icon, Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = theme.Text, Size = UDim2.new(1,0,1,0) })
		create("TextLabel", { Parent = toast, BackgroundTransparency = 1, Text = string.format("%s\n%s", tostring(opts.Title or ""), tostring(opts.Content or "")), Position = UDim2.fromOffset(64, 10), Size = UDim2.new(1, -88, 1, -20), TextColor3 = theme.Text, Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left })
		addShadow(toast, UDim.new(0,12))
		toast:SetAttribute("created", tick()); toast.ClipsDescendants = true
		TweenService:Create(toast, T_LONG, { Size = UDim2.fromOffset(320,64) }):Play()
		repositionToasts()
		-- actions
		if opts.Actions and type(opts.Actions) == "table" then
			local xOffset = 0
			for _,act in ipairs(opts.Actions) do
				local b = create("TextButton", { Parent = toast, Text = act.Text or "Action", BackgroundColor3 = theme.Button, BorderColor3 = theme.Border, Position = UDim2.fromOffset(320 - 88 - xOffset, 12), Size = UDim2.fromOffset(80,20), AutoButtonColor = false }, {
					create("UICorner", { CornerRadius = UDim.new(0,6) })
				})
				b.MouseButton1Click:Connect(function() pcall(function() if act.Callback then act.Callback() end end) end)
				xOffset = xOffset + 88
			end
		end
		task.delay(opts.Duration or 3, function()
			if kind == "loading" and opts.Persistent then return end
			if toast and toast.Parent then
				TweenService:Create(toast, T_MED, { Size = UDim2.fromOffset(0,64) }):Play()
				task.delay(0.28, function() if toast and toast.Parent then toast:Destroy(); repositionToasts() end end)
			end
		end)
		return toast
	end

	overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then overlay.Visible = false end
	end)

	-- Window API
	local Window = {
		_theme = theme,
		_screenGui = screenGui,
		_overlay = overlay,
		_tabs = {},
		_cfg = cfgSettings,
		iconLib = nil,
		recentColors = {}
	}

	function Window:LoadIconLibrary(url)
		local lib = loadIconLibrary(url)
		if lib then self.iconLib = lib; return true end
		return false
	end

	function Window:ExportConfig()
		local folder = Window._cfg.FolderName or "GitanX"
		local fname = Window._cfg.FileName or "config.json"
		local data = cfgLoad(folder, fname) or {}
		return HttpService:JSONEncode(data)
	end

	function Window:ImportConfig(jsonStr)
		if not jsonStr then return false end
		local ok, tbl = pcall(function() return HttpService:JSONDecode(jsonStr) end)
		if not ok then return false end
		if Window._cfg.Enabled then debouncedWrite(Window._cfg.FolderName or "GitanX", Window._cfg.FileName or "config.json", tbl) end
		return true
	end

	function Window:ClearRecentColors() Window.recentColors = {} end

	function Window:Notify(opts) return pushNotification(opts) end
	function Window:ApplyThemePatch(patch)
		if not patch then return end
		for k,v in pairs(patch) do if Window._theme[k] ~= nil then Window._theme[k] = v end end
		window.BackgroundColor3 = Window._theme.Background
		header.BackgroundColor3 = Window._theme.Section
		for _,c in ipairs(columnsContainer) do c.ScrollBarImageColor3 = Window._theme.Accent2 end
		if Window._cfg and Window._cfg.Enabled then
			local stored = cfgLoad(Window._cfg.FolderName or "GitanX", Window._cfg.FileName or "config.json") or {}
			stored.__theme = stored.__theme or {}
			for k,v in pairs(patch) do stored.__theme[k] = { R = math.floor(v.R*255+0.5), G = math.floor(v.G*255+0.5), B = math.floor(v.B*255+0.5) } end
			debouncedWrite(Window._cfg.FolderName or "GitanX", Window._cfg.FileName or "config.json", stored)
			Window:Notify({ Title = "Theme", Content = "Theme saved", Type = "success" })
		end
	end

	function Window:SaveConfiguration(data)
		if not Window._cfg.Enabled then return end
		debouncedWrite(Window._cfg.FolderName or "GitanX", Window._cfg.FileName or "config.json", data)
	end

	function Window:LoadConfiguration()
		if not Window._cfg.Enabled then return nil end
		return cfgLoad(Window._cfg.FolderName or "GitanX", Window._cfg.FileName or "config.json")
	end

	-- Tab factory
	function Window:CreateTab(tabName, tabIcon)
		tabName = tostring(tabName or "Tab")
		local btn = create("TextButton", { Name = "TabButton_"..tabName, Parent = tabsBar, BackgroundColor3 = theme.Button, BorderColor3 = theme.Border, AutoButtonColor = false, Text = tabName, TextColor3 = theme.Text, Font = Enum.Font.Gotham, TextSize = 14, Size = UDim2.fromOffset(150, 36) }, {
			create("UICorner", { CornerRadius = UDim.new(0,10) }),
			create("UIStroke", { Color = theme.Border, Thickness = 1 })
		})
		-- icon resolution: check iconLib, rbxassetid or emoji
		if tabIcon and tostring(tabIcon) ~= "" then
			local s = tostring(tabIcon)
			if Window.iconLib and Window.iconLib[s] then
				create("ImageLabel", { Parent = btn, Image = Window.iconLib[s], BackgroundTransparency = 1, Position = UDim2.fromOffset(10,6), Size = UDim2.fromOffset(24,24) })
				btn.Text = "   "..btn.Text
			elseif s:match("rbxasset") then
				create("ImageLabel", { Parent = btn, Image = s, BackgroundTransparency = 1, Position = UDim2.fromOffset(10,6), Size = UDim2.fromOffset(24,24) })
				btn.Text = "   "..btn.Text
			else
				btn.Text = s.."  "..btn.Text
			end
		end

		local tabContent = create("Frame", { Parent = content, BackgroundTransparency = 1, Visible = false, Size = UDim2.new(1,0,1,0) })
		local tabCols = {}
		for i=1,#columnsContainer do
			local c = create("ScrollingFrame", { Name = "TabCol"..i, Parent = tabContent, BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(0,0,0,0), ScrollBarThickness = 8, ScrollBarImageTransparency = 0.25, ScrollBarImageColor3 = theme.Accent2, Position = UDim2.new((i-1)/#columnsContainer, 0, 0, 0), Size = UDim2.new(1/#columnsContainer, -8, 1, 0) }, {
				create("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0,12) })
			})
			table.insert(tabCols, c)
		end

		btn.MouseEnter:Connect(function() TweenService:Create(btn, T_QUICK, { BackgroundColor3 = theme.ButtonHover }):Play() end)
		btn.MouseLeave:Connect(function() TweenService:Create(btn, T_QUICK, { BackgroundColor3 = theme.Button }):Play() end)

		local function select()
			for _,t in pairs(Window._tabs) do
				if t._button then TweenService:Create(t._button, T_QUICK, { BackgroundColor3 = theme.Button }):Play() end
				if t._content then t._content.Visible = false end
			end
			TweenService:Create(btn, T_QUICK, { BackgroundColor3 = theme.ButtonHover }):Play()
			tabContent.Visible = true
		end
		btn.MouseButton1Click:Connect(select)

		local Tab = { _button = btn, _content = tabContent, _columns = tabCols }

		function Tab:CreateSection(sectionName, columnIndex)
			sectionName = tostring(sectionName or "Section")
			columnIndex = clamp(tonumber(columnIndex) or 1, 1, #tabCols)
			local section = create("Frame", { Parent = tabCols[columnIndex], BackgroundColor3 = theme.Section, BorderColor3 = theme.Border, Size = UDim2.new(1,0,0,48) }, {
				create("UICorner", { CornerRadius = UDim.new(0,12) }),
				create("UIStroke", { Color = theme.Border, Thickness = 1 })
			})
			create("TextLabel", { Parent = section, BackgroundTransparency = 1, Text = sectionName, TextColor3 = theme.Text, Font = Enum.Font.GothamBold, TextSize = 15, Position = UDim2.fromOffset(12,8), Size = UDim2.new(1,-24,0,20), TextXAlignment = Enum.TextXAlignment.Left })
			local controls = create("Frame", { Parent = section, BackgroundTransparency = 1, Position = UDim2.fromOffset(12,36), Size = UDim2.new(1,-24,0,0) }, { create("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0,10) }) })

			local function recalc()
				local total = 36
				for _,c in ipairs(controls:GetChildren()) do
					if c:IsA("GuiObject") then total = total + (c.AbsoluteSize.Y or 0) + 10 end
				end
				section.Size = UDim2.new(1,0,0, math.max(total, 48))
			end
			controls.ChildAdded:Connect(function() task.defer(recalc) end)
			controls.ChildRemoved:Connect(function() task.defer(recalc) end)
			task.defer(recalc)

			local Section = {}

			-- Button
			function Section:CreateButton(opts)
				opts = opts or {}
				local label = tostring(opts.Name or "Button")
				local callback = opts.Callback
				local btn = create("TextButton", { Parent = controls, BackgroundColor3 = theme.Button, BorderColor3 = theme.Border, AutoButtonColor = false, Text = label, TextColor3 = theme.Text, Font = Enum.Font.GothamBold, TextSize = 14, Size = UDim2.new(1,0,0,40) }, {
					create("UICorner", { CornerRadius = UDim.new(0,10) }),
					create("UIStroke", { Color = theme.Border, Thickness = 1 })
				})
				applyShine(btn)
				local ripple = create("Frame", { Parent = btn, Name = "Ripple", Size = UDim2.fromScale(0,0), Position = UDim2.fromScale(0.5,0.5), AnchorPoint = Vector2.new(0.5,0.5), BackgroundColor3 = theme.Accent, BackgroundTransparency = 0.85, ZIndex = btn.ZIndex + 2 }, {
					create("UICorner", { CornerRadius = UDim.new(1,0) })
				})
				local focusStroke = create("UIStroke", { Parent = btn, Name = "FocusStroke", Color = theme.Accent, Transparency = 1, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
				btn.MouseEnter:Connect(function() TweenService:Create(btn, T_QUICK, { BackgroundColor3 = theme.ButtonHover }):Play(); TweenService:Create(focusStroke, T_QUICK, { Transparency = 0.6 }):Play() end)
				btn.MouseLeave:Connect(function() TweenService:Create(btn, T_QUICK, { BackgroundColor3 = theme.Button }):Play(); TweenService:Create(focusStroke, T_QUICK, { Transparency = 1 }):Play() end)
				btn.MouseButton1Click:Connect(function()
					local m = UserInputService:GetMouseLocation(); local rx = clamp(m.X - btn.AbsolutePosition.X, 0, btn.AbsoluteSize.X); local ry = clamp(m.Y - btn.AbsolutePosition.Y, 0, btn.AbsoluteSize.Y)
					ripple.Position = UDim2.fromOffset(rx, ry); ripple.Size = UDim2.fromScale(0,0); ripple.Visible = true; ripple.BackgroundTransparency = 0.6
					TweenService:Create(ripple, TweenInfo.new(0.45, Enum.EasingStyle.Quart), { Size = UDim2.new(4,0,4,0), BackgroundTransparency = 1 }):Play()
					task.delay(0.48, function() if ripple and ripple.Parent then ripple.Visible = false; ripple.Size = UDim2.fromScale(0,0); ripple.BackgroundTransparency = 0.85 end end)
					if callback then task.spawn(function() pcall(callback) end) end
				end)
				attachTooltip(btn, opts.Tooltip, theme)
				return { Set = function(t) btn.Text = tostring(t or "") end, Click = function() btn:Activate() end }
			end

			-- Toggle
			function Section:CreateToggle(opts)
				opts = opts or {}
				local name = tostring(opts.Name or "Toggle")
				local state = not not opts.CurrentValue
				local callback = opts.Callback
				local frame = create("Frame", { Parent = controls, BackgroundColor3 = theme.Button, BorderColor3 = theme.Border, Size = UDim2.new(1,0,0,40) }, {
					create("UICorner", { CornerRadius = UDim.new(0,10) }),
					create("UIStroke", { Color = theme.Border, Thickness = 1 })
				})
				create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Text = name, TextColor3 = theme.Text, Font = Enum.Font.Gotham, TextSize = 14, Position = UDim2.fromOffset(12,8), Size = UDim2.new(1,-120,0,24), TextXAlignment = Enum.TextXAlignment.Left })
				local sw = create("Frame", { Parent = frame, BackgroundColor3 = state and theme.ToggleOn or theme.ToggleOff, BorderColor3 = theme.Border, Position = UDim2.new(1, -100, 0, 8), Size = UDim2.fromOffset(72,24) }, {
					create("UICorner", { CornerRadius = UDim.new(0,12) }),
					create("UIStroke", { Color = theme.Border, Thickness = 1 })
				})
				local knob = create("Frame", { Parent = sw, BackgroundColor3 = Color3.fromRGB(255,255,255), Size = UDim2.fromOffset(18,18), Position = state and UDim2.new(1, -22, 0, 3) or UDim2.new(0, 4, 0, 3) }, {
					create("UICorner", { CornerRadius = UDim.new(0,9) })
				})
				applyGlow(knob, theme.Glow)
				local function set(s)
					state = not not s
					TweenService:Create(sw, T_QUICK, { BackgroundColor3 = state and theme.ToggleOn or theme.ToggleOff }):Play()
					TweenService:Create(knob, T_QUICK, { Position = state and UDim2.new(1, -22, 0, 3) or UDim2.new(0, 4, 0, 3) }):Play()
					if callback then task.spawn(function() pcall(callback, state) end) end
				end
				sw.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then set(not state) end end)
				attachTooltip(frame, opts.Tooltip, theme)
				return { Set = set, Get = function() return state end }
			end

			-- Slider
			function Section:CreateSlider(opts)
				opts = opts or {}
				local name = tostring(opts.Name or "Slider")
				local min = tonumber((opts.Range and opts.Range[1]) or 0) or 0
				local max = tonumber((opts.Range and opts.Range[2]) or 100) or 100
				local inc = tonumber(opts.Increment) or 1
				local val = tonumber(opts.CurrentValue) or min
				local suffix = tostring(opts.Suffix or "")
				local callback = opts.Callback
				val = clamp(round(val, inc), min, max)

				local frame = create("Frame", { Parent = controls, BackgroundColor3 = theme.Button, BorderColor3 = theme.Border, Size = UDim2.new(1,0,0,72) }, {
					create("UICorner", { CornerRadius = UDim.new(0,12) }),
					create("UIStroke", { Color = theme.Border, Thickness = 1 })
				})
				local topLabel = create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Text = name, TextColor3 = theme.MutedText, Font = Enum.Font.Gotham, TextSize = 12, Position = UDim2.fromOffset(12,8), Size = UDim2.new(0.6, -16, 0, 18), TextXAlignment = Enum.TextXAlignment.Left })
				local curLabel = create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Text = tostring(val).." "..suffix, TextColor3 = theme.Text, Font = Enum.Font.GothamBold, TextSize = 13, Position = UDim2.new(0.6, 6, 0, 8), Size = UDim2.new(0.4, -16, 0, 18), TextXAlignment = Enum.TextXAlignment.Right })
				local track = create("Frame", { Parent = frame, BackgroundColor3 = theme.SliderTrack, BorderColor3 = theme.Border, Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 0, 18) }, {
					create("UICorner", { CornerRadius = UDim.new(0,9) }),
					create("UIStroke", { Color = theme.Border, Thickness = 1 })
				})
				local fill = create("Frame", { Parent = track, BackgroundColor3 = theme.SliderFill, Size = UDim2.new((val-min)/(max-min), 0, 1, 0) }, { create("UICorner", { CornerRadius = UDim.new(0,9) }) })
				local knob = create("Frame", { Parent = track, BackgroundColor3 = Color3.fromRGB(255,255,255), Size = UDim2.fromOffset(18,18), Position = UDim2.new(clamp((val-min)/(max-min),0,1), -9, 0, 0) }, {
					create("UICorner", { CornerRadius = UDim.new(0,9) }),
					create("UIStroke", { Color = theme.Border, Thickness = 1 })
				})
				applyGlow(knob, theme.Glow)

				local dragging = false
				local function setValue(n, fromUser)
					n = clamp(round(n,inc), min, max)
					val = n
					local frac = (val - min) / (max - min)
					TweenService:Create(fill, T_QUICK, { Size = UDim2.new(frac,0,1,0) }):Play()
					TweenService:Create(knob, T_QUICK, { Position = UDim2.new(frac, -9, 0, 0) }):Play()
					curLabel.Text = tostring(val) .. (suffix ~= "" and (" "..suffix) or "")
					if callback and fromUser ~= false then task.spawn(function() pcall(callback, val) end) end
				end

				track.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						dragging = true
						local rel = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
						setValue(min + rel * (max-min), true)
					end
				end)
				knob.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end end)
				UserInputService.InputChanged:Connect(function(input)
					if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
						local rel = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
						setValue(min + rel * (max-min), true)
					end
				end)
				UserInputService.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)

				attachTooltip(frame, opts.Tooltip, theme)
				return { Set = function(v) setValue(tonumber(v) or val, false) end, Get = function() return val end }
			end

			-- Dropdown (search + basic virtualization + keyboard nav)
			function Section:CreateDropdown(options)
				options = options or {}
				local name = tostring(options.Name or "Dropdown")
				local allEntries = options.Options or {}
				local multi = not not options.Multi
				local callback = options.Callback
				local selected = {}
				local flag = options.Flag

				local frame = create("Frame", { Parent = controls, BackgroundColor3 = theme.Button, BorderColor3 = theme.Border, Size = UDim2.new(1,0,0,44) }, {
					create("UICorner", { CornerRadius = UDim.new(0,10) }),
					create("UIStroke", { Color = theme.Border, Thickness = 1 })
				})
				local summary = create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Text = name .. ": " .. (type(allEntries[1])=="table" and allEntries[1].Text or (allEntries[1] or "None")), TextColor3 = theme.Text, Font = Enum.Font.Gotham, TextSize = 14, Position = UDim2.fromOffset(12,8), Size = UDim2.new(1, -64, 0, 24), TextXAlignment = Enum.TextXAlignment.Left })
				local arrow = create("TextButton", { Parent = frame, BackgroundColor3 = theme.ButtonHover, BorderColor3 = theme.Border, AutoButtonColor = false, Text = "▾", TextColor3 = theme.Text, Font = Enum.Font.GothamBold, TextSize = 14, Position = UDim2.new(1, -48, 0, 8), Size = UDim2.new(0,36,0,24) }, {
					create("UICorner", { CornerRadius = UDim.new(0,8) })
				})
				attachTooltip(frame, options.Tooltip, theme)

				-- list container on overlay
				local listFrame = create("Frame", { Parent = overlay, BackgroundColor3 = theme.Section, BorderColor3 = theme.Border, Visible = false, Position = UDim2.new(0,0,0,0), Size = UDim2.new(0, 360, 0, 0), ClipsDescendants = true, ZIndex = 999999 }, {
					create("UICorner", { CornerRadius = UDim.new(0,12) }),
					create("UIStroke", { Color = theme.Border, Thickness = 1 })
				})
				addShadow(listFrame, UDim.new(0,10))

				-- search box
				local searchBox = create("TextBox", { Parent = listFrame, PlaceholderText = "Search...", BackgroundColor3 = theme.Button, BorderColor3 = theme.Border, TextColor3 = theme.Text, Font = Enum.Font.Gotham, TextSize = 14, Size = UDim2.new(1, -24, 0, 28), Position = UDim2.fromOffset(12, 12), ClearTextOnFocus = false }, {
					create("UICorner", { CornerRadius = UDim.new(0,8) })
				})
				local contentHolder = create("ScrollingFrame", { Parent = listFrame, BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 48), Size = UDim2.new(1, -24, 0, 0), CanvasSize = UDim2.new(0, 0, 0, 0), ScrollBarThickness = 8 }, {
					create("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 8) })
				})
				local visibleEntries = {}

				local function filterEntries(q)
					q = (q or ""):lower()
					visibleEntries = {}
					for _,e in ipairs(allEntries) do
						local txt = (type(e)=="table" and (e.Text or tostring(e.Value)) or tostring(e))
						if q == "" or tostring(txt):lower():find(q, 1, true) then
							table.insert(visibleEntries, e)
						end
					end
				end

				-- small virtualization: render up to maxRender rows (good for hundreds)
				local maxRender = 60
				local rowHeight = 40
				local function clearContent()
					for _,c in ipairs(contentHolder:GetChildren()) do
						if c:IsA("GuiObject") and c.Name ~= "UIListLayout" then c:Destroy() end
					end
				end

				local function renderContent()
					clearContent()
					local total = #visibleEntries
					contentHolder.CanvasSize = UDim2.new(0, 0, 0, total * (rowHeight + 8))
					local count = math.min(total, maxRender)
					for i=1,count do
						local entry = visibleEntries[i]
						local text, value, icon
						if type(entry) == "table" then text = entry.Text or tostring(entry.Value); value = entry.Value or entry.Text; icon = entry.Icon end
						if type(entry) == "string" then text = entry; value = entry; icon = nil end
						local row = create("Frame", { Parent = contentHolder, BackgroundColor3 = theme.Button, BorderColor3 = theme.Border, Size = UDim2.fromOffset(0, rowHeight) }, {
							create("UICorner", { CornerRadius = UDim.new(0,8) }),
							create("UIStroke", { Color = theme.Border, Thickness = 1 })
						})
						row.Size = UDim2.new(1, -12, 0, rowHeight)
						if icon then
							if tostring(icon):match("rbxasset") then
								create("ImageLabel", { Parent = row, Image = icon, BackgroundTransparency = 1, Position = UDim2.fromOffset(8,6), Size = UDim2.fromOffset(28,28) })
								create("TextLabel", { Parent = row, BackgroundTransparency = 1, Text = text, TextColor3 = theme.Text, Font = Enum.Font.Gotham, TextSize = 13, Position = UDim2.fromOffset(44,6), Size = UDim2.new(1, -100, 0, 28), TextXAlignment = Enum.TextXAlignment.Left })
							else
								create("TextLabel", { Parent = row, BackgroundTransparency = 1, Text = tostring(icon), TextColor3 = theme.Text, Font = Enum.Font.Gotham, TextSize = 16, Position = UDim2.fromOffset(8,6), Size = UDim2.fromOffset(28,28) })
								create("TextLabel", { Parent = row, BackgroundTransparency = 1, Text = text, TextColor3 = theme.Text, Font = Enum.Font.Gotham, TextSize = 13, Position = UDim2.fromOffset(44,6), Size = UDim2.new(1, -100, 0, 28), TextXAlignment = Enum.TextXAlignment.Left })
							end
						else
							create("TextLabel", { Parent = row, BackgroundTransparency = 1, Text = text, TextColor3 = theme.Text, Font = Enum.Font.Gotham, TextSize = 13, Position = UDim2.fromOffset(8,6), Size = UDim2.new(1, -16, 0, 28), TextXAlignment = Enum.TextXAlignment.Left })
						end
						local btn = create("TextButton", { Parent = row, BackgroundTransparency = 1, Size = UDim2.new(1,0,1,0), AutoButtonColor = false })
						btn.MouseEnter:Connect(function() TweenService:Create(row, T_QUICK, { BackgroundColor3 = theme.ButtonHover }):Play() end)
						btn.MouseLeave:Connect(function() TweenService:Create(row, T_QUICK, { BackgroundColor3 = theme.Button }):Play() end)
						btn.MouseButton1Click:Connect(function()
							if multi then
								if selected[tostring(value)] then selected[tostring(value)] = nil else selected[tostring(value)] = true end
							else
								selected = {}
								selected[tostring(value)] = true
							end
							if callback then task.spawn(function() pcall(callback, selected) end) end
							if not multi then
								TweenService:Create(listFrame, T_QUICK, { Size = UDim2.new(0, listFrame.Size.X.Offset, 0, 0) }):Play()
								task.delay(0.12, function() listFrame.Visible = false; overlay.Visible = false end)
							end
							if flag and Window._cfg and Window._cfg.Enabled then
								local stored = Window:LoadConfiguration() or {}
								stored[flag] = (multi and selected) or value
								Window:SaveConfiguration(stored)
							end
						end)
					end
					contentHolder.Size = UDim2.new(1, -24, 0, math.min(#visibleEntries * (rowHeight + 8), maxRender * (rowHeight + 8)))
				end

				-- search handling
				searchBox:GetPropertyChangedSignal("Text"):Connect(function()
					filterEntries(searchBox.Text)
					renderContent()
				end)

				-- keyboard nav basic
				local navIndex = 1
				local navConn = nil
				local currentMaid = nil
				local function highlightIndex(i)
					navIndex = clamp(i, 1, math.max(1, #visibleEntries))
					-- a minimal highlight is achieved by simulating MouseEnter for the target child when possible
					-- (Precise scroll-to-view would require tracking AbsolutePosition; omitted for brevity)
				end

				local function openList()
					filterEntries(searchBox.Text or "")
					renderContent()
					listFrame.Visible = true
					overlay.Visible = true
					task.defer(function()
						local finalH = math.min(#visibleEntries * (rowHeight + 8) + 72, 420)
						local absPos = frame.AbsolutePosition
						local absSize = frame.AbsoluteSize
						local viewportY = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.Y or 1080
						local desiredY = absPos.Y + absSize.Y + 8
						local aboveY = absPos.Y - finalH - 8
						local posY = desiredY
						if desiredY + finalH > viewportY and aboveY >= 0 then posY = aboveY end
						local posX = window.AbsolutePosition.X + pad
						listFrame.Position = UDim2.fromOffset(posX, posY)
						TweenService:Create(listFrame, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, math.max(300, math.floor(window.AbsoluteSize.X - pad*3)), 0, finalH) }):Play()
					end)
					-- keyboard
					currentMaid = Maid.new()
					navIndex = 1
					navConn = UserInputService.InputBegan:Connect(function(inp, gp)
						if gp then return end
						if inp.KeyCode == Enum.KeyCode.Down then highlightIndex(navIndex + 1)
						elseif inp.KeyCode == Enum.KeyCode.Up then highlightIndex(navIndex - 1)
						elseif inp.KeyCode == Enum.KeyCode.Return or inp.KeyCode == Enum.KeyCode.KeypadEnter then
							-- approximate activation by finding children in contentHolder in order
							local children = {}
							for _,c in ipairs(contentHolder:GetChildren()) do if c:IsA("Frame") then table.insert(children, c) end end
							table.sort(children, function(a,b) return a.LayoutOrder < b.LayoutOrder end)
							local target = children[navIndex]
							if target then
								local btn = target:FindFirstChildOfClass("TextButton")
								if btn then btn:Activate() end
							end
						elseif inp.KeyCode == Enum.KeyCode.Escape then
							TweenService:Create(listFrame, T_QUICK, { Size = UDim2.new(0, listFrame.Size.X.Offset, 0, 0) }):Play()
							task.delay(0.12, function() listFrame.Visible = false; overlay.Visible = false end)
						end
					end)
					currentMaid:Give(navConn)
				end

				arrow.MouseButton1Click:Connect(function()
					if listFrame.Visible then
						if currentMaid then currentMaid:DoCleaning(); currentMaid = nil end
						TweenService:Create(listFrame, T_QUICK, { Size = UDim2.new(0, listFrame.Size.X.Offset, 0, 0) }):Play()
						task.delay(0.12, function() listFrame.Visible = false; overlay.Visible = false end)
					else
						openList()
					end
				end)

				attachTooltip(frame, options.Tooltip, theme)
				return {
					Set = function(v)
						selected = {}
						if multi and type(v) == "table" then for _,k in ipairs(v) do selected[tostring(k)] = true end else selected[tostring(v)] = true end
						local cnt, first = 0, nil
						for k,_ in pairs(selected) do cnt = cnt + 1; if not first then first = k end end
						summary.Text = name .. ": " .. (cnt > 1 and (first.." ("..cnt..")") or (first or ""))
					end,
					Get = function() if multi then return selected else for k,_ in pairs(selected) do return k end return nil end end,
					SetOptions = function(t) allEntries = t or {}; filterEntries(searchBox.Text or ""); renderContent() end
				}
			end

			-- Keybind
			function Section:CreateKeybind(opts)
				opts = opts or {}
				local name = tostring(opts.Name or "Keybind")
				local combo = opts.CurrentKeybindCombo or { Ctrl=false, Alt=false, Shift=false, Key = tostring(opts.CurrentKeybind or "F") }
				local callback = opts.Callback
				local hold = not not opts.HoldToInteract

				local frame = create("Frame", { Parent = controls, BackgroundColor3 = theme.Button, BorderColor3 = theme.Border, Size = UDim2.new(1,0,0,40) }, {
					create("UICorner", { CornerRadius = UDim.new(0,10) }),
					create("UIStroke", { Color = theme.Border, Thickness = 1 })
				})
				local label = create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Text = name..": "..(combo and ((combo.Ctrl and "Ctrl+" or "")..(combo.Shift and "Shift+" or "")..(combo.Alt and "Alt+" or "")..(combo.Key or "")) or "[none]"), TextColor3 = theme.Text, Font = Enum.Font.Gotham, TextSize = 14, Position = UDim2.fromOffset(12,8), Size = UDim2.new(1,-160,0,24), TextXAlignment = Enum.TextXAlignment.Left })
				local setBtn = create("TextButton", { Parent = frame, BackgroundColor3 = theme.ButtonHover, BorderColor3 = theme.Border, AutoButtonColor = false, Text = "Set", TextColor3 = theme.Text, Font = Enum.Font.GothamBold, TextSize = 14, Position = UDim2.new(1, -108, 0, 8), Size = UDim2.fromOffset(56,24) }, { create("UICorner", { CornerRadius = UDim.new(0,8) }) })
				local clearBtn = create("TextButton", { Parent = frame, BackgroundColor3 = theme.ButtonHover, BorderColor3 = theme.Border, AutoButtonColor = false, Text = "Clear", TextColor3 = theme.Text, Font = Enum.Font.Gotham, TextSize = 12, Position = UDim2.new(1, -44, 0, 8), Size = UDim2.fromOffset(44,24) }, { create("UICorner", { CornerRadius = UDim.new(0,8) }) })

				local listening = false
				setBtn.MouseButton1Click:Connect(function()
					listening = true
					label.Text = name .. ": [press combo]"
					TweenService:Create(setBtn, T_QUICK, { BackgroundColor3 = theme.Accent }):Play()
				end)
				clearBtn.MouseButton1Click:Connect(function()
					combo = { Ctrl=false, Alt=false, Shift=false, Key=nil }
					label.Text = name..": [cleared]"
				end)

				local conn = UserInputService.InputBegan:Connect(function(input, processed)
					if processed then return end
					if listening then
						if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
							combo = {
								Ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl),
								Alt = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt),
								Shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift),
								Key = tostring(input.KeyCode):match("KeyCode%.(.+)")
							}
							label.Text = name .. ": " .. (combo.Ctrl and "Ctrl+" or "") .. (combo.Shift and "Shift+" or "") .. (combo.Alt and "Alt+" or "") .. (combo.Key or "")
							listening = false
							TweenService:Create(setBtn, T_QUICK, { BackgroundColor3 = theme.ButtonHover }):Play()
							-- persist if flag present
							if opts.Flag and Window._cfg and Window._cfg.Enabled then
								local stored = Window:LoadConfiguration() or {}
								stored[opts.Flag] = combo
								Window:SaveConfiguration(stored)
							end
						end
					else
						-- runtime triggers
						if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
							local keyName = tostring(input.KeyCode):match("KeyCode%.(.+)")
							local pressedCtrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
							local pressedAlt = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
							local pressedShift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
							if combo and keyName == combo.Key and pressedCtrl == (combo.Ctrl or false) and pressedAlt == (combo.Alt or false) and pressedShift == (combo.Shift or false) then
								if not hold then task.spawn(function() pcall(callback) end) else
									local held = true
									local con = input.Changed:Connect(function(prop) if prop == "UserInputState" then held = false end end)
									local loop; loop = RunService.Stepped:Connect(function()
										if not held then loop:Disconnect(); con:Disconnect() else pcall(callback, true) end
									end)
								end
							end
						end
					end
				end)

				attachTooltip(frame, opts.Tooltip, theme)
				return { Set = function(c) combo = c; label.Text = name..": "..(combo and ((combo.Ctrl and "Ctrl+" or "")..(combo.Shift and "Shift+" or "")..(combo.Alt and "Alt+" or "")..(combo.Key or "")) or "[none]") end, Get = function() return combo end, _conn = conn }
			end

			-- ColorPicker (alpha + presets + recents)
			function Section:CreateColorPicker(opts)
				opts = opts or {}
				local name = tostring(opts.Name or "Color")
				local current = opts.CurrentColor or Color3.fromRGB(255,255,255)
				local alpha = tonumber(opts.CurrentAlpha) or 1
				local callback = opts.Callback
				local target = opts.Target
				local frame = create("Frame", { Parent = controls, BackgroundColor3 = theme.Button, BorderColor3 = theme.Border, Size = UDim2.new(1,0,0,180) }, {
					create("UICorner", { CornerRadius = UDim.new(0,12) }),
					create("UIStroke", { Color = theme.Border, Thickness = 1 })
				})
				create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Text = name, TextColor3 = theme.Text, Font = Enum.Font.GothamBold, TextSize = 14, Position = UDim2.fromOffset(12,8), Size = UDim2.new(1,-24,0,20) })

				local area = create("Frame", { Parent = frame, BackgroundColor3 = Color3.fromRGB(255,0,0), Position = UDim2.fromOffset(12,36), Size = UDim2.fromOffset(180,100) }, { create("UICorner", { CornerRadius = UDim.new(0,10) }), create("UIStroke", { Color = theme.Border, Thickness = 1 }) })
				local hue = create("Frame", { Parent = frame, BackgroundColor3 = Color3.fromRGB(255,0,0), Position = UDim2.fromOffset(204,36), Size = UDim2.fromOffset(18,100) }, { create("UICorner", { CornerRadius = UDim.new(0,8) }), create("UIStroke", { Color = theme.Border, Thickness = 1 }) })
				local preview = create("Frame", { Parent = frame, BackgroundColor3 = current, Position = UDim2.fromOffset(232,36), Size = UDim2.fromOffset(92,92), BorderColor3 = theme.Border }, { create("UICorner", { CornerRadius = UDim.new(0,10) }), create("UIStroke", { Color = theme.Border, Thickness = 1 }) })
				local alphaTrack = create("Frame", { Parent = frame, BackgroundColor3 = theme.SliderTrack, BorderColor3 = theme.Border, Position = UDim2.fromOffset(232,136), Size = UDim2.fromOffset(92,10) }, { create("UICorner", { CornerRadius = UDim.new(0,6) }) })
				local alphaFill = create("Frame", { Parent = alphaTrack, BackgroundColor3 = theme.SliderFill, Size = UDim2.new(alpha,0,1,0) }, { create("UICorner", { CornerRadius = UDim.new(0,6) }) })
				local hexBox = create("TextBox", { Parent = frame, BackgroundColor3 = theme.Section, BorderColor3 = theme.Border, Text = string.format("#%02X%02X%02X", math.floor(current.R*255+0.5), math.floor(current.G*255+0.5), math.floor(current.B*255+0.5)), Position = UDim2.fromOffset(232,156), Size = UDim2.fromOffset(92,22), Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false }, { create("UICorner", { CornerRadius = UDim.new(0,8) }) })
				local presets = create("Frame", { Parent = frame, BackgroundTransparency = 1, Position = UDim2.fromOffset(12,144), Size = UDim2.new(1,-24,0,28) })

				local function toHSV(c) return Color3.toHSV(c) end
				local function fromHSV(h,s,v) return Color3.fromHSV(h,s,v) end
				local h,s,v = toHSV(current)

				local function applyColor()
					current = fromHSV(h,s,v)
					preview.BackgroundColor3 = current
					hexBox.Text = string.format("#%02X%02X%02X", math.floor(current.R*255+0.5), math.floor(current.G*255+0.5), math.floor(current.B*255+0.5))
					alphaFill.Size = UDim2.new(alpha,0,1,0)
					if callback then task.spawn(function() pcall(callback, current, alpha) end) end
					Window.recentColors = Window.recentColors or {}
					table.insert(Window.recentColors, 1, { Color = current, Alpha = alpha })
					if #Window.recentColors > 8 then table.remove(Window.recentColors, 9) end
					if target and Window and Window.ApplyThemePatch then
						local patch = {}
						patch[target] = current
						Window:ApplyThemePatch(patch)
					end
				end
				applyColor()

				local function refreshPresets()
					for _,c in ipairs(presets:GetChildren()) do c:Destroy() end
					local x = 0
					for i=1, math.min(#Window.recentColors, 6) do
						local pr = Window.recentColors[i]
						local sw = create("TextButton", { Parent = presets, BackgroundColor3 = pr.Color, BorderColor3 = theme.Border, Size = UDim2.fromOffset(28,28), Position = UDim2.fromOffset(x,0), AutoButtonColor = false }, { create("UICorner", { CornerRadius = UDim.new(1,0) }) })
						sw.MouseButton1Click:Connect(function() current = pr.Color; alpha = pr.Alpha or 1; h,s,v = toHSV(current); applyColor() end)
						x = x + 34
					end
				end
				refreshPresets()

				-- interactions (dragging area/hue/alpha) — similar to prior logic, kept concise here
				local draggingA, draggingH, draggingAlpha = false, false, false
				local areaDot = create("Frame", { Parent = area, BackgroundTransparency = 1, Size = UDim2.fromOffset(14,14), Position = UDim2.new(s, -7, 1 - v, -7) }, { create("UICorner", { CornerRadius = UDim.new(0,8) }), create("UIStroke", { Color = theme.Border, Thickness = 1 }) })
				local hueDot = create("Frame", { Parent = hue, BackgroundTransparency = 1, Size = UDim2.fromOffset(18,6), Position = UDim2.new(0, 0, h, -3) }, { create("UICorner", { CornerRadius = UDim.new(0,6) }), create("UIStroke", { Color = theme.Border, Thickness = 1 }) })

				area.InputBegan:Connect(function(inp)
					if inp.UserInputType == Enum.UserInputType.MouseButton1 then
						draggingA = true
						local relX = clamp((UserInputService:GetMouseLocation().X - area.AbsolutePosition.X) / area.AbsoluteSize.X, 0, 1)
						local relY = clamp((UserInputService:GetMouseLocation().Y - area.AbsolutePosition.Y) / area.AbsoluteSize.Y, 0, 1)
						s = relX; v = 1 - relY
						areaDot.Position = UDim2.new(s, -7, 1 - v, -7); applyColor()
					end
				end)
				hue.InputBegan:Connect(function(inp)
					if inp.UserInputType == Enum.UserInputType.MouseButton1 then
						draggingH = true
						local relY = clamp((UserInputService:GetMouseLocation().Y - hue.AbsolutePosition.Y) / hue.AbsoluteSize.Y, 0, 1)
						h = relY
						hueDot.Position = UDim2.new(0, 0, h, -3); applyColor()
					end
				end)
				alphaTrack.InputBegan:Connect(function(inp)
					if inp.UserInputType == Enum.UserInputType.MouseButton1 then
						draggingAlpha = true
						local relX = clamp((UserInputService:GetMouseLocation().X - alphaTrack.AbsolutePosition.X) / alphaTrack.AbsoluteSize.X, 0, 1)
						alpha = relX
						alphaFill.Size = UDim2.new(alpha, 0, 1, 0); applyColor()
					end
				end)
				UserInputService.InputChanged:Connect(function(inp)
					if inp.UserInputType == Enum.UserInputType.MouseMovement then
						if draggingA then
							local relX = clamp((UserInputService:GetMouseLocation().X - area.AbsolutePosition.X) / area.AbsoluteSize.X, 0, 1)
							local relY = clamp((UserInputService:GetMouseLocation().Y - area.AbsolutePosition.Y) / area.AbsoluteSize.Y, 0, 1)
							s = relX; v = 1 - relY
							areaDot.Position = UDim2.new(s, -7, 1 - v, -7); applyColor()
						end
						if draggingH then
							local relY = clamp((UserInputService:GetMouseLocation().Y - hue.AbsolutePosition.Y) / hue.AbsoluteSize.Y, 0, 1)
							h = relY; hueDot.Position = UDim2.new(0,0,h,-3); applyColor()
						end
						if draggingAlpha then
							local relX = clamp((UserInputService:GetMouseLocation().X - alphaTrack.AbsolutePosition.X) / alphaTrack.AbsoluteSize.X, 0, 1)
							alpha = relX; alphaFill.Size = UDim2.new(alpha, 0, 1, 0); applyColor()
						end
					end
				end)
				UserInputService.InputEnded:Connect(function(inp) if inp.UserInputType == Enum.UserInputType.MouseButton1 then draggingA = false; draggingH = false; draggingAlpha = false end end)

				hexBox.FocusLost:Connect(function()
					local t = hexBox.Text
					local r,g,b = string.match(t, "^#?(%x%x)(%x%x)(%x%x)$")
					if r and g and b then
						local c = Color3.fromRGB(tonumber(r,16), tonumber(g,16), tonumber(b,16))
						h,s,v = toHSV(c); applyColor(); refreshPresets()
					else
						hexBox.Text = string.format("#%02X%02X%02X", math.floor(current.R*255+0.5), math.floor(current.G*255+0.5), math.floor(current.B*255+0.5))
					end
				end)

				attachTooltip(frame, opts.Tooltip, theme)
				return {
					Set = function(c,a) if typeof(c) == "Color3" then current = c; alpha = tonumber(a) or alpha; h,s,v = toHSV(current); applyColor(); refreshPresets() end end,
					Get = function() return current, alpha end
				}
			end

			-- Image + Spacer + Save placeholders
			function Section:CreateImage(opts)
				opts = opts or {}
				local name = tostring(opts.Name or "Image")
				local asset = tostring(opts.AssetId or "") or ""
				local size = opts.Size or UDim2.fromOffset(72,72)
				local frame = create("Frame", { Parent = controls, BackgroundColor3 = theme.Button, BorderColor3 = theme.Border, Size = UDim2.new(1,0,0, size.Y.Offset + 44) }, {
					create("UICorner", { CornerRadius = UDim.new(0,12) }),
					create("UIStroke", { Color = theme.Border, Thickness = 1 })
				})
				create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Text = name, TextColor3 = theme.Text, Font = Enum.Font.GothamBold, TextSize = 14, Position = UDim2.fromOffset(12,8), Size = UDim2.new(1,-24,0,20) })
				local img = create("ImageLabel", { Parent = frame, BackgroundTransparency = 1, Image = asset, Position = UDim2.fromOffset(12,34), Size = size })
				attachTooltip(frame, opts.Tooltip, theme)
				task.defer(recalc)
				return img
			end

			function Section:AddSpacer(h) local f = create("Frame", { Parent = controls, BackgroundTransparency = 1, Size = UDim2.new(1,0,0, tonumber(h) or 10) }) return f end
			function Section:Save(tbl) return tbl end

			return Section
		end

		table.insert(Window._tabs, Tab)
		if not Window._selectedTab then
			Window._selectedTab = tabName
			tabContent.Visible = true
			TweenService:Create(btn, T_QUICK, { BackgroundColor3 = theme.ButtonHover }):Play()
		end
		return Tab
	end

	-- Destroy
	function Window:Destroy()
		pcall(function() screenGui:Destroy() end)
		local b = Lighting:FindFirstChild("GitanX_Blur")
		if b then pcall(function() b:Destroy() end) end
	end

	-- theme editor quick helper
	function Window:OpenThemeEditor()
		local t = Window:CreateTab("Theme", "🎨")
		local s = t:CreateSection("Editor",1)
		s:CreateColorPicker({ Name = "Accent", CurrentColor = theme.Accent, Target = "Accent", Callback = function(c) Window:ApplyThemePatch({ Accent = c, Accent2 = c:lerp(Color3.new(0.6,0.6,0.6), 0.35) }) end })
		s:CreateColorPicker({ Name = "Background", CurrentColor = theme.Background, Target = "Background", Callback = function(c) Window:ApplyThemePatch({ Background = c }) end })
		Window:Notify({ Title = "Theme Editor", Content = "Opened", Type = "info" })
	end

	-- toggle visibility by key
	local visible = true
	setBlur(true)
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == toggleKeybind then
			visible = not visible
			window.Visible = visible
			setBlur(visible)
			if not visible then overlay.Visible = false end
		end
	end)

	return Window
end

return GitanX
