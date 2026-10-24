local shared = odh_shared_plugins
task.spawn(function()
    shared.load_from_github_url("/aux0on/CrashHandler/refs/heads/main/Prevention.lua")
end)

if shared.game_name ~= "Murder Mystery 2" then return end
local afp = shared.CreateTab("Autofarm+", "/aux0on/AFPIcon/refs/heads/main/Untitled163_20260919023714")
local combat_section = afp:AddSection("Autofarm+")
local whitelist = {}

local Players = game:GetService("Players")
while not Players.LocalPlayer do task.wait() end
local player = Players.LocalPlayer

local trueAntiVoidConnection
local originalDestroyHeight = workspace.FallenPartsDestroyHeight

local function setupAntiVoid()
    if not player then return end
    if trueAntiVoidConnection then
        trueAntiVoidConnection:Disconnect()
        trueAntiVoidConnection = nil
    end
    workspace.FallenPartsDestroyHeight = 0/0
    trueAntiVoidConnection = player.CharacterAdded:Connect(function()
        task.wait(0.1)
        workspace.FallenPartsDestroyHeight = 0/0
    end)
end

local Camera = workspace.CurrentCamera
local vU = game:GetService("VirtualUser")
local VIM = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({_tasks = {}, _destroyed = false}, Maid) end
function Maid:GiveTask(task)
    if self._destroyed then self:_cleanupTask(task) return end
    table.insert(self._tasks, task)
    return task
end
function Maid:GiveTasks(...) for _, t in ipairs({...}) do self:GiveTask(t) end end
function Maid:_cleanupTask(task)
    local t = typeof(task)
    if t == "RBXScriptConnection" then task:Disconnect()
    elseif t == "Instance" then task:Destroy()
    elseif t == "function" then task()
    elseif t == "table" and type(task.Destroy) == "function" then task:Destroy() end
end
function Maid:DoCleaning()
    if self._destroyed then return end
    self._destroyed = true
    for _, task in ipairs(self._tasks) do self:_cleanupTask(task) end
    self._tasks = {}
end
function Maid:Destroy() self:DoCleaning() end

local RootMaid = Maid.new()

local noclipEnabled = false
local function restoreCollision()
    local character = player.Character
    if character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
    end
end
local function applyNoclipNow()
    local character = player.Character
    if character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end
end
local function setNoclip(state)
    noclipEnabled = state
    if not state then restoreCollision() else applyNoclipNow() end
end
local noclipSteppedConn = RunService.Stepped:Connect(function()
    if not noclipEnabled then return end
    local character = player.Character
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
    end
end)
RootMaid:GiveTask(noclipSteppedConn)

local roleCache = { data = nil, timestamp = 0, TTL = 0.8 }
local function getCachedRoleData()
    local now = tick()
    if roleCache.data and (now - roleCache.timestamp) < roleCache.TTL then return roleCache.data end
    local ok, result = pcall(function()
        local remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
        if remote and remote:IsA("RemoteFunction") then return remote:InvokeServer() end
    end)
    if ok and result then
        roleCache.data = result
        roleCache.timestamp = now
        return result
    end
    roleCache.timestamp = now
    return roleCache.data
end
local function getMyRole()
    local roleData = getCachedRoleData()
    if not roleData then return nil end
    local data = roleData[player.Name]
    if data then return data.Role end
    return nil
end

local autoKillAllEnabled = false
local assassinModeEnabled = false
local autoShootMurdEnabled = false
local autoResetMurdEnabled = false
local autoResetSheriffEnabled = false
local resetAllEnabled = false
local noRenderEnabled = false
local autoGGEnabled = false

local afkConnection
local isResetting = false
local currentResetConnection = nil
local sheriffFlingMaid = nil
local resetAllMaid = nil
local autoGGMaid = Maid.new()
RootMaid:GiveTask(autoGGMaid)

local hasFlingedMurdererThisLife = false
local hasExecutedThisLife = false
local leftOneThisRound = false          -- set true only after we successfully left 1 alive
local finalKillDoneThisRound = false    -- prevent double final kills

