class_name Hud
extends CanvasLayer
## Heads-up display for the local player.

const HIT_MARKER_TIME := 0.15
const ALERT_TIME := 4.0
## The screen is fully white until this many seconds of blindness remain, then fades.
const FLASH_FADE_TIME := 0.8
const GADGET_KEYS: Array[String] = ["G", "T"]
const PHASE_NAMES: Array[String] = ["WAITING", "SETUP", "LIVE", "ROUND OVER", "MATCH OVER"]

var game: Match
var gadgets: GadgetSystem:
	set(value):
		gadgets = value
		gadgets.alarm_raised.connect(_on_alarm_raised)
var player: Player:
	set(value):
		player = value
		if player != null:
			player.arsenal.hit_landed.connect(_on_hit_landed)

var _marker_left := 0.0
var _alert_left := 0.0

@onready var _readout: Label = $Readout
@onready var _top: Label = $Top
@onready var _objective: Label = $Objective
@onready var _prompt: Label = $Prompt
@onready var _status: Label = $Status
@onready var _hit_marker: Label = $HitMarker
@onready var _banner: Label = $Banner
@onready var _alert: Label = $Alert
@onready var _flash: ColorRect = $Flash


func _process(delta: float) -> void:
	# Nothing to show until the first round has handed out sides and weapons.
	if player == null or game == null or player.arsenal.weapon() == null:
		return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var stance := "CROUCH" if player.is_crouching() else ("SPRINT" if player.is_sprinting() else "STAND")
	_readout.text = "speed %.1f m/s   %s   lean %+.2f   spread %.1f deg" \
			% [speed, stance, player.lean_frac, player.arsenal.spread_deg()]

	var seconds := ceili(maxf(game.time_left, 0.0))
	var mine := game.board.scores[player.roster]
	var theirs := game.board.scores[1 - player.roster]
	_top.text = "Round %d      You %d - %d Them      %s  %d:%02d" % [
		game.board.round_number, mine, theirs, PHASE_NAMES[game.phase], seconds / 60, seconds % 60]
	var objective := _objective_text()
	_objective.text = "%s: %s" % [Team.NAMES[player.team], objective] if objective != "" else ""

	var gun := player.arsenal.weapon()
	var ammo := "RELOADING" if gun.is_reloading() else "%d / %d" % [gun.ammo, gun.stats().mag]
	var safe := "   (weapons safe)" if player.arsenal.safe else ""
	var kit: Array[String] = []
	for slot in player.gadgets.size():
		var charges := player.gadget_charges[slot]
		kit.append("[%s] %s%s" % [GADGET_KEYS[slot], Team.GADGET_NAMES[player.gadgets[slot]],
				"" if charges < 0 else " x%d" % charges])
	_status.text = "HP %d\n%s   %s%s\n%s" % [ceili(player.health), gun.stats().name, ammo, safe, "    ".join(kit)]

	_banner.text = _banner_text()
	_banner.visible = _banner.text != ""

	var target := player.aimed_interactable() if not player.is_dead else null
	if player.peek_door != null:
		_prompt.text = "DOOR CAMERA: %s\nMove the mouse to look around. Release the key to put it away." % player.peek_door.door_name
	else:
		_prompt.text = target.interact_prompt(player) if target != null else ""

	_flash.color.a = clampf(player.flash_left / FLASH_FADE_TIME, 0.0, 1.0)
	_alert_left = maxf(_alert_left - delta, 0.0)
	_alert.visible = _alert_left > 0.0

	_marker_left = maxf(_marker_left - delta, 0.0)
	_hit_marker.visible = _marker_left > 0.0


func _objective_text() -> String:
	var room: String = House.HOSTAGE_ROOMS[game.hostage_room].room
	var entry := player.team == Team.Id.ENTRY
	match game.phase:
		Match.Phase.SETUP:
			return "stage outside. Doors unlock when setup ends. [N] changes your gadgets." if entry \
					else "hostage is in %s. Press F on a yellow marker to move it." % room
		Match.Phase.ACTION:
			if game.hostage.state == Hostage.State.FOLLOWING:
				return "escort the hostage out. Stay close or it stops." if entry \
						else "the hostage is being taken out. Stop the escort."
			return "find and secure the hostage." if entry else "hold the hostage in %s until time runs out." % room
	return ""


func _banner_text() -> String:
	match game.phase:
		Match.Phase.ROUND_END:
			return "%s win the round\n%s" % [Team.NAMES[game.last_winner], Match.REASON_TEXT[game.last_reason]]
		Match.Phase.MATCH_END:
			var won := game.board.winning_roster() == player.roster
			return "%s\n%d - %d" % ["MATCH WON" if won else "MATCH LOST",
					game.board.scores[player.roster], game.board.scores[1 - player.roster]]
	return "YOU ARE DOWN" if player.is_dead else ""


func _on_alarm_raised(door: Door) -> void:
	if player != null and player.team == Team.Id.SUSPECTS:
		_alert.text = "TRIP ALARM: %s" % door.door_name
		_alert_left = ALERT_TIME


func _on_hit_landed(zone: Hitbox.Zone, killed: bool) -> void:
	_marker_left = HIT_MARKER_TIME * (3.0 if killed else 1.0)
	_hit_marker.text = "DOWN" if killed else ("HEAD" if zone == Hitbox.Zone.HEAD else "HIT")
	_hit_marker.modulate = Color.RED if killed or zone == Hitbox.Zone.HEAD else Color.WHITE
