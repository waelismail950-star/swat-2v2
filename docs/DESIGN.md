# SWAT 2v2 — Design

2v2 asymmetric hostage rescue in one two-floor house. Entry Team vs Suspects, best of 5.
Guiding rule: real technique should win because of geometry and mechanics, never because a rule forces it.

Status: **Milestone 3 of 10** (controller, greybox house, doors, weapons). Everything below describes what is built, not what is planned.

## Run it

Requires Godot 4.4.1.

| What | Command |
| --- | --- |
| Play the current build | `godot` from the repo root (or open the project in the editor and press F5) |

The current build is a sandbox: you spawn outside the front door with all three weapons, and six red dummy targets stand around the house. Dummies and you respawn 3 s after going down.
| Run all tests | `./run_tests.sh` |

On Windows, or without bash, the test script is these two commands:

```
godot --headless --import
godot --headless --fixed-fps 60 res://tests/test_runner.tscn
```

Exit code 0 means every test passed.

## Layout

```
config/game_config.gd   every tunable (autoload `Cfg`)
scenes/                 main.tscn, player/player.tscn
scripts/core/           shared constants (physics layers)
scripts/combat/         weapons, hit resolution, hitboxes, shot visuals
scripts/player/         controller, input struct, visible body, first-person gun
scripts/ui/             HUD
scripts/world/          house (map data and builder), door, greybox helper
tests/                  headless runner and test_*.gd
docs/                   this file, KNOWN_ISSUES.md
```

## Controls

WASD move, Shift sprint, Ctrl or C crouch (hold), Q/E lean (hold), mouse look, left click fire, R reload, 1/2/3 weapon, F open/close door, V crack door, Esc frees the mouse, click recaptures it.

## Mechanics

Each entry: what it is, the behavior it pushes players toward, and what beats it.

### Walk / sprint / crouch speeds
- **What:** walk 3.2 m/s, sprint 5.4 m/s (forward only, not while crouched or leaning), crouch 1.7 m/s.
- **Incentive:** speed and control are a trade; sprinting commits you to a direction and stance.
- **Counter:** a sprinting player cannot lean or crouch, so a defender holding an angle sees the full body first. Sprint will also be loud and block firing once sound (M7) and weapons (M3) exist.

### No jump
- **What:** there is no jump.
- **Incentive:** fights are decided by angles and timing, not by jump-peeking over cover.
- **Counter:** not applicable; it removes a mechanic that had no clean counter indoors.

### Crouch
- **What:** capsule shrinks from 1.8 m to 1.15 m, eye drops with it. You cannot stand up while something solid is overhead.
- **Incentive:** use low cover and (from M7) move quietly, at the cost of speed.
- **Counter:** a crouched player is slow, so they lose any race to a doorway or to the hostage.

### Lean (slicing the pie)
- **What:** Q/E shifts the head 0.5 m sideways and rolls the camera 12 degrees. Movement drops to 60 % and sprint is disabled while leaning.
- **Incentive:** clear a room from outside the doorway a slice at a time instead of stepping into the opening.
- **Counter:** the lean lives on the head node, so the head hitbox (M3) moves with the camera and a leaning head can be shot. Leaning is slow, so a defender who hears it can reposition or pre-aim.
- **Wall rule:** the lean is cut short by nearby geometry (0.18 m clearance), so the camera can never see through or into a wall.

### Doors: closed, cracked, open
- **What:** F toggles fully open or closed. V toggles cracked (20 degrees ajar). You must be within 2.2 m and looking at the door.
  - Closed: blocks movement and sight.
  - Cracked: blocks movement, gives a thin diagonal sightline past the latch edge.
  - Open: clear.
- **Incentive:** crack first to look before committing; a fully open door is a decision that tells everyone the doorway is live.
- **Counter:** a cracked door is visible from both sides and the sightline works both ways. Anyone can close it again.

### Doors swing away from the operator
- **What:** a door always opens away from whoever used it, passing through closed if it was ajar the other way.
- **Incentive:** read doors for information: the side a door stands open toward tells you which side it was opened from.
- **Counter:** you can reset the evidence by closing the door or re-opening it from the other side.

### Bodies stop doors, but cannot hold them shut
- **What:** a swinging door stops against a player and continues once they move. If someone is pressed against the far side of a closed door, it opens toward the operator instead.
- **Incentive:** stacking tight on a door has a cost (you can foul your own entry); standing in a doorway is a risk.
- **Counter:** body-blocking gives no free barricade, because the door just opens the other way. Real barricading is the door wedge gadget (M6), which has limited charges.

### Hitscan weapons, low time-to-kill
- **What:** bullets land instantly along the crosshair. 100 health. Walls and doors stop bullets. Numbers at standstill, before tuning:

| Weapon | Side | Body hits to kill | Head | Fire rate | Magazine | Reload |
| --- | --- | --- | --- | --- | --- | --- |
| Carbine (auto) | Entry | 3 | 1 | ~630 rpm | 30 | 2.3 s |
| Pistol (semi) | both | 4 | 1 | up to 400 rpm | 15 | 1.6 s |
| Shotgun (semi, 8 pellets) | Suspects | 1 inside ~3 m, 2 at ~5 m | pellets x4 | 67 rpm | 6 | 2.8 s |

- **Incentive:** whoever sees first and is already aimed wins, so information and positioning decide fights, not reflex duels.
- **Counter:** cover, doors and angles. Nobody tanks damage, so nobody can simply push through a held angle.

### Headshot multiplier (x4)
- **What:** any single carbine or pistol round to the head is lethal.
- **Incentive:** hold head-height angles and expose as little as possible; a leaning head is a small target but a lethal one.
- **Counter:** crouching and leaning move the head off the default height and line, which is where pre-aimed crosshairs sit.

