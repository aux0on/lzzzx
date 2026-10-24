-- Standalone Auto-Kill All (Assassin Mode - Multi-Round Robust Fix)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

while not Players.LocalPlayer do task.wait() end
local player = Players.LocalPlayer

local whitelist = {}
local autoKillAllEnabled = false
local assassinModeEnabled = false

local function notify(text)
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Autofarm+",
        Text = text,
        Duration = 2,
    })
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

    -- Keep killing targets sequentially until exactly 1 living player remains
    while autoKillAllEnabled and assassinModeEnabled and player.Character and getLivingPlayerCount() > 1 do
        local targetName = getCurrentTargetName()
        
        if targetName ~= "" then
            local targetPlayer = Players:FindFirstChild(targetName)
            
            if targetPlayer and isWhitelisted(targetPlayer) then
                task.wait(0.2)
            else
                if killTargetByName(targetName) then
                    task.wait(0.25) -- Brief pause for game UI/target to update
                else
                    task.wait(0.1)
                end
            end
        else
            task.wait(0.1)
        end
    end
end

-- Round Start & Persistence Monitor (Fixes the multi-round bug)
task.spawn(function()
    local executedThisRound = false
    while true do
        task.wait(0.3)
        if autoKillAllEnabled then
            local knife = getKnife()
            if knife then
                if not executedThisRound then
                    executedThisRound = true
                    task.wait(1.0) -- Wait for round start to stabilize
                    if assassinModeEnabled then
                        executeAssassinSequence()
                    else
                        killAllExceptOne()
                    end
                end
            else
                -- Knife is gone (round ended or player died), reset for next round
                executedThisRound = false
            end
        else
            executedThisRound = false
        end
    end
end)

-- Max Coins Event Listener (Kills the final target at max bag)
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

-- Minimal Draggable GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StandaloneAssassinGUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 99999
screenGui.IgnoreGuiInset = true

local success = pcall(function()
    screenGui.Parent = CoreGui
end)
if not success or not screenGui.Parent then
    screenGui.Parent = player:WaitForChild("PlayerGui")
end

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 210, 0, 140)
frame.Position = UDim2.new(0.05, 0, 0.4, 0)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
frame.BorderSizePixel = 0
frame.Visible = true
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 8)
uiCorner.Parent = frame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 30)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Assassin Autofarm"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 14
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.Parent = frame

-- Auto-Kill All Toggle
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0.9, 0, 0, 28)
toggleBtn.Position = UDim2.new(0.05, 0, 0.24, 0)
toggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
toggleBtn.Text = "Auto-Kill All: OFF"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.TextSize = 12
toggleBtn.Font = Enum.Font.SourceSans
toggleBtn.Parent = frame

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 6)
btnCorner.Parent = toggleBtn

toggleBtn.MouseButton1Click:Connect(function()
    autoKillAllEnabled = not autoKillAllEnabled
    if autoKillAllEnabled then
        toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
        toggleBtn.Text = "Auto-Kill All: ON"
        notify("Auto-Kill All Enabled")
    else
        toggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
        toggleBtn.Text = "Auto-Kill All: OFF"
        notify("Auto-Kill All Disabled")
    end
end)

-- Assassin Mode Toggle (Placed directly below Auto-Kill All)
local assassinBtn = Instance.new("TextButton")
assassinBtn.Size = UDim2.new(0.9, 0, 0, 28)
assassinBtn.Position = UDim2.new(0.05, 0, 0.48, 0)
assassinBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
assassinBtn.Text = "Assassin Mode: OFF"
assassinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
assassinBtn.TextSize = 12
assassinBtn.Font = Enum.Font.SourceSans
assassinBtn.Parent = frame

local assassinCorner = Instance.new("UICorner")
assassinCorner.CornerRadius = UDim.new(0, 6)
assassinCorner.Parent = assassinBtn

assassinBtn.MouseButton1Click:Connect(function()
    assassinModeEnabled = not assassinModeEnabled
    if assassinModeEnabled then
        assassinBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
        assassinBtn.Text = "Assassin Mode: ON"
        notify("Assassin Mode Enabled")
    else
        assassinBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
        assassinBtn.Text = "Assassin Mode: OFF"
        notify("Assassin Mode Disabled")
    end
end)

-- Clear Whitelist Button
local clearWhitelistBtn = Instance.new("TextButton")
clearWhitelistBtn.Size = UDim2.new(0.9, 0, 0, 25)
clearWhitelistBtn.Position = UDim2.new(0.05, 0, 0.74, 0)
clearWhitelistBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
clearWhitelistBtn.Text = "Clear Whitelist"
clearWhitelistBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
clearWhitelistBtn.TextSize = 12
clearWhitelistBtn.Font = Enum.Font.SourceSans
clearWhitelistBtn.Parent = frame

local clearCorner2 = Instance.new("UICorner")
clearCorner2.CornerRadius = UDim.new(0, 6)
clearCorner2.Parent = clearWhitelistBtn

clearWhitelistBtn.MouseButton1Click:Connect(function()
    whitelist = {}
    notify("Whitelist cleared")
end)

notify("Standalone Assassin Autofarm loaded!")
