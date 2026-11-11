class_name Weapon
extends RefCounted
## Runtime state of one carried weapon. Stats are read live from Cfg.weapons.

var id: String
var ammo: int
var cooldown := 0.0
var reload_left := 0.0


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
