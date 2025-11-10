local Config = _G.ScannerConfig
if not Config then
    return
end

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

if not game:IsLoaded() then
    game.Loaded:Wait()
end
wait(2)

function missing(t, f, fallback)
    if type(f) == t then return f end
    return fallback
end

local PlaceID = game.PlaceId
local AllIDs = {}
local foundAnything = ""
local actualHour = os.date("!*t").hour
local Deleted = false
local HttpService = game:GetService("HttpService")

local isAutoHopping = false

local function RobustReadFile(file)
    local content = ""
    local success = false
    for i = 1, 10 do
        wait(0.5)
        success, content = pcall(function() return readfile(file) end)
        if success and content and content ~= "" then
            return content
        end
    end
    return nil
end

local function RobustWriteFile(file, content)
    for i = 1, 7 do
        local success, err = pcall(function() writefile(file, content) end)
        if success then
            return true
        end
        wait(0.5)
    end
    return false
end

local hopStateContent = RobustReadFile(AutoHopFile)
if hopStateContent == "true" then
    isAutoHopping = true
end

local serversFileContent = RobustReadFile(NotSameServersFile)
if serversFileContent then
    local decoded, err = pcall(function() return HttpService:JSONDecode(serversFileContent) end)
    if decoded and type(decoded) == "table" and #decoded > 0 then
        if tonumber(decoded[1]) == tonumber(actualHour) then
            AllIDs = decoded
        else
            AllIDs = { actualHour }
        end
    else
        AllIDs = { actualHour }
    end
else
    AllIDs = { actualHour }
end

function TPReturner()
    local Site
    local success, result = pcall(function()
        local url
        if foundAnything == "" then
            url = 'https://games.roblox.com/v1/games/' .. PlaceID .. '/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true'
        else
            url = 'https://games.roblox.com/v1/games/' .. PlaceID .. '/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true&cursor=' .. foundAnything
        end
        local raw = game:HttpGet(url)
        return HttpService:JSONDecode(raw)
    end)

    if not success or not result then
        return
    end

    Site = result
    
    local ID = ""
    if Site.nextPageCursor and Site.nextPageCursor ~= "null" and Site.nextPageCursor ~= nil then
        foundAnything = Site.nextPageCursor
    end
    
    if not Site.data then
        return
    end

    for i,v in pairs(Site.data) do
        local Possible = true
        ID = tostring(v.id)
        if (tonumber(v.maxPlayers) or 0) > (tonumber(v.playing) or 0) then
            for j = 2, #AllIDs do
                if ID == tostring(AllIDs[j]) then
                    Possible = false
                    break
                end
            end
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

local function HopServer()
    pcall(function()
        TPReturner()
        if foundAnything ~= "" then
            TPReturner()
        end
    end)
end

local function CheckForAutoHop(scrollingFrame, noDataLabel)
    if not scrollingFrame or not noDataLabel then return end
    local itemsVisible = false
    for _, child in ipairs(scrollingFrame:GetChildren()) do
        if child:IsA("Frame") and child.Visible and child.Name ~= "ItemTemplate" then
            itemsVisible = true
            break
        end
    end
    noDataLabel.Visible = not itemsVisible
    
    if not itemsVisible and isAutoHopping then
        HopServer()
    end
end

local Plrs = game:GetService("Players")
local Ws = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local PathfindingService = game:GetService("PathfindingService")

pcall(function()
    local water = Ws:WaitForChild("ScriptedMap", 5) and Ws.ScriptedMap:WaitForChild("Water", 5)
    if water then
        local mod = water:FindFirstChild("ScannerPathMod")
        if not mod then
            mod = Instance.new("PathfindingModifier")
            mod.Name = "ScannerPathMod"
            mod.Parent = water
        end
        mod.PassThrough = true
        mod.Label = "Water"
        
        local touchInterest = water:FindFirstChildOfClass("TouchTransmitter")
        if touchInterest then
            touchInterest:Destroy()
        end
    end
end)

if not Plrs.LocalPlayer then
    repeat wait() until Plrs.LocalPlayer
end

local MY_USERNAME = Plrs.LocalPlayer.Name

local mutationLookup = {}
for _,m in ipairs(Mutations) do mutationLookup[m:lower()] = m end

local romanPattern = "%s+(IX|IV|V|V?I{1,3})$"

local function cleanName(name)
    if not name or name == "Unknown" then return "Unknown" end
    local cleaned = name
    cleaned = cleaned:gsub("%[.-%]%s*", "")
    cleaned = cleaned:gsub(romanPattern, "")
    cleaned = cleaned:match("^%s*(.-)%s*$")
    return cleaned
end

local function shouldSkip(name)
    if not name then return true end
    local lower = name:lower()
    for _,word in ipairs(blocked) do
        if lower:find(word, 1, true) then
            return true
        end
    end
    return false
end

local function findMutation(s)
    if not s or s == "Unknown" then return nil end
    local firstWord = tostring(s):match("^([^%s]+)")
    return firstWord and mutationLookup[firstWord:lower()]
end

local function parseSizeToKg(sizeString)
    if not sizeString or type(sizeString) ~= "string" then
        return 0
    end
    local numStr = sizeString:match("^(%d+%.?%d*)%s*kg$")
    if numStr then
        return tonumber(numStr) or 0
    end
    return 0
end

