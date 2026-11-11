class_name Ballistics
extends RefCounted
## Hitscan maths shared by every weapon.


## Casts one bullet. Returns the intersect_ray result (empty if it hit nothing).
## Walls and doors stop bullets; `exclude` should hold the shooter's own hitboxes.
static func cast(world: World3D, from: Vector3, direction: Vector3, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
			from, from + direction * Cfg.weapon_range, Layers.WORLD | Layers.HITBOX, exclude)
	query.collide_with_areas = true
	return world.direct_space_state.intersect_ray(query)


## A random direction inside a cone of `half_angle_deg` around `direction`, uniform over the cone's disc.
static func spread(direction: Vector3, half_angle_deg: float, rng: RandomNumberGenerator) -> Vector3:
	if half_angle_deg <= 0.0:
		return direction
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	var off_axis := deg_to_rad(half_angle_deg) * sqrt(rng.randf())
	return direction.rotated(side.normalized(), off_axis).rotated(direction, rng.randf() * TAU)


static func falloff(stats: Dictionary, distance: float) -> float:
	var t := inverse_lerp(stats.falloff_start, stats.falloff_end, distance)
	return lerpf(1.0, stats.falloff_min, clampf(t, 0.0, 1.0))
