# Playtest checklist

None of this has been played by a person yet. About 45 minutes covers it. Write down anything that feels wrong with **where** (room, door) and **what you expected**; that is enough for me to tell a bug from a tuning problem from a design flaw.

Every number mentioned here is in `config/game_config.gd`. Change it, restart, try again.

## 0. Start

- Solo: run `godot` in the repo folder, click **Play solo with bots**. Or `godot -- --solo`.
- Two windows on one PC: run it twice, **Host a game** in one, **Join** `127.0.0.1` in the other, then **Start match**.
- Wear headphones.

Keys: WASD, mouse, Shift sprint, Ctrl crouch, Q/E lean, left click fire, R reload, 1/2 weapons, F interact (hold on the hostage, hold on a wedged door), V crack door, G and T gadgets, N change gadgets (setup only), Esc frees the mouse.

## 1. Feel (5 minutes, solo, during setup and the first round)

| Try | Looking for | If wrong, change |
| --- | --- | --- |
| Walk, sprint, crouch-walk round the outside of the house | speeds feel deliberate, not sluggish or twitchy | `walk_speed`, `sprint_speed`, `crouch_speed`, `ground_accel` |
| Turn and look up and down | sensitivity is comfortable | `mouse_sensitivity_deg` |
| Stand beside the Front Door frame and lean with Q and E | you can see past the frame without stepping out; the lean is quick but not instant | `lean_offset`, `lean_time`, `lean_roll_deg` |
| Open, close and crack a door (F, V) | swing speed feels right; the crack gives a usable sliver of view | `door_swing_speed_deg`, `door_crack_angle_deg` |
| Fire each weapon at a wall, single shots and held | recoil is noticeable but controllable; the shotgun pause feels heavy | per-weapon `recoil_*`, `fire_interval` |
| Listen to your own footsteps at a crouch, walk and sprint | three clearly different levels | `noise_radius` step entries |

## 2. The core question (20 minutes, solo as Entry, rounds 1-2)

Bots guard the hostage room with shotguns. Try each approach at least twice and note whether you lived.

1. **Solo rush.** Sprint in through the nearest door of the hostage room. *Expected: you die almost every time.* If rushing works, the design has failed; tell me.
2. **Slice the pie.** Open the door, stay in the hall, lean to clear the room a slice at a time. *Expected: you can pick off a guard without stepping in.*
3. **Flash and enter.** Crack the door (V), throw a flashbang through the gap (G), go in on the bang. *Expected: guards are blind and you win the room.* Also throw one at a closed door once and see what it does to you.
4. **Door camera.** Hold T on the shut door before doing anything. *Expected: you learn where the guards are, and it changes what you do next.*
5. **Breaching charge.** Press N during setup until you carry one. Use it on the hostage room door, stand back, enter on the bang.
6. **Secure and escort.** Hold F on the hostage for 3 s, then walk it out. *Expected: it is slow and tense, and you have to stay close.*

Questions to answer afterwards:
- Did leaning and door work ever feel like the smart choice, or just slow?
- Could you tell where the bots were by sound before you saw them?
- Was the hostage ever in real danger from your own shots? It should be.
- Which hostage room was hardest? (My guess: Study and Kids.)

## 3. The other side (10 minutes, solo as Suspects, round 3 onward)

1. In setup, walk to a yellow floor marker and press F to move the hostage. Try a different room each round.
2. Wedge a door (G) and put a trip alarm inside another (T).
3. Hold the room. Note how long the bots take and which door they come through.

Questions:
- Did the wedge and alarm change where you stood?
- Does 25 s of setup feel like too much, too little, or right? (`setup_time`)
- Did the round clock (150 s) ever matter? (`round_time`)

## 4. Multiplayer (10 minutes, two windows, or two PCs on one network)

- Both windows show the same lobby; Switch team works; Start builds the match on both.
- Open a door in one window: it opens in the other.
- Shoot the other player: they take damage and go down on both screens.
- Throw a flashbang at the other window's player: their screen whites out.
- One secures the hostage and extracts: both show the same result and score.
- Close the joining window mid-round: the host carries on with a bot in that slot.

On two PCs over Wi-Fi, also note whether shots that looked on target missed. There is no lag compensation yet.

## 5. If something is off

| What you noticed | Most likely | First thing to change |
| --- | --- | --- |
| Fights end before you can react | time-to-kill too low | weapon `damage`, `headshot_mult` |
| Shotgun guards feel unfair | one-shot range too long | shotgun `damage`, `falloff_start`, `spread_deg` |
| Flashbang wins every room for free | blind too long | `flash_duration`, `flash_look_away_mult` |
| Flashbang never seems to work | fuse or throw wrong for the room sizes | `flash_fuse`, `flash_throw_speed` |
| You never hear anyone | radii too small, or doors muffle too much | `noise_radius`, `sound_closed_door_mult` |
| You always hear everyone | the opposite | same |
| Wedged door is a non-event / a brick wall | force time | `wedge_force_time` |
| Rounds end on the clock | clock too short or Entry too passive | `round_time` |
| Rounds are over in 20 s | house too small for the speeds | `walk_speed`, `sprint_speed`; tell me, the map may need to grow |
| Bots too easy / too hard | bot skill | `bot_reaction_time`, `bot_aim_error_deg` |

## What I already know from bots

`godot --headless --fixed-fps 60 res://tests/balance/probe.tscn` plays bots against bots and prints Entry's win rate by tactic. Latest run, 12 rounds per cell:

| Hostage room | One bot alone | Two bots together | Two bots entering on a flash |
| --- | --- | --- | --- |
| Kitchen | 0 % | 92 % | 100 % |
| Study | 0 % | 0 % | 100 % |
| Master | 0 % | 33 % | 100 % |
| Kids | 0 % | 92 % | 100 % |
| All | 0 % | 54 % | 100 % |

Read it with care. Bots walk straight through doors and never lean, so this measures the cost of *not* using technique. The flash in the third column is a stand-in (guards are blinded as the first bot reaches the door) and is perfectly timed every time. The spread between rooms comes from where the guard posts happen to be and which way each door swings, not from a deliberate difficulty curve.
