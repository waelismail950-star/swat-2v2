class_name NavGraph
extends RefCounted
## Waypoint graph for bots and the hostage. Any two points in the same region can be
## walked between in a straight line (regions are convex rooms); links join regions,
## for example through a door or up a flight of stairs.

var _points: Array[Vector3] = []
var _regions: Array[String] = []
var _links: Array[Array] = []  # per point: indices of explicitly linked points


func add_point(position: Vector3, region: String) -> int:
	_points.append(position)
	_regions.append(region)
	_links.append([])
	return _points.size() - 1


func link(a: int, b: int) -> void:
	_links[a].append(b)
	_links[b].append(a)


## Shortest walkable list of points from `from` to `to` (inclusive of `to`, exclusive of `from`).
## Empty if there is no route.
func route(from: Vector3, from_region: String, to: Vector3, to_region: String) -> Array[Vector3]:
	if from_region == to_region:
		return [to]
	var count := _points.size()
	var cost: Array[float] = []
	var previous: Array[int] = []
	var done: Array[bool] = []
	for i in count:
		cost.append(from.distance_to(_points[i]) if _regions[i] == from_region else INF)
		previous.append(-1)
		done.append(false)

	while true:
		var current := -1
		for i in count:
			if not done[i] and cost[i] < INF and (current == -1 or cost[i] < cost[current]):
				current = i
		if current == -1:
			break
		done[current] = true
		for next in count:
			if done[next] or not (_regions[next] == _regions[current] or _links[current].has(next)):
				continue
			var through := cost[current] + _points[current].distance_to(_points[next])
			if through < cost[next]:
				cost[next] = through
				previous[next] = current

	var last := -1
	var best := INF
	for i in count:
		if _regions[i] == to_region and cost[i] + _points[i].distance_to(to) < best:
			best = cost[i] + _points[i].distance_to(to)
			last = i
	var path: Array[Vector3] = []
	if last == -1:
		return path
	path.append(to)
	while last != -1:
		path.push_front(_points[last])
		last = previous[last]
	return path
