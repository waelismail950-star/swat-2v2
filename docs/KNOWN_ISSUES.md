# Known issues and unfinished work

Updated at Milestone 1.

## Not verified by a human yet
- **Movement feel.** Speeds, acceleration, lean distance and lean timing are first guesses. Tests prove they match the config, not that they feel right.
- **Mouse look.** Not covered by automated tests (the headless runner has no captured mouse). Needs a manual check: turning, pitch limits, sensitivity.

## Limitations
- **Leaning has no body model.** Only the head and camera move. Until hitboxes exist (M3) there is nothing to see or shoot on a leaning player.
- **Lean and crouch are hold-only.** No toggle option.
- **Mouse sensitivity is a config value,** not an in-game setting.
- **The test room is throwaway.** It is replaced by the house in M2. Lighting is flat and overbright.
- **Stairs must be ramps.** The controller does not step up ledges; anything taller than a floor seam blocks it.

## Not started
Doors, weapons, rounds, hostage, networking, gadgets, sound, bots (Milestones 2 to 9).
