class_name House
extends Node3D

signal doors_reset(lock_exterior: bool)
signal exterior_lock_changed(locked: bool)
## The greybox map: one two-floor house built from the tables below.
## X runs east, Z runs south, the footprint is x in [-7, 7], z in [-5, 5].

const UPPER_Y := 3.0   # top of the upper floor
const ROOF_Y := 5.8    # underside of the roof
const WALL_T := 0.2
const SLAB_T := 0.2
const DOOR_W := 1.0
const DOOR_H := 2.1

const WALL_COLOR := Color(0.72, 0.7, 0.65)
const STAIR_COLOR := Color(0.5, 0.42, 0.34)
const GROUND_COLOR := Color(0.3, 0.38, 0.28)
const ROOF_COLOR := Color(0.35, 0.33, 0.33)
## Kept short: lights reach through floors and walls when counted against the
## renderer's per-object light cap (raised to 16 in project settings).
const LIGHT_RANGE := 5.5

## rect is Rect2(x, z, size_x, size_z). `lit` rooms get a ceiling light and a name label.
const ROOMS := [
	{name = "Foyer", y = 0.0, rect = Rect2(-2, -1.5, 4, 6.5), color = Color(0.5, 0.5, 0.52), lit = true},
	{name = "Living", y = 0.0, rect = Rect2(-7, 0, 5, 5), color = Color(0.45, 0.52, 0.45), lit = true},
	{name = "Kitchen", y = 0.0, rect = Rect2(-7, -5, 5, 5), color = Color(0.55, 0.52, 0.42), lit = true},
	{name = "Dining", y = 0.0, rect = Rect2(2, -5, 5, 5), color = Color(0.52, 0.45, 0.45), lit = true},
	{name = "Study", y = 0.0, rect = Rect2(2, 0, 5, 5), color = Color(0.42, 0.48, 0.55), lit = true},
	{name = "Stairwell", y = 0.0, rect = Rect2(-2, -5, 4, 3.5), color = Color(0.4, 0.4, 0.4), lit = false},
	{name = "Upper Hall", y = UPPER_Y, rect = Rect2(-2, -1.5, 4, 6.5), color = Color(0.5, 0.5, 0.52), lit = true},
	{name = "Master", y = UPPER_Y, rect = Rect2(-7, -5, 5, 5), color = Color(0.55, 0.45, 0.52), lit = true},
	{name = "Bedroom", y = UPPER_Y, rect = Rect2(-7, 0, 5, 5), color = Color(0.45, 0.55, 0.55), lit = true},
	{name = "Kids", y = UPPER_Y, rect = Rect2(2, -5, 5, 5), color = Color(0.58, 0.55, 0.4), lit = true},
	{name = "Deck", y = UPPER_Y, rect = Rect2(2, 0, 5, 5), color = Color(0.4, 0.34, 0.28), lit = false},
]

## Walls as [from_x, from_z, to_x, to_z, bottom_y, top_y], axis-aligned.
## Door openings are cut automatically wherever a door in DOORS sits on a wall.
const WALLS := [
	# Exterior.
	[-7, 5, 7, 5, 0.0, UPPER_Y],
	[-7, 5, 2, 5, UPPER_Y, ROOF_Y],
	[-7, -5, 7, -5, 0.0, ROOF_Y],
	[-7, -5, -7, 5, 0.0, ROOF_Y],
	[7, -5, 7, 5, 0.0, UPPER_Y],
	[7, -5, 7, 0, UPPER_Y, ROOF_Y],
	[2, 0, 7, 0, UPPER_Y, ROOF_Y],
	# Interior.
	[-2, -5, -2, 5, 0.0, UPPER_Y],
	[-2, -5, -2, 5, UPPER_Y, ROOF_Y],
	[2, -5, 2, 5, 0.0, UPPER_Y],
	[2, -5, 2, 5, UPPER_Y, ROOF_Y],
	[-7, 0, -2, 0, 0.0, UPPER_Y],
	[-7, 0, -2, 0, UPPER_Y, ROOF_Y],
	[2, 0, 7, 0, 0.0, UPPER_Y],
	# Stairwell: spine between the flights, and the walls that close it off from the halls.
	[0, -3.75, 0, -1.5, 0.0, ROOF_Y],
	[-2, -1.5, 0, -1.5, 0.0, UPPER_Y - SLAB_T],  # stops under the top of flight 2
	[0, -1.5, 2, -1.5, UPPER_Y, ROOF_Y],
	# Deck parapet, with a gap where the exterior ramp arrives.
	[2, 5, 7, 5, UPPER_Y, UPPER_Y + 1.1],
	[7, 1.6, 7, 5, UPPER_Y, UPPER_Y + 1.1],
]