local function parseTool(tool)
    if not tool or shouldSkip(tool.Name) then return nil end
    
    local rawName = tool.Name
    local explicitMut, explicitSize, explicitName = rawName:match("^%[([%w%-%s]+)%]%s+%[(%d+%.?%d*)%s*kg%]%s+(.+)")
    
    if explicitMut and explicitSize and explicitName then
        local data = {}
        data.Name = cleanName(explicitName)
        data.Size = explicitSize .. " kg"
        data.Mutation = findMutation(explicitMut) or explicitMut
        
        if ScanPlants[data.Name] then
            data.Type = "Plant"
        elseif ScanBrainrots[data.Name] then
             data.Type = "Brainrot"
        else
             data.Type = tool:GetAttribute("IsPlant") and "Plant" or "Brainrot"
        end
        
        data.Value = tool:GetAttribute("Value") or "Unknown"
        data.Rarity = tool:GetAttribute("Rarity") or "Unknown"
        
        return data
    end

    local isPlant = tool:GetAttribute("IsPlant")
    if isPlant then
        local data = {}
        data.Type = "Plant"
        data.Name = cleanName(tool:GetAttribute("ItemName") or tool.Name)
        data.Size = (tool:GetAttribute("Size") or "Unknown") .. " kg"
        data.Value = tool:GetAttribute("Value") or "Unknown"
        data.Colors = tool:GetAttribute("Colors") or "Unknown"
        data.Damage = tool:GetAttribute("Damage") or "Unknown"
        
        local mutationString = tool:GetAttribute("MutationString")
        local mut = findMutation(mutationString)
                                or findMutation(tool:GetAttribute("Mutation"))
                                or findMutation(tool.Name:match("%[([^%]]-)%]"))
                                or "Normal"
        data.Mutation = mut
        
        return data
    end

    local data = {}
    data.Type = "Brainrot"
    data.Size = (tool:GetAttribute("Size") or "Unknown") .. " kg"
    data.Name = cleanName(rawName)
    local mutationString = tool:GetAttribute("MutationString")
    local mut
    if mutationString and mutationString == data.Name then
        mut = "Normal"
    else
        mut = findMutation(mutationString)
            or findMutation(tool:GetAttribute("Mutation"))
            or findMutation(rawName:match("%[([^%]]-)%]"))
            or "Normal"
    end
    data.Mutation = mut
    local model = tool:FindFirstChildOfClass("Model")
    if model then
        data.Rarity = model:GetAttribute("Rarity") or "Unknown"
    else
        data.Rarity = "Unknown"
    end
    return data
end

local function getCharacter(player)
    if not player then return nil end
    if player.Character then return player.Character end
    local playersFolder = Ws:FindFirstChild("Players")
    if playersFolder then
        return playersFolder:FindFirstChild(player.Name)
    end
    return nil
end

local function scanPlayer(player)
    local items = {}
    if not player then return items end
    
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") then
                local d = parseTool(tool)
                if d then table.insert(items, d) end
            end
        end
    end

    local char = getCharacter(player)
    if char then
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then
                local d = parseTool(child)
                if d then table.insert(items, d) end
            end
        end
    end
    
    return items
end

local function getPlotBrainrotData(plotModel)
    if not plotModel then return nil end
    local data = {}
    data.Type = "Brainrot"
    local brainrotPart = plotModel:FindFirstChild("Brainrot")
    if not brainrotPart then return nil end
    local rawName = brainrotPart:GetAttribute("Brainrot") or "Unknown"
    data.Name = cleanName(rawName)
    local mut = findMutation(brainrotPart:GetAttribute("Mutation")) or "Normal"
    data.Mutation = mut
    data.Rarity = brainrotPart:GetAttribute("Rarity") or "Unknown"
    data.Size = (brainrotPart:GetAttribute("Size") or "Unknown") .. " kg"
    data.MoneyPerSecond = "Unknown"
    return data
end

local function scanPlotBrainrots(player)
    local items = {}
    if not player then return items end
    local plots = Ws:FindFirstChild("Plots")
    if not plots then return items end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:GetAttribute("Owner") == player.Name then
            local brainrotsFolder = plot:FindFirstChild("Brainrots")
            if brainrotsFolder then
                for _, plotModel in ipairs(brainrotsFolder:GetChildren()) do
                    if plotModel:IsA("Model") then
                        local d = getPlotBrainrotData(plotModel)
                        if d then table.insert(items, d) end
                    end
                end
            end
            break
        end
    end
    return items
end

local function getPlotPlantData(plantModel)
    if not plantModel then return nil end
    local data = {}
    data.Type = "Plant"
    data.Name = cleanName(plantModel.Name)
    data.Colors = plantModel:GetAttribute("Colors") or "Unknown"
    data.Damage = plantModel:GetAttribute("Damage") or "Unknown"
    data.Level = plantModel:GetAttribute("Level") or "Unknown"
    data.Rarity = plantModel:GetAttribute("Rarity") or "Unknown"
    data.Row = plantModel:GetAttribute("Row") or "Unknown"
    data.Size = (plantModel:GetAttribute("Size") or "Unknown") .. " kg"
    
    local mutationString = plantModel:GetAttribute("MutationString")
    local mut = findMutation(mutationString)
                         or findMutation(plantModel:GetAttribute("Mutation"))
                         or findMutation(plantModel.Name:match("%[([^%]]-)%]"))
                         or "Normal"
    data.Mutation = mut
    
    return data
