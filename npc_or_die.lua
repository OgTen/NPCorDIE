local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DEFAULT_PLAYER_COLOR = Color3.fromRGB(255, 0, 0)
local COLOR_FILE = "npc_or_die_colors.json"

local function LoadSavedColors()
    local colors = { PLAYER = DEFAULT_PLAYER_COLOR }
    if isfile and isfile(COLOR_FILE) then
        local success, data = pcall(readfile, COLOR_FILE)
        if success and data then
            local parsed = game:GetService("HttpService"):JSONDecode(data)
            if parsed and parsed.PLAYER then
                colors.PLAYER = Color3.fromRGB(parsed.PLAYER[1]*255, parsed.PLAYER[2]*255, parsed.PLAYER[3]*255)
            end
        end
    end
    return colors
end

local function SaveColors(colors)
    local data = game:GetService("HttpService"):JSONEncode({ PLAYER = {colors.PLAYER.R, colors.PLAYER.G, colors.PLAYER.B} })
    if writefile then writefile(COLOR_FILE, data) end
end

local COLORS = LoadSavedColors()
local PLAYER_COLOR = COLORS.PLAYER

local Settings = {
    ShowBox = false,
    ShowSkeleton = false,
    ShowLabel = false,
    ShowDistance = false,
    ShowSavedMarker = true
}

UI.SetValue("esp_enabled", false)
UI.SetValue("show_box", false)
UI.SetValue("show_skeleton", false)
UI.SetValue("show_label", false)
UI.SetValue("show_distance", false)
UI.SetValue("teleport_enabled", false)
UI.SetValue("save_enabled", false)
UI.SetValue("show_saved_marker", true)

local EntityDrawings = {}
local ScannedPlayers = {}
local IsEnabled = false
local IsScanning = false
local ScanTimer = 0
local SCAN_INTERVAL = 5
local RoundCheckTimer = 0
local ROUND_CHECK_INTERVAL = 2

local LocalPlayer = Players.LocalPlayer
local LocalPlayerName = LocalPlayer and LocalPlayer.Name or ""

local SavedPosition = nil
local character = nil
local hrp = nil

local TeleportKeybind = nil
local SaveKeybind = nil

local MarkerDrawings = { Line = nil, Label = nil }

local MOUSE_KEYS = {
    [0x01] = true, [0x02] = true, [0x04] = true,
    [0x05] = true, [0x06] = true,
}

local function IsRealPlayer(model)
    local hasNameTag = model:FindFirstChild("NameTag") ~= nil
    local hasAudioEmitter = model:FindFirstChild("AudioEmitter") ~= nil
    local hasTask = model:FindFirstChild("Task") ~= nil
    local hasAnimations = model:FindFirstChild("Animations") ~= nil

    local isPlayer = false
    local isSheriff = false

    if hasNameTag then
        if hasAudioEmitter then
            isPlayer = true
        elseif hasTask and hasAnimations then
            isPlayer = true
        end
    end

    if hasNameTag and not hasTask and not hasAnimations then
        isSheriff = true
        isPlayer = false
    end

    return isPlayer, {
        NameTag = hasNameTag,
        AudioEmitter = hasAudioEmitter,
        Task = hasTask,
        Animations = hasAnimations,
        IsSheriff = isSheriff
    }
end

local function GetBodyParts(model)
    local parts = {}
    local allParts = {}

    local function AddPart(name)
        local part = model:FindFirstChild(name)
        if part then
            parts[name] = part
            table.insert(allParts, part)
        end
    end

    AddPart("Head")
    AddPart("UpperTorso")
    AddPart("LowerTorso")
    AddPart("HumanoidRootPart")
    AddPart("LeftUpperArm")
    AddPart("LeftLowerArm")
    AddPart("LeftHand")
    AddPart("RightUpperArm")
    AddPart("RightLowerArm")
    AddPart("RightHand")
    AddPart("LeftUpperLeg")
    AddPart("LeftLowerLeg")
    AddPart("LeftFoot")
    AddPart("RightUpperLeg")
    AddPart("RightLowerLeg")
    AddPart("RightFoot")

    parts.AllParts = allParts
    return parts
end