## `pos` is the centre of the opening (x, z). `axis` is the direction the wall runs.
## `hinge` is which end of the opening carries the hinge along that axis.
const DOORS := [
	{name = "Front Door", y = 0.0, pos = Vector2(0, 5), axis = "x", hinge = -1},
	{name = "Foyer-Living", y = 0.0, pos = Vector2(-2, 2.5), axis = "z", hinge = -1},
	{name = "Living-Kitchen", y = 0.0, pos = Vector2(-4.5, 0), axis = "x", hinge = -1},
	{name = "Kitchen-Foyer", y = 0.0, pos = Vector2(-2, -0.75), axis = "z", hinge = -1},
	{name = "Dining-Foyer", y = 0.0, pos = Vector2(2, -0.75), axis = "z", hinge = 1},
	{name = "Study-Foyer", y = 0.0, pos = Vector2(2, 2.5), axis = "z", hinge = 1},
	{name = "Dining-Study", y = 0.0, pos = Vector2(4.5, 0), axis = "x", hinge = 1},
	{name = "Hall-Master", y = UPPER_Y, pos = Vector2(-2, -0.75), axis = "z", hinge = 1},
	{name = "Hall-Bedroom", y = UPPER_Y, pos = Vector2(-2, 2.5), axis = "z", hinge = 1},
	{name = "Master-Bedroom", y = UPPER_Y, pos = Vector2(-4.5, 0), axis = "x", hinge = -1},
	{name = "Hall-Kids", y = UPPER_Y, pos = Vector2(2, -0.75), axis = "z", hinge = -1},
	{name = "Deck Door", y = UPPER_Y, pos = Vector2(2, 2.5), axis = "z", hinge = 1},
]

const EXTERIOR_DOORS: Array[String] = ["Front Door", "Deck Door"]

## Where each side starts a round, and where a rescued hostage has to get to.
const ENTRY_SPAWNS: Array[Vector3] = [Vector3(3.2, 0, 9), Vector3(4.8, 0, 9)]
const SUSPECT_SPAWNS: Array[Vector3] = [Vector3(-0.8, 0, 2), Vector3(0.8, 0, 2)]
const EXTRACTION := Vector3(4, 0, 9.5)

## Rooms the hostage can be held in. `spot` is where the hostage kneels. `layouts` are
## the guard positions the Suspect bots pick from each round (two guards per layout):
##   0 spread: one covering the door side, one the far corner
##   1 doors:  both close to the doors, ready to shoot whoever opens one
##   2 deep:   both in the back corners, long sightlines, far from any door
## Posts stay clear of the arcs the doors swing through and of the waypoint 1.3 m inside
## each door, which bots walk through.
const HOSTAGE_ROOMS := [
	{room = "Kitchen", spot = Vector3(-5.6, 0, -3.6), layouts = [
		[Vector3(-3.0, 0, -4.2), Vector3(-6.2, 0, -1.2)],
		[Vector3(-3.5, 0, -1.9), Vector3(-5.9, 0, -1.9)],
		[Vector3(-6.4, 0, -4.4), Vector3(-3.4, 0, -4.4)]]},
	{room = "Study", spot = Vector3(5.6, 0, 3.6), layouts = [
		[Vector3(3.0, 0, 4.2), Vector3(6.2, 0, 1.2)],
		[Vector3(3.6, 0, 1.6), Vector3(6.0, 0, 1.4)],
		[Vector3(3.4, 0, 4.4), Vector3(6.4, 0, 4.4)]]},
	{room = "Master", spot = Vector3(-5.6, UPPER_Y, -3.6), layouts = [
		[Vector3(-3.0, UPPER_Y, -4.2), Vector3(-6.2, UPPER_Y, -1.2)],
		[Vector3(-3.5, UPPER_Y, -1.9), Vector3(-5.9, UPPER_Y, -1.9)],
		[Vector3(-6.4, UPPER_Y, -4.4), Vector3(-3.4, UPPER_Y, -4.4)]]},
	{room = "Kids", spot = Vector3(5.6, UPPER_Y, -3.6), layouts = [
		[Vector3(3.0, UPPER_Y, -4.2), Vector3(6.2, UPPER_Y, -1.2)],
		[Vector3(4.6, UPPER_Y, -0.5), Vector3(3.6, UPPER_Y, -1.9)],
		[Vector3(3.4, UPPER_Y, -4.4), Vector3(6.4, UPPER_Y, -4.4)]]},
]
const GUARD_LAYOUTS := 3

