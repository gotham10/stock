local Config = _G.ScannerConfig
if not Config then return end

local SCRIPT_URL = Config.SCRIPT_URL
local NotSameServersFile = Config.NotSameServersFile
local AutoHopFile = Config.AutoHopFile
local HIDE_MY_DATA = Config.HIDE_MY_DATA
local MAX_KG_THRESHOLD_PLANT = Config.MAX_KG_THRESHOLD_PLANT
local MAX_KG_THRESHOLD_BRAINROT = Config.MAX_KG_THRESHOLD_BRAINROT
local ScanPlants = Config.ScanPlants
local ScanBrainrots = Config.ScanBrainrots
local ScanMutations = Config.ScanMutations
local blocked = Config.blocked
local Mutations = Config.Mutations

if not game:IsLoaded() then game.Loaded:Wait() end
wait(2)

function missing(t, f, fallback)
    if type(f) == t then return f end
    return fallback
end

local PlaceID = game.PlaceId
local AllIDs = {}
local foundAnything = ""
local actualHour = os.date("!*t").hour
local HttpService = game:GetService("HttpService")
local isAutoHopping = false

local function RobustReadFile(file)
    local content = ""
    local success = false
    for i = 1, 10 do
        wait(0.5)
        success, content = pcall(function() return readfile(file) end)
        if success and content and content ~= "" then return content end
    end
    return nil
end

local function RobustWriteFile(file, content)
    for i = 1, 7 do
        local success, err = pcall(function() writefile(file, content) end)
        if success then return true end
        wait(0.5)
    end
    return false
end

local hopStateContent = RobustReadFile(AutoHopFile)
if hopStateContent == "true" then isAutoHopping = true end

local serversFileContent = RobustReadFile(NotSameServersFile)
if serversFileContent then
    local decoded, err = pcall(function() return HttpService:JSONDecode(serversFileContent) end)
    if decoded and type(decoded) == "table" and #decoded > 0 then
        if tonumber(decoded[1]) == tonumber(actualHour) then AllIDs = decoded else AllIDs = { actualHour } end
    else AllIDs = { actualHour } end
else AllIDs = { actualHour } end

