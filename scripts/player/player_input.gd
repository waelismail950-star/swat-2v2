class_name PlayerInput
extends RefCounted
## One tick of intent for a player. Humans, bots, tests and (later) the network
## all drive the controller through this, never through the keyboard directly.

## x = strafe right, y = forward. Length is clamped to 1 by the controller.
var move := Vector2.ZERO
## Absolute look angles in radians. Yaw 0 faces -Z.
var yaw := 0.0
var pitch := 0.0
var sprint := false
var crouch := false
## -1 = left, +1 = right, 0 = centered.
var lean := 0.0
var fire := false
var reload := false
## Index into the carried weapons.
var weapon_slot := 0
