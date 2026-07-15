local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local COLORS = {
    PLAYER = Color3.fromRGB(255, 0, 0),
    MARKER = Color3.fromRGB(0, 255, 0)
}

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
UI.SetValue("show_saved_marker", false)

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

local MarkerDrawings = {
    Line = nil,
    Label = nil
}

local MOUSE_KEYS = {
    [0x01] = true,
    [0x02] = true,
    [0x04] = true,
    [0x05] = true,
    [0x06] = true,
}

local function CountTools(model)
    local count = 0
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("Tool") or child:IsA("Accessory") or child:IsA("Clothing") or 
           child:IsA("Shirt") or child:IsA("Pants") or child:IsA("Hat") or
           child:IsA("Part") or child:IsA("MeshPart") then
            count = count + 1
        end
    end
    return count
end

local function IsRealPlayer(model)
    local toolCount = CountTools(model)
    local hasNameTag = model:FindFirstChild("NameTag") ~= nil
    local hasAudioEmitter = model:FindFirstChild("AudioEmitter") ~= nil
    local hasTask = model:FindFirstChild("Task") ~= nil
    local hasAnimations = model:FindFirstChild("Animations") ~= nil

    local isPlayer = false

    if hasNameTag and toolCount >= 28 then
        if hasAudioEmitter then
            isPlayer = true
        elseif hasTask and hasAnimations then
            isPlayer = true
        end
    end

    return isPlayer, {
        Tools = toolCount,
        NameTag = hasNameTag,
        AudioEmitter = hasAudioEmitter,
        Task = hasTask,
        Animations = hasAnimations
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
    local found = {}

    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") then
            local humanoid = child:FindFirstChild("Humanoid")
            local head = child:FindFirstChild("Head")

            if humanoid and head and head:IsA("BasePart") then
                if child.Name ~= LocalPlayerName then
                    local isAlive = humanoid.Health > 0
                    local isPlayer, details = IsRealPlayer(child)

                    if isPlayer and isAlive then
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
    local color = COLORS.PLAYER

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
    UpdateDrawings(players)
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
    local color = COLORS.PLAYER

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
        if not character then
            return false
        end
        hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            return false
        end
    end
    
    if not hrp or not hrp.Parent then
        hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            return false
        end
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
    hrp.CFrame = CFrame.new(pos.X, pos.Y + 3, pos.Z)
    notify("Teleported to saved position!", "NPC Or Die", 3)
end

local function UpdateSavedPositionMarker()
    local camera = workspace.CurrentCamera
    if not camera then return end

    if not SavedPosition or not Settings.ShowSavedMarker then
        if MarkerDrawings.Line then
            MarkerDrawings.Line.Visible = false
        end
        if MarkerDrawings.Label then
            MarkerDrawings.Label.Visible = false
        end
        return
    end

    local headPos = SavedPosition + Vector3.new(0, 3, 0)
    local footPos = SavedPosition - Vector3.new(0, 3, 0)

    local headScreen, headOnScreen = WorldToScreen(headPos)
    local footScreen, footOnScreen = WorldToScreen(footPos)

    if not headOnScreen or not footOnScreen then
        if MarkerDrawings.Line then
            MarkerDrawings.Line.Visible = false
        end
        if MarkerDrawings.Label then
            MarkerDrawings.Label.Visible = false
        end
        return
    end

    if not MarkerDrawings.Line then
        local line = Drawing.new("Line")
        line.Color = COLORS.MARKER
        line.Thickness = 2
        line.Transparency = 1
        line.ZIndex = 1000
        MarkerDrawings.Line = line
    end

    if not MarkerDrawings.Label then
        local label = Drawing.new("Text")
        label.Font = Drawing.Fonts.UI
        label.Size = 14
        label.Color = COLORS.MARKER
        label.Outline = false
        label.Center = true
        label.ZIndex = 1000
        MarkerDrawings.Label = label
    end

    MarkerDrawings.Line.From = footScreen
    MarkerDrawings.Line.To = headScreen
    MarkerDrawings.Line.Visible = true

    MarkerDrawings.Label.Position = headScreen - Vector2.new(0, 20)
    MarkerDrawings.Label.Text = "SAVED POSITION"
    MarkerDrawings.Label.Visible = true
end

local function VKToEnum(vk)
    if vk >= 65 and vk <= 90 then
        return Enum.KeyCode[string.char(vk)]
    end
    local map = {
        [0x70] = Enum.KeyCode.F1, [0x71] = Enum.KeyCode.F2,
        [0x72] = Enum.KeyCode.F3, [0x73] = Enum.KeyCode.F4,
        [0x74] = Enum.KeyCode.F5, [0x75] = Enum.KeyCode.F6,
        [0x76] = Enum.KeyCode.F7, [0x77] = Enum.KeyCode.F8,
        [0x78] = Enum.KeyCode.F9, [0x79] = Enum.KeyCode.F10,
        [0x7A] = Enum.KeyCode.F11, [0x7B] = Enum.KeyCode.F12,
        [0x21] = Enum.KeyCode.PageUp, [0x22] = Enum.KeyCode.PageDown,
        [0x23] = Enum.KeyCode.End, [0x24] = Enum.KeyCode.Home,
        [0x25] = Enum.KeyCode.Left, [0x26] = Enum.KeyCode.Up,
        [0x27] = Enum.KeyCode.Right, [0x28] = Enum.KeyCode.Down,
        [0x2D] = Enum.KeyCode.Insert, [0x2E] = Enum.KeyCode.Delete,
    }
    return map[vk]
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
            PreviousPlayerCount = 0
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
        local vk = TeleportKeybind:GetKey()
        if not MOUSE_KEYS[vk] then
            local enumKey = VKToEnum(vk)
            if enumKey and key == enumKey then
                TeleportToSaved()
            end
        end
    end
    
    if UI.GetValue("save_enabled") == true and SaveKeybind then
        local vk = SaveKeybind:GetKey()
        if not MOUSE_KEYS[vk] then
            local enumKey = VKToEnum(vk)
            if enumKey and key == enumKey then
                SavePosition()
            end
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
