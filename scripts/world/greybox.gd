class_name Greybox
extends RefCounted
## Helpers for building placeholder level geometry out of solid boxes.


## Adds a solid box. `center` and `size` are in the parent's local space.
static func add_box(parent: Node3D, center: Vector3, size: Vector3, color: Color,
		rotation_deg := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation_degrees = rotation_deg

	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)

	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	parent.add_child(body)
	return body