local function CalculateBoundingBox(bodyParts)
    if not bodyParts.AllParts or #bodyParts.AllParts == 0 then
        return nil, nil, nil
    end

    local minX, maxX = math.huge, -math.huge
    local minY, maxY = math.huge, -math.huge
    local allOnScreen = true

    for _, part in ipairs(bodyParts.AllParts) do
        if part and part.Position then
            local screenPos, onScreen = WorldToScreen(part.Position)
            if onScreen then
                if screenPos.X < minX then minX = screenPos.X end
                if screenPos.X > maxX then maxX = screenPos.X end
                if screenPos.Y < minY then minY = screenPos.Y end
                if screenPos.Y > maxY then maxY = screenPos.Y end
            else
                allOnScreen = false
            end
        end
    end

    if not allOnScreen or minX == math.huge then
        return nil, nil, nil
    end

    local padding = 15
    minX = minX - padding
    minY = minY - padding
    maxX = maxX + padding
    maxY = maxY + padding

    local width = maxX - minX
    local height = maxY - minY

    return Vector2.new(minX, minY), width, height
end

local function ScanForPlayers()
    if not IsEnabled then return {} end

    local found = {}

    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") then
            local humanoid = child:FindFirstChild("Humanoid")
            local head = child:FindFirstChild("Head")

            if humanoid and head and head:IsA("BasePart") then
                if child.Name ~= LocalPlayerName then
                    local isAlive = humanoid.Health > 0
                    local isPlayer, details = IsRealPlayer(child)

                    if isPlayer and isAlive and not details.IsSheriff then
                        local bodyParts = GetBodyParts(child)

                        if bodyParts.Head and bodyParts.UpperTorso then
                            table.insert(found, {
                                Model = child,
                                Humanoid = humanoid,
                                IsPlayer = true,
                                Name = child.Name,
                                Details = details,
                                BodyParts = bodyParts
                            })
                        end
                    end
                end
            end
        end
    end

    return found
end

local function CreatePlayerDrawings(player)
    local drawings = {}
    local color = PLAYER_COLOR

    local box = Drawing.new("Square")
    box.Color = color
    box.Thickness = 2
    box.Filled = false
    box.ZIndex = 999
    box.Visible = Settings.ShowBox
    drawings.Box = box

    local function CreateLine(part1, part2)
        if part1 and part2 then
            local line = Drawing.new("Line")
            line.Color = color
            line.Thickness = 2
            line.Transparency = 1
            line.ZIndex = 999
            line.Visible = Settings.ShowSkeleton
            return line
        end
        return nil
    end

    if player.BodyParts.Head and player.BodyParts.UpperTorso then
        drawings.HeadToTorso = CreateLine(player.BodyParts.Head, player.BodyParts.UpperTorso)
    end
    if player.BodyParts.UpperTorso and player.BodyParts.LowerTorso then
        drawings.UpperToLower = CreateLine(player.BodyParts.UpperTorso, player.BodyParts.LowerTorso)
    end
    if player.BodyParts.LowerTorso and player.BodyParts.Root then
        drawings.LowerToRoot = CreateLine(player.BodyParts.LowerTorso, player.BodyParts.Root)
    end

    if player.BodyParts.UpperTorso and player.BodyParts.LeftUpperArm then
        drawings.LeftUpperArm = CreateLine(player.BodyParts.UpperTorso, player.BodyParts.LeftUpperArm)
    end
    if player.BodyParts.LeftUpperArm and player.BodyParts.LeftLowerArm then
        drawings.LeftLowerArm = CreateLine(player.BodyParts.LeftUpperArm, player.BodyParts.LeftLowerArm)
    end
    if player.BodyParts.LeftLowerArm and player.BodyParts.LeftHand then
        drawings.LeftHand = CreateLine(player.BodyParts.LeftLowerArm, player.BodyParts.LeftHand)
    end

    if player.BodyParts.UpperTorso and player.BodyParts.RightUpperArm then
        drawings.RightUpperArm = CreateLine(player.BodyParts.UpperTorso, player.BodyParts.RightUpperArm)
    end
    if player.BodyParts.RightUpperArm and player.BodyParts.RightLowerArm then
        drawings.RightLowerArm = CreateLine(player.BodyParts.RightUpperArm, player.BodyParts.RightLowerArm)
    end
    if player.BodyParts.RightLowerArm and player.BodyParts.RightHand then
        drawings.RightHand = CreateLine(player.BodyParts.RightLowerArm, player.BodyParts.RightHand)
    end

    if player.BodyParts.LowerTorso and player.BodyParts.LeftUpperLeg then
        drawings.LeftUpperLeg = CreateLine(player.BodyParts.LowerTorso, player.BodyParts.LeftUpperLeg)
    end
    if player.BodyParts.LeftUpperLeg and player.BodyParts.LeftLowerLeg then
        drawings.LeftLowerLeg = CreateLine(player.BodyParts.LeftUpperLeg, player.BodyParts.LeftLowerLeg)
    end
    if player.BodyParts.LeftLowerLeg and player.BodyParts.LeftFoot then
        drawings.LeftFoot = CreateLine(player.BodyParts.LeftLowerLeg, player.BodyParts.LeftFoot)
    end

    if player.BodyParts.LowerTorso and player.BodyParts.RightUpperLeg then
        drawings.RightUpperLeg = CreateLine(player.BodyParts.LowerTorso, player.BodyParts.RightUpperLeg)
    end
    if player.BodyParts.RightUpperLeg and player.BodyParts.RightLowerLeg then
        drawings.RightLowerLeg = CreateLine(player.BodyParts.RightUpperLeg, player.BodyParts.RightLowerLeg)
    end
    if player.BodyParts.RightLowerLeg and player.BodyParts.RightFoot then
        drawings.RightFoot = CreateLine(player.BodyParts.RightLowerLeg, player.BodyParts.RightFoot)
    end

    local label = Drawing.new("Text")
    label.Font = Drawing.Fonts.UI
    label.Size = 14
    label.Color = color
    label.Outline = false
    label.Center = true
    label.ZIndex = 999
    label.Visible = Settings.ShowLabel or Settings.ShowDistance
    drawings.Label = label

    return drawings
