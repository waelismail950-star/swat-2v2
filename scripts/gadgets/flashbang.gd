class_name Flashbang
extends Node3D
## A thrown flashbang. The server flies it and decides when it goes off; clients' copies
## are only moved to where the server says it is.

signal detonated(grenade: Flashbang)

const RADIUS := 0.06
## Speed kept after a bounce, along the surface and away from it.
const SLIDE := 0.7
const BOUNCE := 0.35
const REST_SPEED := 0.6

var velocity := Vector3.ZERO
var fuse_left := 0.0
## False on clients.
var flying := true


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.2, 0.15)
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	add_child(visual)


func _physics_process(delta: float) -> void:
	if not flying:
		return
	fuse_left -= delta
	if fuse_left <= 0.0:
		flying = false
		detonated.emit(self)
		return
	velocity.y -= Cfg.gravity * delta
	var step := velocity * delta
	if step.is_zero_approx():
		return
	var query := PhysicsRayQueryParameters3D.create(
			global_position, global_position + step + step.normalized() * RADIUS, Layers.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += step
		return
	var normal: Vector3 = hit.normal
	global_position = hit.position + normal * RADIUS
	var into := velocity.project(normal)
	velocity = (velocity - into) * SLIDE - into * BOUNCE
	# Settled on the floor: stop, so it does not jitter until the fuse runs out.
	if normal.y > 0.7 and velocity.length() < REST_SPEED:
		velocity = Vector3.ZERO