function TPReturner()
    local Site
    local success, result = pcall(function()
        local url
        if foundAnything == "" then url = 'https://games.roblox.com/v1/games/' .. PlaceID .. '/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true'
        else url = 'https://games.roblox.com/v1/games/' .. PlaceID .. '/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true&cursor=' .. foundAnything end
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    if not success or not result then return end
    Site = result
    if Site.nextPageCursor and Site.nextPageCursor ~= "null" then foundAnything = Site.nextPageCursor end
    if not Site.data then return end
    for i,v in pairs(Site.data) do
        local Possible = true
        local ID = tostring(v.id)
        if (tonumber(v.maxPlayers) or 0) > (tonumber(v.playing) or 0) then
            for j = 2, #AllIDs do if ID == tostring(AllIDs[j]) then Possible = false break end end
            if Possible == true then
                table.insert(AllIDs, ID)
                wait()
                pcall(function()
                    RobustWriteFile(NotSameServersFile, HttpService:JSONEncode(AllIDs))
                    wait()
                    game:GetService("TeleportService"):TeleportToPlaceInstance(PlaceID, ID, game.Players.LocalPlayer)
                end)
                wait(4)
            end
        end
    end
end

local function HopServer() pcall(function() TPReturner() if foundAnything ~= "" then TPReturner() end end) end

local function CheckForAutoHop(scrollingFrame, noDataLabel)
    if not scrollingFrame or not noDataLabel then return end
    local itemsVisible = false
    for _, child in ipairs(scrollingFrame:GetChildren()) do
        if child:IsA("Frame") and child.Visible and child.Name ~= "ItemTemplate" then itemsVisible = true break end
    end
    noDataLabel.Visible = not itemsVisible
    if not itemsVisible and isAutoHopping then HopServer() end
end

local Plrs = game:GetService("Players")
local Ws = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local PathfindingService = game:GetService("PathfindingService")

if not Plrs.LocalPlayer then repeat wait() until Plrs.LocalPlayer end
local MY_USERNAME = Plrs.LocalPlayer.Name

local mutationLookup = {}
for _,m in ipairs(Mutations) do mutationLookup[m:lower()] = m end
local romanPattern = "%s+(IX|IV|V|V?I{1,3})$"

local function cleanName(name)
    if not name or name == "Unknown" then return "Unknown" end
    local cleaned = name:gsub("%[.-%]%s*", ""):gsub(romanPattern, ""):match("^%s*(.-)%s*$")
    return cleaned
end

local function shouldSkip(name)
    if not name then return true end
    local lower = name:lower()
    for _,word in ipairs(blocked) do if lower:find(word, 1, true) then return true end end
    return false
end

local function findMutation(s)
    if not s or s == "Unknown" then return nil end
    local firstWord = tostring(s):match("^([^%s]+)")
    return firstWord and mutationLookup[firstWord:lower()]
end

local function parseSizeToKg(sizeString)
    if not sizeString or type(sizeString) ~= "string" then return 0 end
    local numStr = sizeString:match("^(%d+%.?%d*)%s*kg$")
    return numStr and tonumber(numStr) or 0
end

local function parseTool(tool)
    if not tool or shouldSkip(tool.Name) then return nil end
    local rawName = tool.Name
    local explicitMut, explicitSize, explicitName = rawName:match("^%[([%w%-%s]+)%]%s+%[(%d+%.?%d*)%s*kg%]%s+(.+)")
    if explicitMut and explicitSize and explicitName then
        local data = { Name = cleanName(explicitName), Size = explicitSize .. " kg", Mutation = findMutation(explicitMut) or explicitMut }
        if ScanPlants[data.Name] then data.Type = "Plant"
        elseif ScanBrainrots[data.Name] then data.Type = "Brainrot"
        else data.Type = tool:GetAttribute("IsPlant") and "Plant" or "Brainrot" end
        data.Value = tool:GetAttribute("Value") or "Unknown"
        data.Rarity = tool:GetAttribute("Rarity") or "Unknown"
        return data
    end
    local isPlant = tool:GetAttribute("IsPlant")
    if isPlant then
        return { Type = "Plant", Name = cleanName(tool:GetAttribute("ItemName") or tool.Name), Size = (tool:GetAttribute("Size") or "Unknown") .. " kg", Value = tool:GetAttribute("Value") or "Unknown", Colors = tool:GetAttribute("Colors") or "Unknown", Damage = tool:GetAttribute("Damage") or "Unknown", Mutation = findMutation(tool:GetAttribute("MutationString")) or findMutation(tool:GetAttribute("Mutation")) or findMutation(tool.Name:match("%[([^%]]-)%]")) or "Normal" }
    end
    local mut
    local mutationString = tool:GetAttribute("MutationString")
    if mutationString and mutationString == cleanName(rawName) then mut = "Normal"
    else mut = findMutation(mutationString) or findMutation(tool:GetAttribute("Mutation")) or findMutation(rawName:match("%[([^%]]-)%]")) or "Normal" end
    local model = tool:FindFirstChildOfClass("Model")
    return { Type = "Brainrot", Size = (tool:GetAttribute("Size") or "Unknown") .. " kg", Name = cleanName(rawName), Mutation = mut, Rarity = model and model:GetAttribute("Rarity") or "Unknown" }
end

local function getCharacter(player)
    if player.Character then return player.Character end
    local playersFolder = Ws:FindFirstChild("Players")
    return playersFolder and playersFolder:FindFirstChild(player.Name)
end

local function scanPlayer(player)
    local items = {}
    if not player then return items end
    local backpack = player:FindFirstChild("Backpack")
    if backpack then for _, tool in ipairs(backpack:GetChildren()) do if tool:IsA("Tool") then local d = parseTool(tool) if d then table.insert(items, d) end end end end
    local char = getCharacter(player)
    if char then for _, child in ipairs(char:GetChildren()) do if child:IsA("Tool") then local d = parseTool(child) if d then table.insert(items, d) end end end end
    return items
end

local function getPlotBrainrotData(plotModel)
    if not plotModel then return nil end
    local brainrotPart = plotModel:FindFirstChild("Brainrot")
    if not brainrotPart then return nil end
    return { Type = "Brainrot", Name = cleanName(brainrotPart:GetAttribute("Brainrot") or "Unknown"), Mutation = findMutation(brainrotPart:GetAttribute("Mutation")) or "Normal", Rarity = brainrotPart:GetAttribute("Rarity") or "Unknown", Size = (brainrotPart:GetAttribute("Size") or "Unknown") .. " kg" }
end

local function scanPlotBrainrots(player)
    local items = {}
    if not player then return items end
    local plots = Ws:FindFirstChild("Plots")
    if not plots then return items end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:GetAttribute("Owner") == player.Name then
            local brainrotsFolder = plot:FindFirstChild("Brainrots")
            if brainrotsFolder then for _, plotModel in ipairs(brainrotsFolder:GetChildren()) do if plotModel:IsA("Model") then local d = getPlotBrainrotData(plotModel) if d then table.insert(items, d) end end end end
            break
        end
    end
    return items
end

local function getPlotPlantData(plantModel)
    if not plantModel then return nil end
    return { Type = "Plant", Name = cleanName(plantModel.Name), Colors = plantModel:GetAttribute("Colors") or "Unknown", Damage = plantModel:GetAttribute("Damage") or "Unknown", Level = plantModel:GetAttribute("Level") or "Unknown", Rarity = plantModel:GetAttribute("Rarity") or "Unknown", Row = plantModel:GetAttribute("Row") or "Unknown", Size = (plantModel:GetAttribute("Size") or "Unknown") .. " kg", Mutation = findMutation(plantModel:GetAttribute("MutationString")) or findMutation(plantModel:GetAttribute("Mutation")) or findMutation(plantModel.Name:match("%[([^%]]-)%]")) or "Normal" }
end

local function scanPlotPlants(player)
    local items = {}
    if not player then return items end
    local plots = Ws:FindFirstChild("Plots")
    if not plots then return items end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:GetAttribute("Owner") == player.Name then
            local plantsFolder = plot:FindFirstChild("Plants")
            if plantsFolder then for _, plantModel in ipairs(plantsFolder:GetChildren()) do if plantModel:IsA("Model") then local d = getPlotPlantData(plantModel) if d then table.insert(items, d) end end end end
            break
        end
    end
    return items
end

local function buildScanResults()
    local results = {}
    for _,p in ipairs(Plrs:GetPlayers()) do
        if HIDE_MY_DATA and p.Name == MY_USERNAME then continue end
        local allItems = {}
        for _, d in ipairs(scanPlayer(p)) do table.insert(allItems, d) end
        for _, d in ipairs(scanPlotBrainrots(p)) do table.insert(allItems, d) end
        for _, d in ipairs(scanPlotPlants(p)) do table.insert(allItems, d) end
        local pData = { Brainrots = { Items = {} }, Plants = { Items = {} } }
        for _, itemData in ipairs(allItems) do
            if itemData then
                local typ, name = itemData.Type, itemData.Name or "Unknown"
                local list, searchList, generalThreshold = (typ == "Plant" and pData.Plants.Items or pData.Brainrots.Items), (typ == "Plant" and ScanPlants or ScanBrainrots), (typ == "Plant" and MAX_KG_THRESHOLD_PLANT or MAX_KG_THRESHOLD_BRAINROT)
                local specificScanData, sizeInKg, itemMutation = searchList[name], parseSizeToKg(itemData.Size), itemData.Mutation or "Normal"
                if not (specificScanData and specificScanData.ignore) then
                    local shouldAddItem = (specificScanData and ((type(specificScanData.mutations and specificScanData.mutationsBypassKg and specificScanData.mutations[itemMutation]) == "number" and sizeInKg >= specificScanData.mutations[itemMutation]) or (type(specificScanData.mutations and specificScanData.mutationsBypassKg and specificScanData.mutations[itemMutation]) ~= "number" and sizeInKg >= specificScanData.kg))) or (not specificScanData and sizeInKg > generalThreshold)
                    if shouldAddItem or (itemMutation ~= "Normal" and ScanMutations[itemMutation] ~= nil) then
                        if not list[name] then list[name] = { Instances = {}, Summary = { TotalCount = 0, InstanceCounts = {} } } end
                        list[name].Summary.TotalCount = list[name].Summary.TotalCount + 1
                        local val = (typ == "Plant" and itemMutation == "Normal") and (itemData.Colors or "Unknown") or itemMutation
                        local summaryKey = tostring(itemData.Size or "Unknown kg") .. ", " .. tostring(val)
                        list[name].Summary.InstanceCounts[summaryKey] = (list[name].Summary.InstanceCounts[summaryKey] or 0) + 1
                        local instanceData = {}
                        for k, v in pairs(itemData) do if k ~= "Name" and k ~= "Type" then instanceData[k] = v end end
                        table.insert(list[name].Instances, instanceData)
                    end
                end
            end
        end
        results[p.Name] = pData
    end
    return results
end

local function walkPath(humanoid, path)
    if path.Status ~= Enum.PathStatus.Success then return false end
    for _, wp in ipairs(path:GetWaypoints()) do
        if wp.Action == Enum.PathWaypointAction.Jump then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
        humanoid:MoveTo(wp.Position)
        local timer, jumpRetry = 0, false
        repeat
            wait(0.1)
            timer = timer + 0.1
            if (humanoid.Parent.HumanoidRootPart.Position - wp.Position).Magnitude < 4 then break end
            if timer > 1.5 and not jumpRetry then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) jumpRetry = true end
        until timer > 5
        if timer > 5 then return false end
    end
    return true
