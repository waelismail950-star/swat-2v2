class_name Layers
extends RefCounted
## Physics layer bits. Names are mirrored in Project Settings > Layer Names.

const WORLD := 1    # walls, floors, doors
const PLAYER := 2   # player bodies
const HITBOX := 4   # damage zones, hit only by weapon rays
const INTERACT := 8 # things you can press F on that are not solid (hostage, hostage markers)
