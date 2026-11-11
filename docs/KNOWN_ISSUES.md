# Known issues and unfinished work

Updated at Milestone 5.

## Decisions waiting on you
- **Best-of-5 cannot be side-fair.** With one swap after round 2, one roster plays Entry twice and the other up to three times. If one side turns out stronger, that matters. Options: keep it; swap every round; or play best-of-6 with a tiebreak. `swap_sides_after_round` is in the config.
- **One entry point per floor instead of two on the ground floor.** See DESIGN.md, "Why one entry per floor".
- **Whoever shoots the hostage loses,** instead of the hostage dying always being a Suspect win. See DESIGN.md.

## Not verified by a human yet
- **Multiplayer has only been run on one machine.** Automated tests cover a host and a client in one process, and two separate processes over localhost complete a whole match and agree on every round. It has not been run over a real LAN or the internet, and never with latency or packet loss.
- **The menu and lobby have never been clicked by a person.** They were checked by code and by rendered screenshots.
- **Movement, mouse and gun feel.** Speeds, lean, recoil, spread and timings are first guesses. Tests prove they match the config, not that they feel right. Mouse look has no automated test at all.
- **Door feel.** Swing speed, crack angle and reach are first guesses.
- **Round pacing.** An unopposed bot rescue takes 13-23 s, so the 180 s clock is probably far too generous and the house may be too small for it to matter. To be tuned in M8.
- **Map balance.** Suspected weak points to watch in playtests:
  - Kids room has a single door. It may be too strong a hostage room.
  - The Deck Door and the Front Door both open into a long hall; a Suspect at the far end of a hall sees the door open.
  - The stairwell is a blind U-turn. It may be too hard to push without a flashbang (M6).
  - Entry spawns 4 m from the Front Door and Suspects spawn just inside it. Opening it the instant setup ends starts a fight at once.
- **Side balance.** In a 16-round bot-versus-bot sample Entry won 10 and Suspects 6. Bots do not use technique, so this says little about human play.

## Limitations
- **No lag compensation.** Hits are tested against where the server sees players at that instant. Fine on a LAN; above roughly 50 ms latency you have to lead moving targets.
- **Movement is client-authoritative.** The server trusts each machine's position for its own player (it only refuses shots claimed from more than 1.5 m away from that position).
- **Remote players are smoothed, not interpolated between snapshots.** They trail their true position by about 40 ms plus latency, and can look slightly rubbery on a bad connection.
- **If the host leaves, the match ends.** There is no host migration. A client who leaves is replaced by a bot.
- **No joining a match in progress, no reconnecting.**
- **A door can sit at slightly different angles on two machines for a moment** if a player blocks it on one and not the other. State (open, cracked, closed) always matches.
- **No chat, no ping display, no player names in the HUD.**
- **Bots are crude.** They walk straight lines between waypoints, do not lean, crouch, crack doors or use cover, and can get briefly stuck on an open door before shuffling free. Entry bots know the hostage room. Suspect bots stand in the open at fixed posts.
- **If you die early, the round continues** until your bot teammate wins, dies or the clock runs out, which can be a long wait.
- **The hostage's route out of each room is fixed** (the shortest one). Entry cannot choose to extract another way.
- **The hostage ignores players physically.** Doors can swing through it and players can walk through it. This is deliberate, to prevent body-blocking, but looks odd.
- **Suspects can stand right behind the kneeling hostage** as a shield. A standing Suspect's head and shoulders are still exposed above it; a crouching one is fully covered from the front. Watch this in playtests.
- **Anyone can leave the house** once the round is live, including Suspects.
- **No spectator controls.** A downed player sees through one living teammate; there is no free camera.
- **No kill feed, scoreboard screen or names over heads.** Teammates are told apart from enemies by colour only (blue Entry, red Suspects, yellow hostage).
- **Spraying a carbine at a chest about 12 m away walks the rounds into the head.** Recoil levels off roughly one head-height above the aim point at that distance. Revisit in the balance pass (M8).
- **The lean pose looks crude.** The head shifts fully, the torso half, the legs not at all. The hitboxes match what is drawn, so it is fair, just ugly.
- **No aim-down-sights.** Hip fire only, by design for now.
- **No audio.** Gunfire, footsteps and doors are silent until M7.
- **Lean and crouch are hold-only.** No toggle option.
- **Mouse sensitivity is a config value,** not an in-game setting.
- **Stairs are ramps under the hood.** The controller does not step up ledges.
- **Doors do not push players.** A door stops against a body and waits. A player can stall a door by standing in its arc, though they cannot keep it closed.
- **Shotgun reloads the whole magazine at once. Reserve ammo is unlimited.**
- **Cosmetic:** thin light leaks under doors, jagged shadow edges, floor plans in docs/img rendered on a software renderer.

## Not started
Gadgets, sound (Milestones 6 and 7), balance pass (8), hostage self-escape (9, locked).