end

local function computeAndWalk(humanoid, startVec, endVec)
    pcall(function()
        local w = Ws:FindFirstChild("ScriptedMap") and Ws.ScriptedMap:FindFirstChild("Water")
        if w and not w:FindFirstChild("NoWalkMod") then
            local m = Instance.new("PathfindingModifier")
            m.Name = "NoWalkMod"
            m.Label = "DeadlyWater"
            m.PassThrough = false
            m.Parent = w
        end
        if w then for _,c in ipairs(w:GetChildren()) do if c:IsA("TouchTransmitter") then c:Destroy() end end end
    end)
    local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, Costs = { DeadlyWater = math.huge } })
    local success, err = pcall(function() path:ComputeAsync(startVec, endVec) end)
    if success and path.Status == Enum.PathStatus.Success then return walkPath(humanoid, path) end
    return false
end

local function WalkToPlayer(playerName)
    local lp = Plrs.LocalPlayer
    local lc = getCharacter(lp)
    local lh = lc and lc:FindFirstChildOfClass("Humanoid")
    local lr = lh and lc:FindFirstChild("HumanoidRootPart")
    local tp = Plrs:FindFirstChild(playerName)
    local tc = tp and getCharacter(tp)
    local tr = tc and tc:FindFirstChild("HumanoidRootPart")
    if not lr or not tr or not lh then return end
    local plot
    local plots = Ws:FindFirstChild("Plots")
    if plots then for _, p in ipairs(plots:GetChildren()) do if p:GetAttribute("Owner") == playerName then plot = p break end end end
    local waypoints = {}
    if plot then
        local b = plot:FindFirstChild("Bridge")
        if b then table.insert(waypoints, (b:IsA("Model") and b:GetPivot().Position) or b.Position) end
        local bio = plot:FindFirstChild("Biome")
        if bio then for _,c in ipairs(bio:GetChildren()) do if c:IsA("Model") and c.PrimaryPart then table.insert(waypoints, c.PrimaryPart.Position) break end end end
    end
    table.insert(waypoints, tr.Position)
    local currentPos = lr.Position
    for _, wp in ipairs(waypoints) do
        if computeAndWalk(lh, currentPos, wp) then currentPos = lr.Position else break end
    end
