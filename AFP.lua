local shared = odh_shared_plugins
local combat_section = shared.AddSection("Autofarm+")

local trueAntiVoidConnection
local originalDestroyHeight = workspace.FallenPartsDestroyHeight

combat_section:AddToggle("Anti-Void", function(bool)
    if trueAntiVoidConnection then
        trueAntiVoidConnection:Disconnect()
        trueAntiVoidConnection = nil
    end
    
    if bool then
        workspace.FallenPartsDestroyHeight = 0/0
        
        trueAntiVoidConnection = player.CharacterAdded:Connect(function(char)
            task.wait(0.1)
            workspace.FallenPartsDestroyHeight = 0/0
        end)
    else
        workspace.FallenPartsDestroyHeight = originalDestroyHeight
    end
end)

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local vU = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Maid = {}
Maid.__index = Maid

function Maid.new()
    return setmetatable({_tasks = {}, _destroyed = false}, Maid)
end

function Maid:GiveTask(task)
    if self._destroyed then self:_cleanupTask(task) return end
    table.insert(self._tasks, task)
    return task
end

function Maid:GiveTasks(...)
    for _, t in ipairs({...}) do self:GiveTask(t) end
end

function Maid:_cleanupTask(task)
    local t = typeof(task)
    if t == "RBXScriptConnection" then task:Disconnect()
    elseif t == "Instance" then task:Destroy()
    elseif t == "function" then task()
    elseif t == "table" and type(task.Destroy) == "function" then task:Destroy()
    end
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
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end
end

local function setNoclip(state)
    noclipEnabled = state
    if not state then
        restoreCollision()
    else
        applyNoclipNow()
    end
end

local noclipSteppedConn = RunService.Stepped:Connect(function()
    if not noclipEnabled then return end
    local character = player.Character
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            part.CanCollide = false
        end
    end
end)
RootMaid:GiveTask(noclipSteppedConn)

local roleCache = {
    data      = nil,
    timestamp = 0,
    TTL       = 0.8,
}

local function getCachedRoleData()
    local now = tick()
    if roleCache.data and (now - roleCache.timestamp) < roleCache.TTL then
        return roleCache.data
    end
    local ok, result = pcall(function()
        local remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
        if remote and remote:IsA("RemoteFunction") then
            return remote:InvokeServer()
        end
    end)
    if ok and result then
        roleCache.data      = result
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
local autoShootMurdEnabled = false
local autoResetMurdEnabled = false
local autoResetSheriffEnabled = false
local resetAllEnabled = false
local antiAfkEnabled = false
local noRenderEnabled = false
local autoGGEnabled = false

local afkConnection
local isResetting = false
local currentResetConnection = nil

local sheriffFlingMaid = nil
local resetAllMaid = nil
local autoGGMaid = Maid.new()
RootMaid:GiveTask(autoGGMaid)

local maxFlingAttempts = 3
local resetAllState = "waiting"
local hasFlingedMurdererThisLife = false

local blackScreenGui = nil
local blackScreenFrame = nil
local NoRenderColor = Color3.fromRGB(0,0,0)

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
    if noRenderEnabled then
        task.wait(0.5)
        RunService:Set3dRenderingEnabled(false)
        CreateBlackScreen()
    end
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

local function getMurd()
    local roleData = getCachedRoleData()
    if roleData then
        for playerName, data in pairs(roleData) do
            if data.Role == "Murderer" and not data.Killed and not data.Dead then
                local p = Players:FindFirstChild(playerName)
                if p and p ~= player then return p end
            end
        end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then
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
                if p and p ~= player then return p end
            end
        end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then
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

local function hasKnife()
    local char = player.Character
    local bp = player:FindFirstChild("Backpack")
    return (char and char:FindFirstChild("Knife")) or (bp and bp:FindFirstChild("Knife"))
end