local blackScreenGui = nil
local blackScreenFrame = nil
local shootLoopThread = nil

local function CreateBlackScreen()
    if blackScreenGui then return end
    blackScreenGui = Instance.new("ScreenGui")
    blackScreenGui.Name = "NoRenderBackground"
    blackScreenGui.DisplayOrder = -99999
    blackScreenGui.IgnoreGuiInset = true
    blackScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    blackScreenGui.ResetOnSpawn = false
    blackScreenFrame = Instance.new("Frame")
    blackScreenFrame.Size = UDim2.new(1, 0, 1, 0)
    blackScreenFrame.BackgroundColor3 = Color3.fromRGB(0,0,0)
    blackScreenFrame.BorderSizePixel = 0
    blackScreenFrame.Parent = blackScreenGui
    blackScreenGui.Parent = player:WaitForChild("PlayerGui")
end
local function RemoveBlackScreen()
    if blackScreenGui then
        blackScreenGui:Destroy()
        blackScreenGui = nil
        blackScreenFrame = nil
    end
end
local function ToggleNoRender()
    noRenderEnabled = not noRenderEnabled
    RunService:Set3dRenderingEnabled(not noRenderEnabled)
    if noRenderEnabled then CreateBlackScreen() else RemoveBlackScreen() end
end
local function SetNoRenderState(state)
    if state == noRenderEnabled then return end
    ToggleNoRender()
end
local function CleanupNoRender()
    if noRenderEnabled then
        RunService:Set3dRenderingEnabled(true)
        RemoveBlackScreen()
        noRenderEnabled = false
    end
end

player.CharacterAdded:Connect(function()
    hasExecutedThisLife = false
    hasFlingedMurdererThisLife = false
    if noRenderEnabled then
        task.wait(0.5)
        RunService:Set3dRenderingEnabled(false)
        CreateBlackScreen()
    end
    if shootLoopThread then
        task.cancel(shootLoopThread)
        shootLoopThread = nil
    end
    task.wait(1.5)
    if flingMurdererOnRespawn then flingMurdererOnRespawn() end
end)

local function getRole()
    local bp = player:FindFirstChild("Backpack")
    local char = player.Character
    if bp and (bp:FindFirstChild("Knife") or (char and char:FindFirstChild("Knife"))) then
        return "Murderer"
    elseif bp and (bp:FindFirstChild("Gun") or (char and char:FindFirstChild("Gun"))) then
        return "Sheriff"
    end
    return "Innocent"
end

local function isWhitelisted(p)
    if typeof(p) == "Instance" and p:IsA("Player") then
        return table.find(whitelist, p.UserId) ~= nil
    elseif type(p) == "string" then
        local plr = Players:FindFirstChild(p)
        return plr and table.find(whitelist, plr.UserId) ~= nil
    end
    return false
end

local function getKillPart(character)
    if not character then return nil end
    return character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("HumanoidRootPart")
end

local function getMurd()
    local roleData = getCachedRoleData()
    if roleData then
        for playerName, data in pairs(roleData) do
            if data.Role == "Murderer" and not data.Killed and not data.Dead then
                local p = Players:FindFirstChild(playerName)
                if p and p ~= player and not isWhitelisted(p) then return p end
            end
        end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and not isWhitelisted(plr) then
            local bp = plr:FindFirstChild("Backpack")
            local char = plr.Character
            if (bp and bp:FindFirstChild("Knife")) or (char and char:FindFirstChild("Knife")) then
                return plr
            end
        end
    end
    return nil
end

local function getSheriff()
    local roleData = getCachedRoleData()
    if roleData then
        for playerName, data in pairs(roleData) do
            if data.Role == "Sheriff" and not data.Killed and not data.Dead then
                local p = Players:FindFirstChild(playerName)
                if p and p ~= player and not isWhitelisted(p) then return p end
            end
        end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and not isWhitelisted(plr) then
            local bp = plr:FindFirstChild("Backpack")
            local char = plr.Character
            if (bp and bp:FindFirstChild("Gun")) or (char and char:FindFirstChild("Gun")) then
                return plr
            end
        end
    end
    return nil
