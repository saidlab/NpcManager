# NpcManager
> [!NOTE]
> You are free to use this code. Improvements and new features are coming soon.

---
Example using this module
- 
```lua
local NpcManager = require(MODULE_LOCATION_HERE)

local Module = NpcManager.Init({
  [1] = {
      Name = "Dummy",
      Model = "Default", -- Reference to a model in the “Models” folder
      Health = 100,
      WalkSpeed = 16,
      Animations = {
          Idle = "idle_anim" -- Animation in the “Animations” folder
      },
      Events = {
          OnSpawn = true,
          OnDied = true,
          OnMove = true,
          OnDamage = true,
          -- Custom event continuously checked every frame:
          PlayerNearby = function(npcData)
              -- Return true when a player is within 10 studs
              local npc = npcData.Model
              if not npc or not npc.PrimaryPart then
                  return false
              end
              for _, player in ipairs(game.Players:GetPlayers()) do
                  local char = player.Character
                  if char and char.PrimaryPart then
                      if (char.PrimaryPart.Position - npc.PrimaryPart.Position).Magnitude < 10 then
                          return true
                      end
                  end
              end
              return false
          end
          },
          Size = 1.5,
          Position = Vector3.new(0, 5, 0),
          Waypoints = {Vector3.new(0, 5, 0), Vector3.new(10, 5, 0)},
          Loot = {
              {Item = "Gold", Chance = 0.8},
              {Item = "Sword", Chance = 0.2}
          }
    }
})
```

Configurando as pastas dos acessorios e etc:
```lua
Module:setFolder("Models", game.ReplicatedStorage.Models)
Module:setFolder("Animations", game.ReplicatedStorage.Animations)
Module:setFolder("Loot", game.ReplicatedStorage.LootItems)
```

Configurando os Eventos do NPC:
```lua
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
```

Spawnando o NPC pelo ID:
```lua
local myNpc = Module:spawnNpc(1)
```

Spawnando todos os NPCs:
```lua
Module:spawnNpc("all")
```

Clean up when done
```lua
Module:Destroy()
```
