class_name Viewmodel
extends Node3D
## Greybox first-person gun. All motion is procedural: it kicks with recoil and dips while reloading or swapping.

const REST := Vector3(0.24, -0.22, -0.65)
const SIZES := {
	"carbine": Vector3(0.045, 0.07, 0.5),
	"pistol": Vector3(0.035, 0.09, 0.18),
	"shotgun": Vector3(0.055, 0.075, 0.6),
}

var _mesh := BoxMesh.new()
var _shown_id := ""


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.15, 0.17)
	_mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = _mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	position = REST


func update(arsenal: Arsenal) -> void:
	var gun := arsenal.weapon()
	visible = gun != null
	if gun == null:
		return
	if gun.id != _shown_id:
		_shown_id = gun.id
		_mesh.size = SIZES[gun.id]
	var lowered := 0.25 if gun.is_reloading() else 0.0
	var kick := arsenal.recoil.y
	position = position.lerp(REST + Vector3(0, -lowered, kick * 1.5), 0.35)
	rotation.x = lerpf(rotation.x, kick * 1.2 - lowered * 2.0, 0.35)