end

local function createUI()
    if not CoreGui then return nil end
    local old = CoreGui:FindFirstChild("ScannerUI")
    if old then pcall(function() old:Destroy() end) end
    local sg = Instance.new("ScreenGui")
    sg.Name = "ScannerUI"
    sg.ResetOnSpawn = false
    local mf = Instance.new("Frame")
    mf.Name = "MainFrame"
    mf.Size = UDim2.new(0, 350, 0, 400)
    mf.Position = UDim2.new(1, -350, 1, -400)
    mf.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    mf.Active = true
    mf.Draggable = true
    mf.Parent = sg
    local h = Instance.new("Frame")
    h.Name = "Header"
    h.Size = UDim2.new(1, 0, 0, 30)
    h.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    h.Parent = mf
    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1, -220, 1, 0)
    tl.BackgroundTransparency = 1
    tl.TextColor3 = Color3.fromRGB(220, 220, 220)
    tl.Text = "Item Scanner"
    tl.Font = Enum.Font.SourceSansBold
    tl.TextSize = 18
    tl.Parent = h
    local tb = Instance.new("TextButton")
    tb.Size = UDim2.new(0, 30, 1, 0)
    tb.Position = UDim2.new(1, -60, 0, 0)
    tb.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    tb.TextColor3 = Color3.fromRGB(220, 220, 220)
    tb.Text = "-"
    tb.TextSize = 24
    tb.Parent = h
    local cb = Instance.new("TextButton")
    cb.Size = UDim2.new(0, 30, 1, 0)
    cb.Position = UDim2.new(1, -30, 0, 0)
    cb.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    cb.TextColor3 = Color3.fromRGB(220, 220, 220)
    cb.Text = "X"
    cb.TextSize = 20
    cb.Parent = h
    local hb = Instance.new("TextButton")
    hb.Size = UDim2.new(0, 30, 1, 0)
    hb.Position = UDim2.new(1, -90, 0, 0)
    hb.BackgroundColor3 = Color3.fromRGB(50, 80, 200)
    hb.TextColor3 = Color3.fromRGB(220, 220, 220)
    hb.Text = ">>"
    hb.TextSize = 20
    hb.Parent = h
    local ab = Instance.new("TextButton")
    ab.Name = "AutoHopButton"
    ab.Size = UDim2.new(0, 30, 1, 0)
    ab.Position = UDim2.new(1, -150, 0, 0)
    ab.TextColor3 = Color3.fromRGB(220, 220, 220)
    ab.TextSize = 16
    ab.Parent = h
    local hdb = Instance.new("TextButton")
    hdb.Size = UDim2.new(0, 30, 1, 0)
    hdb.Position = UDim2.new(1, -120, 0, 0)
    hdb.TextColor3 = Color3.fromRGB(220, 220, 220)
    hdb.TextSize = 20
    hdb.Parent = h
    local cpb = Instance.new("TextButton")
    cpb.Size = UDim2.new(0, 30, 1, 0)
    cpb.Position = UDim2.new(1, -180, 0, 0)
    cpb.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
    cpb.TextColor3 = Color3.fromRGB(220, 220, 220)
    cpb.Text = "C"
    cpb.TextSize = 16
    cpb.Parent = h
    local function uab() ab.BackgroundColor3 = isAutoHopping and Color3.fromRGB(80, 200, 80) or Color3.fromRGB(200, 80, 80) ab.Text = isAutoHopping and "ON" or "OFF" end
    uab()
    local function uhb() hdb.BackgroundColor3 = HIDE_MY_DATA and Color3.fromRGB(200, 80, 80) or Color3.fromRGB(80, 200, 80) hdb.Text = HIDE_MY_DATA and "H" or "S" end
    uhb()
    local sf = Instance.new("ScrollingFrame")
    sf.Name = "ScrollingFrame"
    sf.Size = UDim2.new(1, 0, 1, -30)
    sf.Position = UDim2.new(0, 0, 0, 30)
    sf.BackgroundTransparency = 1
    sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sf.ScrollBarThickness = 6
    sf.Parent = mf
    local uil = Instance.new("UIListLayout")
    uil.SortOrder = Enum.SortOrder.LayoutOrder
    uil.Padding = UDim.new(0, 5)
    uil.Parent = sf
    local it = Instance.new("Frame")
    it.Name = "ItemTemplate"
    it.Visible = false
    it.Parent = sf
    local dt = Instance.new("TextLabel")
    dt.Name = "DetailTemplate"
    dt.Visible = false
    dt.Parent = it
    local ndl = Instance.new("TextLabel")
    ndl.Name = "NoDataLabel"
    ndl.Size = UDim2.new(1, 0, 0, 30)
    ndl.BackgroundTransparency = 1
    ndl.TextColor3 = Color3.fromRGB(150, 150, 150)
    ndl.Text = "No data found"
    ndl.Visible = false
    ndl.Parent = sf
    tb.MouseButton1Click:Connect(function() sf.Visible = not sf.Visible tb.Text = sf.Visible and "-" or "+" mf:TweenSize(UDim2.new(0, 350, 0, sf.Visible and 400 or 30), "Out", "Quad", 0.2, true) end)
    cb.MouseButton1Click:Connect(function() isAutoHopping = false RobustWriteFile(AutoHopFile, "false") pcall(function() sg:Destroy() end) end)
    hb.MouseButton1Click:Connect(HopServer)
    ab.MouseButton1Click:Connect(function() isAutoHopping = not isAutoHopping RobustWriteFile(AutoHopFile, tostring(isAutoHopping)) CheckForAutoHop(sf, ndl) uab() end)
    hdb.MouseButton1Click:Connect(function() HIDE_MY_DATA = not HIDE_MY_DATA uhb() end)
    cpb.MouseButton1Click:Connect(function()
        local t = {}
        for _,c in ipairs(sf:GetChildren()) do if c:IsA("Frame") and c.Visible and c.Name ~= "ItemTemplate" then table.insert(t, c.PlayerFrame.PlayerNameLabel.Text) table.insert(t, c.ItemName.Text) table.insert(t, c.Summary.Text) for _,d in ipairs(c.DetailsFrame:GetChildren()) do if d:IsA("TextLabel") then table.insert(t, d.Text) end end table.insert(t, "--------------------") end end
        if #t > 0 then pcall(function() setclipboard(table.concat(t, "\n")) end) end
    end)
    pcall(function() sg.Parent = CoreGui end)
    return sg
