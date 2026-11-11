extends Node
## The ONE place for gameplay tunables. Autoloaded as `Cfg`.
## Units: meters, seconds, degrees where the name says _deg. Edit values here, nowhere else.

# --- Player body ---
var stand_height := 1.8
var crouch_height := 1.15
var body_radius := 0.3
## Eye sits this far below the top of the capsule.
var eye_drop := 0.12

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
## After sprinting stops, how long before a weapon can fire.
var sprint_fire_delay := 0.25
var weapon_swap_time := 0.45
## Spread multiplier while crouched.
var crouch_spread_mult := 0.7
## How fast recoil settles back, per second (higher = snappier).
var recoil_recovery_rate := 5.0
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
		recoil_pitch_deg = 1.3, recoil_yaw_deg = 0.5,
		falloff_start = 30.0, falloff_end = 60.0, falloff_min = 0.7,
	},
	"pistol": {
		name = "Pistol", auto = false, damage = 26.0, pellets = 1, fire_interval = 0.15,
		mag = 15, reload_time = 1.6, spread_deg = 0.6, move_spread_deg = 2.0,
		recoil_pitch_deg = 1.8, recoil_yaw_deg = 0.6,
		falloff_start = 20.0, falloff_end = 40.0, falloff_min = 0.6,
	},
	"shotgun": {
		name = "Shotgun", auto = false, damage = 14.0, pellets = 8, fire_interval = 0.9,
		mag = 6, reload_time = 2.8, spread_deg = 4.0, move_spread_deg = 1.5,
		recoil_pitch_deg = 5.0, recoil_yaw_deg = 1.2,
		falloff_start = 4.0, falloff_end = 10.0, falloff_min = 0.3,
	},
}