## How far in front of a door its waypoints sit: clear of the panel when it stands open.
const DOOR_STANDOFF := 1.3

## Door name -> Door.
var doors: Dictionary[String, Door] = {}
var hostage_spots: Array[HostageSpot] = []

var _nav := NavGraph.new()
## Region name -> the doors leading into it.
var _room_doors: Dictionary[String, Array] = {}
## Region name -> centres of the doorways leading into it.
var _entrances: Dictionary[String, Array] = {}


func _ready() -> void:
	_build_ground()
	_build_rooms()
	_build_roof()
	for wall: Array in WALLS:
		_build_wall(Vector2(wall[0], wall[1]), Vector2(wall[2], wall[3]), wall[4], wall[5])
	for spec: Dictionary in DOORS:
		_build_door(spec)
	_build_stairs()
	_build_exterior_ramp()
	_build_nav()
	for i in HOSTAGE_ROOMS.size():
		var spot := HostageSpot.new()
		spot.index = i
		spot.room_name = HOSTAGE_ROOMS[i].room
		spot.position = HOSTAGE_ROOMS[i].spot
		add_child(spot)
		hostage_spots.append(spot)


## Shuts every door at once. Exterior doors are locked if `lock_exterior`.
func reset_doors(lock_exterior: bool) -> void:
	for door: Door in doors.values():
		door.reset(lock_exterior and door.door_name in EXTERIOR_DOORS)
	doors_reset.emit(lock_exterior)


func set_exterior_locked(locked: bool) -> void:
	for door_name in EXTERIOR_DOORS:
		doors[door_name].locked = locked
	exterior_lock_changed.emit(locked)


## Name of the room (or "Stairwell", "Outside") containing a point.
func region_at(point: Vector3) -> String:
	var flat := Vector2(point.x, point.z)
	for room: Dictionary in ROOMS:
		# The stairwell spans both floors, so it ignores height.
		if room.rect.has_point(flat) and (room.name == "Stairwell" or absf(point.y - room.y) < 1.5):
			return room.name
	return "Outside"


## Waypoints to walk from `from` to `to`, ending with `to`. Doors on the way may be shut.
func route(from: Vector3, to: Vector3) -> Array[Vector3]:
	return _nav.route(from, region_at(from), to, region_at(to))


## Centres of the doorways leading into a region.
func entrances(region: String) -> Array:
	return _entrances.get(region, [])


## The doors leading into a region.
func doors_of(region: String) -> Array:
	return _room_doors.get(region, [])