end

local function updateUI(ui, scanResults, currentFrames, highlightedPlayers)
    if not ui or not scanResults then return {}, false end
    local sf = ui.MainFrame.ScrollingFrame
    local it = sf.ItemTemplate
    local ndl = sf.NoDataLabel
    local dataFound, layoutOrder, framesToKeep = false, 1, {}
    for playerName, pData in pairs(scanResults) do
        if pData then
            local function pc(items, cat)
                if not items then return end
                for n, d in pairs(items) do
                    if d then
                        dataFound = true
                        local k = playerName .. "_" .. n
                        framesToKeep[k] = true
                        local f = currentFrames[k]
                        if not f then
                            f = it:Clone()
                            f.Name = k
                            f.Parent = sf
                            f.Visible = true
                            f.Size = UDim2.new(1, 0, 0, 0)
                            f.AutomaticSize = Enum.AutomaticSize.Y
                            f.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
                            local pf = Instance.new("Frame", f) pf.Name = "PlayerFrame" pf.Size = UDim2.new(1,0,0,20) pf.BackgroundTransparency = 1
                            local pl = Instance.new("UIListLayout", pf) pl.FillDirection = Enum.FillDirection.Horizontal pl.VerticalAlignment = Enum.VerticalAlignment.Center
                            local pnl = Instance.new("TextLabel", pf) pnl.Name = "PlayerNameLabel" pnl.Size = UDim2.new(1,-120,1,0) pnl.BackgroundTransparency = 1 pnl.TextColor3 = Color3.fromRGB(200,200,200) pnl.TextXAlignment = Enum.TextXAlignment.Left
                            local hbtn = Instance.new("TextButton", pf) hbtn.Name = "HighlightButton" hbtn.Size = UDim2.new(0,50,1,0)
                            local gbtn = Instance.new("TextButton", pf) gbtn.Name = "GoToButton" gbtn.Size = UDim2.new(0,30,1,0) gbtn.BackgroundColor3 = Color3.fromRGB(80,160,200) gbtn.Text = "Go" gbtn.TextColor3 = Color3.new(1,1,1)
                            local rbtn = Instance.new("TextButton", pf) rbtn.Name = "RemoveItemButton" rbtn.Size = UDim2.new(0,30,1,0) rbtn.BackgroundColor3 = Color3.fromRGB(180,40,40) rbtn.Text = "X" rbtn.TextColor3 = Color3.new(1,1,1)
                            local inl = Instance.new("TextLabel", f) inl.Name = "ItemName" inl.Size = UDim2.new(1,0,0,20) inl.BackgroundTransparency = 1 inl.TextColor3 = Color3.new(1,1,1) inl.TextXAlignment = Enum.TextXAlignment.Left
                            local sl = Instance.new("TextLabel", f) sl.Name = "Summary" sl.Size = UDim2.new(1,0,0,18) sl.BackgroundTransparency = 1 sl.TextColor3 = Color3.fromRGB(180,180,180) sl.TextXAlignment = Enum.TextXAlignment.Left
                            local df = Instance.new("Frame", f) df.Name = "DetailsFrame" df.Size = UDim2.new(1,0,0,0) df.AutomaticSize = Enum.AutomaticSize.Y df.BackgroundTransparency = 1
                            Instance.new("UIListLayout", df)
                            Instance.new("UIListLayout", f).SortOrder = Enum.SortOrder.LayoutOrder
                            currentFrames[k] = f
                            hbtn.MouseButton1Click:Connect(function()
                                if highlightedPlayers[playerName] then highlightedPlayers[playerName] = nil local c = getCharacter(Plrs:FindFirstChild(playerName)) if c and c:FindFirstChild("ScannerHighlight") then c.ScannerHighlight:Destroy() end
                                else highlightedPlayers[playerName] = true local c = getCharacter(Plrs:FindFirstChild(playerName)) if c then local h = Instance.new("Highlight", c) h.Name = "ScannerHighlight" h.FillTransparency = 1 h.OutlineColor = Color3.new(1,1,1) end end
                            end)
                            gbtn.MouseButton1Click:Connect(function() spawn(function() WalkToPlayer(playerName) end) end)
                            rbtn.MouseButton1Click:Connect(function() f:Destroy() currentFrames[k] = nil CheckForAutoHop(sf, ndl) end)
                        end
                        f:SetAttribute("PlayerName", playerName)
                        f.PlayerFrame.PlayerNameLabel.Text = "Player: " .. playerName
                        f.ItemName.Text = "Item: " .. n .. " (" .. cat .. ")"
                        f.Summary.Text = "Total Count: " .. (d.Summary and d.Summary.TotalCount or 0)
                        f.LayoutOrder = layoutOrder
                        layoutOrder = layoutOrder + 1
                        local hbtn = f.PlayerFrame.HighlightButton
                        hbtn.BackgroundColor3 = highlightedPlayers[playerName] and Color3.fromRGB(80, 200, 80) or Color3.fromRGB(200, 80, 80)
                        hbtn.Text = highlightedPlayers[playerName] and "ON" or "OFF"
                        local df = f.DetailsFrame
                        df:ClearAllChildren()
                        Instance.new("UIListLayout", df)
                        if d.Summary and d.Summary.InstanceCounts then for k, c in pairs(d.Summary.InstanceCounts) do local l = it.DetailTemplate:Clone() l.Text = "  - " .. tostring(k) .. ": " .. tostring(c) l.Visible = true l.Parent = df end end
                    end
                end
            end
            if pData.Plants then pc(pData.Plants.Items, "Plant") end
            if pData.Brainrots then pc(pData.Brainrots.Items, "Brainrot") end
        end
    end
    for k, f in pairs(currentFrames) do if not framesToKeep[k] then pcall(function() f:Destroy() end) currentFrames[k] = nil end end
    ndl.Visible = not dataFound
    return currentFrames, dataFound
