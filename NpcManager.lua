--[[
	NPC Manager Module
	Author: S_aid
	Description: Manages the creation, configuration, and events of NPCs.
	
	Example of use:
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

-- Roblox Services
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local NpcManager = {}
NpcManager.__index = NpcManager

-- External type definitions
local Types = require("@self/Type")

-- Function to initialize the NPC management module
function NpcManager.Init(Config: Types.Config)
	local self = setmetatable({}, NpcManager)

	if not Config then
		warn("[NpcManager]: No configuration was specified. No NPCs will be managed.")
		return self
	end

	-- Internal properties
	self._config = Config
	self._events = {}
	self._folders = {}
	self._npcs = {}
	self._npcs_events = {}
	self._waypoints = {}
	self._patrolConnections = {}
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
				-- Clean up entries for destroyed or removed NPCs
				self._npcs_events[clone] = nil
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

-- Registers a callback function for a named event.
-- These callbacks will be called when the corresponding event occurs.
function NpcManager:setEvent(Name: string, Function: () -> ())
	if not self._loaded then return end
	if not Name or not Function then
		return warn("[NpcManager]: Name and function must be provided in setEvent.")
	end
	self._events[Name] = Function
end

-- Spawns one or all of the NPCs specified in the configuration.
function NpcManager:spawnNpc(ID)
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
		warn(string.format("[NpcManager]: NPC with ID %d is already spawned. Use destroyNpc(%d) first.", ID, ID))
		return self._npcs[ID]
	end

	local npcData = config[ID]
	if not npcData then
		return warn(string.format("[NpcManager]: ID %d not found in configuration.", ID))
	end

	local modelTemplate = self:_getModel(npcData)
	if not modelTemplate then
		return warn(string.format("[NpcManager]: Model not found for NPC '%s'.", npcData.Name or ID))
	end

	if not modelTemplate:FindFirstChild("Humanoid") then
		warn(string.format("[NpcManager]: Template for '%s' has no Humanoid.", npcData.Name or ID))
		return nil
	end

	local clone = modelTemplate:Clone()
	clone:SetAttribute("NpcId", ID)
	self._npcs[ID] = clone
	clone.Parent = workspace

	self:_applyBaseProperties(clone, npcData)
	self:_applyEvents(clone, npcData)

	if npcData.Waypoints and #npcData.Waypoints > 0 then
		self._waypoints[ID] = npcData.Waypoints
		self:_startPatrol(clone, npcData.Waypoints)
	end

	if npcData.Events and npcData.Events.OnSpawn and self._events.OnSpawn then
		self._events.OnSpawn(clone, npcData)
	end

	return clone
end

-- Removes a spawned NPC by its ID and cleans up all associated resources.
function NpcManager:destroyNpc(ID: number)
	if not self._loaded then return end
	local npc = self._npcs[ID]
	if not npc then return end

	-- Disconnect patrol loop
	if self._patrolConnections[npc] then
		self._patrolConnections[npc]:Disconnect()
		self._patrolConnections[npc] = nil
	end

	-- Remove custom event triggers
	self._npcs_events[npc] = nil

	-- Destroy the model and clear the reference
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

	-- Destroy all spawned NPCs
	for _, npc in pairs(self._npcs) do
		npc:Destroy()
	end

	-- Clear all tables to free memory
	self._config = nil
	self._events = nil
	self._folders = nil
	self._npcs = nil
	self._npcs_events = nil
	self._waypoints = nil
	self._patrolConnections = nil
	self._loaded = false
end

-- Helper function: checks whether a table is empty (nil or has no entries).
local function isEmpty(tbl)
	return not tbl or next(tbl) == nil
end

-- Connects standard and custom events to the NPC.
-- Standard events are wired directly to Roblox signals.
-- Custom events are stored as trigger functions called every Heartbeat.
function NpcManager:_applyEvents(Clone: Model, Data)
	local humanoid = Clone:FindFirstChild("Humanoid")
	if not humanoid then return end

	local registeredEvents = self._events
	local npcEvents = Data.Events

	if isEmpty(npcEvents) then return end

	-- Mapping of standard event names to Humanoid signals (except OnDied, handled in _handleDeath)
	local defaultEventMap = {
		OnMove = "Running",
		OnDamage = "HealthChanged",
	}

	local customEventTriggers = {}

	-- Always connect the Died signal for internal cleanup (loot, removal, etc.)
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

		elseif eventName == "OnDied" then
			-- OnDied is handled inside _handleDeath to ensure proper execution order
			-- No direct connection needed here; _handleDeath will call the callback

		elseif type(eventValue) == "function" and registeredEvents[eventName] then
			-- Custom event: store a trigger function that will be evaluated every frame
			local filterFunc = eventValue
			local registeredCallback = registeredEvents[eventName]
			customEventTriggers[eventName] = function()
				local result = filterFunc(Data)
				if result then
					registeredCallback(result, Data)
				end
			end
		end
	end

	-- Store custom triggers if any were defined
	if next(customEventTriggers) then
		self._npcs_events[Clone] = customEventTriggers
	end
end

-- Retrieves the NPC model from the configuration.
-- If Data.Model is a string, searches in the previously registered "Models" folder.
-- Otherwise, assumes it is a direct instance.
function NpcManager:_getModel(Data)
	local modelRef = Data.Model
	if type(modelRef) == "string" then
		local modelsFolder = self._folders["Models"]
		if not modelsFolder then
			warn("[NpcManager]: 'Models' folder not defined. Use setFolder('Models', ...).")
			return nil
		end
		local model = modelsFolder:FindFirstChild(modelRef)
		if not model then
			warn(string.format("[NpcManager]: Model '%s' not found in the Models folder.", modelRef))
		end
		return model
	else
		return modelRef -- Must be a direct instance
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
function NpcManager:_applyBaseProperties(Clone, Data)
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
	if Data.Position then
		local pos = Data.Position
		Clone:PivotTo(typeof(pos) == "Vector3" and CFrame.new(pos) or pos)
	end
end

-- Starts a patrol loop for the NPC, following the given waypoints.
-- Uses PathfindingService to compute a path and then moves the NPC step by step.
function NpcManager:_startPatrol(model, waypoints)
	local humanoid = model:FindFirstChild("Humanoid")
	if not humanoid or #waypoints == 0 then return end

	local currentWaypointIndex = 1
	local waypointPath = {}
	local currentPathIndex = 1
	local retryCount = 0
	local MAX_RETRIES = 5

	local function moveToNextPathPoint()
		if currentPathIndex <= #waypointPath then
			local nextPoint = waypointPath[currentPathIndex]
			humanoid:MoveTo(nextPoint.Position)
		end
	end

	local function computeAndStartPath()
		local target = waypoints[currentWaypointIndex]
		local path = PathfindingService:CreatePath()
		path:ComputeAsync(model.PrimaryPart.Position, target)

		if path.Status == Enum.PathStatus.Success then
			waypointPath = path:GetWaypoints()
			currentPathIndex = 1
			retryCount = 0
			moveToNextPathPoint()
		else
			retryCount = retryCount + 1
			if retryCount <= MAX_RETRIES then
				task.wait(0.5)
				computeAndStartPath()
			else
				warn(string.format("[NpcManager]: Failed to compute path for %s after %d attempts", model.Name, MAX_RETRIES))
			end
		end
	end

	computeAndStartPath()

	local connection
	connection = humanoid.MoveToFinished:Connect(function(reached)
		if not reached then return end

		currentPathIndex = currentPathIndex + 1
		if currentPathIndex <= #waypointPath then
			moveToNextPathPoint()
		else
			currentWaypointIndex = currentWaypointIndex % #waypoints + 1
			computeAndStartPath()
		end
	end)

	self._patrolConnections[model] = connection
end

-- Handles everything that should happen when an NPC dies:
-- - Drops loot items (if configured)
-- - Calls the user's OnDied callback (if registered)
-- - Cleans up connections and removes the model from the world
function NpcManager:_handleDeath(Clone, Data)
	if Data.Loot and self._folders["Loot"] then
		local lootFolder = self._folders["Loot"]
		local dropPos = Clone.PrimaryPart and Clone.PrimaryPart.Position or Clone:GetPivot().Position
		for _, lootEntry in ipairs(Data.Loot) do
			if math.random() <= (lootEntry.Chance or 1) then
				local item = lootFolder:FindFirstChild(lootEntry.Item)
				if item then
					local drop = item:Clone()
					drop.Parent = workspace
					drop:PivotTo(CFrame.new(dropPos + Vector3.new(math.random(-2,2), 0, math.random(-2,2))))
				end
			end
		end
	end

	if Data.Events and Data.Events.OnDied and self._events.OnDied then
		self._events.OnDied(Clone, Data)
	end

	if self._patrolConnections[Clone] then
		self._patrolConnections[Clone]:Disconnect()
		self._patrolConnections[Clone] = nil
	end

	self._npcs_events[Clone] = nil

	local npcId = Clone:GetAttribute("NpcId")
	if npcId and self._npcs[npcId] == Clone then
		self._npcs[npcId] = nil
	end

	Clone:Destroy()
end

return NpcManager
