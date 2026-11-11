class_name Greybox
extends RefCounted
## Helpers for building placeholder level geometry out of boxes.
## `center` and `size` are in the parent's local space.


## A visible, solid box.
static func add_box(parent: Node3D, center: Vector3, size: Vector3, color: Color,
		rotation_deg := Vector3.ZERO) -> StaticBody3D:
	var body := add_collider(parent, center, size, rotation_deg)
	add_visual(body, Vector3.ZERO, size, color)
	return body


## Collision only, nothing drawn.
static func add_collider(parent: Node3D, center: Vector3, size: Vector3,
		rotation_deg := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation_degrees = rotation_deg
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	return body


## Drawn only, no collision.
static func add_visual(parent: Node3D, center: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = center
	parent.add_child(visual)
	return visual
