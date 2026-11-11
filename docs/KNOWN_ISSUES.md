# Known issues and unfinished work

Updated at Milestone 2.

## Not verified by a human yet
- **Movement feel.** Speeds, acceleration, lean distance and lean timing are first guesses. Tests prove they match the config, not that they feel right.
- **Mouse look.** Not covered by automated tests (the headless runner has no captured mouse). Needs a manual check: turning, pitch limits, sensitivity.
- **Door feel.** Swing speed, crack angle and reach are first guesses.
- **Map balance.** The layout is untested by humans. Suspected weak points to watch in playtests:
  - Kids room has a single door. It may be too strong a hostage room.
  - The Deck Door and the Front Door both open into a long hall; a Suspect at the far end of a hall sees the door open.
  - The stairwell is a blind U-turn. It may be too hard to push without a flashbang (M6).

## Limitations
- **Leaning has no body model.** Only the head and camera move. Until hitboxes exist (M3) there is nothing to see or shoot on a leaning player.
- **Lean and crouch are hold-only.** No toggle option.
- **Mouse sensitivity is a config value,** not an in-game setting.
- **Stairs are ramps under the hood.** The controller does not step up ledges; anything taller than a floor seam blocks it.
- **Doors do not push players.** A door stops against a body and waits. A player can stall a door indefinitely by standing in its arc, though they cannot keep it closed.
- **Anyone can open any door at any time,** including exterior doors. Locking exterior doors during setup arrives with round logic (M4).
- **Light leaks through door edges.** Thin bright lines on the floor near doors come from the 3 cm gap around each panel. Cosmetic.
- **Shadow edges are jagged** along some wall bases. Cosmetic, greybox lighting.
- **Screenshots in docs/img are rendered on a software renderer** from a debug camera; colours on a real GPU may differ slightly.

## Not started
Weapons, rounds, hostage, networking, gadgets, sound, bots (Milestones 3 to 9).
