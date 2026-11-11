class_name Hud
extends CanvasLayer
## Heads-up display for one local player.

const HIT_MARKER_TIME := 0.15

var player: Player:
	set(value):
		player = value
		player.arsenal.hit_landed.connect(_on_hit_landed)

var _marker_left := 0.0

@onready var _readout: Label = $Readout
@onready var _prompt: Label = $Prompt
@onready var _status: Label = $Status
@onready var _hit_marker: Label = $HitMarker
@onready var _banner: Label = $Banner


func _process(delta: float) -> void:
	if player == null:
		return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var stance := "CROUCH" if player.is_crouching() else ("SPRINT" if player.is_sprinting() else "STAND")
	_readout.text = "speed %.1f m/s   %s   lean %+.2f   spread %.1f deg" \
			% [speed, stance, player.lean_frac, player.arsenal.spread_deg()]

	var gun := player.arsenal.weapon()
	var ammo := "RELOADING" if gun.is_reloading() else "%d / %d" % [gun.ammo, gun.stats().mag]
	_status.text = "HP %d\n%s   %s" % [ceili(player.health), gun.stats().name, ammo]
	_banner.visible = player.is_dead

	var door := player.aimed_door() if not player.is_dead else null
	_prompt.visible = door != null
	if door != null:
		_prompt.text = "%s (%s)\n[F] %s    [V] %s" % [
			door.door_name, Door.State.keys()[door.state].to_lower(),
			"close" if door.state == Door.State.OPEN else "open",
			"close" if door.state == Door.State.CRACKED else "crack"]

	_marker_left = maxf(_marker_left - delta, 0.0)
	_hit_marker.visible = _marker_left > 0.0


func _on_hit_landed(zone: Hitbox.Zone, killed: bool) -> void:
	_marker_left = HIT_MARKER_TIME * (3.0 if killed else 1.0)
	_hit_marker.text = "DOWN" if killed else ("HEAD" if zone == Hitbox.Zone.HEAD else "HIT")
	_hit_marker.modulate = Color.RED if killed or zone == Hitbox.Zone.HEAD else Color.WHITE
