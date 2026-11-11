extends Node
## The ONE place for gameplay tunables. Autoloaded as `Cfg`.
## Units: meters, seconds, degrees where the name says _deg. Edit values here, nowhere else.

# --- Player body ---
var stand_height := 1.8
var crouch_height := 1.15
var body_radius := 0.3
## Eye sits this far below the top of the capsule.
var eye_drop := 0.12

# --- Hitboxes (also what other players see) ---
var head_radius := 0.13
var torso_width := 0.46
var legs_width := 0.38
var body_depth := 0.26
## Gap between the top of the capsule and the shoulders.
var neck_gap := 0.26
## The torso follows this fraction of the head's lean.
var torso_lean_frac := 0.5

# --- Movement ---
var walk_speed := 3.2
var sprint_speed := 5.4
var crouch_speed := 1.7
## Speed multiplier while a lean key is held.
var lean_move_mult := 0.6
var ground_accel := 30.0
var ground_decel := 40.0
var gravity := 18.0
## Time to go fully standing <-> fully crouched.
var crouch_time := 0.25

# --- Lean ---
## Sideways head shift at full lean.
var lean_offset := 0.5
var lean_roll_deg := 12.0
## Time to go centered -> full lean.
var lean_time := 0.18
## Clearance the leaned head keeps from walls (must exceed the camera near plane).
var lean_head_radius := 0.18

# --- Look ---
var mouse_sensitivity_deg := 0.12  # degrees per pixel of mouse motion
var pitch_limit_deg := 85.0

# --- Doors ---
var door_swing_speed_deg := 240.0  # degrees per second
## How far a cracked door stands ajar. Must stay too narrow to walk through.
var door_crack_angle_deg := 20.0
var door_open_angle_deg := 90.0
## Max distance from the eye to a door you can operate.
var interact_range := 2.2

# --- Combat ---
var max_health := 100.0
## Damage multiplier for a hit on the head zone.
var headshot_mult := 4.0
## True: any hit on the head kills outright, whatever the weapon, armor or range
## (a single shotgun pellet included). False: headshot_mult applies instead.
var headshot_lethal := true
## After sprinting stops, how long before a weapon can fire.
var sprint_fire_delay := 0.25
var weapon_swap_time := 0.45
## Spread multiplier while crouched.
var crouch_spread_mult := 0.7
## How fast recoil settles back, per second (higher = snappier). A held trigger levels off
## around recoil_pitch_deg / (fire_interval * this) degrees above the aim point.
var recoil_recovery_rate := 7.0
var weapon_range := 100.0

## Per weapon:
##   damage           per pellet, before headshot and falloff
##   pellets          rays per shot
##   fire_interval    seconds between shots
##   auto             true = hold to fire
##   mag, reload_time magazine size and seconds to reload (reserve ammo is unlimited)
##   spread_deg       cone half-angle when still; move_spread_deg is added at full sprint speed
##   recoil_pitch_deg upward kick per shot; recoil_yaw_deg is the max random sideways kick
##   falloff_*        damage scales from 1 at falloff_start to falloff_min at falloff_end (meters)
var weapons := {
	"carbine": {
		name = "Carbine", auto = true, damage = 34.0, pellets = 1, fire_interval = 0.095,
		mag = 30, reload_time = 2.3, spread_deg = 0.4, move_spread_deg = 3.0,
		recoil_pitch_deg = 1.1, recoil_yaw_deg = 0.5,
		falloff_start = 30.0, falloff_end = 60.0, falloff_min = 0.7,
	},
	"pistol": {
		name = "Pistol", auto = false, damage = 26.0, pellets = 1, fire_interval = 0.15,
		mag = 15, reload_time = 1.6, spread_deg = 0.6, move_spread_deg = 2.0,
		recoil_pitch_deg = 1.8, recoil_yaw_deg = 0.6,
		falloff_start = 20.0, falloff_end = 40.0, falloff_min = 0.6,
	},
	"shotgun": {
		name = "Shotgun", auto = false, damage = 16.0, pellets = 8, fire_interval = 0.9,
		mag = 6, reload_time = 2.8, spread_deg = 4.0, move_spread_deg = 1.5,
		recoil_pitch_deg = 5.0, recoil_yaw_deg = 1.2,
		falloff_start = 4.0, falloff_end = 10.0, falloff_min = 0.3,
	},
}