end

local function getGun()
    local char = player.Character
    if char and char:FindFirstChild("Gun") then return char.Gun end
    local bp = player:FindFirstChild("Backpack")
    if bp and bp:FindFirstChild("Gun") then return bp.Gun end
end
local function hasGun()
    local char = player.Character
    local bp = player:FindFirstChild("Backpack")
    return (char and char:FindFirstChild("Gun")) or (bp and bp:FindFirstChild("Gun"))
end

local function getKnife()
    local char = player.Character
    if char then
        local k = char:FindFirstChild("Knife")
        if k then return k end
    end
    local bp = player:FindFirstChild("Backpack")
    if bp then
        local k = bp:FindFirstChild("Knife")
        if k then return k end
    end
    return nil
end
local function hasKnife()
    return getKnife() ~= nil
end

local function getCurrentTargetName()
    local pGui = player:FindFirstChild("PlayerGui")
    if not pGui then return nil end
    local mainGui = pGui:FindFirstChild("MainGUI")
    if not mainGui then return nil end
    local gameFrame = mainGui:FindFirstChild("Game")
    if not gameFrame then return nil end
    local assassinTarget = gameFrame:FindFirstChild("AssassinTarget")
    if not assassinTarget then return nil end
    local targetNameObj = assassinTarget:FindFirstChild("TargetName")
    if targetNameObj and (targetNameObj:IsA("TextLabel") or targetNameObj:IsA("TextBox")) then
        local text = targetNameObj.Text
        if text and text ~= "" and text ~= "Nikilis" then
            return text
        end
    end
    return nil
end

local function killTargetByName(targetName)
    if not targetName or targetName == "" or targetName == "Nikilis" then return false end
    if isWhitelisted(targetName) then return "WHITELISTED" end

    local knife = getKnife()
    if not knife then return false end
    local events = knife:FindFirstChild("Events")
    if not events then return false end
    local handleTouched = events:FindFirstChild("HandleTouched")
    if not handleTouched then return false end

    local targetPlayer = Players:FindFirstChild(targetName)
    if targetPlayer and targetPlayer.Character then
        local part = getKillPart(targetPlayer.Character)
        local humanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
        if part and humanoid and humanoid.Health > 0 then
            handleTouched:FireServer(part)
            return true
        end
    end
    return false
end

local function getLivingPlayerCount()
    local count = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character and not isWhitelisted(p) then
            local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                count = count + 1
            end
        end
    end
    return count
end

