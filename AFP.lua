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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local autoKillAllEnabled = false
local assassinModeEnabled = false

local function isWhitelisted(p)
    if typeof(p) == "Instance" and p:IsA("Player") then
        return table.find(whitelist, p.UserId) ~= nil
    elseif type(p) == "string" then
        local plr = Players:FindFirstChild(p)
        return plr and table.find(whitelist, plr.UserId) ~= nil
    end
    return false
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
    if not pGui then return "" end
    local mainGui = pGui:FindFirstChild("MainGUI")
    if not mainGui then return "" end
    local gameFrame = mainGui:FindFirstChild("Game")
    if not gameFrame then return "" end
    local assassinTarget = gameFrame:FindFirstChild("AssassinTarget")
    if not assassinTarget then return "" end
    local targetNameObj = assassinTarget:FindFirstChild("TargetName")
    if targetNameObj and (targetNameObj:IsA("TextLabel") or targetNameObj:IsA("TextBox")) then
        return targetNameObj.Text or ""
    end
    return ""
end

local function killTargetByName(targetName)
    if targetName == "" then return false end
    local knife = getKnife()
    if not knife then return false end
    local events = knife:FindFirstChild("Events")
    if not events then return false end
    local handleTouched = events:FindFirstChild("HandleTouched")
    if not handleTouched then return false end

    local targetPlayer = Players:FindFirstChild(targetName)
    if targetPlayer and targetPlayer.Character then
        local upperTorso = targetPlayer.Character:FindFirstChild("UpperTorso")
        local humanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
        if upperTorso and humanoid and humanoid.Health > 0 then
            handleTouched:FireServer(upperTorso)
            return true
        end
    end
    return false
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
            local upperTorso = p.Character:FindFirstChild("UpperTorso")
            local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
            if upperTorso and humanoid and humanoid.Health > 0 then
                handleTouched:FireServer(upperTorso)
            end
        end
    end
end

local function killAllExceptOne()
    local knife = getKnife()
    if not knife then return end
    local allPlayers = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character and not isWhitelisted(p) then
            local upperTorso = p.Character:FindFirstChild("UpperTorso")
            local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
            if upperTorso and humanoid and humanoid.Health > 0 then
                table.insert(allPlayers, upperTorso)
            end
        end
    end
    if #allPlayers <= 1 then return end
    local survivorIndex = math.random(1, #allPlayers)
    local survivor = allPlayers[survivorIndex]

    local events = knife:FindFirstChild("Events")
    local handleTouched = events and events:FindFirstChild("HandleTouched")
    if not handleTouched then return end

    for _, upperTorso in ipairs(allPlayers) do
        if upperTorso ~= survivor then
            handleTouched:FireServer(upperTorso)
            task.wait(0.05)
        end
    end
end

local function getLivingPlayerCount()
    local count = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 and not isWhitelisted(p) then
                count = count + 1
            end
        end
    end
    return count
end

local function executeAssassinSequence()
    local knife = getKnife()
    if not knife then return end

    while autoKillAllEnabled and assassinModeEnabled and player.Character and getLivingPlayerCount() > 1 do
        local targetName = getCurrentTargetName()
        
        if targetName ~= "" then
            local targetPlayer = Players:FindFirstChild(targetName)
            
            if targetPlayer and isWhitelisted(targetPlayer) then
                task.wait(0.2)
            else
                if killTargetByName(targetName) then
                    task.wait(0.25)
                else
                    task.wait(0.1)
                end
            end
        else
            task.wait(0.1)
        end
    end
end

-- Round Start & Persistence Monitor
task.spawn(function()
    local executedThisRound = false
    while true do
        task.wait(0.3)
        if autoKillAllEnabled then
            local knife = getKnife()
            if knife then
                if not executedThisRound then
                    executedThisRound = true
                    task.wait(1.0)
                    if assassinModeEnabled then
                        executeAssassinSequence()
                    else
                        killAllExceptOne()
                    end
                end
            else
                executedThisRound = false
            end
        else
            executedThisRound = false
        end
    end
end)

-- Max Coins Event Listener
task.spawn(function()
    local CoinCollected = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Gameplay"):WaitForChild("CoinCollected")
    CoinCollected.OnClientEvent:Connect(function(_, currentCoins, maxCoins)
        if currentCoins < maxCoins then return end

        if hasKnife() and autoKillAllEnabled then
            task.spawn(function()
                if assassinModeEnabled then
                    local timeout = tick() + 5
                    while tick() < timeout and hasKnife() do
                        local targetName = getCurrentTargetName()
                        if targetName ~= "" then
                            killTargetByName(targetName)
                            task.wait(0.2)
                        else
                            task.wait(0.1)
                        end
                    end
                else
                    for i = 1, 3 do
                        killAll()
                        if i < 3 then task.wait(2.5) end
                    end
                end
            end)
        end
    end)
end)

combat_section:AddToggle("Auto-Kill All", function(v)
    autoKillAllEnabled = v
    if v then
        shared.Notify("Auto-Kill All Enabled", 2)
    else
        shared.Notify("Auto-Kill All Disabled", 2)
    end
end)

combat_section:AddToggle("Assassin Mode", function(v)
    assassinModeEnabled = v
    if v then
        shared.Notify("Assassin Mode Enabled", 2)
    else
        shared.Notify("Assassin Mode Disabled", 2)
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

shared.Notify("Autofarm+ loaded successfully!", 1)
