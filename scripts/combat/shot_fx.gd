class_name ShotFx
extends RefCounted
## Throwaway visuals for a shot: a brief tracer and an impact dot.

const TRACER_TIME := 0.05
const IMPACT_TIME := 0.6


static func tracer(parent: Node3D, from: Vector3, to: Vector3, hit_something: bool) -> void:
	var length := from.distance_to(to)
	if length < 0.3:
		return
	var line := _mesh(parent, BoxMesh.new(), Color(1.0, 0.9, 0.5), TRACER_TIME)
	(line.mesh as BoxMesh).size = Vector3(0.012, 0.012, length)
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	line.look_at_from_position((from + to) * 0.5, to, up)
	if hit_something:
		var dot := _mesh(parent, SphereMesh.new(), Color(0.1, 0.1, 0.1), IMPACT_TIME)
		(dot.mesh as SphereMesh).radius = 0.03
		(dot.mesh as SphereMesh).height = 0.06
		dot.global_position = to


static func _mesh(parent: Node3D, mesh: PrimitiveMesh, color: Color, lifetime: float) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	parent.get_tree().create_timer(lifetime).timeout.connect(instance.queue_free)
	return instance
