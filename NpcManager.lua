--[[
				NPC Manager Module

	Main script exemple:
		local NpcManager = require( MODULE_LOCATION_HERE )
		local Module = NpcManager.Init({
			[1] = {
				Name = "Dummy",
				Model = "Default",
				Health = 100,
				WalkSpeed = 16, 
				Animations = {
					Idle = "idle_anim"
				},
				Events = {
					OnSpawn = true,
					OnDied = true,
					OnMove = true,
					OnDamage = true,
					-- Custom event continuously checked every frame:
					PlayerNearby = function(npcData)
						local npc = npcData.Model
						if not npc or not npc.PrimaryPart then return false end
						for _, player in ipairs(game.Players:GetPlayers()) do
							local char = player.Character
							if char and char.PrimaryPart then
								if (char.PrimaryPart.Position - npc.PrimaryPart.Position).Magnitude < 10 then
									return true
								end
							end
						end
						return false
					end,
				},
				Size = 1.5,
				Position = Vector3.new(0, 5, 0),
				Waypoints = {Vector3.new(0,5,0), Vector3.new(10,5,0)},
			},
		})
		
		Module:setFolder("Models", game.ReplicatedStorage.Models)
		Module:setFolder("Animations", game.ReplicatedStorage.Animations)
		
		Module:setEvent("OnSpawn", function(npc)
			print(npc.Name .. " spawned!")
		end)
		Module:setEvent("OnDied", function(npcData)
			print(npcData.Name .. " died!")
		end)
		Module:setEvent("PlayerNearby", function(isNearby, npcData)
			if isNearby then
				print("Player near " .. npcData.Name)
			end
		end)
		
		local myNpc = Module:spawnNpc(1)
		Module:spawnNpc("all")
		
		-- Clean up when done (optional)
		-- Module:Destroy()
]]

local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local NpcManager = {}
NpcManager.__index = NpcManager

local Types = require("@self/Type")

-- Function to initialize the NPC management module
function NpcManager.Init(Config: Types.Config)
	local self = setmetatable({}, NpcManager)

	if not Config then
		warn("[NpcManager]: Missing config. No NPCs will be managed.")
		return self
	end

	self._config = Config
	self._events = {}
	self._folders = {}
	self._npcs = {}
	self._npcs_events = {}
	self._waypoints = {}
	self._pConnections = {}
	self._loaded = true

	-- Single heartbeat loop to continuously check all custom events for all NPCs
	self._heartbeatConnection = RunService.Heartbeat:Connect(function()
		for clone, eventTriggers in pairs(self._npcs_events) do
			-- If the clone still exists in the world, run its trigger functions
			if clone and clone.Parent then
				for _, triggerFunc in pairs(eventTriggers) do
					triggerFunc()
				end
			else
				self._npcs_events[clone] = nil -- Clean up entries for destroyed or removed NPCs
			end
		end
	end)

	return self
end

-- Defines a folder to make it easier to reference resources by string.
-- Example: self:setFolder("Models", game.ReplicatedStorage.Models)
function NpcManager:setFolder(Name: string, Path: Instance | Folder)
	if not self._loaded then return end
	if not Name or not Path then
		return warn("[NpcManager]: Folder name or path not specified.")
	end
	self._folders[Name] = Path
end

-- Registers a callback function
function NpcManager:setEvent(Name: string, Function: () -> ())
	if not self._loaded then return end
	if not Name or not Function then
		return warn("[NpcManager]: Name and function must be provided in setEvent.")
	end
	self._events[Name] = Function
end

