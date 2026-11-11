# SWAT 2v2 — Design

2v2 asymmetric hostage rescue in one two-floor house. Entry Team vs Suspects, best of 5.
Guiding rule: real technique should win because of geometry and mechanics, never because a rule forces it.

Status: **Milestone 7 of 10** (controller, greybox house, doors, weapons, rounds and hostage, bots, LAN multiplayer, gadgets, sound). Everything below describes what is built, not what is planned.

## Run it

Requires Godot 4.4.1.

| What | Command |
| --- | --- |
| Play | `godot` from the repo root (or open the project in the editor and press F5), then use the menu |
| Run all headless tests | `./run_tests.sh` |
| Run a real host + client match on one machine | `./tests/net/two_instances.sh` |

On Windows, or without bash, `run_tests.sh` is these two commands:

```
godot --headless --import
godot --headless --fixed-fps 60 res://tests/test_runner.tscn
```

Exit code 0 means every test passed.

### Playing

- **Play solo with bots:** you and one bot against two bots, full best-of-5. Your team plays Entry for rounds 1-2 and Suspects from round 3.
- **Host a game:** opens a lobby. Give the others your IP address. Press Start when ready; empty slots are filled with bots.
- **Join:** type the host's IP address. In the lobby, Switch team moves you between Team A (Entry first) and Team B (Suspects first).
- The game uses **UDP port 24565**. On a LAN the host may need to allow Godot through the firewall. Over the internet the host must forward that port.
- If you go down you watch through a living teammate's eyes.

To test multiplayer alone, start the game twice on one machine: host in one window, join `127.0.0.1` in the other.

Options after `--` skip the menu, for example `godot -- --solo`:

| Option | Effect |
| --- | --- |
| `--solo` | straight into a solo match |
| `--host` | host and wait in the lobby |
| `--join=ADDRESS` | join that host |
| `--name=NAME` | your player name |
| `--autostart=N` | host only: start as soon as N humans are in the lobby |
| `--autopilot` | a bot plays for you |
| `--quick` | host only: 3 s setup, 60 s rounds, quit when the match ends |
| `--netlog` | print one line of match state per second |

## Layout

```
config/game_config.gd   every tunable (autoload `Cfg`)
scenes/                 main.tscn, player/player.tscn
scripts/audio/          sound propagation and the generated placeholder sounds
scripts/core/           match state machine, scoreboard, teams, physics layers
scripts/gadgets/        gadget rules and the flashbang
scripts/game/           world: builds a match's scene and replicates the server's decisions
scripts/net/            session: connection, lobby, match start
scripts/ai/             bots for local test mode
scripts/combat/         weapons, hit resolution, hitboxes, shot visuals
scripts/player/         controller, input struct, visible body, first-person gun
scripts/ui/             HUD, menu
scripts/world/          house (map data and builder), door, hostage, hostage markers, waypoint graph
tests/                  headless runner and test_*.gd; net/ holds the two-process check
docs/                   this file, KNOWN_ISSUES.md
```

## Controls

WASD move, Shift sprint, Ctrl or C crouch (hold), Q/E lean (hold), mouse look, left click fire, R reload, 1/2 weapon, F interact (doors, hostage marker; hold on the hostage to secure, hold on a wedged door to force it), V crack door, G and T use your two gadgets, N changes your gadget pair during setup, Esc frees the mouse, click recaptures it.

## Round flow

1. **Setup (25 s).** Suspects spawn in the Foyer; the hostage starts in a random one of four rooms. A Suspect can move it by pressing F on the yellow marker in another candidate room. Entry spawns outside. Exterior doors are locked and all weapons are safe.
2. **Live (180 s).** Doors unlock, weapons go hot. Entry finds the hostage and holds F on it for 3 s to secure it.
3. **Extraction.** The secured hostage walks a fixed route to the extraction point outside (where Entry spawned), but only while a living Entry operator is within 4 m.
4. **Round over (6 s),** then the next round. First roster to 3 wins takes the match; a new match starts 12 s later.

