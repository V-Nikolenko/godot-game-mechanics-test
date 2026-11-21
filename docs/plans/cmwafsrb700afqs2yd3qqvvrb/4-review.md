VERDICT: CHANGES_REQUESTED

# Review: t6 Carrier shell task plan (`3-plan.md`), round 1

I checked this plan against the epic plan (§2.1, §2.2, §2.6 including all of §2.6.4, §2.7, §2.8, §2.9, §2.11, §2.13 and §2.16) and against the code it relies on:
`base_enemy.gd`, `enemy_module.gd`, `modular_hull.gd`, `enemy_mover.gd`, `global/hazards/hazard_drift.gd`, `heavy_gunship/*`, `contact_profile.gd`,
`hurtbox_component.gd`, `health.gd`, `beam_behavior.gd`, `plasma_nova_module.gd`, `jamming_structure.gd`, `support_ship_brain.gd`, `anchor_idle.gd`,
`enemy_brain.gd`, `enemy_ai_harness.gd`, `test_enemy_module.gd`, `test_heavy_gunship.gd`, `test_base_enemy.gd`, `test_enemy_dual_mode.gd` and the
gate-time table in `tests/README.md`.

## What holds up

Most of the plan holds up. The scene follows the t4 template. Every part hurtbox sits within |x| ≤ 92 px, and no two part hurtboxes overlap; the hangar and
the core touch only at the corner (28, −28). The armoured-hull refusal follows the Ram's branch. Core exposure counts `destroyed_count([ENGINE, WEAPON,
HANGAR])`; `ModularHull` connects before the root, so `module_destroyed` fires before `_on_core_destroyed`.

The `emp_seconds_left()` seam is right: `apply_emp` sets `_emp_left` before `on_emp_started()` (`base_enemy.gd:182-189`). With `hazard_resistance` 1.0,
both the slow factor and the drift come out exactly zero (`enemy_mover.gd:231`, `hazard_drift.gd:15`). D5 (`acceleration` / `braking` 0 in CROSS) makes
the crossing speed instant. The support filter line and the roster rows match the gates as written. D2, D4, D6 and D7 are fine.

D3 (the list as a hold deadband) is a defensible reading of an under-specified epic line. One correction to its reasoning: an offset added to the facing
target could never exceed the mover's turn cap (`enemy_mover.gd:267-269`). So the real argument is that an offset makes a fixed lean, not a drift, and
the deadband is what gives the drift the row asks for. Keep D3.

D1 (root body on layer 0, mask 0) is the right choice, but its stated reason is weak; see finding 13.

The blocking problems are below.

## Findings

### 1. HIGH: in Assault, losing an engine during PANIC slows the crossing
**Where:** `3-plan.md:81` and `:111`, checked against `enemy_mover.gd:228-229`.

**Problem:** `_update_engines()` writes `max_speed = config.max_speed · speed_factor()` whenever the phase is not CROSS. In Assault, PANIC "is the CROSS
motion with the phase reading PANIC". So an engine destroyed after the core opens caps the mover at 70 × 0.8 = 56 px/s, or 28 px/s with no engines.

- This breaks the constant-90 px/s requirement.
- It also breaks t12's fixed Assault life (§2.13, constraints 1 and 2), and t7's "Assault: unchanged crossing speed" (§2.7).
- Row 11 cannot catch it: its PANIC case reaches PANIC after the engines it kills. On the tick the third part dies, `_update_engines()` still sees CROSS.
- In real play the player keeps shooting after the core opens, and the engines are the easiest targets.

**Required change:**
- Decide every mover-limit write by *mode* (an `_assault` flag fixed in `_start()`), never by phase. In Assault, `max_speed` stays `assault_max_speed`
  and `acceleration` / `braking` stay 0 in every phase.
- Add a row: Assault, core exposed (PANIC), then destroy `EnginePort` and then `EngineStarboard`. `dy` stays 1.5 px every tick and `mover.max_speed`
  stays 110.

### 2. MEDIUM: a second EMP during the window stops the crossing
**Where:** `3-plan.md:112`, checked against `base_enemy.gd:178-189`.

**Problem:** `apply_emp` calls `on_emp_started()` only when a window *starts*. A refresh only extends `_emp_left` (`maxf`). The boost committed at the
start runs out at the original duration. For the rest of the window the brain is not ticked, so the mover steps with no request. With D5's
`acceleration` 0, the velocity drops to zero at once and the carrier sits still until the window ends.

The player's own EMP Blast (5 s window, 15 s cooldown) cannot cause this alone. Two sources overlapping can: a placed EMP mine, an `EmpZone` with
`TARGET_ALL`, or the player's blast. That contradicts "an EMP does not stop the crossing".

**Required change:**
- Re-commit the boost whenever the window grows. For example, `Carrier.apply_emp()` calls `super`, then in Assault re-boosts to `emp_seconds_left()`.
- Add a row: a 5 s EMP, then a second 5 s EMP applied 3 s in. `dy` = 1.5 px on every tick through 8 s and after.

### 3. MEDIUM: the free-below check is skipped during an EMP
**Where:** `3-plan.md:104`, checked against `base_enemy.gd:129-134`.

**Problem:** The check that frees the carrier below the rect runs in the brain's tick, and the brain is not ticked during an EMP window. A carrier EMP'd
while near the bottom is freed up to 5 s (450 px) late. That contradicts "its Assault life is therefore fixed" (§2.6.3) and t12's "the crossing is
EMP-proof, so no EMP term" (§2.13). The life would gain an EMP term after all.

**Required change:**
- Run the free check where an EMP cannot skip it. For example, `Carrier._physics_process(delta)` calls `super._physics_process(delta)` and then checks.
  This is a position read plus `queue_free()`, so it does not touch the single-writer gate.
- Extend row 13: with an EMP applied 1 s before the edge, the carrier is freed on the same tick as without one.

### 4. MEDIUM: row 10's silhouette count contradicts the plan's own core-plating swap
**Where:** `3-plan.md:168-170`.

**Problem:** The row destroys four outer parts, so the third loss opens the core. `_open_core_plating` then swaps the core sprite to `core_open_texture`.
The number of sprites "showing their intact texture" therefore goes 7 → 6 → 5 → **3** → 2, not 7 → 6 → 5 → 4 → 3. The row fails against the design.

**Required change:**
- Define the silhouette precisely. One option: the set of parts whose sprite shows `wreck_texture` grows by exactly one at each loss. Another: count
  intact textures with the core excluded.
- Add an explicit check that the core sprite shows `core_open_texture` from the frame after the third loss, and `wreck_texture` after `Core.destroy()`.
  Nothing else in the test list checks the plating art that §2.6.2 asks for.
- Optional: have `_open_core_plating` do nothing on a destroyed core, so a same-frame scripted kill cannot overwrite the wreck texture.

### 5. MEDIUM: the gate-time estimate is missing, and its fallback targets the wrong rows
**Where:** `3-plan.md:185-187`, checked against `tests/README.md:433` (16× rule), `:682` and `:687`.

**Problem:** As written, the real-physics rows add up to about 2,000 frames:

| Row | Frames |
|---|---|
| Row 3: bullet + 120-frame beam | ≈ 140 |
| Row 4: three combinations × (three counts × (bullet ≈ 20 + beam 120) + after exposure ≈ 140) | ≈ 1,680 |
| Row 6 | ≈ 140 |
| Row 14 | a few dozen |

A frame-counted file is paced by the tick rate, so at 8× this is about 4.1 s of wall time. That is over both the 2.0 s allotment and the 3.0 s
escalation line, before the hand-ticked rows are counted. The named fallback ("the turn rows share one run per engine count") targets hand-ticked rows,
which cost almost nothing in wall time.

**Required change:** Put the frame budget in the plan, with these levers:
- At each count, run the bullet and the 2 s beam in the same 120-frame window.
- Fold rows 3 and 6 into one combination's carrier, at count 0.
- Run the file at 16×. Phase 10 t1's rule allows it for frame-counted rows, and no row here has a tolerance smaller than an idle frame.
- State the expected file time (about 1,450 frames at 16× ≈ 1.5 s, plus about 0.5 s of hand-ticked CPU).

None of these cuts an assertion.

### 6. MEDIUM: row 3's beam-on-bare-hull check cannot fail
**Where:** `3-plan.md:153-154`, checked against `beam_behavior.gd:93-101`.

**Problem:** `BeamBehavior` picks a target only when the target node's *centre* lies within 12 px of the beam line. The root's centre is the core's centre
(0, 0). A beam "across bare hull" away from that centre never targets the root at all, so "hull Health unchanged" passes even with no
`_on_received_damage` override.

**Required change:**
- Aim the hull beam through the root's centre. Assert that `armor_deflected` fires during the hold (count > 0), with Health unchanged.
- For the nova, assert `armor_deflected` fires exactly once.
- Row 4's core beam meets the root too; assert the same there.

### 7. MEDIUM-LOW: the physics-flush exposure path the Risks section relies on is not tested
**Where:** `3-plan.md:188`.

**Problem:** Every part kill in row 4 is a scripted `destroy()` from test code, at idle time. The risk the plan names (a kill inside a physics flush,
then a deferred `set_vulnerable`) is therefore never exercised.

**Required change:** Add a case where the third part is killed by real bullets, inside a physics flush, for example `GunStarboard` (160 HP takes four
50-damage bullets). Assert:
- the core is still locked during that physics frame;
- the next bullet at the core is consumed, and the core loses its damage.

### 8. LOW-MEDIUM: row 7 is marked "both" but cannot run in Assault
**Where:** `3-plan.md:161`.

**Problem:** In Assault the carrier is in CROSS, faces straight down every tick and never turns. A run with no supervisor may "fix" this by forcing
SCREEN in the Assault harness, which tests nothing real.

**Required change:** Mark row 7 as Open Space only. Name row 12's sway caps (30 / 15 / 3 px/s) as the Assault half of "module death changes movement",
which is how the acceptance criteria read in both harnesses.

### 9. LOW-MEDIUM: the PANIC row's final-position check is ill-defined
**Where:** `3-plan.md:165-166`.

**Problem:** A 120 px/s chaser overtakes a carrier moving at 70 px/s or less (less with engines lost) within seconds. Once the two overlap, "on the far
side of the anchor from the player" is undefined, and the target point flips as the player moves. The row is flaky by construction.

**Required change:**
- Keep the chaser for the leash bound only (never beyond `leash + 50`), as §2.6.4 states it.
- Prove the far-side retreat with a still player at a fixed offset from the anchor, for example anchor + (500, 0). Assert the hull ends within a stated
  tolerance of `anchor − (900, 0)`.
- Say which three parts are destroyed to open the core, since that sets the speed factor.

### 10. LOW: the sway seeks the edge of the firing arc
**Where:** `3-plan.md:105-108`.

**Problem:** `tx` is the edge of the arc, so the hull moves toward that edge even when the player is already well inside it. The rows still pass because
the ±30 px leash clamps it.

**Required change:**
- Use an edge with an inward margin, or hold `tx = x` when the player is already inside a live battery's arc.
- Record that `SWAY_ARC_HALF_DEG` 75 must be read from the battery slot's traverse once t7 adds it, so there is one source.

### 11. LOW: two new behaviours have no test
- **Engine plume.** "Engine plumes go out with the engine" (§2.6.3, §2.9) is new code (`CarrierEnginePlume`) with no row. Add one assertion: after
  `EnginePort.destroy()`, its `Light` is not visible and `EngineStarboard`'s still is.
- **`homing_point()`.** No row covers it either. A cheap optional row: with the core locked, `homing_point(from below)` returns an engine or gun centre,
  never the core.

### 12. LOW: smaller test-list gaps
- **ENEMIES_CLEARED guard.** The plan adds the "no Carrier in an `ENEMIES_CLEARED` section" row in `test_engagement_deadline.gd` (line 183) without the
  boundary §2.13 attaches to it ("a synthetic section with one fails"). Either add the boundary now or leave the whole row to t12.
- **Dual-mode spawn row.** Row 15's spawn row in `test_enemy_dual_mode.gd` does not say what it asserts. Suggested: Open Space with `start_engaged` →
  SCREEN; Assault → CROSS and `y` grows.
- **Row 4's third part.** The third destroyed part of each combination is not named. Naming it, for example `HangarStarboard` for the {GunPort,
  HangarPort} combination, shows that "any 3 of the 6" really is any.

### 13. LOW: D1's stated reason is wrong
**Where:** `3-plan.md:131`, checked against `beam_behavior.gd:64-71` and the scenes' root bodies.

**Problem:** The beam's block ray would not stop on a layer-1 hull anyway: `is_laser_blocking()` false already handles that. The real context:
- Every other enemy root, the Gunship and the Ram included, is on the default layer 1.
- The player body (layer 4, mask 1) therefore collides with them.

Layer 0 is still right: it matches the epic's "mask 0, ploughs through" and the station.

**Required change:** Record the actual reason and the consequence in DECISIONS. The player can fly onto the hull. Contact deals 15 damage and one
220 px/s shove only on *entry* (`HurtBox._on_area_entered`, `ContactProfile._on_contact`). Hugging the hull is what t7's anti-approach pulse punishes.

## Summary of required changes before approval

Findings 1–9 must be fixed in the plan. Findings 10–13 should be folded in while editing.

- **Finding 1:** a mode-keyed (not phase-keyed) mover-limit rule in Assault, with an engine-loss-in-PANIC row.
- **Findings 2 and 3:** the EMP refresh and the free-below check made EMP-proof, each with a row.
- **Finding 4:** row 10's silhouette defined correctly, plus a check of the core-plating texture.
- **Finding 5:** a real gate-time budget: concurrent bullet and beam, shared carriers, 16×.
- **Findings 6–9:** row 3's beam and nova checks able to fail, a physics-flush exposure case, row 7 scoped to Open Space, and a deterministic PANIC row.

## Round 2

VERDICT: CHANGES_REQUESTED

I re-read the revised `3-plan.md` (lines 1–256) against the same code, and added a check of `mining_laser.tres` (`beam_dps` 12),
`beam_behavior.gd:93-101` and `:148-156`, `player_base.gd:178-195` and `player_ship.gd:268`.

### The round 1 findings

All 13 are fixed. Only finding 5 brought new trouble, described below.

| # | Status | Where it is fixed and why it holds |
|---|---|---|
| 1 | Fixed | A mode flag fixed in `_start()` drives every mover-limit write (`3-plan.md:83-87`, `:92`, `:125`). Row 15 kills both engines during Assault PANIC and asserts `max_speed` stays 110. |
| 2 | Fixed | The `apply_emp` override re-commits the boost when the window grows (`:69-71`, `:126-128`). The double-EMP case is in row 15. `jamming_structure.gd:71` is the precedent for the override. |
| 3 | Fixed | The free check moved to the root's `_physics_process` after `super` (`:72-75`). A position read plus `queue_free()` is outside the single-writer gate's patterns (`test_enemy_mover_single_writer.gd:35-37`). Row 17 covers the EMP case. |
| 4 | Fixed | The silhouette is now the set of parts showing `wreck_texture`, and the `core_open_texture` and core wreck-texture checks are explicit (rows A4, 9, 14). `_open_core_plating()` skips a destroyed core (`:68`). |
| 5 | Fixed, with a new problem | 16×, concurrent windows and an approximate 550-frame budget (`:167-193`, `:235`). The budget arithmetic is plausible. But sharing one carrier per combination brought in the problem in finding R2-1. |
| 6 | Fixed | The beam is aimed through the hull centre and `armor_deflected` is asserted for the beam and the nova (`:174-178`). |
| 7 | Fixed | Row A3 kills carrier C's third part with real bullets inside a physics flush. See R2-2 for a robustness note and R2-1 for its HP arithmetic. |
| 8 | Fixed | Row 10 is Open Space only; the Assault half is the sway caps. |
| 9 | Fixed | Row 13 uses a still player for the far-side check and the chaser for the leash bound only; the three parts are named. |
| 10–13 | Fixed | |

### New findings

#### R2-1. MEDIUM: in the shared scenario, the novas and one beam wear down the open parts, so row A passes by luck or fails
**Where:** `3-plan.md:173-188`, checked against `beam_behavior.gd:93-101` and `mining_laser.tres`.

**Problem 1: the novas.** Every nova hits every live part on the map, so each nova takes 50 HP from every open part on every carrier. Row A fires four
novas: at counts 0, 1 and 2, and after exposure.

**Problem 2: the hangar beam.** On carrier A, the hangar beam is a `BeamDriver` 300 px below `HangarPort` firing up, along local x 60. It also burns
every part whose centre lies within 12 px of that line: `GunPort` (64, 40) and `EnginePort` (56, −116), both 4 px off. Over 120 frames the mining laser
does about 55 damage (12 dps, heat rising to 3× at 0.7/s).

**What that does to the windows:**

- **Carrier A, `GunPort`:** 160 − 55 (beam) − 50 − 50 (novas 0 and 1) leaves about 5 HP, so the count-2 nova kills it. The core then opens from
  the nova, and window 3's scripted `destroy()` does nothing. The count-2 checks happen to come before that nova, so the row passes only by a margin of
  about 5 HP. Any small change to the beam's heat or damage, or to `_DAMAGE`, kills `GunPort` at the count-1 nova. The scripted count-2 destroy then
  becomes the third loss, and the count-2 "core still locked" checks fail for a reason far from the code under test.
- **Carrier C, `GunPort`:** it has 10 HP left when row A3's "four real bullets (160 HP, 4 × 50)" arrive. The first bullet kills it, so the row's
  arithmetic is wrong.
- **The hangar bullet:** if it is fired from below like the beams, it meets the vulnerable `GunPort` first and is consumed there. It never reaches
  `HangarPort`, so "`deflected` grows" fails outright.

**Required change:**
1. Aim the closed-hangar bullet and beam so they cross no other part's hurtbox or centre. For example, fire them horizontally from outboard along
   local y −56: a `BeamDriver` rotated −90° at `HangarPort` + (300, 0), firing −x. That line crosses only the two locked hangars, and carrier A is the
   leftmost hull, so it meets no other carrier.
2. Write the HP ledger into the plan. Each nova takes 50 from every open part. A gun has 10 HP before the post-exposure nova and an engine has 30, and
   the post-exposure nova destroys them; no row reads them after that.
3. Add a guard assertion at every window: `destroyed_count([ENGINE, WEAPON, HANGAR])` equals that window's count on every carrier. An unplanned kill
   then fails at the window where it happens, with a clear message.
4. Restate row A3 as: "carrier C's `GunPort`, alive at 10 HP, is killed by a real bullet inside a physics flush (all the bullets fired with it are
   consumed: a part killed this frame still consumes)", not "160 HP, 4 × 50".

#### R2-2. LOW: row A3's "first observed frame" depends on engine-internal ordering
**Where:** `3-plan.md:182-184`.

**Problem:** The row reads `Core.is_vulnerable()` after `await physics_frame`. Its claim that the deferred `set_vulnerable` is still pending then rests
on an ordering inside Godot's main loop: area queries flushed, then `physics_frame` emitted, then the message queue flushed. An unattended run that
finds a different order has no good way out.

**Suggested change:** Make it deterministic. Connect a test handler to C's `GunPort.destroyed`; it runs inside the flush, after `ModularHull` and the
carrier have handled the kill. Assert there that `is_core_exposed()` is true and `Core.is_vulnerable()` is false, then assert the core is vulnerable
after the next `physics_frame`.

#### R2-3. LOW: row 7's `homing_point()` probe point is underspecified
**Where:** `3-plan.md:198-199`.

**Problem:** "From right above the core" (−y, the stern side) is ambiguous. From about 60 px or more above, the engines at (±56, −116) are nearer than
the core, so `homing_point()` correctly returns an engine.

**Suggested change:** Name the probe point, for example core + (0, −20), or one inside the core's hurtbox.

#### R2-4. LOW: row 9 never reaches the `_open_core_plating()` guard
**Where:** `3-plan.md:201`.

**Problem:** Row 9 destroys a core that was never exposed, so the destroyed-core guard in `_open_core_plating()` (`:68`) never runs.

**Suggested change:** If the guard is meant to be pinned, expose the core and `destroy()` it in the same frame before the deferred plating call runs,
then assert the sprite shows `wreck_texture`.

### Required for approval

Fix R2-1; it is a small edit to section A. R2-2 to R2-4 are recommended. Nothing else in the revision needs to change.

## Round 3

VERDICT: APPROVED

I checked the "Review round 2 — what changed" section (`3-plan.md:258-275`) against `enemy_module.gd`, `modular_hull.gd`, `beam_behavior.gd:93-101`,
`base_enemy.gd:319-334` and the scene's part layout.

### R2-1: fixed
- **The new hangar line hits only the hangars.** A shot along local y −56 from (360, −56), firing −x, crosses no other part:
  - The only part centres within 12 px of the line are the two hangars, at (±60, −56).
  - The core (y −28..28), the guns (y 16..64) and the engines (y −140..−92) all stay at least 28 px off it.
  - The root's centre is 56 px off, so the beam does not target it.
  - The bullet crosses the root hurtbox, `HangarPort` and `HangarStarboard`, all deflecting, so `deflected` on `HangarPort` grows as the row says.
  - Carrier A is the leftmost hull, and the driver at world x ≈ 660 sits between A and B (B's hull spans x 812–988), so the 1,200 px ray meets no
    other carrier.
- **The other beams no longer burn other parts.** The core beam runs along local x 0 and crosses only the core and the root. With the hangar beam moved,
  no beam crosses an open part.
- **The ledger holds.** Each window costs an open part at most one 50-damage nova, and every window ends by restoring each live open part. Every gun is
  therefore at 160 HP when window 3 starts, and row A3's four 50-damage bullets fired together kill carrier C's `GunPort` on the fourth hit, inside one
  physics flush; all four are consumed.
- **The per-window guard is in.** `destroyed_count([ENGINE, WEAPON, HANGAR])` is asserted at each window (0, 1, 2, 3), so an unplanned kill now fails
  where it happens.
- The restore (`health.set_health(max_health)` on part `Health`) is a test-side write that no production listener reacts to beyond the sparks. The core
  is never restored after exposure.

### R2-2: fixed
`ModularHull` connects to `GunPort.destroyed` in its `_ready()`, before the test does. Godot calls a signal's connections in connection order, so a test
handler on that signal runs after `ModularHull` has re-emitted `module_destroyed` and after the carrier has queued its deferred `set_vulnerable`. Inside
the handler, `is_core_exposed()` reads true and `Core.is_vulnerable()` reads false, every time.

### R2-3: fixed
From local (0, 20):

| Part | Distance |
|---|---|
| Core | 20 px (locked, so skipped until exposure) |
| `GunPort` and `GunStarboard` | √(64² + 20²) ≈ 67.1 px each, an exact integer tie |
| Engines | ≈ 147 px |

`homing_point()` uses a strict `<`, so the earlier part in tree order wins the tie: `GunPort`, as the plan says. After exposure, the core wins at 20 px.

### R2-4: fixed in intent, with one change the implementer must make
**The problem as written.** The row asks for the core sprite's texture "after the next frame". But destroying the core runs `_on_core_destroyed` →
`health.set_health(0)` → `BaseEnemy._on_health_changed` → `queue_free()` in that same call. By the next frame the carrier, the core and its `Sprite`
are freed, so the assertion would read a freed instance.

**The change.** Make the guard observable without outliving the carrier, using either of these:
- connect a recorder to the core `Sprite`'s `texture_changed` signal before the destroys, await one frame, then assert the recording never shows
  `core_open_texture` after `wreck_texture`; or
- call `_open_core_plating()` directly on the destroyed core in the same frame and assert the texture is still `wreck_texture`.

The intent is unchanged and nothing in the design is affected, so this does not block approval.

### Summary
All round-1 and round-2 findings are resolved, and the fixes add no design problem. The only open item is the test mechanics of R2-4, described above,
which the implementer must apply.