-- Spawns one or all of the NPCs specified in the configuration.
function NpcManager:spawnNpc(ID: number | string)
	if not self._loaded then return end
	if not ID then
		return warn("[NpcManager]: Spawn ID not specified.")
	end

	local config = self._config

	if type(ID) ~= "number" and ID == "all" then
		for npcId in pairs(config) do
			self:spawnNpc(npcId)
		end
		return self._npcs
	end

	if self._npcs[ID] and not self._npcs[ID].Parent then
		self._npcs[ID] = nil
	end

	if self._npcs[ID] and self._npcs[ID].Parent then
		warn(`[NpcManager]: NPC with ID '{ID}' is already spawned. Use destroyNpc({ID}) first.`)
		return self._npcs[ID]
	end

	local npcData = config[ID]
	if not npcData then
		return warn(`[NpcManager]: ID '{ID}' not found in configuration.`)
	end

	local modelTemplate = self:_getModel(npcData)
	if not modelTemplate then
		return warn(`[NpcManager]: Model not found for NPC '{npcData.Name}'.`)
	end

	if not modelTemplate:FindFirstChild("Humanoid") then
		return warn(`[NpcManager]: Template for '{npcData.Name}' has no Humanoid.`)
	end

	local cloneModel = modelTemplate:Clone()
	cloneModel.Parent = workspace
	cloneModel:SetAttribute("NpcId", ID)
	self._npcs[ID] = cloneModel

	self:_applyBaseProperties(cloneModel, npcData)
	self:_applyEvents(cloneModel, npcData)

	if npcData.Waypoints and #npcData.Waypoints > 0 then
		self._waypoints[ID] = npcData.Waypoints
		self:_startPatrol(cloneModel, npcData.Waypoints)
	end

	if npcData.Events and npcData.Events.OnSpawn and self._events.OnSpawn then
		self._events.OnSpawn(cloneModel, npcData)
	end

	return cloneModel
end

-- Removes a spawned NPC by its ID and cleans up all associated resources.
function NpcManager:destroyNpc(ID: number)
	if not self._loaded then return end
	local npc = self._npcs[ID]
	if not npc then return end

	-- Disconnect patrol loop
	if self._pConnections[npc] then
		self._pConnections[npc]:Disconnect()
		self._pConnections[npc] = nil
	end
	
	self._npcs_events[npc] = nil -- Remove custom event triggers
	
	npc:Destroy()
	self._npcs[ID] = nil
end

-- Destroys the entire NpcManager instance, disconnecting all loops and clearing data.
function NpcManager:Destroy()
	if not self._loaded then return end
	if self._heartbeatConnection then
		self._heartbeatConnection:Disconnect()
		self._heartbeatConnection = nil
	end

	for _, npc in pairs(self._npcs) do
		npc:Destroy()
	end

	self._config = nil
	self._events = nil
	self._folders = nil
	self._npcs = nil
	self._npcs_events = nil
	self._waypoints = nil
	self._pConnections = nil
	self._loaded = false
end

-- Helper function: checks whether a table is empty (nil or has no entries).
local function isEmpty(tbl)
	return not tbl or next(tbl) == nil
end

-- Custom events to the NPC and connects.
function NpcManager:_applyEvents(Clone: Model, Data)
	local humanoid = Clone:FindFirstChild("Humanoid")
	if not humanoid then return end

	local registeredEvents = self._events
	local npcEvents = Data.Events

	if isEmpty(npcEvents) then return end

	local defaultEventMap = {
		OnMove = "Running", 
		OnDamage = "HealthChanged",
	}

	local customTriggers = {}

	humanoid.Died:Connect(function()
		self:_handleDeath(Clone, Data)
	end)

	for eventName, eventValue in pairs(npcEvents) do
		if defaultEventMap[eventName] and eventValue == true then
			-- Standard event: connect directly to the corresponding signal if a callback is registered
			local robloxEventName = defaultEventMap[eventName]
			local callback = registeredEvents[eventName]
			if callback then
				humanoid[robloxEventName]:Connect(function(...)
					callback(Clone, ...)
				end)
			end
		elseif type(eventValue) == "function" and registeredEvents[eventName] then
			-- Custom event: store a trigger function that will be evaluated every frame
			local filterFunc = eventValue
			local getCallback = registeredEvents[eventName]
			customTriggers[eventName] = function()
				local Result = filterFunc(Data)
				if Result then
					getCallback(Result, Data)
				end
			end
		end
	end

	-- Store custom triggers if any were defined
	if next(customTriggers) then
		self._npcs_events[Clone] = customTriggers
	end
end

-- Retrieves the NPC model from the configuration.
function NpcManager:_getModel(Data)
	local getModel = Data.Model
	if type(getModel) == "string" then
		local ModelsFolder = self._folders["Models"]
		if not ModelsFolder then
			return warn("[NpcManager]: 'Models' folder not defined. Use setFolder('Models', ...).")
		end
		local Model = ModelsFolder:FindFirstChild(getModel)
		if not Model then
			return warn(`[NpcManager]: Model {getModel} not found in the Models folder.`)
		end
		return Model
	else
		return getModel
	end
end

