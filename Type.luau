export type AnimationType = {
	Idle: string?,
	Attack: string?,
	Walk: string?,
	Run: string?,
	Hit: string?,
	Jump: string?,
}

type EventType = {
	OnSpawn: boolean?,
	OnDied: boolean?,
	OnMove: boolean?,
	OnDamage: boolean?,
	[string]: () -> ()?
}

export type RangeType = number | {number}

export type NPCData = {
	Name: string,
	Age: number?,
	Profession: string?,
	PovView: number?,
	ViewDistance: number?,
	Health: number?,
	Size: RangeType?,
	WalkSpeed: RangeType?,
	Position: Vector3,
	Tool: string?,
	Tools: {string}?,
	Animations: AnimationType?,
	Events: {EventType}?,
	Model: string,
}

export type Config = {[number]: NPCData}

return {}