-- CORE: leave exactly one other player alive. Never touches the last one.
local function leaveExactlyOne()
    local knife = getKnife()
    if not knife then return false end
    local events = knife:FindFirstChild("Events")
    if not events then return false end
    local handleTouched = events:FindFirstChild("HandleTouched")
    if not handleTouched then return false end

    local living = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character and not isWhitelisted(p) then
            local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
            local part = getKillPart(p.Character)
            if humanoid and humanoid.Health > 0 and part then
                table.insert(living, {player = p, part = part, name = p.Name})
            end
        end
    end

    if #living <= 1 then
        return #living == 1 -- already only one (or zero)
    end

    -- pick one random survivor and never touch them
    local survivorIndex = math.random(1, #living)
    local survivor = living[survivorIndex]

    for i, entry in ipairs(living) do
        if entry.part ~= survivor.part then
            handleTouched:FireServer(entry.part)
            task.wait(0.04)
            handleTouched:FireServer(entry.part)
            task.wait(0.10)
        end
    end

    -- wait for deaths to register, then confirm
    task.wait(0.6)
    return getLivingPlayerCount() <= 1
end

-- Assassin path also forced to stop at 1
local function executeAssassinSequence()
    local knife = getKnife()
    if not knife then return end
    task.wait(0.5)

    while autoKillAllEnabled and assassinModeEnabled and player.Character do
        local living = getLivingPlayerCount()
        if living <= 1 then
            break -- hard stop
        end

        local targetName = getCurrentTargetName()
        if targetName then
            local result = killTargetByName(targetName)
            if result == "WHITELISTED" then
                shared.Notify("Target whitelisted — stopped", 2)
                break
            elseif result == true then
                task.wait(0.55)
                if getLivingPlayerCount() <= 1 then break end
            else
                task.wait(0.12)
            end
        else
            task.wait(0.12)
        end
    end
end

local function touch(a, b)
    pcall(function()
        firetouchinterest(a, b, 0)
        firetouchinterest(a, b, 1)
    end)
end

local function setRootReference(root, target)
    pcall(function()
        sethiddenproperty(root, "PhysicsRepRootRef", InstanceHandle.new(target))
        sethiddenproperty(root, "PhysicsRepRootPart", target)
    end)
end
local function clearRootReference(root)
    pcall(function()
        sethiddenproperty(root, "PhysicsRepRootRef", nil)
        sethiddenproperty(root, "PhysicsRepRootPart", nil)
    end)
end
local function fullyRestoreCharacter(character, savedData)
    if not character or not savedData then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then return end
    humanoid.PlatformStand = false
    for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do track:Stop() end
    rootPart.AssemblyLinearVelocity = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero
    rootPart.Velocity = Vector3.zero
    rootPart.RotVelocity = Vector3.zero
    rootPart.CFrame = savedData.cframe
    clearRootReference(rootPart)
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = true end
    end
end

local function resetPlayer(TargetPlayer, attempts)
    if not TargetPlayer or not TargetPlayer.Parent then return end
    local maxAttempts = attempts or 3
    local currentAttempt = 1
    while currentAttempt <= maxAttempts and TargetPlayer.Parent do
        local tChar = TargetPlayer.Character
        local tHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
        if tHum and tHum.Health <= 0 then break end

        local Character = player.Character
        if not Character then break end
        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        local RootPart = Humanoid and Humanoid.RootPart
        if not (Character and Humanoid and RootPart and tChar) then break end

        local TRootPart = tChar:FindFirstChild("HumanoidRootPart")
        local THead = tChar:FindFirstChild("Head")
        if not TRootPart then break end

        isResetting = true
        local savedData = { cframe = RootPart.CFrame }
        Humanoid.PlatformStand = true

        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.Velocity = Vector3.new(0, -50000, 0)
        bv.Parent = RootPart

        local bg = Instance.new("BodyGyro")
        bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        bg.P = 1000000
        bg.Parent = RootPart

        Workspace.FallenPartsDestroyHeight = 0/0
        local startTime = tick()
        local resetDuration = 1.0
        local completed = false
        local conn
        conn = RunService.Heartbeat:Connect(function()
            if tick() - startTime > resetDuration or not TargetPlayer.Character or not TRootPart.Parent then
                Workspace.FallenPartsDestroyHeight = originalDestroyHeight
                bv:Destroy()
                bg:Destroy()
                clearRootReference(RootPart)
                fullyRestoreCharacter(Character, savedData)
                if conn then conn:Disconnect() end
                completed = true
                return
            end
            if TRootPart and TRootPart.Parent and Character and Character.Parent then
                local headPos = THead and THead.Position or (TRootPart.Position + Vector3.new(0, 2.5, 0))
                RootPart.CFrame = CFrame.new(headPos) * CFrame.Angles(math.pi / 2, 0, 0)
                RootPart.AssemblyLinearVelocity = Vector3.new(0, -50000, 0)
                RootPart.AssemblyAngularVelocity = Vector3.new(7500, 7500, 7500)
                for i = 1, 5 do
                    touch(RootPart, TRootPart)
                    if THead then touch(RootPart, THead) end
                end
                setRootReference(RootPart, TRootPart)
            end
        end)

        while not completed and TargetPlayer.Parent do task.wait(0.05) end
        if not completed then
            Workspace.FallenPartsDestroyHeight = originalDestroyHeight
            if bv.Parent then bv:Destroy() end
            if bg.Parent then bg:Destroy() end
            clearRootReference(RootPart)
            fullyRestoreCharacter(Character, savedData)
            if conn then conn:Disconnect() end
        end
        isResetting = false
        task.wait(0.15)
        local postHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
        if not postHum or postHum.Health <= 0 then break end
        currentAttempt = currentAttempt + 1
    end
end

local function killAll()
    local knife = getKnife()
    if not knife then return end
    local events = knife:FindFirstChild("Events")
    if not events then return end
    local handleTouched = events:FindFirstChild("HandleTouched")
    if not handleTouched then return end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character and not isWhitelisted(p) then
            local part = getKillPart(p.Character)
            local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
            if part and humanoid and humanoid.Health > 0 then
                handleTouched:FireServer(part)
            end
        end
    end
end

local function equipGun()
    local gun = getGun()
    if not gun then return false end
    if gun.Parent == player.Character then return true end
    if gun.Parent == player.Backpack then
        local char = player.Character
        if char then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:EquipTool(gun)
                for _ = 1, 10 do
                    task.wait(0.1)
                    if gun.Parent == char then return true end
                end
            end
        end
    end
    return false
end
local function unequipGun()
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local gun = getGun()
    if gun and gun.Parent == char then
        local backpack = player:FindFirstChild("Backpack")
        if backpack then gun.Parent = backpack end
    end
end
local function shootMurd()
    if not equipGun() then return end
    task.wait(0.2)
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
    if isMobile then
        vU:Button1Down(center, Camera.CFrame)
        task.wait(0.1)
        vU:Button1Up(center, Camera.CFrame)
    else
        VIM:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
        task.wait(0.1)
        VIM:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
    end
end
local function startShootingMurderer()
    if shootLoopThread then
        task.cancel(shootLoopThread)
        shootLoopThread = nil
    end
    shootLoopThread = task.spawn(function()
        while true do
            if not hasGun() then break end
            local murd = getMurd()
            if not murd or not murd.Character then break end
            local humanoid = murd.Character:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then break end
            shootMurd()
            task.wait(0.5)
        end
        unequipGun()
        shootLoopThread = nil
    end)
end

-------------------------------------------------
-- ROUND START: leave exactly one other player
-------------------------------------------------
task.spawn(function()
    local executedThisRound = false
    while true do
        task.wait(0.25)
        if autoKillAllEnabled then
            if hasKnife() then
                if not executedThisRound then
                    executedThisRound = true
                    leftOneThisRound = false
                    finalKillDoneThisRound = false

                    task.wait(1.35) -- let everyone spawn / roles settle

                    if getLivingPlayerCount() > 1 then
                        if assassinModeEnabled then
                            executeAssassinSequence()
                        else
                            leaveExactlyOne()
                        end
                    end

                    -- confirm we actually left one
                    task.wait(0.4)
                    if getLivingPlayerCount() <= 1 then
                        leftOneThisRound = true
                    end
                end
            else
                executedThisRound = false
                leftOneThisRound = false
                finalKillDoneThisRound = false
            end
        else
            executedThisRound = false
            leftOneThisRound = false
            finalKillDoneThisRound = false
        end
    end
end)

-------------------------------------------------
-- MAX COINS ONLY: kill the last remaining person
-------------------------------------------------
task.spawn(function()
    local CoinCollected = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Gameplay"):WaitForChild("CoinCollected")
    CoinCollected.OnClientEvent:Connect(function(_, currentCoins, maxCoins)
        if currentCoins < maxCoins then return end
        if not autoKillAllEnabled then return end
        if not hasKnife() then return end
        if finalKillDoneThisRound then return end

        -- hard gate: only allowed after we already left one
        if not leftOneThisRound then return end

        finalKillDoneThisRound = true

        task.spawn(function()
            local timeout = tick() + 12
            while tick() < timeout and not hasKnife() do
                task.wait(0.1)
            end
            if not hasKnife() then return end

            if assassinModeEnabled then
                local targetName = getCurrentTargetName()
                if targetName then
                    killTargetByName(targetName)
                    task.wait(0.4)
                end
                -- fallback wipe in case target name is stale
                if getLivingPlayerCount() > 0 then
                    killAll()
                end
            else
                for i = 1, 3 do
                    killAll()
                    if i < 3 then task.wait(2.0) end
                end
            end
        end)
    end)
end)

-- rest of the original toggles / systems (unchanged)
combat_section:AddToggle("Disable 3D Rendering", function(v)
    SetNoRenderState(v)
end)
combat_section:AddToggle("Auto-Kill All", function(v)
    autoKillAllEnabled = v
end)
combat_section:AddToggle("Assassin Mode", function(v)
    assassinModeEnabled = v
end)
combat_section:AddToggle("Auto-Shoot Murd", function(v)
    autoShootMurdEnabled = v
end)
combat_section:AddToggle("Auto-Reset Murderer", function(v)
    autoResetMurdEnabled = v
    if updateNoclip then updateNoclip() end
    if v and player.Character and not hasFlingedMurdererThisLife then
        task.spawn(function()
            if flingMurdererOnRespawn then flingMurdererOnRespawn() end
        end)
    end
end)
combat_section:AddToggle("Auto-Reset Sheriff", function(v)
    autoResetSheriffEnabled = v
    if v then
        if startSheriffFling then startSheriffFling() end
    else
        if stopSheriffFling then stopSheriffFling() end
    end
    if updateNoclip then updateNoclip() end
end)
combat_section:AddToggle("Auto-Reset All", function(v)
    if toggleResetAll then toggleResetAll(v) end
end)
combat_section:AddToggle("Coin Aura", function(v)
    if v then
        if startAura then startAura() end
    else
        if stopAura then stopAura() end
    end
end)
combat_section:AddSlider("Coin Aura Radius", 1, 8, 8, function(value)
    if auraData then auraData.radius = value end
end)

local function findGunDropPart()
    local gunDrop = workspace:FindFirstChild("GunDrop", true)
    if gunDrop and gunDrop:IsA("BasePart") then return gunDrop end
    return nil
end
local function bringGun()
    local character = player.Character
    if not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    local gunDrop = findGunDropPart()
    if gunDrop then touch(rootPart, gunDrop) end
end
local function grabGun()
    if not findGunDropPart() then return false end
    if hasGun() then return true end
    bringGun()
    task.wait(0.5)
    return hasGun()
end
combat_section:AddToggle("Auto-Grab Gun", function(enabled)
    autoGGEnabled = enabled
    autoGGMaid:DoCleaning()
    if enabled then
        task.spawn(function()
            while autoGGEnabled do
                if player.Character and findGunDropPart() and not hasGun() then
                    grabGun()
                end
                task.wait(0.5)
            end
        end)
    end
end)

combat_section:AddPlayerDropdown("Whitelist Player", function(p)
    if not table.find(whitelist, p.UserId) then
        table.insert(whitelist, p.UserId)
        shared.Notify(p.Name .. " whitelisted.", 2)
    end
end)
combat_section:AddButton("Clear Whitelist", function()
    whitelist = {}
    shared.Notify("Whitelist cleared.", 2)
end)

local function setupAntiAFK()
    if not player then return end
    if afkConnection then afkConnection:Disconnect() afkConnection = nil end
    afkConnection = player.Idled:Connect(function()
        vU:CaptureController()
        vU:ClickButton2(Vector2.new())
    end)
end

setupAntiVoid()
setupAntiAFK()

RootMaid:GiveTask(function()
    if trueAntiVoidConnection then
        trueAntiVoidConnection:Disconnect()
        trueAntiVoidConnection = nil
    end
    workspace.FallenPartsDestroyHeight = originalDestroyHeight
    if afkConnection then afkConnection:Disconnect() afkConnection = nil end
    if shootLoopThread then task.cancel(shootLoopThread) shootLoopThread = nil end
    if stopAura then stopAura() end
end)
RootMaid:GiveTask(function()
    CleanupNoRender()
    if currentResetConnection then currentResetConnection:Disconnect() end
    if sheriffFlingMaid then sheriffFlingMaid:Destroy() end
    if resetAllMaid then resetAllMaid:Destroy() end
    autoGGMaid:DoCleaning()
    setNoclip(false)
end)

shared.Notify("Autofarm+ — leave 1 alive at start, kill last only at max bag", 2)