func _build_nav() -> void:
	for spec: Dictionary in DOORS:
		var p: Vector2 = spec.pos
		var centre := Vector3(p.x, spec.y, p.y)
		var normal := Vector3(0, 0, 1) if spec.axis == "x" else Vector3(1, 0, 0)
		var sides: Array[int] = []
		for sign: float in [1.0, -1.0]:
			var point := centre + normal * DOOR_STANDOFF * sign
			var region := region_at(point)
			sides.append(_nav.add_point(point, region))
			if not _entrances.has(region):
				_entrances[region] = []
				_room_doors[region] = []
			_entrances[region].append(centre)
			_room_doors[region].append(doors[spec.name])
		_nav.link(sides[0], sides[1])

	# Stairs: foot, both ends of the mid landing, top.
	var foot := _nav.add_point(Vector3(1.0, 0, -1.0), "Foyer")
	var landing_east := _nav.add_point(Vector3(1.0, UPPER_Y * 0.5, -4.3), "Stairwell")
	var landing_west := _nav.add_point(Vector3(-1.0, UPPER_Y * 0.5, -4.3), "Stairwell")
	var top := _nav.add_point(Vector3(-1.0, UPPER_Y, -0.9), "Upper Hall")
	_nav.link(foot, landing_east)
	_nav.link(landing_east, landing_west)
	_nav.link(landing_west, top)

	# Exterior ramp: base, top landing, and a point just inside the parapet gap.
	var ramp_base := _nav.add_point(Vector3(7.9, 0, 7.5), "Outside")
	var ramp_top := _nav.add_point(Vector3(7.9, UPPER_Y, 0.7), "Deck")
	_nav.add_point(Vector3(6.3, UPPER_Y, 0.7), "Deck")
	_nav.link(ramp_base, ramp_top)


func _build_ground() -> void:
	# Four slabs around the footprint so outdoor ground is flush with the room floors.
	for rect: Rect2 in [Rect2(-25, -25, 50, 20), Rect2(-25, 5, 50, 20),
			Rect2(-25, -5, 18, 10), Rect2(7, -5, 18, 10)]:
		_slab(rect, 0.0, GROUND_COLOR)


func _build_rooms() -> void:
	for room: Dictionary in ROOMS:
		var rect: Rect2 = room.rect
		_slab(rect, room.y, room.color)
		var center := rect.get_center()

		if room.lit:
			var label := Label3D.new()
			label.text = room.name
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.pixel_size = 0.008
			label.position = Vector3(center.x, room.y + 2.2, center.y)
			add_child(label)

			var light := OmniLight3D.new()
			light.position = Vector3(center.x, room.y + 2.5, center.y)
			light.omni_range = LIGHT_RANGE
			light.shadow_enabled = true
			add_child(light)

	var stair_light := OmniLight3D.new()
	stair_light.position = Vector3(0, 4.2, -4.4)
	stair_light.omni_range = LIGHT_RANGE
	stair_light.shadow_enabled = true
	add_child(stair_light)


func _build_roof() -> void:
	for rect: Rect2 in [Rect2(-7, -5, 5, 10), Rect2(-2, -5, 4, 10), Rect2(2, -5, 5, 5)]:
		_slab(rect, ROOF_Y + SLAB_T, ROOF_COLOR)


## A horizontal slab whose top surface is at `top_y`.
func _slab(rect: Rect2, top_y: float, color: Color) -> void:
	var center := rect.get_center()
	Greybox.add_box(self, Vector3(center.x, top_y - SLAB_T * 0.5, center.y),
			Vector3(rect.size.x, SLAB_T, rect.size.y), color)


func _build_wall(from: Vector2, to: Vector2, bottom: float, top: float) -> void:
	var along_x := is_equal_approx(from.y, to.y)
	var start := from.x if along_x else from.y
	var end := to.x if along_x else to.y
	var line := from.y if along_x else from.x

	# Openings as [start, end] along the wall, for doors standing on this wall at its base.
	var openings: Array[Vector2] = []
	for spec: Dictionary in DOORS:
		var p: Vector2 = spec.pos
		var door_along := p.x if along_x else p.y
		var door_line := p.y if along_x else p.x
		if (spec.axis == "x") == along_x and is_equal_approx(door_line, line) \
				and is_equal_approx(spec.y, bottom) and door_along > start and door_along < end:
			openings.append(Vector2(door_along - DOOR_W * 0.5, door_along + DOOR_W * 0.5))
	openings.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	# Ends overshoot by half a thickness so corners close up.
	var cursor := start - WALL_T * 0.5
	for opening in openings:
		_wall_piece(along_x, line, cursor, opening.x, bottom, top)
		_wall_piece(along_x, line, opening.x, opening.y, bottom + DOOR_H, top)
		cursor = opening.y
	_wall_piece(along_x, line, cursor, end + WALL_T * 0.5, bottom, top)


