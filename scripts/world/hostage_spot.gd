class_name HostageSpot
extends Area3D
## A floor marker in a room where the hostage may be held. During setup a Suspect
## presses interact on it to move the hostage there.

signal chosen(spot: HostageSpot, player: Player)

const COLOR := Color(0.9, 0.8, 0.2)

var index := 0
var room_name := ""
var enabled := false:
	set(value):
		enabled = value
		collision_layer = Layers.INTERACT if enabled else 0


func _ready() -> void:
	monitoring = false
	collision_mask = 0
	collision_layer = Layers.INTERACT if enabled else 0
	var shape := CylinderShape3D.new()
	shape.radius = 0.6
	shape.height = 1.0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.5
	add_child(collider)

	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.02
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	mesh.material = material
	var disc := MeshInstance3D.new()
	disc.mesh = mesh
	disc.position.y = 0.01
	add_child(disc)


func interact_prompt(player: Player) -> String:
	if enabled and player.team == Team.Id.SUSPECTS:
		return "[F] Hold the hostage here (%s)" % room_name
	return ""


func on_interact(player: Player) -> void:
	if enabled and player.team == Team.Id.SUSPECTS:
		chosen.emit(self, player)