# --- Teams ---
## Suspects move at this fraction of every Entry speed.
var suspect_speed_mult := 0.9
## Entry light armor: multiplier on body damage taken. Headshots ignore it.
var entry_body_damage_mult := 0.8

# --- Match ---
## Wins needed to take the match (3 = best of 5).
var rounds_to_win := 3
## Sides swap once, after this many rounds.
var swap_sides_after_round := 2
var setup_time := 25.0
var round_time := 150.0
## Pause on the result screen between rounds.
var round_end_time := 6.0
## Pause on the final score before a new match starts.
var match_end_time := 12.0

# --- Hostage ---
## 1 means any direct hit is fatal.
var hostage_health := 1.0
## Seconds an Entry operator must hold interact to secure the hostage.
var hostage_secure_time := 3.0
var hostage_speed := 2.4
## A secured hostage only moves while an Entry operator is within this distance.
var hostage_follow_radius := 4.0

# --- Bots (local test mode) ---
## Seconds a bot must see an enemy before it may fire.
var bot_reaction_time := 0.45
## Reaction time for an enemy that appears already inside this many degrees of the bot's aim:
## a guard holding an angle punishes a sloppy peek far faster than one who has to turn.
var bot_preaim_deg := 7.0
var bot_preaim_reaction_time := 0.12
## Chance per round that a Suspect bot wedges a door of the hostage room / sets a trip alarm.
var bot_wedge_chance := 0.6
var bot_alarm_chance := 0.7
var bot_aim_error_deg := 2.5
var bot_turn_speed_deg := 300.0
var bot_fov_deg := 110.0
var bot_view_range := 25.0

# --- Gadgets ---
## Uses per round. -1 means unlimited.
var gadget_charges := {
	"flashbang": 2, "door_camera": -1, "breach": 1,   # Entry
	"wedge": 2, "alarm": 2,                            # Suspects
}
var flash_throw_speed := 11.0
var flash_fuse := 1.5
## Beyond this distance from the bang, nobody is affected.
var flash_radius := 9.0
## Seconds of blindness at point-blank range, facing the bang.
var flash_duration := 2.5
## Blindness multiplier when facing away from the bang.
var flash_look_away_mult := 0.2
var breach_fuse := 2.5
## A breaching charge stuns (flashes) players this close to the door, with line of sight.
var breach_stun_radius := 3.5
var breach_stun_duration := 2.5
## Seconds of holding interact to force a wedged door.
var wedge_force_time := 4.0
## A trip alarm goes off when an Entry operator comes this close.
var alarm_radius := 1.2
var door_camera_fov_deg := 100.0
## How far the door camera can be panned to either side.
var door_camera_pan_deg := 60.0

# --- Sound ---
## How far each sound carries in open air (meters). It fades to nothing at this distance.
var noise_radius := {
	"step_crouch": 4.0, "step_walk": 10.0, "step_sprint": 18.0,
	"door_open": 12.0, "door_crack": 5.0, "door_close": 9.0,
	"shot_carbine": 60.0, "shot_pistol": 50.0, "shot_shotgun": 60.0,
	"throw": 8.0, "bang": 60.0, "fuse": 12.0, "force": 16.0, "alarm": 30.0,
}
## Loudness multiplier for each door a sound passes through on its way to the listener.
var sound_closed_door_mult := 0.35
var sound_cracked_door_mult := 0.75
## Loudness multiplier for sound going straight through a wall or floor.
var sound_wall_mult := 0.2
## Distance travelled per footstep.
var stride_crouch := 0.6
var stride_walk := 0.8
var stride_sprint := 1.1
## Moving faster than this fraction of walk speed counts as sprinting for footsteps.
var sprint_step_threshold := 1.2
## Seconds between beeps of a breaching charge, and between thumps when forcing a door.
var fuse_beep_interval := 0.4
var force_thump_interval := 0.5
var master_volume := 1.0