local function touch(a, b)
    pcall(function()
        firetouchinterest(a, b, 0)
        firetouchinterest(a, b, 1)
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
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = true end
    end
end

local function resetPlayer(TargetPlayer)
    if not TargetPlayer then return end
    if isResetting then return end

    local Character = player.Character
    if not Character then return end
    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    local RootPart = Humanoid and Humanoid.RootPart
    local TCharacter = TargetPlayer.Character
    if not (Character and Humanoid and RootPart and TCharacter) then return end

    local TRootPart = TCharacter:FindFirstChild("HumanoidRootPart")
    local THead = TCharacter:FindFirstChild("Head")
    if not TRootPart then return end

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

    local originalDestroyHeight = Workspace.FallenPartsDestroyHeight
    Workspace.FallenPartsDestroyHeight = -100000

    local startTime = tick()
    local resetDuration = 1.5

    currentResetConnection = RunService.Heartbeat:Connect(function()
        if tick() - startTime > resetDuration or not TargetPlayer.Character or not TRootPart.Parent then
            Workspace.FallenPartsDestroyHeight = originalDestroyHeight
            bv:Destroy()
            bg:Destroy()
            fullyRestoreCharacter(Character, savedData)
            if currentResetConnection then
                currentResetConnection:Disconnect()
                currentResetConnection = nil
            end
            isResetting = false
            return
        end

        if TRootPart and TRootPart.Parent and Character and Character.Parent then
            local headPos = THead and THead.Position or (TRootPart.Position + Vector3.new(0, 2.5, 0))
            RootPart.CFrame = CFrame.new(headPos)
            RootPart.AssemblyLinearVelocity = Vector3.new(0, -50000, 0)
            RootPart.AssemblyAngularVelocity = Vector3.new(7500, 7500, 7500)

            for i = 1, 5 do
                touch(RootPart, TRootPart)
                if THead then touch(RootPart, THead) end
            end
            pcall(sethiddenproperty, RootPart, "PhysicsRepRootPart", TRootPart)
        end
    end)
end

local function killAll()
    local character = player.Character
    if not character then return end
    local knife = character:FindFirstChild("Knife") or (player.Backpack and player.Backpack:FindFirstChild("Knife"))
    if not knife then return end
    local events = knife:FindFirstChild("Events")
    if not events then return end
    local handleTouched = events:FindFirstChild("HandleTouched")
    if not handleTouched then return end

    local targets = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local upperTorso = p.Character:FindFirstChild("UpperTorso")
            if upperTorso then table.insert(targets, upperTorso) end
        end
    end

    for i = 1, 3 do
        for _, upperTorso in ipairs(targets) do
            handleTouched:FireServer(upperTorso)
        end
        if i < 3 then task.wait(1) end
    end
end

local function killAllExceptOne()
    local character = player.Character
    if not character then return end
    local knife = character:FindFirstChild("Knife") or (player.Backpack and player.Backpack:FindFirstChild("Knife"))
    if not knife then return end
    local events = knife:FindFirstChild("Events")
    if not events then return end
    local handleTouched = events:FindFirstChild("HandleTouched")
    if not handleTouched then return end

    local targets = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local upperTorso = p.Character:FindFirstChild("UpperTorso")
            if upperTorso then table.insert(targets, upperTorso) end
        end
    end

    if #targets == 0 then return end

    local survivorIndex = math.random(1, #targets)
    local survivor = targets[survivorIndex]
    local killTargets = {}
    for i, target in ipairs(targets) do
        if target ~= survivor then
            table.insert(killTargets, target)
        end
    end

    if #killTargets == 0 then return end

    for _, upperTorso in ipairs(killTargets) do
        handleTouched:FireServer(upperTorso)
        task.wait(0.1)
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

local function shootMurd()
    if not equipGun() then return end
    task.wait(0.2)
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    vU:Button1Down(center, Camera.CFrame)
    task.wait(0.1)
    vU:Button1Up(center, Camera.CFrame)
end

local function startShootingMurderer()
    task.spawn(function()
        local attempts = 0
        while not hasGun() and attempts < 20 do
            task.wait(0.1)
            attempts = attempts + 1
        end
        if not hasGun() then return end

        local murd = getMurd()
        if not murd or not murd.Character then return end

        for i = 1, 12 do
            if not hasGun() then break end
            local currentMurd = getMurd()
            if not currentMurd or not currentMurd.Character then break end
            local humanoid = currentMurd.Character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health <= 0 then break end
            shootMurd()
            task.wait(3)
        end
    end)
end

local function executeResetAll()
    local role = getMyRole() or getRole()

    if role == "Murderer" then
        killAllExceptOne()
    else
        local murderer = getMurd()
        if not murderer then return end

        local targets = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player and p ~= murderer then
                table.insert(targets, p)
            end
        end

        for _, p in ipairs(targets) do
            resetPlayer(p)
            while isResetting do
                task.wait()
            end
            task.wait(0.2)
        end
    end
end

local function startResetAllMonitor()
    if resetAllMaid then resetAllMaid:Destroy() end
    resetAllMaid = Maid.new()
    resetAllState = "waiting"

    local thread = task.spawn(function()
        while resetAllEnabled do
            local role = getMyRole() or getRole()

            if resetAllState == "waiting" then
                local shouldRun = false

                if role == "Murderer" then
                    if hasKnife() then
                        shouldRun = true
                    end
                else
                    if getMurd() then
                        shouldRun = true
                    end
                end

                if shouldRun then
                    executeResetAll()
                    resetAllState = "done"
                end
            elseif resetAllState == "done" then
                if role == "Murderer" then
                    if not hasKnife() then
                        resetAllState = "waiting"
                    end
                else
                    if not getMurd() then
                        resetAllState = "waiting"
                    end
                end
            end

            task.wait(0.5)
        end
    end)
    resetAllMaid:GiveTask(function() task.cancel(thread) end)
end

local function stopResetAllMonitor()
    if resetAllMaid then
        resetAllMaid:Destroy()
        resetAllMaid = nil
    end
    resetAllState = "waiting"
end

local function toggleResetAll(enabled)
    resetAllEnabled = enabled
    if enabled then
        startResetAllMonitor()
    else
        stopResetAllMonitor()
    end
    updateNoclip()
end

local function updateNoclip()
    setNoclip(autoResetSheriffEnabled or autoResetMurdEnabled or resetAllEnabled)
end

local function startSheriffFling()
    if sheriffFlingMaid then sheriffFlingMaid:Destroy() end
    sheriffFlingMaid = Maid.new()
    local thread = task.spawn(function()
        local attempts = 0
        while autoResetSheriffEnabled do
            if attempts >= maxFlingAttempts then
                autoResetSheriffEnabled = false
                shared.Notify("Sheriff Fling", "Max attempts reached (" .. maxFlingAttempts .. ")", 3)
                break
            end
            pcall(function()
                local target = getSheriff()
                if target and target ~= player then
                    resetPlayer(target)
                    attempts = attempts + 1
                end
            end)
            task.wait(0.4)
        end
        if sheriffFlingMaid then
            sheriffFlingMaid:Destroy()
            sheriffFlingMaid = nil
        end
        updateNoclip()
    end)
    sheriffFlingMaid:GiveTask(function() task.cancel(thread) end)
end

local function stopSheriffFling()
    if sheriffFlingMaid then
        sheriffFlingMaid:Destroy()
        sheriffFlingMaid = nil
    end
end

local function flingMurdererOnRespawn()
    if not autoResetMurdEnabled then return end
    if hasFlingedMurdererThisLife then return end

    local role = getMyRole() or getRole()
    if role == "Murderer" then return end

    if autoShootMurdEnabled and hasGun() then
        return
    end

    local murd = getMurd()
    if murd then
        resetPlayer(murd)
        hasFlingedMurdererThisLife = true
    end
end

player.CharacterAdded:Connect(function()
    hasFlingedMurdererThisLife = false
    task.wait(1.5)
    flingMurdererOnRespawn()
end)

task.spawn(function()
    local CoinCollected = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Gameplay"):WaitForChild("CoinCollected")
    CoinCollected.OnClientEvent:Connect(function(_, currentCoins, maxCoins)
        if currentCoins < maxCoins then return end

        local role = getMyRole() or getRole()

        if role == "Murderer" and autoKillAllEnabled then
            task.spawn(killAll)
            return
        end

        if hasGun() and autoShootMurdEnabled then
            task.spawn(startShootingMurderer)
            return
        end

        if role ~= "Murderer" and autoResetMurdEnabled then
            if not (autoShootMurdEnabled and hasGun()) then
                task.spawn(function()
                    local target = getMurd()
                    if target then resetPlayer(target) end
                end)
            end
        end
    end)
end)

combat_section:AddToggle("Disable 3D Rendering", function(v)
    SetNoRenderState(v)
end)

combat_section:AddToggle("Auto-Kill All", function(v)
    autoKillAllEnabled = v
end)

combat_section:AddToggle("Auto-Shoot Murd", function(v)
    autoShootMurdEnabled = v
end)

combat_section:AddToggle("Auto-Reset Murderer", function(v)
    autoResetMurdEnabled = v
    updateNoclip()
    if v and player.Character and not hasFlingedMurdererThisLife then
        task.spawn(flingMurdererOnRespawn)
    end
end)

combat_section:AddToggle("Auto-Reset Sheriff", function(v)
    autoResetSheriffEnabled = v
    if v then
        startSheriffFling()
    else
        stopSheriffFling()
    end
    updateNoclip()
end)

combat_section:AddToggle("Auto-Reset All", function(v)
    toggleResetAll(v)
end)

combat_section:AddSlider("Max Fling Attempts", 1, 20, 3, function(value)
    maxFlingAttempts = value
end)

local function findGunDropPart()
    local gunDrop = workspace:FindFirstChild("GunDrop", true)
    if gunDrop and gunDrop:IsA("BasePart") then
        return gunDrop
    end
    return nil
end

local function bringGun()
    local character = player.Character
    if not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    local gunDrop = findGunDropPart()
    if gunDrop then
        touch(rootPart, gunDrop)
    end
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

combat_section:AddToggle("Anti-AFK", function(v)
    antiAfkEnabled = v
    if afkConnection then
        afkConnection:Disconnect()
        afkConnection = nil
    end
    if v then
        afkConnection = player.Idled:Connect(function()
            vU:CaptureController()
            vU:ClickButton2(Vector2.new())
        end)
    end
end)

if antiAfkEnabled then
    player.Idled:Connect(function()
        vU:CaptureController()
        vU:ClickButton2(Vector2.new())
    end)
end

RootMaid:GiveTask(function()
    CleanupNoRender()
    if afkConnection then afkConnection:Disconnect() end
    if currentResetConnection then currentResetConnection:Disconnect() end
    if sheriffFlingMaid then sheriffFlingMaid:Destroy() end
    if resetAllMaid then resetAllMaid:Destroy() end
    autoGGMaid:DoCleaning()
    setNoclip(false)
    if trueAntiVoidConnection then trueAntiVoidConnection:Disconnect() end
    workspace.FallenPartsDestroyHeight = originalDestroyHeight
end)

shared.Notify("Autofarm+ loaded successfully!", 3)
