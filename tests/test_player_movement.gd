extends TestCase

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var player: Player


func _ready() -> void:
	Greybox.add_box(self, Vector3(0, -0.25, 0), Vector3(60, 0.5, 60), Color.GRAY)
	player = PLAYER_SCENE.instantiate()
	player.controlled_locally = false
	add_child(player)


func _horizontal_speed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func test_walk_reaches_walk_speed_and_moves_forward() -> void:
	player.input.move = Vector2(0, 1)
	await wait(1.0)
	check_near(_horizontal_speed(), Cfg.walk_speed, 0.05, "walk speed")
	check(player.global_position.z < -2.0, "yaw 0 should move toward -Z")
	check(player.is_on_floor(), "should be grounded")


func test_stops_when_input_released() -> void:
	player.input.move = Vector2(0, 1)
	await wait(0.5)
	player.input.move = Vector2.ZERO
	await wait(0.5)
	check_near(_horizontal_speed(), 0.0, 0.01, "should stop")


func test_movement_follows_yaw() -> void:
	player.input.yaw = -PI / 2  # turn right: forward becomes +X
	player.input.move = Vector2(0, 1)
	await wait(1.0)
	check(player.global_position.x > 2.0, "should have moved toward +X")
	check_near(player.global_position.z, 0.0, 0.05, "should not drift on Z")


func test_diagonal_is_not_faster() -> void:
	player.input.move = Vector2(1, 1)
	await wait(1.0)
	check_near(_horizontal_speed(), Cfg.walk_speed, 0.05, "diagonal speed")


func test_sprint_only_forward() -> void:
	player.input.sprint = true
	player.input.move = Vector2(0, 1)
	await wait(1.0)
	check_near(_horizontal_speed(), Cfg.sprint_speed, 0.05, "sprint speed")
	player.input.move = Vector2(0, -1)
	await wait(1.0)
	check_near(_horizontal_speed(), Cfg.walk_speed, 0.05, "no backward sprint")


func test_crouch_slows_and_shrinks() -> void:
	var standing_eye := player.camera.global_position.y
	player.input.crouch = true
	player.input.sprint = true
	player.input.move = Vector2(0, 1)
	await wait(1.0)
	check(player.is_crouching(), "should be crouching")
	check_near(_horizontal_speed(), Cfg.crouch_speed, 0.05, "crouch speed (sprint ignored)")
	check_near(player.current_height(), Cfg.crouch_height, 0.001, "crouch height")
	check_near(standing_eye - player.camera.global_position.y,
			Cfg.stand_height - Cfg.crouch_height, 0.02, "eye should drop by the height difference")
	player.input.crouch = false
	await wait(0.5)
	check_near(player.current_height(), Cfg.stand_height, 0.001, "should stand back up")


func test_cannot_stand_under_low_ceiling() -> void:
	# Beam with its underside at 1.3 m, covering z in [-5, -2].
	Greybox.add_box(self, Vector3(0, 1.8, -3.5), Vector3(4, 1.0, 3), Color.ORANGE)
	player.input.move = Vector2(0, 1)
	await wait(1.5)
	check(player.global_position.z > -2.0, "standing player must be blocked by the beam")

	player.input.crouch = true
	await wait(1.2)
	var z := player.global_position.z
	check(z < -2.5 and z > -4.5, "crouched player should be under the beam (z=%.2f)" % z)

	player.input.crouch = false
	player.input.move = Vector2.ZERO
	await wait(0.5)
	check(player.is_crouching(), "must stay crouched under the beam")

	player.input.move = Vector2(0, 1)
	await wait(3.0)
	check(player.global_position.z < -5.5, "should exit the far side")
	check_near(player.current_height(), Cfg.stand_height, 0.001, "should stand once clear")


func test_pitch_is_clamped() -> void:
	player.input.pitch = 10.0
	await wait(0.1)
	check_near(rad_to_deg(player.head.rotation.x), Cfg.pitch_limit_deg, 0.01, "pitch clamp")


func test_lean_shifts_camera_and_slows() -> void:
	player.input.lean = 1.0
	await wait(Cfg.lean_time + 0.1)
	check_near(player.camera.global_position.x, Cfg.lean_offset, 0.01, "right lean offset")
	check_near(rad_to_deg(player.camera.rotation.z), -Cfg.lean_roll_deg, 0.1, "right lean roll")

	player.input.move = Vector2(0, 1)
	player.input.sprint = true
	await wait(1.0)
	check_near(_horizontal_speed(), Cfg.walk_speed * Cfg.lean_move_mult, 0.05, "lean blocks sprint and slows")

	player.input.move = Vector2.ZERO
	player.input.lean = -1.0
	await wait(Cfg.lean_time * 2 + 0.3)
	check_near(player.camera.global_position.x - player.global_position.x,
			-Cfg.lean_offset, 0.01, "left lean offset")

	player.input.lean = 0.0
	await wait(Cfg.lean_time + 0.1)
	check_near(player.lean_frac, 0.0, 0.001, "lean recenters")


func test_lean_is_clamped_by_wall() -> void:
	# Wall face at x = 0.4: full lean (0.5) would put the camera inside it.
	Greybox.add_box(self, Vector3(0.9, 1.5, 0), Vector3(1.0, 3, 4), Color.ORANGE)
	player.input.lean = 1.0
	await wait(0.5)
	var cam_x := player.camera.global_position.x
	check(cam_x <= 0.4 - Cfg.lean_head_radius + 0.01, "camera too close to wall (x=%.3f)" % cam_x)
	check(cam_x > 0.1, "should still lean partway (x=%.3f)" % cam_x)

	# Leaning away from the wall is unaffected.
	player.input.lean = -1.0
	await wait(0.6)
	check_near(player.camera.global_position.x, -Cfg.lean_offset, 0.01, "free side leans fully")


func test_walking_into_wall_while_leaned_pushes_lean_back() -> void:
	Greybox.add_box(self, Vector3(2.5, 1.5, 0), Vector3(1.0, 3, 4), Color.ORANGE)  # face at x = 2.0
	player.input.lean = 1.0
	player.input.move = Vector2(1, 0)
	await wait(2.5)
	var cam_x := player.camera.global_position.x
	check(player.global_position.x > 1.5, "should have reached the wall")
	check(cam_x <= 2.0 - Cfg.lean_head_radius + 0.01, "camera pushed into wall (x=%.3f)" % cam_x)


func test_ramp_can_be_climbed() -> void:
	# 30 degree ramp rising toward -Z, starting about 1 m in front of the player.
	Greybox.add_box(self, Vector3(0, 1.15, -3.3), Vector3(2, 0.2, 5), Color.ORANGE, Vector3(30, 0, 0))
	player.input.move = Vector2(0, 1)
	await wait(2.0)
	check(player.global_position.y > 1.0, "should climb the ramp (y=%.2f)" % player.global_position.y)


func test_keyboard_actions_drive_local_player() -> void:
	player.controlled_locally = true
	Input.action_press("move_forward")
	Input.action_press("crouch")
	Input.action_press("lean_right")
	await wait(1.0)
	Input.action_release("move_forward")
	Input.action_release("crouch")
	Input.action_release("lean_right")
	check(player.global_position.z < -0.5, "move_forward action should move the player")
	check(player.is_crouching(), "crouch action should crouch")
	check(player.lean_frac > 0.9, "lean_right action should lean right")