func _wall_piece(along_x: bool, line: float, start: float, end: float, bottom: float, top: float) -> void:
	var mid := (start + end) * 0.5
	var length := end - start
	var center := Vector3(mid, (bottom + top) * 0.5, line) if along_x \
			else Vector3(line, (bottom + top) * 0.5, mid)
	var size := Vector3(length, top - bottom, WALL_T) if along_x \
			else Vector3(WALL_T, top - bottom, length)
	Greybox.add_box(self, center, size, WALL_COLOR)


func _build_door(spec: Dictionary) -> void:
	var door := Door.new()
	door.door_name = spec.name
	door.name = spec.name
	door.width = DOOR_W
	door.height = DOOR_H
	var p: Vector2 = spec.pos
	var half: float = DOOR_W * 0.5 * spec.hinge
	# Local +X must point from the hinge toward the latch.
	if spec.axis == "x":
		door.position = Vector3(p.x + half, spec.y, p.y)
		door.rotation.y = PI if spec.hinge > 0 else 0.0
	else:
		door.position = Vector3(p.x, spec.y, p.y + half)
		door.rotation.y = PI * 0.5 if spec.hinge > 0 else -PI * 0.5
	add_child(door)
	doors[door.door_name] = door


func _build_stairs() -> void:
	# U-shaped: flight 1 climbs north on the east side to a mid landing, flight 2 climbs
	# back south on the west side to the upper hall.
	Greybox.add_box(self, Vector3(0, 0.75, -4.375), Vector3(4, 1.5, 1.25), STAIR_COLOR)
	_build_flight(1.0, 1.8, -1.51, -1.0, 0.0)
	_build_flight(-1.0, 1.8, -3.74, 1.0, UPPER_Y * 0.5)


## One straight flight rising half a storey. `dir` is -1 to climb toward -Z, +1 toward +Z.
## Collision is a smooth ramp through the step noses; the steps themselves are visual only.
func _build_flight(center_x: float, width: float, z_start: float, dir: float, base_y: float) -> void:
	const RISERS := 8
	const TREAD := 0.28
	var rise := UPPER_Y * 0.5
	var step_h := rise / RISERS
	var z_end := z_start + dir * TREAD * RISERS
	_add_ramp(center_x, width, z_start, z_end, base_y, base_y + rise, false)
	for i in range(1, RISERS):
		var z_mid := z_start + dir * TREAD * (i + 0.5)
		Greybox.add_visual(self, Vector3(center_x, base_y + step_h * i * 0.5, z_mid),
				Vector3(width, step_h * i, TREAD), STAIR_COLOR)


func _build_exterior_ramp() -> void:
	_add_ramp(7.9, 1.6, 6.8, 1.6, 0.0, UPPER_Y, true)
	Greybox.add_box(self, Vector3(7.9, UPPER_Y * 0.5, 0.8), Vector3(1.6, UPPER_Y, 1.6), STAIR_COLOR)


## A ramp along Z whose top surface runs from (z_low, y_low) to (z_high, y_high).
func _add_ramp(center_x: float, width: float, z_low: float, z_high: float,
		y_low: float, y_high: float, visible: bool) -> void:
	const THICKNESS := 0.2
	var run := z_high - z_low
	var rise := y_high - y_low
	var angle := atan2(rise, absf(run))
	var dir := signf(run)
	var normal := Vector3(0.0, cos(angle), -dir * sin(angle))
	var center := Vector3(center_x, (y_low + y_high) * 0.5, (z_low + z_high) * 0.5) - normal * THICKNESS * 0.5
	var size := Vector3(width, THICKNESS, Vector2(run, rise).length())
	var rotation_deg := Vector3(rad_to_deg(-dir * angle), 0.0, 0.0)
	if visible:
		Greybox.add_box(self, center, size, STAIR_COLOR, rotation_deg)
	else:
		Greybox.add_collider(self, center, size, rotation_deg)
