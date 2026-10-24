local shared = odh_shared_plugins
task.spawn(function()
    shared.load_from_github_url("/aux0on/CrashHandler/refs/heads/main/Prevention.lua")
end)

if shared.game_name ~= "Murder Mystery 2" then return end

local afp = shared.CreateTab("Autofarm+", "/aux0on/AFPIcon/refs/heads/main/Untitled163_20260919023714")
local section = afp:AddSection("Assassin")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

while not Players.LocalPlayer do task.wait() end
local player = Players.LocalPlayer

local autoKillEnabled = false
local whitelist = {}

local STATE = { IDLE = "IDLE", KILLING = "KILLING", WAITING = "WAITING", FINAL = "FINAL", DONE = "DONE" }

local state = STATE.IDLE
local maxCoinsReached = false
local lastTargetName = nil
local lastKillAt = 0
local killingStartedAt = 0
local hasSeenTargetName = false
local TARGET_RETRY_DELAY = 4.0
local FALLBACK_COOLDOWN = 1.2

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

local function hasKnife() return getKnife() ~= nil end

local function getKillPart(character)
    if not character then return nil end
    return character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("HumanoidRootPart")
end

local function getActualLivingPlayers()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character and not isWhitelisted(p) then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then table.insert(list, p) end
        end
    end
    return list
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
        if text and text ~= "" and text ~= "Nikilis" then return text end
    end
    return nil
end

local function fireKnifeKill(part)
    local knife = getKnife()
    if not knife then return false end
    local events = knife:FindFirstChild("Events")
    if not events then return false end
    local handleTouched = events:FindFirstChild("HandleTouched")
    if not handleTouched then return false end
    handleTouched:FireServer(part)
    return true
end

local function fireAtPlayer(p)
    if not p or not p.Character or isWhitelisted(p) then return false end
    local part = getKillPart(p.Character)
    local hum = p.Character:FindFirstChildOfClass("Humanoid")
    if part and hum and hum.Health > 0 then
        return fireKnifeKill(part)
    end
    return false
end

-- Is `targetName` the only living player left besides us?
local function isTargetTheLastOne(targetName)
    local living = getActualLivingPlayers()
    if #living == 0 then return false end
    for _, p in ipairs(living) do
        if p.Name ~= targetName then return false end
    end
    return true
end

local function resetRound()
    state = STATE.IDLE
    maxCoinsReached = false
    lastTargetName = nil
    lastKillAt = 0
    killingStartedAt = 0
    hasSeenTargetName = false
end

