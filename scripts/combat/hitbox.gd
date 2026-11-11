class_name Hitbox
extends Area3D
## A damage zone. Weapon rays hit these; nothing else collides with them.
## `target` must implement take_hit(damage: float, zone: Zone, shooter: Node) -> bool (true = killed).

enum Zone { BODY, HEAD }

var zone := Zone.BODY
var target: Node


static func create(for_target: Node, in_zone: Zone, shape: Shape3D) -> Hitbox:
	var hitbox := Hitbox.new()
	hitbox.target = for_target
	hitbox.zone = in_zone
	hitbox.monitoring = false
	hitbox.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	hitbox.add_child(collider)
	hitbox.set_active(true)
	return hitbox


func set_active(active: bool) -> void:
	collision_layer = Layers.HITBOX if active else 0