| Round ends when | Winner |
| --- | --- |
| Hostage reaches the extraction point | Entry |
| Both Suspects are down | Entry |
| A Suspect shoots the hostage | Entry |
| Both Entry operators are down | Suspects |
| An Entry operator shoots the hostage | Suspects |
| The clock runs out | Suspects |

Sides swap once, after round 2 (configurable).

## Mechanics

Each entry: what it is, the behavior it pushes players toward, and what beats it.

### Walk / sprint / crouch speeds
- **What:** walk 3.2 m/s, sprint 5.4 m/s (forward only, not while crouched or leaning), crouch 1.7 m/s.
- **Incentive:** speed and control are a trade; sprinting commits you to a direction and stance.
- **Counter:** a sprinting player cannot lean, crouch or fire, is seen full-body by anyone holding the angle, and is heard 18 m away.

### No jump
- **What:** there is no jump.
- **Incentive:** fights are decided by angles and timing, not by jump-peeking over cover.
- **Counter:** not applicable; it removes a mechanic that had no clean counter indoors.

### Crouch
- **What:** capsule shrinks from 1.8 m to 1.15 m, eye drops with it. You cannot stand up while something solid is overhead.
- **Incentive:** use low cover and move quietly, at the cost of speed.
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
- **Counter:** body-blocking gives no free barricade, because the door just opens the other way. Real barricading is the door wedge gadget, which has limited charges.

### Hitscan weapons, low time-to-kill
- **What:** bullets land instantly along the crosshair. 100 health. Walls and doors stop bullets. Numbers at standstill, before tuning:

| Weapon | Carried by | Body hits to kill a Suspect / an Entry operator | Head | Fire rate | Magazine | Reload |
| --- | --- | --- | --- | --- | --- | --- |
| Carbine (auto) | Entry | 3 / 4 | 1 | ~630 rpm | 30 | 2.3 s |
| Pistol (semi) | both | 4 / 5 | 1 | up to 400 rpm | 15 | 1.6 s |
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
- **Counter:** a reloading player cannot shoot back for up to 2.8 s. (Reloads are not audible to others yet.)

### Shotgun versus carbine
- **What:** the shotgun kills in one blast at doorway range, armor included, but needs two beyond about 4 m and has a 0.9 s gap between shots. The carbine kills in 0.2 s at any range in the house.
- **Incentive:** Suspects with shotguns want to fight at doorways and corners; Entry wants to fight down halls and from outside the room.
- **Counter:** each weapon loses at the other's range, and a missed shotgun blast is a 0.9 s opening.

### Friendly fire
- **What:** every bullet hurts whoever it hits, teammates included.
- **Incentive:** trigger discipline and deliberate stacking; do not shoot past your partner's head.
- **Counter:** not applicable.

### Going down
- **What:** at 0 health a player becomes a flat marker on the floor, stops blocking movement and bullets, and their camera drops to floor level. Nothing graphic.

### Sides are asymmetric
- **What:** Entry carries carbine + pistol, moves at full speed and takes 20 % less body damage (light armor; headshots ignore it). Suspects carry shotgun + pistol and move 10 % slower.
- **Incentive:** Entry wins on tempo and range, Suspects on position and close quarters.
- **Counter:** each side's edge is the other's weakness: Entry is punished for walking into shotgun range, Suspects for being caught in a hall.

### Setup phase
- **What:** 25 s in which Suspects choose the hostage room and take positions; Entry is locked outside with weapons safe and no view in.
- **Incentive:** Suspects plan a defence around a room; Entry plans an approach without knowing which room it is.
- **Counter:** the door camera answers what is behind one door; which room holds the hostage still has to be worked out.

### The hostage is fragile, and whoever shoots it loses
- **What:** one direct hit from any weapon kills the hostage. If Entry fired the shot, Suspects win the round; if a Suspect did, Entry wins.
- **Incentive:** both sides must control their fire near the hostage. Entry cannot spray into the hostage room; Suspects cannot spray at an operator standing next to it.
- **Counter:** Suspects can stand close to the hostage to make shots risky; Entry counters with angles, patience and headshots, since the kneeling hostage is only 1.2 m tall.
- **Deviation from the brief:** the brief said the hostage dying is always a Suspect win. That makes "shoot the hostage at the start" the winning Suspect strategy, so the shooter's side loses instead.