task.spawn(function()
    while true do
        task.wait(0.1)

        if not autoKillEnabled then
            if state ~= STATE.IDLE then resetRound() end
            continue
        end

        if not hasKnife() then
            if state ~= STATE.IDLE then
                print("[Assassin] Knife gone — reset for next round")
                resetRound()
            end
            continue
        end

        if state == STATE.IDLE then
            maxCoinsReached = false
            lastTargetName = nil
            lastKillAt = 0
            hasSeenTargetName = false
            killingStartedAt = tick()
            state = STATE.KILLING
            print("[Assassin] Knife detected — starting")
            task.wait(1.5)
            if not hasKnife() then resetRound() continue end
        end

        if state == STATE.KILLING then
            local targetName = getCurrentTargetName()
            if targetName then hasSeenTargetName = true end

            if targetName and isWhitelisted(targetName) then
                print("[Assassin] Target " .. targetName .. " is whitelisted — holding")
                state = STATE.WAITING
            elseif targetName then
                local target = Players:FindFirstChild(targetName)
                local hum = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")

                if target and hum and hum.Health > 0 then
                    if isTargetTheLastOne(targetName) then
                        state = STATE.WAITING
                        print("[Assassin] " .. targetName .. " is last — waiting for max coins")
                    elseif targetName ~= lastTargetName then
                        if fireAtPlayer(target) then
                            lastTargetName = targetName
                            lastKillAt = tick()
                            print("[Assassin] Fired at target: " .. targetName)
                        end
                    elseif tick() - lastKillAt >= TARGET_RETRY_DELAY then
                        if fireAtPlayer(target) then
                            lastKillAt = tick()
                            print("[Assassin] Retried target: " .. targetName)
                        end
                    end
                else
                    -- GUI hasn't caught up to the kill yet
                    task.wait(0.3)
                end
            else
                -- No target name. Either Assassin GUI is loading, or we're not in Assassin mode.
                local living = getActualLivingPlayers()
                if #living <= 1 then
                    state = STATE.WAITING
                    print("[Assassin] " .. #living .. " living left — waiting for max coins")
                elseif not hasSeenTargetName and tick() - killingStartedAt > 5 then
                    -- Fallback for non-Assassin mode: kill one player at a time
                    if tick() - lastKillAt >= FALLBACK_COOLDOWN then
                        local victim = living[1]
                        if victim and fireAtPlayer(victim) then
                            lastKillAt = tick()
                            print("[Assassin] (fallback) Fired at: " .. victim.Name)
                        end
                    end
                end
                task.wait(0.2)
            end

        elseif state == STATE.WAITING then
            local living = getActualLivingPlayers()
            if #living == 0 then
                state = STATE.DONE
                print("[Assassin] No targets remain — done")
            elseif maxCoinsReached then
                state = STATE.FINAL
                lastTargetName = nil
                lastKillAt = 0
                print("[Assassin] Max coins reached — killing last target")
            end

        elseif state == STATE.FINAL then
            local living = getActualLivingPlayers()
            if #living == 0 then
                state = STATE.DONE
                print("[Assassin] Round complete")
            elseif tick() - lastKillAt >= FALLBACK_COOLDOWN then
                local victim = nil
                local targetName = getCurrentTargetName()
                if targetName then
                    local t = Players:FindFirstChild(targetName)
                    if t and t.Character and not isWhitelisted(t) then
                        local hum = t.Character:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then victim = t end
                    end
                end
                if not victim then
                    for _, p in ipairs(living) do
                        if not isWhitelisted(p) then victim = p break end
                    end
                end
                if victim and fireAtPlayer(victim) then
                    lastKillAt = tick()
                    print("[Assassin] Final kill fired at: " .. victim.Name)
                end
            end
            task.wait(0.2)

        elseif state == STATE.DONE then
            -- Idle until the knife despawns (handled at the top of this loop)
        end
    end
end)

-- Exact CoinCollected signature from your Autofarm+ script
task.spawn(function()
    local ok, CoinCollected = pcall(function()
        return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Gameplay"):WaitForChild("CoinCollected", 10)
    end)
    if not ok or not CoinCollected then
        shared.Notify("CoinCollected remote missing", 3)
        return
    end

    CoinCollected.OnClientEvent:Connect(function(_, currentCoins, maxCoins)
        if not autoKillEnabled then return end
        if maxCoinsReached then return end
        if type(currentCoins) ~= "number" or type(maxCoins) ~= "number" then return end
        if maxCoins <= 0 then return end
        if currentCoins < maxCoins then return end

        maxCoinsReached = true
        print(string.format("[Assassin] Max coins detected (%d/%d)", currentCoins, maxCoins))
    end)
end)

section:AddToggle("Auto-Kill All", function(v)
    autoKillEnabled = v
    resetRound()
    if v then
        shared.Notify("Assassin enabled — leave 1, final at max bag", 2)
    else
        shared.Notify("Assassin disabled", 2)
    end
end)

section:AddPlayerDropdown("Whitelist Player", function(p)
    if not table.find(whitelist, p.UserId) then
        table.insert(whitelist, p.UserId)
        shared.Notify(p.Name .. " whitelisted.", 2)
    end
end)

section:AddButton("Clear Whitelist", function()
    whitelist = {}
    shared.Notify("Whitelist cleared.", 2)
end)

shared.Notify("Assassin Kill loaded", 1)
