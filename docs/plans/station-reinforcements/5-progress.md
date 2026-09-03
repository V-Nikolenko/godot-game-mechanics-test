# Progress — Station reinforcements (EPIC sub-item 4b)

- [x] **Step 0 — round-2 review + plan corrections.** Round 1 was `CHANGES_REQUESTED`; a previous
      cycle wrote Revision 2 but never ran the re-review. Dispatched it: **round 2 = `APPROVED`**,
      appended to `4-review.md` below a `---` (round 1 left intact). Folded its four non-blocking
      findings and the nits into `3-plan.md` as **[R3]**, and corrected `2-research.md`, which round
      1 had also asked for and which had been missed:
      - `2-research.md` F5 — half-extent 67 → **37**, margins re-derived to **777 / 397**, the
        "±420 was insufficient" claim replaced with an honest "±440 is the round number".
      - `2-research.md` F2 — popcorn list swapped `ram_ship` → `fighter`, with the mask defect
        recorded.
      - N1 — the bullet-killable citation is `base_enemy.gd:25` (runtime mask 1121), not the
        authored `light_assault_ship.tscn:83` that `BaseEnemy._ready()` overwrites.
      - N2 — test 10 must restart the timer before `armor_broken` or its `is_stopped()` is vacuous.
      - N3 — test 17 must `set_process(false)` and read `_combo` directly.
      - N4 — the density risk now carries the real FORWARD-mode figures (0.3 s / 420 px/s).
- [x] **Step 1 — `SpaceStationConfig`.** Three fields with doc comments:
      `reinforcement_first_delay` 8.0, `reinforcement_interval` 10.0, `reinforcement_max_alive` 4.
      Added to `space_station_config.gd` and `space_station_config.tres`.
- [x] **Step 2 — test file first.** `tests/integration/test_station_reinforcements.gd`, 18 cases.
      Watched it fail: `Parse error` / "does not extend GutTest", because `StationReinforcements`
      did not exist yet.
- [x] **Step 3 — the node.** `assault/scenes/enemies/space_station/station_reinforcements.gd`
      (`uid://jfdcv6l6phrr`). Config copy, squad table via `WaveBuilder`, one-shot `Timer`,
      `_on_timer_timeout()`, `spawn_next_squad()`, `_spawn_entry()`, whole-squad cap, `_stop()` on
      both `armor_broken` and `died`.
- [x] **Step 4 — scene wiring.** `Reinforcements` `Node2D` added to `space_station.tscn` as the
      fourth sibling behaviour node, `load_steps` 16 → 17, with a comment recording why the ships
      are siblings of the station rather than children.
- [x] **Step 5 — green.** 18/18 in the new file, then the whole suite.
- [x] **Step 6 — gate.** `bash /agent/verify.sh` → `GATE PASS`.
      **24 scripts / 232 tests / 868 asserts**, up from 23 / 214 / 767.
- [x] **Step 7 — docs + backlog.**

**Resume at:** nothing — complete.

## Deviations from plan

One, and it changed a test rather than the design.

**Test 11 (`died` stops reinforcements) needed a disconnect to be meaningful.** The plan described
it as "kill the core, then `spawn_next_squad()` adds nothing". That does not work as written:
`space_station.gd:124-130` refuses *all* core damage while a turret lives, so the only route to
`died` runs through `armor_broken` — which already stops the node. The case as planned would have
passed without the `died` connection existing at all.

The shipped case unhooks `armor_broken` from `_stop` first, asserts the spawner is still running
(the precondition that makes the rest discriminate), then kills the core and asserts both that no
squad spawns and that the timer is stopped. `died` is genuinely the backstop it claims to be, and
the test now fails if it is removed.

## Also worth knowing

- `spawn_next_squad()` **advances the cycle even when the cap skips the squad**. Not in the plan
  either way. The alternative — hold the index — would mean a capped fight re-attempts the same
  edge every interval and the rotation freezes on one side until the player clears the screen.
  Advancing costs the player a squad and keeps the LEFT→RIGHT→BOTTOM→TOP rhythm intact, which is
  the property research finding 3 is about. Recorded here rather than left implicit.
- `reinforcement_lifetime` (7.0 s) is an `@export` **on the node**, not a config field, for the
  same reason `laser_emitter_radius` and the gunnery `spawn_radius` values are: it is derived from
  the squad geometry sitting next to it in the same file, not a tunable stat.
