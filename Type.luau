export type AnimationType = {
	Idle: string?,
	Attack: string?,
	Walk: string?,
	Run: string?,
	Hit: string?,
	Jump: string?,
}

export type RangeType = number | {number}

export type LootEntry = {
	Item: string,
	Chance: number?,
}

export type EventsType = {
	OnSpawn: boolean?,
	OnDied: boolean?,
	OnMove: boolean?,
	OnDamage: boolean?,
	[string]: boolean | ((npcData: any) -> boolean)?,
}

export type NPCData = {
	Name: string,
	Model: string | Instance,
	Age: number?,
	Profession: string?,
	PovView: number?,
	ViewDistance: number?,
	Health: number?,
	Size: RangeType?,
	WalkSpeed: RangeType?,
	Position: Vector3 | CFrame,
	Tool: string?,
	Tools: {string}?,
	Animations: AnimationType?,
	Events: EventsType?,
	Waypoints: {Vector3}?,
	Loot: {LootEntry}?,
}

export type Config = {[number]: NPCData}

return {}