### Hitboxes follow the body exactly
- **What:** head, torso and legs. Each visible part has a hitbox of the same shape. The head follows the full lean, the torso half of it, and everything drops with a crouch.
- **Incentive:** leaning trades a full-body exposure for a head-and-shoulder one.
- **Counter:** whatever part of an enemy you can see, you can shoot. There is no free peek.

### Spread grows with movement
- **What:** each weapon has a small cone at rest that widens with speed (carbine 0.4 to about 2.2 degrees at walking pace) and tightens by 30 % when crouched.
- **Incentive:** stop or slow down before shooting; plant, then fire.
- **Counter:** a planted shooter is a stationary target.

### Sprinting lowers the weapon
- **What:** no firing or reloading while sprinting, and a 0.25 s delay after stopping.
- **Incentive:** do not run through doorways; a sprinting player loses to anyone already holding the angle.
- **Counter:** sprinting is still the fastest way to cross open ground or reach the hostage when you know the lane is clear.

### Recoil
- **What:** each shot kicks the view up with a small random sideways push; it settles on its own. Holding the trigger climbs, then levels off about 2.7 degrees above the aim point for the carbine.
- **Incentive:** short bursts at range; aim lower when spraying.
- **Counter:** not applicable (it is a cost on the shooter).

### Magazines and reloads
- **What:** unlimited reserve ammo, but a reload takes 1.6 to 2.8 s and is abandoned if you swap weapons. Swapping takes 0.45 s.
- **Incentive:** reload behind cover, count rounds, and use the sidearm when the primary runs dry mid-fight.
- **Counter:** push a player you heard run dry (meaningful once sound exists in M7).

### Shotgun versus carbine
- **What:** the shotgun kills in one blast at doorway range but needs two beyond about 4 m and has a 0.9 s gap between shots. The carbine kills in 0.2 s at any range in the house.
- **Incentive:** Suspects with shotguns want to fight at doorways and corners; Entry wants to fight down halls and from outside the room.
- **Counter:** each weapon loses at the other's range, and a missed shotgun blast is a 0.9 s opening.

### Friendly fire
- **What:** every bullet hurts whoever it hits, teammates included.
- **Incentive:** trigger discipline and deliberate stacking; do not shoot past your partner's head.
- **Counter:** not applicable.

### Going down
- **What:** at 0 health a player becomes a flat marker on the floor, stops blocking movement and bullets, and their camera drops to floor level. Nothing graphic.

## Map: the house

Floor plans (north is up): [ground floor](img/plan_ground.png), [upper floor](img/plan_upper.png).

- **Footprint:** 14 m x 10 m, two floors, 3 m floor to floor. Rooms are 5 m x 5 m, the central hall is 4 m wide.
- **Ground floor:** Foyer (centre), Living and Kitchen (west), Dining and Study (east).
- **Upper floor:** Upper Hall (centre), Master and Bedroom (west), Kids (north-east), open Deck (south-east).
- **Entry points:** Front Door (ground, south) and Deck Door (upper, reached by the exterior ramp on the east side).
- **Stairwell:** one enclosed U-shaped stair at the north end of the halls. Each flight is a 1.8 m wide corridor and the mid-landing is a blind 180 degree turn.
- **Loops:** Foyer-Living-Kitchen-Foyer, Foyer-Study-Dining-Foyer, Upper Hall-Bedroom-Master-Upper Hall.
- **Dead end:** Kids has one door. It is the strongroom: easiest to hold, impossible to leave.
- **Doors:** 12, all 1 m wide. No windows, so nobody outside can see in.

Why one entry per floor: with both entries on the ground floor, every upstairs room would sit behind a single stair that two Suspects can hold until the clock runs out. This way every room has at least two approach routes, and the stairwell connects the two halls instead of gating a whole floor.

Sightline intent:
- Each hall is a long corridor with doors on both sides, so crossing it is exposed to any cracked door.
- Doors off the halls open into the corner of a room, so the first step inside exposes you to most of the room: the fatal funnel. Leaning from the hall clears most of it first.
- The two stair-side doors on each floor sit right at the stair mouth, so a team coming off the stairs is immediately between two doors.

## Architecture notes

- The controller never reads the keyboard directly. `Player.simulate()` consumes a `PlayerInput` (move, look angles, sprint, crouch, lean). Humans fill it from the keyboard, tests fill it from code, and bots and the network will do the same.
- The player origin is at the feet. `Head` carries lean offset and pitch; `Camera` carries lean roll.
- Level geometry is built from boxes in code (`Greybox`), driven by the `ROOMS`, `WALLS` and `DOORS` tables at the top of `scripts/world/house.gd`. Door openings are cut automatically wherever a door sits on a wall. To move a wall or door, edit the table.
- Stairs collide as smooth ramps through the step noses; the visible steps are decoration. The controller cannot climb ledges.
- A door's authoritative data is `state` plus `swing_sign`. The panel angle is derived and animated locally, which is what will be replicated in M5.
- Physics layers: 1 = world (walls, floors, doors), 2 = players, 3 = hitboxes (hit only by weapon rays).
- `Arsenal` (a child of each player) owns trigger logic, ammo, spread and recoil, and resolves each shot by raycast. That resolution step is what moves to the server in M5.
- Anything shootable exposes `take_hit(damage, zone, shooter)` and owns `Hitbox` areas that point back at it. The hostage will use the same interface.
- Recoil is a view offset added on top of the player's look angles, so it never fights the mouse.
- Renderer is GL Compatibility: it runs on weak laptops and is enough for greybox.

## Tunables

All in `config/game_config.gd`. Current groups: player body, movement, lean, look, doors, combat (including the per-weapon table).

Map dimensions are not tunables; they live in `scripts/world/house.gd`.