### Securing takes an uninterrupted 3 s
- **What:** an Entry operator must stand within reach, look at the hostage and hold F for 3 s. Letting go or looking away resets it.
- **Incentive:** clear the room first, or have a partner cover you; the securing operator cannot shoot.
- **Counter:** a Suspect who survives nearby gets a free shot at a stationary operator.

### Escort: the hostage only moves while an operator is close
- **What:** the secured hostage walks at 2.4 m/s along a fixed route and stops whenever no living operator is within 4 m. It waits at closed doors. Players can walk through it.
- **Incentive:** Entry has to leave the house as a group at walking pace, through known doors; Suspects get a last ambush on a predictable route.
- **Counter:** Entry can clear the route first and open its doors in advance. Suspects cannot body-block the hostage, only stop the escorts.

### The clock
- **What:** if 180 s pass, Suspects win.
- **Incentive:** Entry cannot wait outside for a mistake; Suspects are rewarded for staying alive and holding ground near the hostage rather than hunting.
- **Counter:** a Suspect who hides far from the hostage keeps the clock but gives up the room, and an unopposed rescue takes only 15-25 s.

## Sound

All audio is placeholder, generated in code (noise bursts and tones). What matters is who can hear what.

### Footsteps depend on how you move
- **What:** one step per stride. Crouch-walking carries 4 m, walking 10 m, sprinting 18 m. Standing still is silent.
- **Incentive:** approach a held room at a crouch; sprint only when being heard does not matter.
- **Counter:** crouch-walking is half the speed of walking, so quiet costs time on the clock.

### Sound travels through doorways and is cut by doors
- **What:** sound reaches you along the walking route. Every closed door on the way cuts it to 35 %, a cracked door to 75 %, an open door not at all. What gets through is played from the nearest doorway on your side, so you hear which door it came from.
- **Incentive:** keep doors shut to hide your movement; crack a door to listen as well as look.
- **Counter:** a shut door muffles in both directions. Shutting yourself in to stay quiet also deafens you.

### Walls and floors leak a little
- **What:** a sound also travels in a straight line through structure at 20 %, muffled. Whichever of the two paths is louder is what you hear.
- **Incentive:** stop and listen: footsteps directly above or beyond a wall give away a room.
- **Counter:** crouch-walking overhead is nearly inaudible below.

### Everything loud announces itself
| Sound | Carries | What it tells the other side |
| --- | --- | --- |
| Door opening / closing / cracking | 12 m / 9 m / 5 m | which door, and that cracking is the quiet option |
| Gunshot | 50-60 m | where the fight is; heard through the whole house |
| Flashbang thrown | 8 m | about 1.5 s of warning to look away |
| Flashbang or charge going off | 60 m | which room was just hit |
| Breaching charge fuse (beeps) | 12 m | which door is about to blow, for 2.5 s |
| Forcing a wedged door (thumps) | 16 m | which door is being forced, for 4 s |
| Trip alarm | 30 m | to Suspects: that door. To Entry: you have been detected |

- **Incentive:** every loud option trades secrecy for speed or force.
- **Counter:** each of these sounds is the counter to the action that makes it.

## Gadgets

Each player carries two. Entry chooses a pair during setup by pressing N (flashbang + door camera, flashbang + breaching charge, or door camera + breaching charge). Suspects always carry door wedge + trip alarm. Charges refill every round. Suspects may place theirs during setup; Entry gadgets only work once the round is live. Bots do not use gadgets.

### Flashbang (Entry, 2 per round)
- **What:** G throws it where you are looking. It bounces, and 1.5 s later blinds every player within 9 m who has line of sight to it: up to 3.5 s when close and facing it, 40 % of that when facing away. It never harms the hostage.
- **Incentive:** crack the door, throw, then enter together while the room is blind. A solo rush without it meets defenders who can see.
- **Counter:** look away or break line of sight when you see it land; shut the door; it blinds teammates and the thrower just as readily, so a badly timed entry or a bounce off a closed door blinds the wrong side.

