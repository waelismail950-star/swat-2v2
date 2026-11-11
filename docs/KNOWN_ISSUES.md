# Known issues and unfinished work

Updated at Milestone 8. Nothing here has been checked by a human player; start with [PLAYTEST.md](PLAYTEST.md).

## Decisions waiting on you
- **Best-of-5 cannot be side-fair.** With one swap after round 2, one roster plays Entry twice and the other up to three times. If one side turns out stronger, that matters. Options: keep it; swap every round; or play best-of-6 with a tiebreak. `swap_sides_after_round` is in the config.
- **One entry point per floor instead of two on the ground floor.** See DESIGN.md, "Why one entry per floor".
- **Whoever shoots the hostage loses,** instead of the hostage dying always being a Suspect win. See DESIGN.md.

## Not verified by a human yet
- **Nobody has heard the game.** There is no audio device here. Tests prove which sounds are made, how loud the model says they are, where they seem to come from and that the generated audio is valid and not silent. Whether it sounds right, whether direction is readable in headphones, and whether the volumes are sensible are all untested.
- **Multiplayer has only been run on one machine.** Automated tests cover a host and a client in one process, and two separate processes over localhost complete a whole match and agree on every round. It has not been run over a real LAN or the internet, and never with latency or packet loss.
- **The menu and lobby have never been clicked by a person.** They were checked by code and by rendered screenshots.
- **Gadget feel and balance.** Throw arc, fuse lengths, blind durations and the 4 s wedge force time are first guesses.
- **Movement, mouse and gun feel.** Speeds, lean, recoil, spread and timings are first guesses. Tests prove they match the config, not that they feel right. Mouse look has no automated test at all.
- **Door feel.** Swing speed, crack angle and reach are first guesses.
- **Round pacing.** An unopposed bot rescue takes 13-23 s and the clock is 150 s. Whether careful human rounds fill that time, or the house is simply too small, is unknown.
- **Map balance.** Suspected weak points to watch in playtests:
  - Kids room has a single door. It may be too strong a hostage room.
  - The Deck Door and the Front Door both open into a long hall; a Suspect at the far end of a hall sees the door open.
  - The stairwell is a blind U-turn. It may be too hard to push without a flashbang.
  - Entry spawns 4 m from the Front Door and Suspects spawn just inside it. Opening it the instant setup ends starts a fight at once.
- **Side balance.** Bot-versus-bot: a lone Entry bot wins 0 % against two guards, a pair 54 %, a pair entering on a flash 100 %. That supports "coordination beats rushing" but says nothing about humans who lean, listen and bait. The Study is the extreme case (0 % without a flash, 100 % with).

## Limitations
- **All audio is placeholder:** synthesised noise bursts and beeps, no recorded sounds, no music, no voices.
- **Reloading, weapon swapping and securing the hostage are silent.** So is a flashbang bouncing; only the throw and the bang are heard.
- **Sound paths use doorway waypoints, not true acoustics.** A sound heard through doors comes from the first doorway on your side. Two sounds in different places behind the same door seem to come from the same spot.
- **Walls and floors all leak the same amount.** One wall or three walls between you and a sound are treated alike.
- **Bots are deaf.** They react only to what they see.
- **Your own footsteps are played quietly** at a fixed level so you can tell which kind you are making.
- **Bots do not use gadgets,** though they are blinded by flashes like anyone else.
- **Flashbangs pass through players** and only bounce off walls, floors and doors.
- **The trip alarm sits right in front of the door camera's lens** and hides the middle of its view. That reveals the alarm, which is intended, but it also hides part of the room.
- **Forcing a wedged door shows no progress bar.**
- **Suspects cannot pick gadgets:** only two are built for them, so they carry both.
- **Not built:** drone ping, noise decoy, barricade. Each side has room for one more within the scope limit.
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
- **The Study and the Master bedroom are much harder for bots to take than the Kitchen and Kids room.** The cause is which way the hall door swings (an open door shields the entrant from one corner in some rooms and not others) and how close the guard posts are to the door. It may or may not matter to humans.
- **The lean pose looks crude.** The head shifts fully, the torso half, the legs not at all. The hitboxes match what is drawn, so it is fair, just ugly.
- **No aim-down-sights.** Hip fire only, by design for now.
- **Lean and crouch are hold-only.** No toggle option.
- **Mouse sensitivity is a config value,** not an in-game setting.
- **Stairs are ramps under the hood.** The controller does not step up ledges.
- **Doors do not push players.** A door stops against a body and waits. A player can stall a door by standing in its arc, though they cannot keep it closed.
- **Shotgun reloads the whole magazine at once. Reserve ammo is unlimited.**
- **Cosmetic:** thin light leaks under doors, jagged shadow edges, floor plans in docs/img rendered on a software renderer.

## Not started
Hostage self-escape (Milestone 9, locked until you have playtested). Polish (Milestone 10: real assets and audio, only if the game is fun).
