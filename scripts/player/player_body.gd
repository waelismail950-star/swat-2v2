class_name PlayerBody
extends Node3D
## What other players see and shoot: head, torso and legs. Each visible part has a
## hitbox of exactly the same shape, so what you can see is what you can hit.

var _parts: Array[Node3D] = []  # head, torso, legs; each holds a mesh and a hitbox
var _hitboxes: Array[Hitbox] = []
var _torso_shape := BoxShape3D.new()
var _legs_shape := BoxShape3D.new()
var _torso_mesh := BoxMesh.new()
var _legs_mesh := BoxMesh.new()
var _material := StandardMaterial3D.new()
var _marker: MeshInstance3D
var _first_person := false


func setup(target: Node) -> void:
	var head_shape := SphereShape3D.new()
	head_shape.radius = Cfg.head_radius
	var head_mesh := SphereMesh.new()
	head_mesh.radius = Cfg.head_radius
	head_mesh.height = Cfg.head_radius * 2.0
	_add_part(target, Hitbox.Zone.HEAD, head_shape, head_mesh)
	_add_part(target, Hitbox.Zone.BODY, _torso_shape, _torso_mesh)
	_add_part(target, Hitbox.Zone.BODY, _legs_shape, _legs_mesh)

	# Shown instead of the body when the player is down.
	_marker = Greybox.add_visual(self, Vector3(0, 0.08, 0), Vector3(0.5, 0.16, 0.9), Color.WHITE)
	_marker.material_override = _material
	_marker.visible = false


func set_color(color: Color) -> void:
	_material.albedo_color = color


## The local player does not draw their own body.
func set_first_person(first_person: bool) -> void:
	_first_person = first_person
	_refresh_visibility(true)


func set_alive(alive: bool) -> void:
	for hitbox in _hitboxes:
		hitbox.set_active(alive)
	_refresh_visibility(alive)


func hitbox_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for hitbox in _hitboxes:
		rids.append(hitbox.get_rid())
	return rids


## Positions the parts for a capsule of `height` and a lean of `lean_frac` (-1..1).
func pose(height: float, lean_frac: float) -> void:
	var hip := height * 0.5
	var shoulder := height - Cfg.neck_gap
	var lean := lean_frac * Cfg.lean_offset
	_parts[0].position = Vector3(lean, height - Cfg.eye_drop, 0.0)
	_parts[1].position = Vector3(lean * Cfg.torso_lean_frac, (hip + shoulder) * 0.5, 0.0)
	_parts[2].position = Vector3(0.0, hip * 0.5, 0.0)
	var torso_size := Vector3(Cfg.torso_width, shoulder - hip, Cfg.body_depth)
	var legs_size := Vector3(Cfg.legs_width, hip, Cfg.body_depth)
	_torso_shape.size = torso_size
	_torso_mesh.size = torso_size
	_legs_shape.size = legs_size
	_legs_mesh.size = legs_size


func _add_part(target: Node, zone: Hitbox.Zone, shape: Shape3D, mesh: Mesh) -> void:
	var part := Node3D.new()
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material
	part.add_child(visual)
	var hitbox := Hitbox.create(target, zone, shape)
	part.add_child(hitbox)
	add_child(part)
	_parts.append(part)
	_hitboxes.append(hitbox)


func _refresh_visibility(alive: bool) -> void:
	for part in _parts:
		part.visible = alive and not _first_person
	_marker.visible = not alive