### Door camera (Entry, unlimited)
- **What:** hold its key on a shut door to see the room from floor level on the far side; the mouse pans 60 degrees each way.
- **Incentive:** know what is behind a door before you open it, instead of guessing.
- **Counter:** while looking you cannot move or shoot, and a black lens pokes out under the door where defenders can see it, so they learn which door you are at. The low viewpoint has blind spots along the door's own wall. It stops working the moment the door moves.

### Breaching charge (Entry, 1 per round)
- **What:** stick it to a shut door. 2.5 s later the door is blown open, any wedge is destroyed, and everyone within 3.5 m of the doorway with line of sight is stunned (blinded) for up to 2.5 s. No damage.
- **Incentive:** a fast, violent entry through one chosen door for a team that stacks back from it and goes in on the bang.
- **Counter:** the fuse announces the door and the timing, so defenders can step out of the blast and pre-aim; operators who stay beside the door are stunned too; there is only one.

### Door wedge (Suspects, 2 per round)
- **What:** jams a shut door so it will not open or crack. A yellow wedge shows at its foot.
- **Incentive:** channel Entry toward the doors you are watching and buy time on the clock.
- **Counter:** anyone can force a wedged door by holding F on it for 4 uninterrupted seconds, a breaching charge removes it instantly, and most rooms have another door. A Suspect can pull the wedge out with F, so it also blocks the Suspects' own retreat until they do.

### Trip alarm (Suspects, 2 per round)
- **What:** a small orange box placed on the floor just inside a doorway. The first Entry operator to come within 1.2 m sets it off, alerting both Suspects to that door. It is used up.
- **Incentive:** watch one approach with a gadget so both defenders can watch the other.
- **Counter:** it is visible: the door camera or a cracked door shows it, one bullet destroys it without raising the alert, and another door avoids it.

## Bots (local test mode)

Bots exist so the game can be tested without four people. They are not meant to be good.

- They press the same inputs a player does: same movement, weapons, doors and interact key.
- **Entry bots** walk to the hostage, open doors on the way, secure it and escort it out. **They cheat:** they know which room the hostage is in.
- **Suspect bots** walk to a guard post in the hostage room and sweep between its doorways. If the hostage is taken they chase it.
- All bots shoot enemies they can see inside a 110 degree field of view, after a 0.45 s reaction time, with 2.5 degrees of aim error. They hold fire if the hostage or a teammate is in the cone.
- They do not lean, crouch, crack doors, use cover or coordinate. A careful human should beat them, which is the point.

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

Round locations: Entry spawns on the lawn south-east of the house, between the Front Door and the foot of the ramp; that spot is also the extraction point. Suspects spawn in the Foyer. Hostage rooms are Kitchen, Study, Master and Kids, with the hostage in the corner farthest from the hall.

Sightline intent:
- Each hall is a long corridor with doors on both sides, so crossing it is exposed to any cracked door.
- Doors off the halls open into the corner of a room, so the first step inside exposes you to most of the room: the fatal funnel. Leaning from the hall clears most of it first.
- The two stair-side doors on each floor sit right at the stair mouth, so a team coming off the stairs is immediately between two doors.

## Networking

Listen-server on Godot's high-level multiplayer (ENet), four players at most. One player hosts and is the server; the host also runs the bots.

**Who decides what**

| Thing | Decided by | How others learn it |
| --- | --- | --- |
| A player's position, view, stance, lean | the machine that owns that player | sent every physics tick, smoothed on arrival |
| Whether a shot hit, health, going down | server | reliable message per change |
| Door state | server | reliable message per change; each machine swings the panel itself |
| Hostage position, state, secure progress | server | sent every tick |
| Phase, clock, score, hostage room, round result | server | reliable message per change; clients count the clock down locally |
| Teams, spawns, loadouts | server | sent with each respawn |

**What a client may ask for.** A client never changes the world itself. It sends three kinds of request, each of which the server checks:
- *I fired:* weapon slot, eye position, one direction per pellet. Rejected if the player is down, weapons are safe, the eye position is more than 1.5 m from where the server sees it, the pellet count is wrong, or the fire-rate and ammunition budgets are exhausted.
- *I pressed interact / crack on this thing.* Rejected if the player is down or not within reach.
- *I am holding interact on this thing / I let go.* The server keeps counting only while the player stays in reach.