end

scannerUI = createUI()
if scannerUI then
    local success, res = pcall(buildScanResults)
    if success and res then currentFrames = updateUI(scannerUI, res, currentFrames, highlightedPlayers) end
    spawn(function()
        while scannerUI and scannerUI.Parent do
            wait(5)
            local hs = RobustReadFile(AutoHopFile)
            if hs == "true" then isAutoHopping = true elseif hs == "false" then isAutoHopping = false end
            if scannerUI.Parent then local ab = scannerUI.MainFrame.Header:FindFirstChild("AutoHopButton") if ab then ab.BackgroundColor3 = isAutoHopping and Color3.fromRGB(80, 200, 80) or Color3.fromRGB(200, 80, 80) ab.Text = isAutoHopping and "ON" or "OFF" end end
            local s, r = pcall(buildScanResults)
            local df = false
            if s and r then
                local cp = {} for _,p in ipairs(Plrs:GetPlayers()) do cp[p.Name] = true end
                for pn in pairs(highlightedPlayers) do if not cp[pn] then highlightedPlayers[pn] = nil end end
                currentFrames, df = updateUI(scannerUI, r, currentFrames, highlightedPlayers)
            end
            if isAutoHopping then if not df then wait(2) HopServer() else isAutoHopping = false RobustWriteFile(AutoHopFile, "false") end end
        end
        for pn in pairs(highlightedPlayers) do local c = getCharacter(Plrs:FindFirstChild(pn)) if c and c:FindFirstChild("ScannerHighlight") then c.ScannerHighlight:Destroy() end end
        highlightedPlayers = {}
    end)
end