end

local function UpdateDrawings(entities)
    for _, playerData in pairs(EntityDrawings) do
        for _, drawing in pairs(playerData) do
            if drawing and drawing.Remove then
                drawing:Remove()
            end
        end
    end
    EntityDrawings = {}

    for i, player in ipairs(entities) do
        EntityDrawings[i] = CreatePlayerDrawings(player)
    end

    ScannedPlayers = entities
end

local function PerformFullScan()
    local players = ScanForPlayers()
    
    local changed = false
    if #players ~= #ScannedPlayers then
        changed = true
    else
        for i = 1, math.min(#players, 10) do
            if players[i].Name ~= ScannedPlayers[i].Name then
                changed = true
                break
            end
        end
    end
    
    if changed then
        UpdateDrawings(players)
        ScannedPlayers = players
    end
    
    IsScanning = true
    ScanTimer = 0
end

local function CheckRoundStatus()
    local nameCounts = {}
    local totalPlayers = 0
    
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") then
            local humanoid = child:FindFirstChild("Humanoid")
            if humanoid then
                local name = child.Name
                nameCounts[name] = (nameCounts[name] or 0) + 1
                totalPlayers = totalPlayers + 1
            end
        end
    end
    
    local allUnique = true
    for _, count in pairs(nameCounts) do
        if count > 1 then
            allUnique = false
            break
        end
    end
    
    local wasInRound = InRound
    InRound = not allUnique and totalPlayers > 1
    
    if InRound and not wasInRound then
        notify("Round started - ESP activated", "NPC Or Die", 3)
        PerformFullScan()
    elseif not InRound and wasInRound then
        notify("Round ended - ESP deactivated", "NPC Or Die", 3)
        SavedPosition = nil
        for _, drawings in pairs(EntityDrawings) do
            for _, drawing in pairs(drawings) do
                if drawing and drawing.Remove then
                    drawing:Remove()
                end
            end
        end
        EntityDrawings = {}
        ScannedPlayers = {}
        IsScanning = false
    end
end

local function UpdatePlayerDrawings(drawings, player)
    local camera = workspace.CurrentCamera
    if not camera then return end

    local headPos = player.BodyParts.Head and player.BodyParts.Head.Position
    local dist = headPos and math.floor((headPos - camera.Position).Magnitude) or 0
    local color = PLAYER_COLOR

    if Settings.ShowBox then
        local boxPos, boxWidth, boxHeight = CalculateBoundingBox(player.BodyParts)
        if boxPos and boxWidth and boxHeight then
            drawings.Box.Color = color
            drawings.Box.Position = boxPos
            drawings.Box.Size = Vector2.new(boxWidth, boxHeight)
            drawings.Box.Visible = true
        else
            drawings.Box.Visible = false
        end
    else
        drawings.Box.Visible = false
    end

    if Settings.ShowSkeleton then
        for name, line in pairs(drawings) do
            if name ~= "Box" and name ~= "Label" then
                line.Color = color

                local part1, part2 = nil, nil

                local connections = {
                    HeadToTorso = {"Head", "UpperTorso"},
                    UpperToLower = {"UpperTorso", "LowerTorso"},
                    LowerToRoot = {"LowerTorso", "Root"},
                    LeftUpperArm = {"UpperTorso", "LeftUpperArm"},
                    LeftLowerArm = {"LeftUpperArm", "LeftLowerArm"},
                    LeftHand = {"LeftLowerArm", "LeftHand"},
                    RightUpperArm = {"UpperTorso", "RightUpperArm"},
                    RightLowerArm = {"RightUpperArm", "RightLowerArm"},
                    RightHand = {"RightLowerArm", "RightHand"},
                    LeftUpperLeg = {"LowerTorso", "LeftUpperLeg"},
                    LeftLowerLeg = {"LeftUpperLeg", "LeftLowerLeg"},
                    LeftFoot = {"LeftLowerLeg", "LeftFoot"},
                    RightUpperLeg = {"LowerTorso", "RightUpperLeg"},
                    RightLowerLeg = {"RightUpperLeg", "RightLowerLeg"},
                    RightFoot = {"RightLowerLeg", "RightFoot"}
                }

                if connections[name] then
                    part1 = player.BodyParts[connections[name][1]]
                    part2 = player.BodyParts[connections[name][2]]
                end

                if part1 and part2 then
                    local pos1 = part1.Position
                    local pos2 = part2.Position

                    if pos1 and pos2 then
                        local screen1, on1 = WorldToScreen(pos1)
                        local screen2, on2 = WorldToScreen(pos2)

                        if on1 and on2 then
                            line.From = screen1
                            line.To = screen2
                            line.Visible = true
                        else
                            line.Visible = false
                        end
                    end
                end
            end
        end
    else
        for name, line in pairs(drawings) do
            if name ~= "Box" and name ~= "Label" then
                line.Visible = false
            end
        end
    end

    if (Settings.ShowLabel or Settings.ShowDistance) and headPos then
        local screenPos, onScreen = WorldToScreen(headPos)
        if onScreen then
            local labelText = ""

            if Settings.ShowLabel then
                labelText = player.Name
            end

            if Settings.ShowDistance then
                if labelText ~= "" then
                    labelText = labelText .. " [" .. dist .. "m]"
                else
                    labelText = "[" .. dist .. "m]"
                end
            end

            drawings.Label.Color = color
            drawings.Label.Position = screenPos - Vector2.new(0, 30)
            drawings.Label.Text = labelText
            drawings.Label.Visible = true
        else
            drawings.Label.Visible = false
        end
    else
        drawings.Label.Visible = false
    end
end

local function DisplayScannedPlayers()
    if #ScannedPlayers == 0 then
        for _, drawings in pairs(EntityDrawings) do
            for _, drawing in pairs(drawings) do
                if drawing and drawing.Visible ~= nil then
                    drawing.Visible = false
                end
            end
        end
        return
    end

    local alivePlayers = {}
    for _, player in ipairs(ScannedPlayers) do
        if player.Model and player.Model.Parent and player.Humanoid and player.Humanoid.Health > 0 then
            table.insert(alivePlayers, player)
        end
    end

    if #alivePlayers ~= #ScannedPlayers then
        ScannedPlayers = alivePlayers
        UpdateDrawings(alivePlayers)
        return
    end

    if #EntityDrawings ~= #ScannedPlayers then
        UpdateDrawings(ScannedPlayers)
    end

    for i, player in ipairs(ScannedPlayers) do
        if EntityDrawings[i] then
            UpdatePlayerDrawings(EntityDrawings[i], player)
        end
    end
end

local function EnsureCharacter()
    if not character or not character.Parent then
        character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        if not character then return false end
        hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
    end
    
    if not hrp or not hrp.Parent then
        hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
    end
    
    return true
end

local function SavePosition()
    if not EnsureCharacter() then
        notify("Character not found!", "NPC Or Die", 3)
        return
    end
    
    if not hrp then
        notify("Root part not found!", "NPC Or Die", 3)
        return
    end

    SavedPosition = hrp.Position
    notify("Position saved!", "NPC Or Die", 3)
end

local function TeleportToSaved()
    if not SavedPosition then
        notify("No position saved! Press save hotkey first.", "NPC Or Die", 3)
        return
    end
    
    if not EnsureCharacter() then
        notify("Character not found!", "NPC Or Die", 3)
        return
    end
    
    if not hrp then
        notify("Root part not found!", "NPC Or Die", 3)
        return
    end
    
    local pos = SavedPosition
    hrp.CFrame = CFrame.new(pos.X, pos.Y, pos.Z)
    notify("Teleported to saved position!", "NPC Or Die", 3)
end

local function UpdateSavedPositionMarker()
    local camera = workspace.CurrentCamera
    if not camera then return end

    if not SavedPosition or not Settings.ShowSavedMarker then
        if MarkerDrawings.Line then MarkerDrawings.Line.Visible = false end
        if MarkerDrawings.Label then MarkerDrawings.Label.Visible = false end
        return
    end

    local headPos = SavedPosition + Vector3.new(0, 3, 0)
    local footPos = SavedPosition - Vector3.new(0, 3, 0)

    local headScreen, headOnScreen = WorldToScreen(headPos)
    local footScreen, footOnScreen = WorldToScreen(footPos)

    if not headOnScreen or not footOnScreen then
        if MarkerDrawings.Line then MarkerDrawings.Line.Visible = false end
        if MarkerDrawings.Label then MarkerDrawings.Label.Visible = false end
        return
    end

    if not MarkerDrawings.Line then
        MarkerDrawings.Line = Drawing.new("Line")
        MarkerDrawings.Line.Color = COLORS.MARKER
        MarkerDrawings.Line.Thickness = 2
        MarkerDrawings.Line.Transparency = 1
        MarkerDrawings.Line.ZIndex = 1000
    end

    if not MarkerDrawings.Label then
        MarkerDrawings.Label = Drawing.new("Text")
        MarkerDrawings.Label.Font = Drawing.Fonts.UI
        MarkerDrawings.Label.Size = 14
        MarkerDrawings.Label.Color = COLORS.MARKER
        MarkerDrawings.Label.Outline = false
        MarkerDrawings.Label.Center = true
        MarkerDrawings.Label.ZIndex = 1000
    end

    MarkerDrawings.Line.From = footScreen
    MarkerDrawings.Line.To = headScreen
    MarkerDrawings.Line.Visible = true

    MarkerDrawings.Label.Position = headScreen - Vector2.new(0, 20)
    MarkerDrawings.Label.Text = "SAVED POSITION"
    MarkerDrawings.Label.Visible = true
end

UI.AddTab("NPC Or Die", function(tab)
    local teleportSection = tab:Section("Teleport", "Left")
    
    teleportSection:Toggle("teleport_enabled", "Teleport To Position", false, function(state)
        if state then
            notify("Teleport enabled", "NPC Or Die", 3)
        else
            notify("Teleport disabled", "NPC Or Die", 3)
        end
    end)
    TeleportKeybind = teleportSection:Keybind("teleport_kb", 0x4C, "click")
    TeleportKeybind:AddToHotkey("Teleport to Saved", "teleport_enabled")
    
    teleportSection:Toggle("save_enabled", "Save Position", false, function(state)
        if state then
            notify("Save position enabled", "NPC Or Die", 3)
        else
            notify("Save position disabled", "NPC Or Die", 3)
        end
    end)
    SaveKeybind = teleportSection:Keybind("save_kb", 0x4B, "click")
    SaveKeybind:AddToHotkey("Save Position", "save_enabled")

    local visualSection = tab:Section("Visuals", "Right")

    visualSection:Toggle("esp_enabled", "Enable ESP", UI.GetValue("esp_enabled") or false, function(state)
        IsEnabled = state
        if state then
            CheckRoundStatus()
            if InRound then
                notify("ESP Enabled", "NPC Or Die", 3)
            else
                notify("ESP Enabled - Waiting for round to start", "NPC Or Die", 3)
            end
        else
            for _, drawings in pairs(EntityDrawings) do
                for _, drawing in pairs(drawings) do
                    if drawing and drawing.Remove then
                        drawing:Remove()
                    end
                end
            end
            EntityDrawings = {}
            ScannedPlayers = {}
            IsScanning = false
            notify("ESP Disabled", "NPC Or Die", 3)
        end
    end)

    visualSection:ColorPicker("player_color", PLAYER_COLOR.R, PLAYER_COLOR.G, PLAYER_COLOR.B, 1, function(color, alpha)
        PLAYER_COLOR = color
        COLORS.PLAYER = color
        SaveColors(COLORS)
        for _, drawings in pairs(EntityDrawings) do
            for _, drawing in pairs(drawings) do
                if drawing and drawing.Color then
                    drawing.Color = color
                end
            end
        end
        if MarkerDrawings.Line then MarkerDrawings.Line.Color = color end
        if MarkerDrawings.Label then MarkerDrawings.Label.Color = color end
    end)

    visualSection:Spacing()

    visualSection:Toggle("show_box", "Full Body Box", UI.GetValue("show_box") or false, function(state)
        Settings.ShowBox = state
    end)

    visualSection:Toggle("show_skeleton", "Skeleton", UI.GetValue("show_skeleton") or false, function(state)
        Settings.ShowSkeleton = state
    end)

    visualSection:Toggle("show_label", "Player Names", UI.GetValue("show_label") or false, function(state)
        Settings.ShowLabel = state
    end)

    visualSection:Toggle("show_distance", "Distance", UI.GetValue("show_distance") or false, function(state)
        Settings.ShowDistance = state
    end)

    visualSection:Toggle("show_saved_marker", "Saved Position Marker", UI.GetValue("show_saved_marker") or true, function(state)
        Settings.ShowSavedMarker = state
    end)

    visualSection:Spacing()

    local infoSection = tab:Section("Info", "Right")
    infoSection:Text("Teleport to your saved position.")
    infoSection:Text("See whos the real criminal.")
    infoSection:Spacing()
    infoSection:Tip("by og_ten")
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    local key = input.KeyCode
    
    if UI.GetValue("teleport_enabled") == true and TeleportKeybind then
        local boundKey = TeleportKeybind:GetKey()
        if boundKey >= 65 and boundKey <= 90 then
            boundKey = boundKey + 32
        end
        if key == boundKey then
            TeleportToSaved()
        end
    end
    
    if UI.GetValue("save_enabled") == true and SaveKeybind then
        local boundKey = SaveKeybind:GetKey()
        if boundKey >= 65 and boundKey <= 90 then
            boundKey = boundKey + 32
        end
        if key == boundKey then
            SavePosition()
        end
    end
end)

RunService.RenderStepped:Connect(function()
    UpdateSavedPositionMarker()
    
    if IsEnabled then
        RoundCheckTimer = RoundCheckTimer + 1/60
        if RoundCheckTimer >= ROUND_CHECK_INTERVAL then
            RoundCheckTimer = 0
            CheckRoundStatus()
        end
        
        if InRound and IsScanning then
            DisplayScannedPlayers()
            ScanTimer = ScanTimer + 1/60
            if ScanTimer >= SCAN_INTERVAL then
                ScanTimer = 0
                PerformFullScan()
            end
        elseif InRound and not IsScanning then
            IsScanning = true
            PerformFullScan()
        end
    end
end)

RunService.Heartbeat:Connect(function()
    if IsEnabled and InRound then
        local stillAlive = {}
        for _, player in ipairs(ScannedPlayers) do
            if player.Model and player.Model.Parent and player.Humanoid and player.Humanoid.Health > 0 then
                table.insert(stillAlive, player)
            end
        end

        if #stillAlive ~= #ScannedPlayers then
            ScannedPlayers = stillAlive
            UpdateDrawings(stillAlive)
        end
    end
end)

notify("NPC Or Die ESP Loaded", "NPC Or Die", 4)