end

local function scanPlotPlants(player)
    local items = {}
    if not player then return items end
    local plots = Ws:FindFirstChild("Plots")
    if not plots then return items end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:GetAttribute("Owner") == player.Name then
            local plantsFolder = plot:FindFirstChild("Plants")
            if plantsFolder then
                for _, plantModel in ipairs(plantsFolder:GetChildren()) do
                    if plantModel:IsA("Model") then
                        local d = getPlotPlantData(plantModel)
                        if d then table.insert(items, d) end
                    end
                end
            end
            break
        end
    end
    return items
end

local function buildScanResults()
    local results = {}
    
    for _,p in ipairs(Plrs:GetPlayers()) do
        if HIDE_MY_DATA and p.Name == MY_USERNAME then
            continue
        end
        
        local allItems = {}
        local backpackItems = scanPlayer(p)
        for _, itemData in ipairs(backpackItems) do table.insert(allItems, itemData) end
        
        local plotBrainrots = scanPlotBrainrots(p)
        for _, itemData in ipairs(plotBrainrots) do table.insert(allItems, itemData) end
        
        local plotPlants = scanPlotPlants(p)
        for _, itemData in ipairs(plotPlants) do table.insert(allItems, itemData) end
        
        local pData = { Brainrots = { Items = {} }, Plants = { Items = {} } }
        
        for _, itemData in ipairs(allItems) do
            if itemData then
                local typ = itemData.Type
                local name = itemData.Name or "Unknown"
                
                local list, searchList, generalThreshold
                if typ == "Plant" then
                    list = pData.Plants.Items
                    searchList = ScanPlants
                    generalThreshold = MAX_KG_THRESHOLD_PLANT
                else
                    list = pData.Brainrots.Items
                    searchList = ScanBrainrots
                    generalThreshold = MAX_KG_THRESHOLD_BRAINROT
                end
                
                local specificScanData = searchList[name]
                local sizeInKg = parseSizeToKg(itemData.Size)
                local itemMutation = itemData.Mutation or "Normal"

                if not (specificScanData and specificScanData.ignore) then
                    local shouldAddItem = false
                    local isGlobalMutationWhitelisted = false
                    if itemMutation ~= "Normal" then
                        isGlobalMutationWhitelisted = ScanMutations[itemMutation] ~= nil
                    end

                    if specificScanData then
                        local mutationKg
                        
                        if specificScanData.mutations and specificScanData.mutationsBypassKg then
                            mutationKg = specificScanData.mutations[itemMutation]
                        end

                        if type(mutationKg) == "number" then
                            if sizeInKg >= mutationKg then  
                                shouldAddItem = true
                            end
                        else
                            if sizeInKg >= specificScanData.kg then
                                shouldAddItem = true
                            end
                        end
                    else
                        if typ == "Plant" and sizeInKg > generalThreshold then
                            shouldAddItem = true
                        elseif typ == "Brainrot" and sizeInKg > generalThreshold then
                            shouldAddItem = true
                        end
                    end
                    
                    if shouldAddItem or isGlobalMutationWhitelisted then
                        if not list[name] then
                            list[name] = { Instances = {}, Summary = { TotalCount = 0 } }
                            list[name].Summary.InstanceCounts = {}
                        end
                        
                        local entry = list[name]
                        entry.Summary.TotalCount = entry.Summary.TotalCount + 1
                        
                        local val
                        if typ == "Plant" then
                            val = itemData.Mutation or "Normal"
                            if val == "Normal" then
                                val = itemData.Colors or "Unknown"
                            end
                        else
                            val = itemData.Mutation or "Normal"
                        end
                        
                        local sizeVal = itemData.Size
                        if not sizeVal or sizeVal == " kg" then
                            sizeVal = "Unknown kg"
                        end
                        
                        local summaryKey = tostring(sizeVal) .. ", " .. tostring(val)
                        entry.Summary.InstanceCounts[summaryKey] = (entry.Summary.InstanceCounts[summaryKey] or 0) + 1
                        
                        local instanceData = {}
                        for k, v in pairs(itemData) do
                            if k ~= "Name" and k ~= "Type" then
                                instanceData[k] = v
                            end
                        end
                        table.insert(entry.Instances, instanceData)
                    end
                end
            end
        end
        results[p.Name] = pData
    end
    return results
end

local scannerUI = nil
local currentFrames = {}
local highlightedPlayers = {}
local removedItems = {}
local isFollowing = false
local followTargetName = nil

local function walkPath(humanoid, path)
    if not humanoid or not humanoid.Parent or not path then return false end
    if path.Status ~= Enum.PathStatus.Success then
        return false
    end
    local waypoints = path:GetWaypoints()
    for i, waypoint in ipairs(waypoints) do
        if not humanoid or not humanoid.Parent then return false end
        if not isFollowing or not followTargetName then return false end
        
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
        
        humanoid:MoveTo(waypoint.Position)
        
        local moveResult = false
        local success, result = pcall(function() return humanoid.MoveToFinished:Wait(5.0) end)
        if success then
            moveResult = result
        end
        
        if not moveResult then
            if not humanoid or not humanoid.Parent then return false end
            local lastPos = humanoid.Parent:GetPivot().Position
            wait(1.0)
            if not humanoid or not humanoid.Parent then return false end
            
            if (humanoid.Parent:GetPivot().Position - lastPos).Magnitude < 0.5 then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                wait(0.5)
                if not humanoid or not humanoid.Parent then return false end
                humanoid:MoveTo(waypoint.Position)
                
                success, result = pcall(function() return humanoid.MoveToFinished:Wait(3.0) end)
                if success then
                    moveResult = result
                end
                
                if not moveResult then
                    return false
                end
            else
                return false
            end
        end
    end
    return true
