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
    trueAntiVoidConnection = player.CharacterAdded:Connect(function(char)
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
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local LogService = game:GetService("LogService")

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

local lastConsoleCFrame = nil
local shootPlatform = nil

local function parseCFrameFromMessage(msg)
    local nums = {}
    for numStr in msg:gmatch("[-+]?%d+%.?%d*") do
        local n = tonumber(numStr)
        if n then
            table.insert(nums, n)
        end
    end
    if #nums >= 12 then
        return CFrame.new(
            nums[1], nums[2], nums[3],
            nums[4], nums[5], nums[6],
            nums[7], nums[8], nums[9],
            nums[10], nums[11], nums[12]
        )
    elseif #nums >= 3 then
        return CFrame.new(nums[1], nums[2], nums[3])
    end
    return nil
end

local logConn = LogService.MessageOut:Connect(function(message)
    local parsed = parseCFrameFromMessage(message)
    if parsed and parsed.Position.Magnitude > 1 then
        lastConsoleCFrame = parsed
    end
end)
RootMaid:GiveTask(logConn)

local function removeShootPlatform()
    if shootPlatform then
        shootPlatform:Destroy()
        shootPlatform = nil
    end
end

local function createAndTeleportToShootPlatform()
    removeShootPlatform()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local baseCF = lastConsoleCFrame or root.CFrame
    local offsetCF = baseCF + Vector3.new(300, 0, 0)

    local part = Instance.new("Part")
    part.Name = "AutoShootPlatform"
    part.Size = Vector3.new(12, 1, 12)
    part.Anchored = true
    part.CanCollide = true
    part.Transparency = 0.5
    part.Material = Enum.Material.SmoothPlastic
    part.CFrame = offsetCF * CFrame.new(0, -3.5, 0)
    part.Parent = Workspace
    shootPlatform = part

    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    root.CFrame = offsetCF
end

local noclipEnabled = false
local noclipSteppedConn = nil

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
        if noclipSteppedConn then
            noclipSteppedConn:Disconnect()
            noclipSteppedConn = nil
        end
        restoreCollision()
    else
        applyNoclipNow()
        if not noclipSteppedConn then
            noclipSteppedConn = RunService.Stepped:Connect(function()
                if not noclipEnabled then return end
                local character = player.Character
                if not character then return end
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end)
        end
    end
end

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
local autoLeave1MurdEnabled = false
local noRenderEnabled = false
local autoGGEnabled = false
local coinAuraEnabled = false
local killWlUsersAtMaxEnabled = false

local afkConnection
local isResetting = false
local currentResetConnection = nil

local sheriffFlingMaid = nil
local resetAllMaid = nil
local autoLeave1MurdMaid = nil
local autoGGMaid = Maid.new()
RootMaid:GiveTask(autoGGMaid)

local resetAllState = "waiting"
local autoLeave1MurdState = "waiting"
local hasExecutedThisLife = false

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
    autoLeave1MurdState = "waiting"
    resetAllState = "waiting"
    removeShootPlatform()
    if noRenderEnabled then
        task.wait(0.5)
        RunService:Set3dRenderingEnabled(false)
        CreateBlackScreen()
    end
    if shootLoopThread then
        task.cancel(shootLoopThread)
        shootLoopThread = nil
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

local function isWhitelisted(p)
    return table.find(whitelist, p.UserId) ~= nil
end

local function getAnyMurd()
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

local function getMurd()
    local roleData = getCachedRoleData()
    if roleData then
        for playerName, data in pairs(roleData) do
            if data.Role == "Murderer" and not data.Killed and not data.Dead then
                local p = Players:FindFirstChild(playerName)
                if p and p ~= player and (killWlUsersAtMaxEnabled or not isWhitelisted(p)) then return p end
            end
        end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and (killWlUsersAtMaxEnabled or not isWhitelisted(plr)) then
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
    for currentAttempt = 1, maxAttempts do
        if not TargetPlayer.Parent then break end
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

        while not completed and TargetPlayer.Parent do
            task.wait(0.05)
        end

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
        if not postHum or postHum.Health <= 0 then
            break
        end
    end
end

local function killAll()
    local knife = getKnife()
    if not knife then return end
    local events = knife:FindFirstChild("Events")
    if not events then return end
    local handleTouched = events:FindFirstChild("HandleTouched")
    if not handleTouched then return end

    local targets = {}
    local pList = Players:GetPlayers()
    for _, p in ipairs(pList) do
        if p ~= player and p.Character then
            if killWlUsersAtMaxEnabled or not isWhitelisted(p) then
                local upperTorso = p.Character:FindFirstChild("UpperTorso")
                if upperTorso then table.insert(targets, upperTorso) end
            end
        end
    end

    for _, upperTorso in ipairs(targets) do
        handleTouched:FireServer(upperTorso)
    end
end

local function killAllExceptOne()
    local knife = getKnife()
    if not knife then return false end
    local events = knife:FindFirstChild("Events")
    if not events then return false end
    local handleTouched = events:FindFirstChild("HandleTouched")
    if not handleTouched then return false end

    local eligiblePlayers = {}
    local pList = Players:GetPlayers()
    for _, p in ipairs(pList) do
        if p ~= player and p.Character then
            if killWlUsersAtMaxEnabled or not isWhitelisted(p) then
                local upperTorso = p.Character:FindFirstChild("UpperTorso")
                if upperTorso then
                    table.insert(eligiblePlayers, {player = p, torso = upperTorso})
                end
            end
        end
    end

    if #eligiblePlayers < 1 then return false end

    local whitelistedEntry = nil
    if not killWlUsersAtMaxEnabled then
        for _, entry in ipairs(eligiblePlayers) do
            if isWhitelisted(entry.player) then
                whitelistedEntry = entry
                break
            end
        end
    end

    local survivor
    if whitelistedEntry then
        survivor = whitelistedEntry.torso
    else
        local survivorIndex = math.random(1, #eligiblePlayers)
        survivor = eligiblePlayers[survivorIndex].torso
    end

    for _, entry in ipairs(eligiblePlayers) do
        if entry.torso ~= survivor then
            handleTouched:FireServer(entry.torso)
            task.wait(0.05)
        end
    end
    return true
end

local function clickRectangularShootButton()
    local roots = {CoreGui}
    if gethui then
        pcall(function() table.insert(roots, gethui()) end)
    end
    local playerGui = player:FindFirstChild("PlayerGui")
    if playerGui then
        table.insert(roots, playerGui)
    end

    local clicked = false
    for _, root in ipairs(roots) do
        if clicked then break end
        pcall(function()
            for _, gui in ipairs(root:GetDescendants()) do
                if (gui:IsA("TextButton") or gui:IsA("ImageButton") or gui:IsA("TextLabel")) and gui.Visible then
                    local nameLower = gui.Name:lower()
                    local textLower = (gui:IsA("TextButton") or gui:IsA("TextLabel")) and gui.Text:lower() or ""
                    
                    if (textLower == "shoot" or textLower == "shoot murderer" or nameLower:find("shoot")) 
                        and not textLower:find("auto") 
                        and not textLower:find("piercer") then
                        
                        local targetBtn = gui
                        if gui:IsA("TextLabel") then
                            targetBtn = gui.Parent:FindFirstChildWhichIsA("GuiButton") or gui.Parent
                        end

                        if targetBtn and targetBtn.AbsoluteSize.X > 0 and targetBtn.AbsoluteSize.Y > 0 then
                            local inset = GuiService:GetGuiInset()
                            local tapX = targetBtn.AbsolutePosition.X + (targetBtn.AbsoluteSize.X / 2)
                            local tapY = targetBtn.AbsolutePosition.Y + (targetBtn.AbsoluteSize.Y / 2) + inset.Y

                            if targetBtn:IsA("GuiButton") and firesignal then
                                pcall(function() firesignal(targetBtn.MouseButton1Click) end)
                                pcall(function() firesignal(targetBtn.Activated) end)
                            end

                            VIM:SendMouseButtonEvent(tapX, tapY, 0, true, game, 0)
                            task.wait(0.05)
                            VIM:SendMouseButtonEvent(tapX, tapY, 0, false, game, 0)
                            clicked = true
                            break
                        end
                    end
                end
            end
        end)
    end
    return clicked
end

local function startShootingMurderer()
    if shootLoopThread then
        task.cancel(shootLoopThread)
        shootLoopThread = nil
    end
    shootLoopThread = task.spawn(function()
        while autoShootMurdEnabled do
            if not hasGun() then
                break
            end

            local murd = getMurd()
            if not murd or not murd.Character then
                break
            end

            local humanoid = murd.Character:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then
                break
            end

            clickRectangularShootButton()
            
            task.wait(3)
        end
        shootLoopThread = nil
    end)
end

local function executeResetAll()
    local role = getMyRole() or getRole()

    if role == "Murderer" or hasKnife() then
        if not hasExecutedThisLife then
            hasExecutedThisLife = true
            task.wait(1.0)
            killAllExceptOne()
        end
    else
        local murderer = getAnyMurd()
        local sheriff = getSheriff()

        if sheriff and sheriff ~= player and not isWhitelisted(sheriff) then
            local tChar = sheriff.Character
            local tHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
            if tHum and tHum.Health > 0 then
                resetPlayer(sheriff, 3)
                task.wait(0.2)
            end
        end

        local pList = Players:GetPlayers()
        for _, p in ipairs(pList) do
            if p ~= player and p ~= murderer and not isWhitelisted(p) then
                local tChar = p.Character
                local tHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
                if tHum and tHum.Health > 0 then
                    resetPlayer(p, 1)
                    task.wait(0.2)
                end
            end
        end
    end
end

local function updateNoclip()
    setNoclip(autoResetMurdEnabled or autoResetSheriffEnabled or resetAllEnabled)
end

local function startResetAllMonitor()
    if resetAllMaid then resetAllMaid:Destroy() end
    resetAllMaid = Maid.new()
    resetAllState = "waiting"

    local thread = task.spawn(function()
        while resetAllEnabled do
            updateNoclip()
            roleCache.data = nil
            roleCache.timestamp = 0
            local role = getMyRole() or getRole()

            if resetAllState == "waiting" then
                local shouldRun = false

                if role == "Murderer" or hasKnife() then
                    if not hasExecutedThisLife then
                        shouldRun = true
                    end
                else
                    if getAnyMurd() then
                        shouldRun = true
                    end
                end

                if shouldRun then
                    executeResetAll()
                    resetAllState = "done"
                end
            elseif resetAllState == "done" then
                if role == "Murderer" or hasKnife() then
                    if not hasKnife() then
                        resetAllState = "waiting"
                    end
                else
                    if not getAnyMurd() then
                        resetAllState = "waiting"
                    end
                end
            end

            task.wait(0.1)
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

local function startAutoLeave1MurdMonitor()
    if autoLeave1MurdMaid then autoLeave1MurdMaid:Destroy() end
    autoLeave1MurdMaid = Maid.new()
    autoLeave1MurdState = "waiting"

    local thread = task.spawn(function()
        while autoLeave1MurdEnabled do
            local isMurdRole = (getMyRole() == "Murderer") or (getRole() == "Murderer")

            if autoLeave1MurdState == "waiting" and isMurdRole and not hasExecutedThisLife then
                while autoLeave1MurdEnabled and isMurdRole and not hasKnife() do
                    task.wait(0.2)
                    isMurdRole = (getMyRole() == "Murderer") or (getRole() == "Murderer")
                end

                if autoLeave1MurdEnabled and hasKnife() and not hasExecutedThisLife then
                    hasExecutedThisLife = true
                    task.wait(0.5)
                    killAllExceptOne()
                    autoLeave1MurdState = "done"
                end
            elseif autoLeave1MurdState == "done" then
                if not hasKnife() then
                    autoLeave1MurdState = "waiting"
                end
            end

            task.wait(0.1)
        end
    end)
    autoLeave1MurdMaid:GiveTask(function() task.cancel(thread) end)
end

local function stopAutoLeave1MurdMonitor()
    if autoLeave1MurdMaid then
        autoLeave1MurdMaid:Destroy()
        autoLeave1MurdMaid = nil
    end
    autoLeave1MurdState = "waiting"
end

local function toggleAutoLeave1Murd(enabled)
    autoLeave1MurdEnabled = enabled
    if enabled then
        startAutoLeave1MurdMonitor()
    else
        stopAutoLeave1MurdMonitor()
    end
end

local function startSheriffFling()
    if sheriffFlingMaid then sheriffFlingMaid:Destroy() end
    sheriffFlingMaid = Maid.new()
    local thread = task.spawn(function()
        while autoResetSheriffEnabled do
            updateNoclip()
            local role = getMyRole() or getRole()
            if role ~= "Murderer" then
                local target = getSheriff()
                if target and target ~= player then
                    resetPlayer(target, 3)
                    while getSheriff() and autoResetSheriffEnabled and ((getMyRole() or getRole()) ~= "Murderer") do
                        task.wait(0.5)
                    end
                end
            end
            task.wait(0.3)
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
    updateNoclip()
end

local auraData = {
    enabled = false,
    thread = nil,
    radius = 8,
    activeThisLife = false,
}

local function getCoinContainers()
    local containers = {}
    local children = Workspace:GetChildren()
    for _, map in ipairs(children) do
        local container = map:FindFirstChild("CoinContainer")
        if container then
            table.insert(containers, container)
        end
    end
    return containers
end

local function getCoinParts(containers)
    local parts = {}
    for _, container in ipairs(containers) do
        local descendants = container:GetDescendants()
        for _, descendant in ipairs(descendants) do
            if descendant:IsA("BasePart") and descendant:FindFirstChild("TouchInterest") then
                table.insert(parts, descendant)
            end
        end
    end
    return parts
end

local function collectNearbyCoins()
    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local rootPos = rootPart.Position
    local containers = getCoinContainers()
    local coinParts = getCoinParts(containers)

    for _, part in ipairs(coinParts) do
        if (rootPos - part.Position).Magnitude <= auraData.radius then
            touch(rootPart, part)
        end
    end
end

local function startAura()
    auraData.enabled = true
    if auraData.thread then
        auraData.thread:Disconnect()
        auraData.thread = nil
    end
    auraData.thread = RunService.Heartbeat:Connect(collectNearbyCoins)
end

local function stopAura()
    auraData.enabled = false
    if auraData.thread then
        auraData.thread:Disconnect()
        auraData.thread = nil
    end
end

player.CharacterAdded:Connect(function()
    auraData.activeThisLife = false
end)

task.spawn(function()
    local CoinCollected = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Gameplay"):WaitForChild("CoinCollected")
    CoinCollected.OnClientEvent:Connect(function(_, currentCoins, maxCoins)
        if coinAuraEnabled and not auraData.activeThisLife and currentCoins >= 5 then
            auraData.activeThisLife = true
            startAura()
        end

        if currentCoins < maxCoins then return end

        local role = getMyRole() or getRole()

        if (role == "Murderer" or hasKnife()) and autoKillAllEnabled then
            task.spawn(function()
                local timeout = tick() + 15
                while tick() < timeout and not hasKnife() do
                    task.wait(0.1)
                end
                if hasKnife() then
                    for i = 1, 3 do
                        killAll()
                        if i < 3 then
                            task.wait(2.5)
                        end
                    end
                end
            end)
            return
        end

        if autoShootMurdEnabled then
            task.spawn(function()
                local currentLifeChar = player.Character
                task.wait(0.5)
                if player.Character == currentLifeChar and autoShootMurdEnabled then
                    createAndTeleportToShootPlatform()
                end
                
                -- Directly check loop instead of blocking indefinitely
                local timeoutTick = tick() + 10
                while player.Character == currentLifeChar and not hasGun() and autoShootMurdEnabled and tick() < timeoutTick do
                    task.wait(0.2)
                end
                
                if player.Character == currentLifeChar and hasGun() then
                    startShootingMurderer()
                elseif autoResetMurdEnabled then
                    local target = getMurd()
                    if target then resetPlayer(target, 3) end
                end
            end)
        end

        if role ~= "Murderer" and not hasKnife() and autoResetMurdEnabled and not autoShootMurdEnabled then
            task.spawn(function()
                task.wait(0.5)
                local target = getMurd()
                if target then resetPlayer(target, 3) end
            end)
        end
    end)
end)

combat_section:AddLabel("You must enable piercer bullet (premium feature) and the rectangular shoot murderer button for auto shoot murderer to work.")

combat_section:AddToggle("Disable 3D Rendering", function(v)
    SetNoRenderState(v)
end)

combat_section:AddToggle("Auto-Kill All", function(v)
    autoKillAllEnabled = v
    if v then
        task.spawn(function()
            while autoKillAllEnabled do
                if not hasExecutedThisLife and hasKnife() then
                    hasExecutedThisLife = true
                    task.wait(1.0)
                    killAllExceptOne()
                    break
                end
                task.wait(0.1)
            end
        end)
    end
end)

combat_section:AddToggle("Auto-Shoot Murd", function(v)
    autoShootMurdEnabled = v
    if not v then
        if shootLoopThread then
            task.cancel(shootLoopThread)
            shootLoopThread = nil
        end
        removeShootPlatform()
    else
        if hasGun() then
            startShootingMurderer()
        end
    end
end)

combat_section:AddToggle("Auto-Reset Murderer", function(v)
    autoResetMurdEnabled = v
    updateNoclip()
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

combat_section:AddToggle("Auto Leave 1 (Inno)", function(v)
    toggleResetAll(v)
end)

combat_section:AddToggle("Auto Leave 1 (Murd)", function(v)
    toggleAutoLeave1Murd(v)
end)

combat_section:AddToggle("Coin Aura", function(v)
    coinAuraEnabled = v
    if v then
        auraData.activeThisLife = false
    else
        stopAura()
    end
end)

combat_section:AddSlider("Coin Aura Radius", 1, 8, 8, function(value)
    auraData.radius = value
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
                local currentLifeChar = player.Character
                roleCache.data = nil
                roleCache.timestamp = 0
                local role = getMyRole() or getRole()

                if role == "Innocent" and not hasGun() then
                    while autoGGEnabled and player.Character == currentLifeChar and hasGun() do
                        task.wait(0.5)
                    end
                    while autoGGEnabled and player.Character == currentLifeChar and not hasGun() do
                        if findGunDropPart() then
                            grabGun()
                        end
                        task.wait(0.5)
                    end
                end
                task.wait(1.0)
            end
        end)
    end
end)

combat_section:AddToggle("Kill WL Users at Max", function(v)
    killWlUsersAtMaxEnabled = v
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
    if afkConnection then
        afkConnection:Disconnect()
        afkConnection = nil
    end
    afkConnection = player.Idled:Connect(function()
        local vU = game:GetService("VirtualUser")
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
    if afkConnection then
        afkConnection:Disconnect()
        afkConnection = nil
    end
    if shootLoopThread then
        task.cancel(shootLoopThread)
        shootLoopThread = nil
    end
    removeShootPlatform()
    stopAura()
end)

RootMaid:GiveTask(function()
    CleanupNoRender()
    if currentResetConnection then currentResetConnection:Disconnect() end
    if sheriffFlingMaid then sheriffFlingMaid:Destroy() end
    if resetAllMaid then resetAllMaid:Destroy() end
    if autoLeave1MurdMaid then autoLeave1MurdMaid:Destroy() end
    autoGGMaid:DoCleaning()
    setNoclip(false)
end)

shared.Notify("Autofarm+ loaded successfully!", 1)
