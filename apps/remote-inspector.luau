--!strict
-- Sentinel App: Remote Inspector
-- Lists every RemoteEvent/RemoteFunction, the scripts that handle it on the server,
-- and whether those handlers validate arguments and rate-limit callers.

local App = {}
App.Id = "remote-inspector"
App.Name = "Remote Inspector"
App.Version = "1.0.0"

local ctx: any = nil
local root: Frame? = nil

function App.Init(c: any)
	ctx = c
end

local function escapePattern(s: string): string
	return (string.gsub(s, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

type Handler = { Script: LuaSourceContainer, Validates: boolean, RateLimits: boolean, Level: string }
type Info = { Remote: Instance, Handlers: { Handler }, Clients: number }

local function inspect(): { Info }
	local scripts = ctx.Instances.GetScripts()
	local sources = {}
	for _, s in scripts do
		sources[s] = ctx.Instances.GetSource(s)
	end
	local out: { Info } = {}
	for _, r in ctx.Instances.GetRemotes() do
		local pat = "[^%w_]" .. escapePattern(r.Name) .. "[^%w_]"
		local info: Info = { Remote = r, Handlers = {}, Clients = 0 }
		for s, src in sources do
			if not string.find(" " .. src .. " ", pat) then
				continue
			end
			if string.find(src, "OnServerEvent") or string.find(src, "OnServerInvoke") then
				local validates = string.find(src, "typeof%s*%(") ~= nil or string.find(src, "type%s*%(") ~= nil
				local rate = string.find(src, "os%.clock") ~= nil or string.find(src, "tick%s*%(") ~= nil or string.find(src, "cooldown") ~= nil or string.find(src, "Cooldown") ~= nil
				local level = ctx.Scanner.Analyze(src, s:GetFullName()).Level
				table.insert(info.Handlers, { Script = s, Validates = validates, RateLimits = rate, Level = level })
			elseif s:IsA("LocalScript") or string.find(src, "FireServer") or string.find(src, "InvokeServer") then
				info.Clients += 1
			end
		end
		table.insert(out, info)
	end
	table.sort(out, function(a, b)
		return #a.Handlers < #b.Handlers
	end)
	return out
end

local function render(list: Instance)
	local W = ctx.UI.Widgets
	local T = ctx.UI.Theme
	W.ClearChildren(list, true)
	local infos = inspect()
	if #infos == 0 then
		local c = W.Card(list, 1)
		W.Label(c, "No RemoteEvents or RemoteFunctions found in this place.", { Color = "SubText" })
		return
	end
	for i, info in infos do
		local c = W.Card(list, i)
		local head = W.Row(c, 0)
		W.Badge(head, info.Remote.ClassName, T.Get("Accent"), 1)
		local name = W.Label(head, info.Remote:GetFullName(), { Bold = true, Wrap = false, Order = 2 })
		name.RichText = false
		if #info.Handlers == 0 then
			W.Label(c, "⚠ No server handler found by name. Unused remotes are safe to remove; remotes created by other scripts at runtime won't show here.", { Color = "Warn", Size = 13, Order = 1 })
		end
		for j, h in info.Handlers do
			local row = W.Row(c, 1 + j)
			W.Button(row, "Open", function()
				ctx.Selection.Select({ h.Script })
				ctx.Selection.Open(h.Script, 1)
			end, "Ghost", 1)
			local notes = {}
			table.insert(notes, if h.Validates then "✓ checks types" else "✗ no type checks")
			table.insert(notes, if h.RateLimits then "✓ rate limit" else "✗ no rate limit")
			if h.Level ~= "Clean" and h.Level ~= "Low" then
				table.insert(notes, "scanner: " .. h.Level)
			end
			local l = W.Label(row, h.Script:GetFullName() .. "  —  " .. table.concat(notes, " · "), { Size = 13, Order = 2, Width = UDim.new(1, -70) })
			l.RichText = false
		end
		W.Label(c, string.format("Client scripts using it: %d", info.Clients), { Color = "DimText", Size = 12, Order = 100 })
	end
end

function App.Mount(parent: Frame)
	local W = ctx.UI.Widgets
	local scroll = W.Scroll(parent)
	root = scroll :: any
	local bar = W.Row(scroll, 0)
	local list = W.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = scroll,
	})
	W.List(list, 8)
	W.Button(bar, "Refresh", function()
		render(list)
	end, "Primary", 1)
	render(list)
end

function App.Unmount()
	if root then
		(root :: Frame):Destroy()
		root = nil
	end
end

return App
