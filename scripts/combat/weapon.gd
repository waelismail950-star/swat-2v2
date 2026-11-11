class_name Weapon
extends RefCounted
## Runtime state of one carried weapon. Stats are read live from Cfg.weapons.

var id: String
var ammo: int
var cooldown := 0.0
var reload_left := 0.0
# Server-side bookkeeping for a remote player's weapon.
var last_shot_time := -1000.0
var rate_credit := 1.0


func _init(weapon_id: String) -> void:
	id = weapon_id
	ammo = stats().mag


func stats() -> Dictionary:
	return Cfg.weapons[id]


func is_reloading() -> bool:
	return reload_left > 0.0


func refill() -> void:
	ammo = stats().mag
	cooldown = 0.0
	reload_left = 0.0
	last_shot_time = -1000.0
	rate_credit = 1.0