end

local function computeAndWalk(humanoid, startVec, endVec)
    if not humanoid or not humanoid.Parent then return false end
    local pathParams = {
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        Costs = {
            Water = 1000
        }
    }
    local path = PathfindingService:CreatePath(pathParams)
    local success, err = pcall(function() path:ComputeAsync(startVec, endVec) end)
    if not success or path.Status ~= Enum.PathStatus.Success then
        return false
    end
    return walkPath(humanoid, path)
end

local function ToggleFollowPlayer(playerName)
    if isFollowing and followTargetName == playerName then
        isFollowing = false
        followTargetName = nil
        local localChar = getCharacter(Plrs.LocalPlayer)
        local localHumanoid = localChar and localChar:FindFirstChildOfClass("Humanoid")
        if localHumanoid then
            localHumanoid:MoveTo(localChar.HumanoidRootPart.Position) 
        end
    else
        isFollowing = true
        followTargetName = playerName
    end
end

local RunScanAndUpdate
local updateUI

local function createUI()
    if not CoreGui then return nil end
    
    local oldGui = CoreGui:FindFirstChild("ScannerUI")
    if oldGui then
        pcall(function() oldGui:Destroy() end)
    end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ScannerUI"
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.ResetOnSpawn = false
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 350, 0, 400)
    mainFrame.Position = UDim2.new(1, -350, 1, -400)
    mainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    mainFrame.BorderColor3 = Color3.fromRGB(80, 80, 80)
    mainFrame.BorderSizePixel = 2
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 30)
    header.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    header.BorderColor3 = Color3.fromRGB(80, 80, 80)
    header.Parent = mainFrame
    
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -250, 1, 0)
    title.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(220, 220, 220)
    title.Text = "Item Scanner"
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 18
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextWrapped = true
    title.Parent = header
    
    local toggleButton = Instance.new("TextButton")
    toggleButton.Name = "ToggleButton"
    toggleButton.Size = UDim2.new(0, 30, 1, 0)
    toggleButton.Position = UDim2.new(1, -60, 0, 0)
    toggleButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    toggleButton.TextColor3 = Color3.fromRGB(220, 220, 220)
    toggleButton.Text = "-"
    toggleButton.Font = Enum.Font.SourceSansBold
    toggleButton.TextSize = 24
    toggleButton.Parent = header
    
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0, 30, 1, 0)
    closeButton.Position = UDim2.new(1, -30, 0, 0)
    closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    closeButton.TextColor3 = Color3.fromRGB(220, 220, 220)
    closeButton.Text = "X"
    closeButton.Font = Enum.Font.SourceSansBold
    closeButton.TextSize = 20
    closeButton.Parent = header

    local hopButton = Instance.new("TextButton")
    hopButton.Name = "HopButton"
    hopButton.Size = UDim2.new(0, 30, 1, 0)
    hopButton.Position = UDim2.new(1, -90, 0, 0)
    hopButton.BackgroundColor3 = Color3.fromRGB(50, 80, 200)
    hopButton.TextColor3 = Color3.fromRGB(220, 220, 220)
    hopButton.Text = ">>"
    hopButton.Font = Enum.Font.SourceSansBold
    hopButton.TextSize = 20
    hopButton.Parent = header
    
    local autoHopButton = Instance.new("TextButton")
    autoHopButton.Name = "AutoHopButton"
    autoHopButton.Size = UDim2.new(0, 30, 1, 0)
    autoHopButton.Position = UDim2.new(1, -150, 0, 0)
    autoHopButton.TextColor3 = Color3.fromRGB(220, 220, 220)
    autoHopButton.Font = Enum.Font.SourceSansBold
    autoHopButton.TextSize = 16
    autoHopButton.Parent = header
    
    local hideDataButton = Instance.new("TextButton")
    hideDataButton.Name = "HideDataButton"
    hideDataButton.Size = UDim2.new(0, 30, 1, 0)
    hideDataButton.Position = UDim2.new(1, -120, 0, 0)
    hideDataButton.TextColor3 = Color3.fromRGB(220, 220, 220)
    hideDataButton.Font = Enum.Font.SourceSansBold
    hideDataButton.TextSize = 20
    hideDataButton.Parent = header
    
    local copyButton = Instance.new("TextButton")
    copyButton.Name = "CopyButton"
    copyButton.Size = UDim2.new(0, 30, 1, 0)
    copyButton.Position = UDim2.new(1, -180, 0, 0)
    copyButton.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
    copyButton.TextColor3 = Color3.fromRGB(220, 220, 220)
    copyButton.Text = "C"
    copyButton.Font = Enum.Font.SourceSansBold
    copyButton.TextSize = 16
    copyButton.Parent = header

    local refreshButton = Instance.new("TextButton")
    refreshButton.Name = "RefreshButton"
    refreshButton.Size = UDim2.new(0, 30, 1, 0)
    refreshButton.Position = UDim2.new(1, -210, 0, 0)
    refreshButton.BackgroundColor3 = Color3.fromRGB(80, 150, 200)
    refreshButton.TextColor3 = Color3.fromRGB(220, 220, 220)
    refreshButton.Text = "R"
    refreshButton.Font = Enum.Font.SourceSansBold
    refreshButton.TextSize = 16
    refreshButton.Parent = header

    local function updateAutoHopButtonVisuals()
        if isAutoHopping then
            autoHopButton.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
            autoHopButton.Text = "ON"
        else
            autoHopButton.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
            autoHopButton.Text = "OFF"
        end
    end
    
    updateAutoHopButtonVisuals()

    local function updateHideButtonVisuals()
        if HIDE_MY_DATA then
            hideDataButton.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
            hideDataButton.Text = "H"
        else
            hideDataButton.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
            hideDataButton.Text = "S"
        end
    end
    updateHideButtonVisuals()
    
    local scrollingFrame = Instance.new("ScrollingFrame")
    scrollingFrame.Name = "ScrollingFrame"
    scrollingFrame.Size = UDim2.new(1, 0, 1, -30)
    scrollingFrame.Position = UDim2.new(0, 0, 0, 30)
    scrollingFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    scrollingFrame.BackgroundTransparency = 1
    scrollingFrame.BorderSizePixel = 0
    scrollingFrame.ScrollingDirection = Enum.ScrollingDirection.Y
    scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollingFrame.ScrollBarThickness = 6
    scrollingFrame.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 120)
    scrollingFrame.Parent = mainFrame
    
    local sfPadding = Instance.new("UIPadding")
    sfPadding.PaddingLeft = UDim.new(0, 5)
    sfPadding.PaddingRight = UDim.new(0, 5)
    sfPadding.PaddingTop = UDim.new(0, 5)
    sfPadding.PaddingBottom = UDim.new(0, 5)
    sfPadding.Parent = scrollingFrame
    
    local uiListLayout = Instance.new("UIListLayout")
    uiListLayout.Name = "UIListLayout"
    uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    uiListLayout.Padding = UDim.new(0, 5)
    uiListLayout.Parent = scrollingFrame

    local itemTemplate = Instance.new("Frame")
    itemTemplate.Name = "ItemTemplate"
    itemTemplate.Size = UDim2.new(1, 0, 0, 0)
    itemTemplate.AutomaticSize = Enum.AutomaticSize.Y
    itemTemplate.Position = UDim2.new(0, 0, 0, 0)
    itemTemplate.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    itemTemplate.BorderColor3 = Color3.fromRGB(70, 70, 70)
    itemTemplate.ClipsDescendants = true
    itemTemplate.Visible = false
    itemTemplate.LayoutOrder = 1
    itemTemplate.Parent = scrollingFrame
    
    local itemPadding = Instance.new("UIPadding")
    itemPadding.PaddingTop = UDim.new(0, 5)
    itemPadding.PaddingBottom = UDim.new(0, 5)
    itemPadding.PaddingLeft = UDim.new(0, 5)
    itemPadding.PaddingRight = UDim.new(0, 5)
    itemPadding.Parent = itemTemplate

    local itemLayout = Instance.new("UIListLayout")
    itemLayout.SortOrder = Enum.SortOrder.LayoutOrder
    itemLayout.Padding = UDim.new(0, 2)
    itemLayout.Parent = itemTemplate

    local playerFrame = Instance.new("Frame")
    playerFrame.Name = "PlayerFrame"
    playerFrame.Size = UDim2.new(1, 0, 0, 20)
    playerFrame.BackgroundTransparency = 1
    playerFrame.LayoutOrder = 1
    playerFrame.Parent = itemTemplate

    local playerLayout = Instance.new("UIListLayout")
    playerLayout.FillDirection = Enum.FillDirection.Horizontal
    playerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    playerLayout.SortOrder = Enum.SortOrder.LayoutOrder
    playerLayout.Parent = playerFrame

    local playerNameLabel = Instance.new("TextLabel")
    playerNameLabel.Name = "PlayerNameLabel"
    playerNameLabel.Size = UDim2.new(1, -120, 1, 0)
    playerNameLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    playerNameLabel.BackgroundTransparency = 1
    playerNameLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    playerNameLabel.Text = "Player: PlayerName"
    playerNameLabel.Font = Enum.Font.SourceSansBold
    playerNameLabel.TextSize = 16
    playerNameLabel.TextXAlignment = Enum.TextXAlignment.Left
    playerNameLabel.LayoutOrder = 1
    playerNameLabel.Parent = playerFrame

    local highlightButton = Instance.new("TextButton")
    highlightButton.Name = "HighlightButton"
    highlightButton.Size = UDim2.new(0, 50, 1, 0)
    highlightButton.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
    highlightButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    highlightButton.Text = "OFF"
    highlightButton.Font = Enum.Font.SourceSansBold
    highlightButton.TextSize = 14
    highlightButton.LayoutOrder = 2
    highlightButton.Parent = playerFrame
    
    local goToButton = Instance.new("TextButton")
    goToButton.Name = "GoToButton"
    goToButton.Size = UDim2.new(0, 30, 1, 0)
    goToButton.BackgroundColor3 = Color3.fromRGB(80, 160, 200)
    goToButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    goToButton.Text = "Go"
    goToButton.Font = Enum.Font.SourceSansBold
    goToButton.TextSize = 14
    goToButton.LayoutOrder = 3
    goToButton.Parent = playerFrame

    local removeItemButton = Instance.new("TextButton")
    removeItemButton.Name = "RemoveItemButton"
    removeItemButton.Size = UDim2.new(0, 30, 1, 0)
    removeItemButton.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
    removeItemButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    removeItemButton.Text = "X"
    removeItemButton.Font = Enum.Font.SourceSansBold
    removeItemButton.TextSize = 14
    removeItemButton.LayoutOrder = 4
    removeItemButton.Parent = playerFrame

    local itemName = Instance.new("TextLabel")
    itemName.Name = "ItemName"
    itemName.Size = UDim2.new(1, 0, 0, 20)
    itemName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    itemName.BackgroundTransparency = 1
    itemName.TextColor3 = Color3.fromRGB(255, 255, 255)
    itemName.Text = "Item: ItemName (Type)"
    itemName.Font = Enum.Font.SourceSansSemibold
    itemName.TextSize = 18
    itemName.TextXAlignment = Enum.TextXAlignment.Left
    itemName.LayoutOrder = 2
    itemName.Parent = itemTemplate

    local summary = Instance.new("TextLabel")
    summary.Name = "Summary"
    summary.Size = UDim2.new(1, 0, 0, 18)
    summary.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    summary.BackgroundTransparency = 1
    summary.TextColor3 = Color3.fromRGB(180, 180, 180)
    summary.Text = "Total Count: 0"
    summary.Font = Enum.Font.SourceSans
    summary.TextSize = 14
    summary.TextXAlignment = Enum.TextXAlignment.Left
    summary.LayoutOrder = 3
    summary.Parent = itemTemplate
    
    local detailsFrame = Instance.new("Frame")
    detailsFrame.Name = "DetailsFrame"
    detailsFrame.Size = UDim2.new(1, 0, 0, 0)
    detailsFrame.AutomaticSize = Enum.AutomaticSize.Y
    detailsFrame.BackgroundTransparency = 1
    detailsFrame.LayoutOrder = 4
    detailsFrame.Parent = itemTemplate
    
    local detailsLayout = Instance.new("UIListLayout")
    detailsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    detailsLayout.Padding = UDim.new(0, 0)
    detailsLayout.Parent = detailsFrame
    
    local detailTemplate = Instance.new("TextLabel")
    detailTemplate.Name = "DetailTemplate"
    detailTemplate.Size = UDim2.new(1, 0, 0, 16)
    detailTemplate.Position = UDim2.new(0, 0, 0, 0)
    detailTemplate.BackgroundTransparency = 1
    detailTemplate.TextColor3 = Color3.fromRGB(190, 190, 190)
    detailTemplate.Text = "       - Detail: Value"
    detailTemplate.Font = Enum.Font.SourceSans
    detailTemplate.TextSize = 14
    detailTemplate.TextXAlignment = Enum.TextXAlignment.Left
    detailTemplate.Visible = false
    detailTemplate.Parent = itemTemplate

    local noDataLabel = Instance.new("TextLabel")
    noDataLabel.Name = "NoDataLabel"
    noDataLabel.Size = UDim2.new(1, 0, 0, 30)
    noDataLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    noDataLabel.BackgroundTransparency = 1
    noDataLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    noDataLabel.Text = "No data found"
    noDataLabel.Font = Enum.Font.SourceSansItalic
    noDataLabel.TextSize = 18
    noDataLabel.TextWrapped = true
    noDataLabel.Visible = false
    noDataLabel.LayoutOrder = 9999
    noDataLabel.Parent = scrollingFrame

    toggleButton.MouseButton1Click:Connect(function()
        scrollingFrame.Visible = not scrollingFrame.Visible
        if scrollingFrame.Visible then
            toggleButton.Text = "-"
            mainFrame:TweenSize(UDim2.new(0, 350, 0, 400), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
        else
            toggleButton.Text = "+"
            mainFrame:TweenSize(UDim2.new(0, 350, 0, 30), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
        end
    end)
    
    closeButton.MouseButton1Click:Connect(function()
        isAutoHopping = false
        isFollowing = false
        followTargetName = nil
        RobustWriteFile(AutoHopFile, "false")
        pcall(function() screenGui:Destroy() end)
    end)
    
    hopButton.MouseButton1Click:Connect(HopServer)
    
    autoHopButton.MouseButton1Click:Connect(function()
        isAutoHopping = not isAutoHopping
        if isAutoHopping then
            RobustWriteFile(AutoHopFile, "true")
            CheckForAutoHop(scrollingFrame, noDataLabel)
        else
            RobustWriteFile(AutoHopFile, "false")
        end
        updateAutoHopButtonVisuals()
    end)
    
    hideDataButton.MouseButton1Click:Connect(function()
        HIDE_MY_DATA = not HIDE_MY_DATA
        updateHideButtonVisuals()
    end)
    
    copyButton.MouseButton1Click:Connect(function()
        if not scrollingFrame then return end
        
        local allFrames = {}
        for _, child in ipairs(scrollingFrame:GetChildren()) do
            if child:IsA("Frame") and child.Name ~= "ItemTemplate" and child.Visible then
                table.insert(allFrames, child)
            end
        end
        
        table.sort(allFrames, function(a, b)
            return a.LayoutOrder < b.LayoutOrder
        end)
        
        local clipboardText = {}
        
        for _, frame in ipairs(allFrames) do
            local playerLabel = frame:FindFirstChild("PlayerFrame") and frame.PlayerFrame:FindFirstChild("PlayerNameLabel")
            local itemLabel = frame:FindFirstChild("ItemName")
            local summaryLabel = frame:FindFirstChild("Summary")
            local detailsFrame = frame:FindFirstChild("DetailsFrame")
            
            if playerLabel and itemLabel and summaryLabel and detailsFrame then
                table.insert(clipboardText, playerLabel.Text)
                table.insert(clipboardText, itemLabel.Text)
                table.insert(clipboardText, summaryLabel.Text)
                
                local detailFrames = {}
                for _, detail in ipairs(detailsFrame:GetChildren()) do
                    if detail:IsA("TextLabel") then
                        table.insert(detailFrames, detail)
                    end
                end
                
                table.sort(detailFrames, function(a,b) return a.LayoutOrder < b.LayoutOrder end)
                
                for _, detail in ipairs(detailFrames) do
                    table.insert(clipboardText, detail.Text)
                end
                
                table.insert(clipboardText, "--------------------")
            end
        end
        
        if #clipboardText > 0 then
            pcall(function() setclipboard(table.concat(clipboardText, "\n")) end)
        end
    end)
    
    refreshButton.MouseButton1Click:Connect(function()
        removedItems = {}
        if RunScanAndUpdate then
            RunScanAndUpdate()
        end
    end)
    
    pcall(function() screenGui.Parent = CoreGui end)
    return screenGui
end

updateUI = function(ui, scanResults, currentFrames, highlightedPlayers, removedItems)
    if not ui or not scanResults or not currentFrames or not highlightedPlayers or not removedItems then return {}, false end
    
    local scrollingFrame = ui.MainFrame.ScrollingFrame
    local itemTemplate = scrollingFrame.ItemTemplate
    local detailTemplate = itemTemplate.DetailTemplate
    local noDataLabel = scrollingFrame.NoDataLabel
    
    if not scrollingFrame or not itemTemplate or not detailTemplate or not noDataLabel then return {}, false end

    local dataFound = false
    local layoutOrder = 1
    local framesToKeep = {}
    
    for playerName, pData in pairs(scanResults) do
        if pData then
            local function processCategory(items, categoryName)
                if not items then return end
                for itemName, itemData in pairs(items) do
                    if itemData then
                        local key = playerName .. "_" .. itemName
                        
                        if not removedItems[key] then
                            dataFound = true
                            framesToKeep[key] = true
                            
                            local existingFrame = currentFrames[key]
                            local newItem
                            
                            if existingFrame then
                                newItem = existingFrame
                            else
                                newItem = itemTemplate:Clone()
                                newItem.Name = key
                                newItem.Parent = scrollingFrame
                                currentFrames[key] = newItem
                            end
                            
                            newItem:SetAttribute("PlayerName", playerName)
                            newItem.PlayerFrame.PlayerNameLabel.Text = "Player: " .. playerName
                            newItem.ItemName.Text = "Item: " .. itemName .. " (" .. categoryName .. ")"
                            newItem.Summary.Text = "Total Count: " .. (itemData.Summary and itemData.Summary.TotalCount or 0)
                            newItem.LayoutOrder = layoutOrder
                            layoutOrder = layoutOrder + 1
                            
                            local highlightButton = newItem.PlayerFrame.HighlightButton
                            local goToButton = newItem.PlayerFrame.GoToButton
                            local removeItemButton = newItem.PlayerFrame.RemoveItemButton
                            
                            local function updateHighlightButtonVisuals()
                                if highlightedPlayers[playerName] then
                                    highlightButton.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
                                    highlightButton.Text = "ON"
                                else
                                    highlightButton.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
                                    highlightButton.Text = "OFF"
                                end
                            end
                            
                            updateHighlightButtonVisuals()
                            
                            if not existingFrame then
                                highlightButton.MouseButton1Click:Connect(function()
                                    local frame = highlightButton.Parent.Parent
                                    if not frame then return end
                                    local pName = frame:GetAttribute("PlayerName")
                                    if not pName then return end
                                    
                                    local p = Plrs:FindFirstChild(pName)
                                    local char = getCharacter(p)
                                    
                                    if highlightedPlayers[pName] then
                                        highlightedPlayers[pName] = nil
                                        if char then
                                            local h = char:FindFirstChild("ScannerHighlight")
                                            if h then pcall(function() h:Destroy() end) end
                                        end
                                    else
                                        highlightedPlayers[pName] = true
                                        if char then
                                            local h = Instance.new("Highlight")
                                            h.Name = "ScannerHighlight"
                                            h.OutlineColor = Color3.fromRGB(255, 255, 255)
                                            h.FillTransparency = 1
                                            h.Adornee = char
                                            h.Parent = char
                                        end
                                    end
                                    updateHighlightButtonVisuals()
                                end)
                                
                                goToButton.MouseButton1Click:Connect(function()
                                    local frame = goToButton.Parent.Parent
                                    if not frame then return end
                                    local pName = frame:GetAttribute("PlayerName")
                                    if pName then
                                        ToggleFollowPlayer(pName)
                                    end
                                end)
                                
                                removeItemButton.MouseButton1Click:Connect(function()
                                    local frame = removeItemButton.Parent.Parent
                                    if not frame then return end
                                    local key = frame.Name
                                    if key then
                                        removedItems[key] = true
                                    end
                                    pcall(function() frame:Destroy() end)
                                    currentFrames[key] = nil 
                                    CheckForAutoHop(scrollingFrame, noDataLabel)
                                end)
                            end
                            
                            local detailsFrame = newItem.DetailsFrame
                            detailsFrame:ClearAllChildren()
                            local detailsLayout = Instance.new("UIListLayout")
                            detailsLayout.SortOrder = Enum.SortOrder.LayoutOrder
                            detailsLayout.Padding = UDim.new(0, 0)
                            detailsLayout.Parent = detailsFrame
                            
                            local detailOrder = 1
                            
                            local instanceCounts = itemData.Summary and itemData.Summary.InstanceCounts
                            if instanceCounts then
                                for combinedKey, count in pairs(instanceCounts) do
                                    local newDetail = detailTemplate:Clone()
                                    newDetail.Text = "  - " .. tostring(combinedKey) .. ": " .. tostring(count)
                                    newDetail.LayoutOrder = detailOrder
                                    newDetail.Visible = true
                                    newDetail.Parent = detailsFrame
                                    detailOrder = detailOrder + 1
                                end
                            end
                            
                            newItem.Visible = true
                        end
                    end
                end
            end
            
            if pData.Plants then processCategory(pData.Plants.Items, "Plant") end
            if pData.Brainrots then processCategory(pData.Brainrots.Items, "Brainrot") end
        end
    end
    
    for key, frame in pairs(currentFrames) do
        if not framesToKeep[key] then
            pcall(function() frame:Destroy() end)
            currentFrames[key] = nil
        end
    end
    
    noDataLabel.Visible = not dataFound
    
    return currentFrames, dataFound
end

RunScanAndUpdate = function()
    if not scannerUI or not scannerUI.Parent then return end
    
    local hopStateContent = RobustReadFile(AutoHopFile)
    if hopStateContent == "true" then
        isAutoHopping = true
    elseif hopStateContent == "false" then
        isAutoHopping = false
    end

    if scannerUI and scannerUI.Parent then
        local autoHopBtn = scannerUI.MainFrame.Header:FindFirstChild("AutoHopButton")
        if autoHopBtn then
            if isAutoHopping then
                autoHopBtn.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
                autoHopBtn.Text = "ON"
            else
                autoHopBtn.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
                autoHopBtn.Text = "OFF"
            end
        end
    end

    local success, scanResults = pcall(buildScanResults)
    local dataFound = false
    
    if success and scanResults then
        local currentPlayers = {}
        for _,p in ipairs(Plrs:GetPlayers()) do currentPlayers[p.Name] = true end
        for playerName, isHighlighted in pairs(highlightedPlayers) do
            if not currentPlayers[playerName] then
                highlightedPlayers[playerName] = nil
            end
        end
        
        currentFrames, dataFound = updateUI(scannerUI, scanResults, currentFrames, highlightedPlayers, removedItems)
    end
    
    if isAutoHopping then
        if not dataFound then
            wait(2) 
            HopServer()
        else
            isAutoHopping = false
            RobustWriteFile(AutoHopFile, "false")
            if scannerUI and scannerUI.Parent then
                local autoHopBtn = scannerUI.MainFrame.Header:FindFirstChild("AutoHopButton")
                if autoHopBtn then
                    autoHopBtn.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
                    autoHopBtn.Text = "OFF"
                end
            end
        end
    end
end

scannerUI = createUI()

if scannerUI then
    RunScanAndUpdate() 

    spawn(function()
        wait(5) 
        while scannerUI and scannerUI.Parent do
            RunScanAndUpdate()
            wait(5)
        end
        
        for playerName, _ in pairs(highlightedPlayers) do
            local p = Plrs:FindFirstChild(playerName)
            local char = getCharacter(p)
            if char then
                local h = char:FindFirstChild("ScannerHighlight")
                if h then pcall(function() h:Destroy() end) end
            end
        end
        highlightedPlayers = {}
    end)
    
    spawn(function()
        while scannerUI and scannerUI.Parent do
            if isFollowing and followTargetName then
                local localPlayer = Plrs.LocalPlayer
                local localChar = getCharacter(localPlayer)
                local localHumanoid = localChar and localChar:FindFirstChildOfClass("Humanoid")
                local localRoot = localHumanoid and localChar:FindFirstChild("HumanoidRootPart")
                
                local targetPlayer = Plrs:FindFirstChild(followTargetName)
                local targetChar = targetPlayer and getCharacter(targetPlayer)
                local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")

                if not localRoot or not targetRoot or not localHumanoid then
                    isFollowing = false
                    followTargetName = nil
                else
                    if (localRoot.Position - targetRoot.Position).Magnitude > 8 then
                        computeAndWalk(localHumanoid, localRoot.Position, targetRoot.Position)
                    else
                        localHumanoid:MoveTo(localRoot.Position)
                    end
                end
            end
            
            if not isFollowing then
                wait(0.5)
            else
                wait(1.0)
            end
        end
    end)
end
