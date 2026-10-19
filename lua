--[[ Universal Speed / Fly / Infinite Jump (no UI, mobile friendly)
     Edit CONFIG, then execute. Re-executing cleans up the old instance first.

     Toggle at runtime from your executor console:
       Hub.SetSpeed(true/false)   Hub.SetFly(true/false)   Hub.SetInfJump(true/false)
       Hub.ToggleFly()            Hub.Destroy()            Hub.Config.WalkSpeed = 80
]]

------------------------------ CONFIG ------------------------------
local CONFIG = {
	SpeedEnabled = true,
	WalkSpeed    = 50,    -- Roblox default is 16. 30-60 is fast; 100+ is more likely to get flagged.

	FlyEnabled   = false, -- start with fly on or off
	FlySpeed     = 70,    -- studs/second. Raise or lower to taste.
	FlySmoothing = 10,    -- higher = snappier, lower = floatier (try 5-15)

	InfiniteJump = true,

	SpoofWalkSpeed = true, -- hide the modified WalkSpeed from game scripts (needs hookmetamethod)
}
--------------------------------------------------------------------

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")

local env = (getgenv and getgenv()) or _G
if env.Hub and env.Hub.Destroy then pcall(env.Hub.Destroy) end

local LocalPlayer = Players.LocalPlayer
local Hub = { Config = CONFIG }
env.Hub = Hub

-- Connection bookkeeping (global = lives for the script, char = per character)
local globalConns, charConns = {}, {}
local function track(list, conn) list[#list + 1] = conn return conn end
local function disconnectAll(list)
	for i = #list, 1, -1 do
		pcall(function() list[i]:Disconnect() end)
		list[i] = nil
	end
end

local humanoid, rootPart
local flyObjects, flyConn, speedConn

---------------------------- SPEED ----------------------------
local function applySpeed()
	if humanoid and CONFIG.SpeedEnabled then
		humanoid.WalkSpeed = CONFIG.WalkSpeed
	end
end

local function bindSpeedGuard()
	if speedConn then speedConn:Disconnect() speedConn = nil end
	if not humanoid then return end
	-- If the game resets WalkSpeed, put ours back (only writes when different, so no loop)
	speedConn = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if CONFIG.SpeedEnabled and humanoid.WalkSpeed ~= CONFIG.WalkSpeed then
			humanoid.WalkSpeed = CONFIG.WalkSpeed
		end
	end)
	track(charConns, speedConn)
end

-- Optional: game scripts reading WalkSpeed see the default value instead of ours
local oldIndex
if CONFIG.SpoofWalkSpeed and hookmetamethod and newcclosure and checkcaller then
	pcall(function()
		oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
			if not checkcaller() and CONFIG.SpeedEnabled and self == humanoid and key == "WalkSpeed" then
				return 16
			end
			return oldIndex(self, key)
		end))
	end)
end

function Hub.SetSpeed(on)
	CONFIG.SpeedEnabled = on and true or false
	if humanoid then humanoid.WalkSpeed = CONFIG.SpeedEnabled and CONFIG.WalkSpeed or 16 end
end

----------------------------- FLY -----------------------------
local controlModule
pcall(function()
	controlModule = require(LocalPlayer:WaitForChild("PlayerScripts", 5):WaitForChild("PlayerModule", 5)):GetControls()
end)

-- Returns (right, back) input from the mobile thumbstick / keyboard
local function getMoveInput(cam)
	if controlModule then
		local ok, v = pcall(function() return controlModule:GetMoveVector() end)
		if ok and v then return v.X, v.Z end
	end
	if humanoid then
		local rel = cam.CFrame:VectorToObjectSpace(humanoid.MoveDirection)
		return rel.X, rel.Z
	end
	return 0, 0
end

local function stopFly()
	if flyConn then flyConn:Disconnect() flyConn = nil end
	if flyObjects then
		for _, obj in ipairs(flyObjects) do pcall(function() obj:Destroy() end) end
		flyObjects = nil
	end
	if humanoid then humanoid.PlatformStand = false end
end

local function startFly()
	stopFly()
	if not (humanoid and rootPart and rootPart.Parent) then return end

	local attachment = Instance.new("Attachment")
	attachment.Name = "FlyAttachment"
	attachment.Parent = rootPart

	local linear = Instance.new("LinearVelocity")
	linear.Attachment0 = attachment
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linear.MaxForce = math.huge
	linear.VectorVelocity = Vector3.zero
	linear.Parent = rootPart

	local align = Instance.new("AlignOrientation")
	align.Attachment0 = attachment
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.MaxTorque = math.huge
	align.Responsiveness = 40
	align.CFrame = rootPart.CFrame.Rotation
	align.Parent = rootPart

	flyObjects = { attachment, linear, align }
	humanoid.PlatformStand = true

	local current = Vector3.zero
	flyConn = RunService.Heartbeat:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		if not (cam and rootPart and rootPart.Parent) then return end

		local right, back = getMoveInput(cam)
		-- Camera direction decides "forward", so looking up/down climbs/dives
		local target = (cam.CFrame.LookVector * -back + cam.CFrame.RightVector * right)
		if target.Magnitude > 1 then target = target.Unit end
		target = target * CONFIG.FlySpeed

		current = current:Lerp(target, math.clamp(dt * CONFIG.FlySmoothing, 0, 1))
		linear.VectorVelocity = current

		local look = cam.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
		end
	end)
end

function Hub.SetFly(on)
	CONFIG.FlyEnabled = on and true or false
	if CONFIG.FlyEnabled then startFly() else stopFly() end
end
function Hub.ToggleFly() Hub.SetFly(not CONFIG.FlyEnabled) end

------------------------ INFINITE JUMP ------------------------
function Hub.SetInfJump(on) CONFIG.InfiniteJump = on and true or false end

track(globalConns, UserInputService.JumpRequest:Connect(function()
	if CONFIG.InfiniteJump and humanoid and humanoid.Health > 0 and not CONFIG.FlyEnabled then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end))

--------------------- CHARACTER / RESPAWN ---------------------
local function onCharacter(char)
	disconnectAll(charConns)
	stopFly()
	humanoid = char:WaitForChild("Humanoid", 10)
	rootPart = char:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and rootPart) then return end

	applySpeed()
	bindSpeedGuard()
	if CONFIG.FlyEnabled then startFly() end

	track(charConns, humanoid.Died:Connect(stopFly))
end

track(globalConns, LocalPlayer.CharacterAdded:Connect(onCharacter))
if LocalPlayer.Character then task.spawn(onCharacter, LocalPlayer.Character) end

------------------------- CLEANUP -------------------------
function Hub.Destroy()
	stopFly()
	disconnectAll(charConns)
	disconnectAll(globalConns)
	CONFIG.SpeedEnabled, CONFIG.InfiniteJump, CONFIG.SpoofWalkSpeed = false, false, false -- disables the hook too
	if humanoid then humanoid.WalkSpeed = 16 end
	env.Hub = nil
end
