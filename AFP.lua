local shared = odh_shared_plugins
local combat_section = shared.AddSection("Autofarm+")

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local vU = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local autoKillAllEnabled = false
local autoShootMurdEnabled = false
local autoResetMurdEnabled = false
local antiAfkEnabled = false
local noRenderEnabled = false

local afkConnection
local hasResetThisLife = false
local isResetting = false
local currentResetConnection = nil
local hasResetOnMaxCoins = false

local blackScreenGui = nil
local blackScreenFrame = nil
local NoRenderColor = Color3.fromRGB(0, 0, 0)

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
    blackScreenFrame.BackgroundColor3 = NoRenderColor
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
    
    if noRenderEnabled then
        CreateBlackScreen()
    else
        RemoveBlackScreen()
    end
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

local function getGun()
	local char = player.Character
	if char and char:FindFirstChild("Gun") then
		return char.Gun
	end
	local bp = player:FindFirstChild("Backpack")
	if bp and bp:FindFirstChild("Gun") then
		return bp.Gun
	end
end

local function hasGun()
	local char = player.Character
	local bp = player:FindFirstChild("Backpack")
	return (char and char:FindFirstChild("Gun")) or (bp and bp:FindFirstChild("Gun"))
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
	
	for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
		track:Stop()
	end
	
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	rootPart.Velocity = Vector3.zero
	rootPart.RotVelocity = Vector3.zero
	
	rootPart.CFrame = savedData.cframe
	
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = true
		end
	end
end

local function resetMurderer(TargetPlayer)
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
	
	local savedData = {
		cframe = RootPart.CFrame,
		platform = Humanoid.PlatformStand,
		position = RootPart.Position
	}
	
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

local function autoResetOnRespawn()
	if not autoResetMurdEnabled then return end
	if hasResetThisLife then return end
	
	local role = getRole()
	if role == "Murderer" then return end

	local murd = getMurd()
	if not murd then return end

	hasResetThisLife = true
	task.wait(0.5)
	task.spawn(function()
		resetMurderer(murd)
	end)
end

player.CharacterAdded:Connect(function()
	hasResetThisLife = false
	hasResetOnMaxCoins = false
	task.wait(2)
	autoResetOnRespawn()
end)

local function shootMurd()
	local gun = getGun()
	if not gun then return end
	if gun.Parent == player.Backpack then
		player.Character.Humanoid:EquipTool(gun)
	end
	task.wait(0.3)
	local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
	vU:Button1Down(center, Camera.CFrame)
	task.wait(0.1)
	vU:Button1Up(center, Camera.CFrame)
end

task.spawn(function()
	local CoinCollected = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Gameplay"):WaitForChild("CoinCollected")

	CoinCollected.OnClientEvent:Connect(function(_, currentCoins, maxCoins)
		if currentCoins < maxCoins then
			hasResetOnMaxCoins = false
			return
		end

		local role = getRole()
		
		if role == "Murderer" and autoKillAllEnabled then
			task.spawn(function()
				killAll()
			end)
		end
		
		if role == "Sheriff" and autoShootMurdEnabled and hasGun() then
			task.spawn(function()
				for i = 1, 12 do
					shootMurd()
					task.wait(3)
					local murd = getMurd()
					if not murd or not murd.Character or murd.Character:FindFirstChildOfClass("Humanoid").Health <= 0 then
						break
					end
				end
			end)
		end
		
		if role ~= "Murderer" and autoResetMurdEnabled then
			if autoShootMurdEnabled and hasGun() then
				return
			end
			
			if not hasResetOnMaxCoins then
				hasResetOnMaxCoins = true
				task.wait(0.5)
				task.spawn(function()
					local murd = getMurd()
					if murd and murd ~= player then
						resetMurderer(murd)
					end
				end)
			end
		end
	end)
end)

combat_section:AddToggle("Disable 3D Rendering", function(v)
    SetNoRenderState(v)
end)

combat_section:AddToggle("Auto Kill All", function(v)
	autoKillAllEnabled = v
end)

combat_section:AddToggle("Auto Shoot Murd", function(v)
	autoShootMurdEnabled = v
end)

combat_section:AddToggle("Auto Reset Murderer", function(v)
	autoResetMurdEnabled = v
end)

combat_section:AddToggle("Anti AFK", function(v)
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
