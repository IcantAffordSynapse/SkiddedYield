-- Infinite Yield -- ESP / Visual command set
-- Real logic ported from IY, adapted to run(args, speaker) + makeExLine.

--=====================================================================
-- SHARED SERVICES / STATE / HELPERS
--=====================================================================

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local Workspace   = workspace

local LocalPlayer = Players.LocalPlayer

-- Hidden-UI container: use the executor's gethui() if present so game
-- scripts can't easily find/wipe the ESP folders; else fall back to CoreGui.
local COREGUI
do
    local ok, hidden = pcall(function()
        local f = gethui or get_hidden_gui
        return f and f()
    end)
    COREGUI = (ok and hidden) or game:GetService("CoreGui")
end

local function notify(title, text)
    if text ~= nil then
        makeExLine(tostring(title) .. ": " .. tostring(text))
    else
        makeExLine(tostring(title))
    end
end

local function getRoot(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return hum and hum.RootPart
end

local function round(num, dp)
    local mult = 10 ^ (dp or 0)
    return math.floor(num * mult + 0.5) / mult
end

local function isNumber(str)
    return tonumber(str) ~= nil or str == "inf"
end

local function getstring(begin, args)
    return table.concat(args, " ", begin)
end

local function FindInTable(tbl, val)
    if tbl == nil then return false end
    for _, v in pairs(tbl) do if v == val then return true end end
    return false
end

-- shared visual state
local ESPenabled     = false
local CHMSenabled    = false
local espTransparency = 0.3
local xrayEnabled    = false

-- point at your dispatcher so toggle* / cross-calling commands work
local execCmd = function(_) end

--=====================================================================
-- getPlayer (compact) -- ESP set only needs simple name/self resolution.
-- If you already merged the teleport module's full getPlayer, delete this
-- and let the shared one win; the signatures match (returns names).
--=====================================================================

local function splitString(str, delim)
    local broken = {}
    delim = delim or ","
    for w in string.gmatch(str, "[^" .. delim .. "]+") do table.insert(broken, w) end
    return broken
end

local function getPlayer(list, speaker)
    if list == nil then return { speaker.Name } end
    local found = {}
    for _, name in pairs(splitString(list, ",")) do
        local low = name:lower()
        if low == "all" then
            return (function() local t = {} for _, p in pairs(Players:GetPlayers()) do t[#t+1]=p.Name end return t end)()
        elseif low == "others" then
            for _, p in pairs(Players:GetPlayers()) do if p ~= speaker then found[#found+1] = p.Name end end
        elseif low == "me" then
            found[#found+1] = speaker.Name
        else
            local at = low:sub(1,1) == "@"
            local q = at and low:sub(2) or low
            for _, p in pairs(Players:GetPlayers()) do
                local target = at and p.Name:lower() or p.Name:lower()
                if p.Name:lower():sub(1, #q) == q or (not at and p.DisplayName:lower():sub(1, #q) == q) then
                    found[#found+1] = p.Name
                end
            end
        end
    end
    return found
end

--=====================================================================
-- ESP ENGINE -- boxes + name/health/distance billboard, self-rehooking
--=====================================================================

local function ESP(plr, logic)
    task.spawn(function()
        for _, v in pairs(COREGUI:GetChildren()) do
            if v.Name == plr.Name .. "_ESP" then v:Destroy() end
        end
        task.wait()
        if plr.Character and plr.Name ~= LocalPlayer.Name and not COREGUI:FindFirstChild(plr.Name .. "_ESP") then
            local ESPholder = Instance.new("Folder")
            ESPholder.Name = plr.Name .. "_ESP"
            ESPholder.Parent = COREGUI
            repeat task.wait(1) until plr.Character and getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")

            for _, n in pairs(plr.Character:GetChildren()) do
                if n:IsA("BasePart") then
                    local a = Instance.new("BoxHandleAdornment")
                    a.Name = plr.Name
                    a.Parent = ESPholder
                    a.Adornee = n
                    a.AlwaysOnTop = true
                    a.ZIndex = 10
                    a.Size = n.Size
                    a.Transparency = espTransparency
                    if logic == true then
                        a.Color = BrickColor.new(plr.TeamColor == LocalPlayer.TeamColor and "Bright green" or "Bright red")
                    else
                        a.Color = plr.TeamColor
                    end
                end
            end

            if plr.Character and plr.Character:FindFirstChild("Head") then
                local BillboardGui = Instance.new("BillboardGui")
                local TextLabel = Instance.new("TextLabel")
                BillboardGui.Adornee = plr.Character.Head
                BillboardGui.Name = plr.Name
                BillboardGui.Parent = ESPholder
                BillboardGui.Size = UDim2.new(0, 100, 0, 150)
                BillboardGui.StudsOffset = Vector3.new(0, 1, 0)
                BillboardGui.AlwaysOnTop = true
                TextLabel.Parent = BillboardGui
                TextLabel.BackgroundTransparency = 1
                TextLabel.Position = UDim2.new(0, 0, 0, -50)
                TextLabel.Size = UDim2.new(0, 100, 0, 100)
                TextLabel.Font = Enum.Font.SourceSansSemibold
                TextLabel.TextSize = 20
                TextLabel.TextColor3 = Color3.new(1, 1, 1)
                TextLabel.TextStrokeTransparency = 0
                TextLabel.TextYAlignment = Enum.TextYAlignment.Bottom
                TextLabel.Text = "Name: " .. plr.Name
                TextLabel.ZIndex = 10

                local espLoopFunc, teamChange, addedFunc

                addedFunc = plr.CharacterAdded:Connect(function()
                    if ESPenabled then
                        espLoopFunc:Disconnect()
                        teamChange:Disconnect()
                        ESPholder:Destroy()
                        repeat task.wait(1) until getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")
                        ESP(plr, logic)
                        addedFunc:Disconnect()
                    else
                        teamChange:Disconnect()
                        addedFunc:Disconnect()
                    end
                end)

                teamChange = plr:GetPropertyChangedSignal("TeamColor"):Connect(function()
                    if ESPenabled then
                        espLoopFunc:Disconnect()
                        addedFunc:Disconnect()
                        ESPholder:Destroy()
                        repeat task.wait(1) until getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")
                        ESP(plr, logic)
                        teamChange:Disconnect()
                    else
                        teamChange:Disconnect()
                    end
                end)

                espLoopFunc = RunService.RenderStepped:Connect(function()
                    if COREGUI:FindFirstChild(plr.Name .. "_ESP") then
                        if plr.Character and getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")
                           and LocalPlayer.Character and getRoot(LocalPlayer.Character) then
                            local pos = math.floor((getRoot(LocalPlayer.Character).Position - getRoot(plr.Character).Position).Magnitude)
                            TextLabel.Text = "Name: " .. plr.Name
                                .. " | Health: " .. round(plr.Character:FindFirstChildOfClass("Humanoid").Health, 1)
                                .. " | Studs: " .. pos
                        end
                    else
                        teamChange:Disconnect()
                        addedFunc:Disconnect()
                        espLoopFunc:Disconnect()
                    end
                end)
            end
        end
    end)
end

--=====================================================================
-- CHAMS ENGINE -- boxes only (no billboard text)
--=====================================================================

local function CHMS(plr)
    task.spawn(function()
        for _, v in pairs(COREGUI:GetChildren()) do
            if v.Name == plr.Name .. "_CHMS" then v:Destroy() end
        end
        task.wait()
        if plr.Character and plr.Name ~= LocalPlayer.Name and not COREGUI:FindFirstChild(plr.Name .. "_CHMS") then
            local ESPholder = Instance.new("Folder")
            ESPholder.Name = plr.Name .. "_CHMS"
            ESPholder.Parent = COREGUI
            repeat task.wait(1) until plr.Character and getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")

            for _, n in pairs(plr.Character:GetChildren()) do
                if n:IsA("BasePart") then
                    local a = Instance.new("BoxHandleAdornment")
                    a.Name = plr.Name
                    a.Parent = ESPholder
                    a.Adornee = n
                    a.AlwaysOnTop = true
                    a.ZIndex = 10
                    a.Size = n.Size
                    a.Transparency = espTransparency
                    a.Color = plr.TeamColor
                end
            end

            local addedFunc, teamChange, chmsRemoved
            addedFunc = plr.CharacterAdded:Connect(function()
                if CHMSenabled then
                    ESPholder:Destroy()
                    teamChange:Disconnect()
                    repeat task.wait(1) until getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")
                    CHMS(plr)
                    addedFunc:Disconnect()
                else
                    teamChange:Disconnect()
                    addedFunc:Disconnect()
                end
            end)
            teamChange = plr:GetPropertyChangedSignal("TeamColor"):Connect(function()
                if CHMSenabled then
                    ESPholder:Destroy()
                    addedFunc:Disconnect()
                    repeat task.wait(1) until getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")
                    CHMS(plr)
                    teamChange:Disconnect()
                else
                    teamChange:Disconnect()
                end
            end)
            chmsRemoved = ESPholder.AncestryChanged:Connect(function()
                teamChange:Disconnect()
                addedFunc:Disconnect()
                chmsRemoved:Disconnect()
            end)
        end
    end)
end

--=====================================================================
-- LOCATE ENGINE -- single-player ESP (boxes + billboard), keyed _LC
--=====================================================================

local function Locate(plr)
    task.spawn(function()
        for _, v in pairs(COREGUI:GetChildren()) do
            if v.Name == plr.Name .. "_LC" then v:Destroy() end
        end
        task.wait()
        if plr.Character and plr.Name ~= LocalPlayer.Name and not COREGUI:FindFirstChild(plr.Name .. "_LC") then
            local ESPholder = Instance.new("Folder")
            ESPholder.Name = plr.Name .. "_LC"
            ESPholder.Parent = COREGUI
            repeat task.wait(1) until plr.Character and getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")

            for _, n in pairs(plr.Character:GetChildren()) do
                if n:IsA("BasePart") then
                    local a = Instance.new("BoxHandleAdornment")
                    a.Name = plr.Name
                    a.Parent = ESPholder
                    a.Adornee = n
                    a.AlwaysOnTop = true
                    a.ZIndex = 10
                    a.Size = n.Size
                    a.Transparency = espTransparency
                    a.Color = plr.TeamColor
                end
            end

            if plr.Character and plr.Character:FindFirstChild("Head") then
                local BillboardGui = Instance.new("BillboardGui")
                local TextLabel = Instance.new("TextLabel")
                BillboardGui.Adornee = plr.Character.Head
                BillboardGui.Name = plr.Name
                BillboardGui.Parent = ESPholder
                BillboardGui.Size = UDim2.new(0, 100, 0, 150)
                BillboardGui.StudsOffset = Vector3.new(0, 1, 0)
                BillboardGui.AlwaysOnTop = true
                TextLabel.Parent = BillboardGui
                TextLabel.BackgroundTransparency = 1
                TextLabel.Position = UDim2.new(0, 0, 0, -50)
                TextLabel.Size = UDim2.new(0, 100, 0, 100)
                TextLabel.Font = Enum.Font.SourceSansSemibold
                TextLabel.TextSize = 20
                TextLabel.TextColor3 = Color3.new(1, 1, 1)
                TextLabel.TextStrokeTransparency = 0
                TextLabel.TextYAlignment = Enum.TextYAlignment.Bottom
                TextLabel.Text = "Name: " .. plr.Name
                TextLabel.ZIndex = 10

                local lcLoopFunc, addedFunc, teamChange

                addedFunc = plr.CharacterAdded:Connect(function()
                    if ESPholder ~= nil and ESPholder.Parent ~= nil then
                        lcLoopFunc:Disconnect()
                        teamChange:Disconnect()
                        ESPholder:Destroy()
                        repeat task.wait(1) until getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")
                        Locate(plr)
                        addedFunc:Disconnect()
                    else
                        teamChange:Disconnect()
                        addedFunc:Disconnect()
                    end
                end)
                teamChange = plr:GetPropertyChangedSignal("TeamColor"):Connect(function()
                    if ESPholder ~= nil and ESPholder.Parent ~= nil then
                        lcLoopFunc:Disconnect()
                        addedFunc:Disconnect()
                        ESPholder:Destroy()
                        repeat task.wait(1) until getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")
                        Locate(plr)
                        teamChange:Disconnect()
                    else
                        teamChange:Disconnect()
                    end
                end)
                lcLoopFunc = RunService.RenderStepped:Connect(function()
                    if COREGUI:FindFirstChild(plr.Name .. "_LC") then
                        if plr.Character and getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")
                           and LocalPlayer.Character and getRoot(LocalPlayer.Character) then
                            local pos = math.floor((getRoot(LocalPlayer.Character).Position - getRoot(plr.Character).Position).Magnitude)
                            TextLabel.Text = "Name: " .. plr.Name
                                .. " | Health: " .. round(plr.Character:FindFirstChildOfClass("Humanoid").Health, 1)
                                .. " | Studs: " .. pos
                        end
                    else
                        teamChange:Disconnect()
                        addedFunc:Disconnect()
                        lcLoopFunc:Disconnect()
                    end
                end)
            end
        end
    end)
end

--=====================================================================
-- PART ESP ENGINE
--=====================================================================

local espParts = {}
local partEspTrigger = nil

local function partAdded(part)
    if #espParts > 0 then
        if FindInTable(espParts, part.Name:lower()) and part:IsA("BasePart") then
            local a = Instance.new("BoxHandleAdornment")
            a.Name = part.Name:lower() .. "_PESP"
            a.Parent = part
            a.Adornee = part
            a.AlwaysOnTop = true
            a.ZIndex = 0
            a.Size = part.Size
            a.Transparency = espTransparency
            a.Color = BrickColor.new("Lime green")
        end
    else
        if partEspTrigger then partEspTrigger:Disconnect() partEspTrigger = nil end
    end
end

--=====================================================================
-- XRAY ENGINE
--=====================================================================

local xrayLoop
local function xray()
    for _, v in pairs(Workspace:GetDescendants()) do
        if v:IsA("BasePart") and not v.Parent:FindFirstChildWhichIsA("Humanoid") and not v.Parent.Parent:FindFirstChildWhichIsA("Humanoid") then
            v.LocalTransparencyModifier = xrayEnabled and 0.5 or 0
        end
    end
end

--=====================================================================
-- PLAYER LIFECYCLE -- keep ESP/CHMS consistent as players join/leave
--=====================================================================

Players.PlayerRemoving:Connect(function(player)
    for _, v in pairs(COREGUI:GetChildren()) do
        if v.Name == player.Name .. "_ESP" or v.Name == player.Name .. "_LC" or v.Name == player.Name .. "_CHMS" then
            v:Destroy()
        end
    end
end)

Players.PlayerAdded:Connect(function(plr)
    if ESPenabled then
        repeat task.wait(1) until plr.Character and getRoot(plr.Character)
        ESP(plr)
    end
    if CHMSenabled then
        repeat task.wait(1) until plr.Character and getRoot(plr.Character)
        CHMS(plr)
    end
end)

--=====================================================================
-- COMMANDS
--=====================================================================

local commands = {}

commands.esp = {
    aliases = {},
    desc = "View all players and their status",
    usage = "esp",
    run = function(args, speaker)
        if not CHMSenabled then
            ESPenabled = true
            for _, v in pairs(Players:GetPlayers()) do
                if v.Name ~= speaker.Name then ESP(v) end
            end
        else
            notify("ESP", "Disable chams (nochams) before using esp")
        end
    end,
}

commands.espteam = {
    aliases = {},
    desc = "ESP but teammates are green and bad guys are red",
    usage = "espteam",
    run = function(args, speaker)
        if not CHMSenabled then
            ESPenabled = true
            for _, v in pairs(Players:GetPlayers()) do
                if v.Name ~= speaker.Name then ESP(v, true) end
            end
        else
            notify("ESP", "Disable chams (nochams) before using esp")
        end
    end,
}

commands.noesp = {
    aliases = { "unesp", "unespteam" },
    desc = "Removes ESP",
    usage = "noesp / unesp / unespteam",
    run = function(args, speaker)
        ESPenabled = false
        for _, c in pairs(COREGUI:GetChildren()) do
            if string.sub(c.Name, -4) == "_ESP" then c:Destroy() end
        end
    end,
}

commands.esptransparency = {
    aliases = {},
    desc = "Changes the transparency of ESP related commands",
    usage = "esptransparency [number]",
    run = function(args, speaker)
        espTransparency = tonumber(args[1]) or 0.3
        if ESPenabled then execCmd("esp") end
        if CHMSenabled then execCmd("chams") end
        -- TODO: your settings save here (IY persists espTransparency)
    end,
}

commands.chams = {
    aliases = {},
    desc = "ESP but without text in the way",
    usage = "chams",
    run = function(args, speaker)
        if not ESPenabled then
            CHMSenabled = true
            for _, v in pairs(Players:GetPlayers()) do
                if v.Name ~= speaker.Name then CHMS(v) end
            end
        else
            notify("Chams", "Disable ESP (noesp) before using chams")
        end
    end,
}

commands.nochams = {
    aliases = { "unchams" },
    desc = "Removes chams",
    usage = "nochams / unchams",
    run = function(args, speaker)
        CHMSenabled = false
        for _, v in pairs(Players:GetPlayers()) do
            for _, c in pairs(COREGUI:GetChildren()) do
                if c.Name == v.Name .. "_CHMS" then c:Destroy() end
            end
        end
    end,
}

commands.locate = {
    aliases = {},
    desc = "View a single player and their status",
    usage = "locate [player]",
    run = function(args, speaker)
        for _, v in pairs(getPlayer(args[1], speaker)) do
            Locate(Players[v])
        end
    end,
}

commands.nolocate = {
    aliases = { "unlocate" },
    desc = "Removes locate",
    usage = "unlocate / nolocate [player]",
    run = function(args, speaker)
        if args[1] then
            for _, v in pairs(getPlayer(args[1], speaker)) do
                for _, c in pairs(COREGUI:GetChildren()) do
                    if c.Name == Players[v].Name .. "_LC" then c:Destroy() end
                end
            end
        else
            for _, c in pairs(COREGUI:GetChildren()) do
                if string.sub(c.Name, -3) == "_LC" then c:Destroy() end
            end
        end
    end,
}

commands.partesp = {
    aliases = {},
    desc = "Highlights a part",
    usage = "partesp [part name]",
    run = function(args, speaker)
        local partEspName = getstring(1, args):lower()
        if not FindInTable(espParts, partEspName) then
            table.insert(espParts, partEspName)
            for _, v in pairs(Workspace:GetDescendants()) do
                if v:IsA("BasePart") and v.Name:lower() == partEspName then
                    local a = Instance.new("BoxHandleAdornment")
                    a.Name = partEspName .. "_PESP"
                    a.Parent = v
                    a.Adornee = v
                    a.AlwaysOnTop = true
                    a.ZIndex = 0
                    a.Size = v.Size
                    a.Transparency = espTransparency
                    a.Color = BrickColor.new("Lime green")
                end
            end
        end
        if partEspTrigger == nil then
            partEspTrigger = Workspace.DescendantAdded:Connect(partAdded)
        end
    end,
}

commands.unpartesp = {
    aliases = { "nopartesp" },
    desc = "Removes partesp",
    usage = "unpartesp / nopartesp [part name]",
    run = function(args, speaker)
        if args[1] then
            local partEspName = getstring(1, args):lower()
            for i = #espParts, 1, -1 do
                if espParts[i] == partEspName then table.remove(espParts, i) end
            end
            for _, v in pairs(Workspace:GetDescendants()) do
                if v:IsA("BoxHandleAdornment") and v.Name == partEspName .. "_PESP" then v:Destroy() end
            end
        else
            if partEspTrigger then partEspTrigger:Disconnect() partEspTrigger = nil end
            espParts = {}
            for _, v in pairs(Workspace:GetDescendants()) do
                if v:IsA("BoxHandleAdornment") and v.Name:sub(-5) == "_PESP" then v:Destroy() end
            end
        end
    end,
}

commands.xray = {
    aliases = {},
    desc = "Makes all parts in workspace transparent",
    usage = "xray",
    run = function(args, speaker)
        xrayEnabled = true
        xray()
    end,
}

commands.unxray = {
    aliases = { "noxray" },
    desc = "Restores transparency to all parts in workspace",
    usage = "unxray / noxray",
    run = function(args, speaker)
        xrayEnabled = false
        xray()
    end,
}

commands.togglexray = {
    aliases = {},
    desc = "Toggles xray",
    usage = "togglexray",
    run = function(args, speaker)
        xrayEnabled = not xrayEnabled
        xray()
    end,
}

commands.loopxray = {
    aliases = {},
    desc = "Makes all parts in workspace transparent but looped",
    usage = "loopxray",
    run = function(args, speaker)
        pcall(function() xrayLoop:Disconnect() end)
        xrayLoop = RunService.RenderStepped:Connect(function()
            xrayEnabled = true
            xray()
        end)
    end,
}

commands.unloopxray = {
    aliases = {},
    desc = "Unloops xray",
    usage = "unloopxray",
    run = function(args, speaker)
        pcall(function() xrayLoop:Disconnect() end)
        xrayEnabled = false
        xray()
    end,
}

--=====================================================================
-- exec hook (esptransparency re-applies esp/chams by name)
--=====================================================================

function commands._setExec(fn)
    if type(fn) == "function" then execCmd = fn end
end

return commands
