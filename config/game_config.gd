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