-- Returns a random value within a range, or the value itself.
function NpcManager:_getRangeValue(value)
	if typeof(value) == "table" then
		return math.random(value[1], value[2])
	end
	return value
end

-- Applies basic properties (Name, WalkSpeed, Health, Size, Position) to the Clone.
function NpcManager:_applyBaseProperties(Clone: Model, Data)
	local humanoid = Clone:FindFirstChild("Humanoid")
	if Data.Name then Clone.Name = Data.Name end
	if humanoid and Data.WalkSpeed then
		humanoid.WalkSpeed = self:_getRangeValue(Data.WalkSpeed)
	end
	if humanoid and Data.Health then
		humanoid.MaxHealth = Data.Health
		humanoid.Health = Data.Health
	end
	if Data.Size then
		local scale = self:_getRangeValue(Data.Size)
		local primary = Clone.PrimaryPart
		if primary then
			local oldCFrame = primary.CFrame
			for _, part in ipairs(Clone:GetDescendants()) do
				if part:IsA("BasePart") then
					local newSize = part.Size * scale
					local offset = (part.Position - primary.Position) * scale
					part.Size = newSize
					part.Position = primary.Position + offset
				end
			end
			Clone:PivotTo(oldCFrame)
		else
			warn("[NpcManager]: Cannot scale NPC without PrimaryPart")
		end
	end
	
	local getPosition = Data.Position
	if getPosition then
		Clone:PivotTo(typeof(getPosition) == "Vector3" and CFrame.new(getPosition) or getPosition)
	end
end

-- Starts a patrol loop for the NPC, following the given waypoints.
function NpcManager:_startPatrol(Model: Model, Waypoints)
	local humanoid = Model:FindFirstChild("Humanoid")
	if not humanoid or #Waypoints == 0 then return end

	local wayPath, currentWaypointIndex, PathIndex, retryCount = {}, 1, 1, 0

	local function NextPathPoint()
		if PathIndex <= #wayPath then
			local nextPoint = wayPath[PathIndex]
			humanoid:MoveTo(nextPoint.Position)
		end
	end

	local function StartPath()
		local target = Waypoints[currentWaypointIndex]
		local path = PathfindingService:CreatePath()
		path:ComputeAsync(Model.PrimaryPart.Position, target)

		if path.Status == Enum.PathStatus.Success then
			wayPath = path:GetWaypoints()
			PathIndex = 1
			retryCount = 0
			NextPathPoint()
		else
			retryCount = retryCount + 1
			if retryCount <= 5 then
				task.wait(0.5)
				StartPath()
			else
				return warn(`[NpcManager]: Failed to compute path for {Model.Name} after 5 attempts`)
			end
		end
	end

	StartPath()

	local Event
	Event = humanoid.MoveToFinished:Connect(function(reached)
		if not reached then return end

		PathIndex = PathIndex + 1
		if PathIndex <= #wayPath then
			NextPathPoint()
		else
			currentWaypointIndex = currentWaypointIndex % #Waypoints + 1
			StartPath()
		end
	end)

	self._pConnections[Model] = Event
end

-- Handles everything that should happen when an NPC dies.
function NpcManager:_handleDeath(Clone: Model, Data)
	if Data.Loot and self._folders["Loot"] then
		local lootFolder = self._folders["Loot"]
		local dropPos = Clone.PrimaryPart and Clone.PrimaryPart.Position or Clone:GetPivot().Position
		
		for _, lootEntry in ipairs(Data.Loot) do
			if math.random() <= (lootEntry.Chance or 1) then
				local getItem = lootFolder:FindFirstChild(lootEntry.Item)
				if getItem then
					local drop = getItem:Clone()
					drop.Parent = workspace
					drop:PivotTo(CFrame.new(dropPos + Vector3.new(math.random(-2,2), 0, math.random(-2,2))))
				end
			end
		end
	end

	if Data.Events and Data.Events.OnDied and self._events.OnDied then
		self._events.OnDied(Clone, Data)
	end

	if self._pConnections[Clone] then
		self._pConnections[Clone]:Disconnect()
		self._pConnections[Clone] = nil
	end

	self._npcs_events[Clone] = nil

	local npcID = Clone:GetAttribute("NpcId")
	if npcID and self._npcs[npcID] == Clone then
		self._npcs[npcID] = nil
	end

	Clone:Destroy()
end

return NpcManager