The shooter's own machine draws its tracers immediately; damage, hit markers and deaths wait for the server.

**Deliberate simplifications**
- **Movement is client-authoritative.** No server-side movement, prediction or rollback. A cheating client could teleport; among friends that is an acceptable trade for never rubber-banding.
- **No lag compensation.** The server tests a shot against where it currently sees other players. On a LAN the difference is a few centimetres. Above roughly 50 ms of latency, moving targets have to be led.
- **Joining is only possible in the lobby.** A match in progress cannot be joined.
- **A client who disconnects is replaced by a bot.** If the host leaves, the match ends for everyone.
- **Fire rate is checked with a small burst allowance** (3 shots), so shots bunched up by the network are not discarded. The server cannot see reloads, so it infers one from any pause as long as a reload.

**How it is built**
- Gadget use is one more client request (*I used the gadget in this slot, at this door or in this direction*). The server applies the rules, then replicates the results: door attachments ride along with door state, grenades are flown by the server, blindness and remaining charges are sent per player.
- `Session` (connection, lobby, start) and `World` (the match's scene) sit at the same node paths on every machine, so remote calls line up. `World` is built identically everywhere from one participant list sent by the host.
- A player node's network authority is the machine that owns it. Messages on the player node go owner -> everyone (state) or owner -> server (requests). Messages on `World` go server -> clients only.
- Offline play uses the same code: with no connection the local machine is "the server".

## Architecture notes

- The controller never reads the keyboard directly. `Player.simulate()` consumes a `PlayerInput` (move, look angles, sprint, crouch, lean). Humans fill it from the keyboard, tests fill it from code, and bots and the network will do the same.
- The player origin is at the feet. `Head` carries lean offset and pitch; `Camera` carries lean roll.
- Level geometry is built from boxes in code (`Greybox`), driven by the `ROOMS`, `WALLS` and `DOORS` tables at the top of `scripts/world/house.gd`. Door openings are cut automatically wherever a door sits on a wall. To move a wall or door, edit the table.
- Stairs collide as smooth ramps through the step noses; the visible steps are decoration. The controller cannot climb ledges.
- A door's authoritative data is `state` plus `swing_sign`. The panel angle is derived and animated on each machine.
- Physics layers: 1 = world (walls, floors, doors), 2 = players, 3 = hitboxes (hit only by weapon rays).
- `Arsenal` (a child of each player) owns trigger logic, ammo, spread and recoil. The owner picks each pellet's direction; only the server turns a shot into damage.
- Anything shootable exposes `take_hit(damage, zone, shooter)` and owns `Hitbox` areas that point back at it. The hostage will use the same interface.
- Recoil is a view offset added on top of the player's look angles, so it never fights the mouse.
- `Match` is the single authority on round state: phase, clock, score, hostage room, and who won and why. Everything else reports to it through signals (`Player.died`, `Hostage.killed`, `Hostage.extracted`). `Scoreboard` holds the pure score and side-swap rules.
- The two groups of players are "rosters" 0 and 1 for the whole match; which roster is Entry changes at the swap.
- Anything you can press F on is a node with `interact_prompt(player)` and `on_interact(player)`, optionally `on_interact_hold` and `on_crack`. Doors, hostage markers and the hostage all use it; the HUD prompt comes from the same call.
- Routes for bots and the hostage come from a small waypoint graph (`NavGraph`) generated from the door table plus hand-placed stair and ramp points. Rooms are convex, so any two points in a room connect directly. The hostage's route from each room is therefore fixed and predictable.
- Respawned players hold still for two physics ticks: teleports reach the physics server a tick late, and moving before that makes players collide with where others used to stand.
- Sound needs no network messages: each machine derives every sound from state it already has (player positions and stance, door states, shots it is shown, gadget events) and runs the propagation model for its own listener.
- Renderer is GL Compatibility: it runs on weak laptops and is enough for greybox.

## Tunables

All in `config/game_config.gd`. Current groups: player body, movement, lean, look, doors, combat (including the per-weapon table), teams, match, hostage, bots, gadgets, sound.

Map dimensions are not tunables; they live in `scripts/world/house.gd`.
