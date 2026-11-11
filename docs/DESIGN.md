# SWAT 2v2 — Design

2v2 asymmetric hostage rescue in one two-floor house. Entry Team vs Suspects, best of 5.
Guiding rule: real technique should win because of geometry and mechanics, never because a rule forces it.

Status: **Milestone 1 of 10** (first-person controller). Everything below describes what is built, not what is planned.

## Run it

Requires Godot 4.4.1.

| What | Command |
| --- | --- |
| Play the current build | `godot` from the repo root (or open the project in the editor and press F5) |
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
scripts/player/         controller and its input struct
scripts/world/          greybox geometry helper
tests/                  headless runner and test_*.gd
docs/                   this file, KNOWN_ISSUES.md
```

## Controls

WASD move, Shift sprint, Ctrl or C crouch (hold), Q/E lean (hold), mouse look, Esc frees the mouse, click recaptures it.

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

## Architecture notes

- The controller never reads the keyboard directly. `Player.simulate()` consumes a `PlayerInput` (move, look angles, sprint, crouch, lean). Humans fill it from the keyboard, tests fill it from code, and bots and the network will do the same.
- The player origin is at the feet. `Head` carries lean offset and pitch; `Camera` carries lean roll.
- Level geometry is built from boxes in code (`Greybox.add_box`), because that is faster to iterate from the command line than editor-authored scenes.
- Renderer is GL Compatibility: it runs on weak laptops and is enough for greybox.

## Tunables

All in `config/game_config.gd`. Current groups: player body, movement, lean, look.
