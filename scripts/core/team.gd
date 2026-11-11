class_name Team
extends RefCounted
## The two sides of a round. Indexable arrays below are ordered by Id.

enum Id { ENTRY, SUSPECTS }

const NAMES: Array[String] = ["Entry Team", "Suspects"]
const COLORS: Array[Color] = [Color(0.25, 0.45, 0.85), Color(0.8, 0.3, 0.25)]
## Weapon ids in slot order.
const LOADOUTS: Array[Array] = [["carbine", "pistol"], ["shotgun", "pistol"]]


## Gadget pairs each side can choose between during setup.
const GADGET_LOADOUTS: Array[Array] = [
	[["flashbang", "door_camera"], ["flashbang", "breach"], ["door_camera", "breach"]],
	[["wedge", "alarm"]],
]
const GADGET_NAMES := {
	"flashbang": "Flashbang", "door_camera": "Door camera", "breach": "Breaching charge",
	"wedge": "Door wedge", "alarm": "Trip alarm",
}


static func other(id: Id) -> Id:
	return Id.SUSPECTS if id == Id.ENTRY else Id.ENTRY
