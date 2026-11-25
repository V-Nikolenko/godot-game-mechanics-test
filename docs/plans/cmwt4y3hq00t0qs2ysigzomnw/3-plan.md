# t16: Space Fortress geometry weapons (task plan)

The approved design is the epic plan `docs/plans/cmug256so0031m52wbxomst72/3-plan.md` §2.7.2–§2.7.7 B, with §2.5.5 (the §25 row), §2.5.6 (EMP and the fade tick),
§2.6 (spins) and §2.16 (numbers). This file does not redesign it. It fixes the points the epic plan leaves to the implementer, the build order and the test rows.

## Problem
Today the fortress only shoots from its five batteries. The boss's shape should be its weapon: from `shields_exposed`, hull spokes light up and the hull spins
to sweep them round; from `core_exposed`, an expanding ring with two gaps pushes the player outward (arena control); in `critical`, the core spits a precessing
bullet ring that leaves no permanent safe lane. Every one of these has to be fair to dodge, and the Assault fight has to stay under a bullet-density ceiling the
station set, measured rather than estimated.

## Design (only what the epic plan leaves open)

**Config** (`space_fortress_config.gd/.tres`, new flat group `Geometry weapons`): `spoke_count` 2, `critical_spoke_count` 4, `spoke_period` 8.0,
`critical_spoke_period` 6.0; `ring_period` 6.0, `critical_ring_period` 3.5; `core_ring_period` 2.0, `core_ring_count` 12, `core_ring_damage` 10,
`core_ring_speed` 210.0, `core_ring_spawn_radius` 60.0, `core_ring_step` 0.24. Beam and ring tuning stays in their scenes.

**Scenes** (both in `assault/scenes/enemies/space_fortress/`, the `carrier_pulse_ring.tscn` precedent, UID-less ext_resources):
- `fortress_spoke_beam.tscn`: `instance=` of `enemy_beams/beam.tscn`. It authors **every** export the gates or the fortress read: `kind` BEAM, `telegraph_seconds`
  1.2, `commit_seconds` 0, `active_seconds` 2.5, `fade_seconds` 0.15, `ignite_grace` 0.1, `length` 900, `hit_half_width` 12, `draw_half_width` 16,
  `tip_grace_px` 24, `telegraph_width` 4, `damage` 14, `rehit_interval` 0.55, `blocked_by_cover` true, `registers_hazard` true.
- `fortress_pulse_ring.tscn`: `instance=` of `enemy_beams/energy_ring.tscn`. It authors `telegraph_seconds` 1.0, `fade_seconds` 0.15, `ring_speed` 300,
  `max_radius` 640, `band` 24, `gap_count` 2, `gap_deg` 50, `gap_spin_deg` 30, `damage` 14, `telegraph_width` 4.
- `space_fortress.tscn` gains `HullBeams` (Node2D) with `Spoke0` (0, −176) rotation −90°, `Spoke1` (0, 176) +90°, `Spoke2` (176, 0) 0°, `Spoke3` (−176, 0) 180°.
  Each holds a `Beam` instance of the spoke scene at its origin, unrotated, so the beam points outward along the emitter's local +X. A `PulseRing` instance of
  the ring scene sits at the root origin.

**Root (`space_fortress.gd`)**
- `_ready()` builds `CoreRingPool` in code: `BulletPool.new()`, `name`, `bullet_scene` = `enemy_bullet.tscn`, `pool_size` = `EnemyRounds.pool_size_for(core_ring_count,
  life, core_ring_period)` with `life` = min(`max_time`, `max_distance` / `core_ring_speed`) read from the scene's `ProjectileLifetime` through
  `EnemyBeamScenes.export_of_scene` (18.0 / 2400.0 are the fallbacks). That is 72 at the shipped values. Then `add_child`. It calls
  `brain.bind_geometry(spokes, ring, pool)`, which runs `setup(self, owner_group)` on each spoke and on the ring.
- `_physics_process(delta)`: `super(delta)`; then, if `is_ai_suspended() or is_emp_disrupted()` (the brain did not tick), `brain.tick_fades(delta)`. That ticks each
  spoke and the ring **only while it is in FADE**, so a cancelled attack reaches OFF with no `Timer`.
- Accessors for tests and docs: `spoke_beams() -> Array[EnemyBeam]`, `pulse_ring() -> EnergyRing`, `core_ring_pool() -> BulletPool`.

**Brain (`fortress_brain.gd`)**: per-boss-phase settings written in `on_boss_phase()` (these are the snapshot fields):

| boss phase | spokes (count, period) | ring pulse (armed, period) | core ring (armed, period) |
|---|---|---|---|
| batteries | 0, 0.0 | false, 0.0 | false, 0.0 |
| shields_exposed | 2, 8.0 | false, 0.0 | false, 0.0 |
| core_exposed | 2, 8.0 | true, 6.0 | false, 0.0 |
| critical | 4, 6.0 | true, 3.5 | true, 2.0 |

- **Clocks.** A weapon armed for the first time starts its countdown at its period, so the first shot comes one period after the phase begins (the station's
  "one interval after the handover" rule). When a period shortens on entering `critical`, the countdown becomes min(left, new period). A countdown runs only
  while the brain ticks and `is_engaged()`. When it reaches ≤ 1e-6 the weapon fires if the brain may fire (a target, and in Assault the hull centre inside
  `view_rect()`, the batteries' `in_view` rule; an EMP never reaches here because the brain is not ticked). Then `left += period`, floored at 0. If the brain may not
  fire, the countdown waits at 0.
- **Tick order** inside `tick()`, after `_tick_weapons()`: first tick every spoke and the ring (`tick(delta)`, the only clock, which also finishes a volley started
  earlier), then advance the clocks and start new attacks (a new beam's first tick is the next frame), then the spin bookkeeping.
- **Spoke volley:** `start()` on `Spoke0`, `Spoke1` (count 2) or on all four (count 4); the volley's spokes are remembered. **Spin, edge-triggered
  (review B1):** a remembered volley spoke turns ACTIVE while `_volley_spinning` is false → `begin_spin(0)` (it alternates) and `_volley_spinning = true`; once
  no remembered spoke is ACTIVE any more while `_volley_spinning` → `end_spin()`, `_volley_spinning = false`, volley forgotten. A spin started by hand with
  `begin_spin()` (t6's public seam, used by `test_spins_volley_alternating_and_critical_continuous`) is never ended by this bookkeeping. So the hull spins only
  while a volley's beams are lit.
- **Ring pulse:** `ring.start(rng.randf_range(0.0, 360.0))` (the Carrier's gap draw).
- **Core ring:** a `RadialAttackPattern.new()` built in `bind_geometry()` from the config (`arc` TAU, `aim_at_player` false). Each ring sets
  `base_angle` = the running angle, fires `pattern.fire(actor, pool)`, then the angle becomes `fposmod(angle + core_ring_step, TAU)`.
- `on_emp_started()` additionally cancels every spoke and the ring, `end_spin()`s and leaves the core ring alone (its bullets in flight keep flying; the
  clocks freeze because the brain is not ticked). `silence()` (death) cancels the spokes and the ring, `end_spin()`s and runs `cancel_active()` on the core-ring pool.
- `tick_fades(delta)`: ticks each spoke / the ring in FADE.
- Snapshots: `attacks_snapshot()` = `[cooldown_factor, max_attacks, spoke_count, spoke_period, core_ring_armed, core_ring_period]` (t7's placeholders are replaced in place);
  `arena_snapshot()` = `[ring_armed, ring_period]`.

## Build sequence
1. Tests first: append rows 7–12 to `tests/integration/test_fortress_weapons.gd`, update row 6's literals, update the §25 row in `test_space_fortress.gd` (ARENA
   built, the shields_exposed ATTACKS exemption removed) and add the 210 px/s source to `test_enemy_bullet_lifetime.gd`. **Keep the movement block quiet
   (review B1, N4):** `test_space_fortress.gd::_mover_spawn` writes `spoke_period`, `critical_spoke_period`, `ring_period`, `critical_ring_period` and
   `core_ring_period` = 1e6 on the private config by default (a `quiet_geometry := true` parameter). The movement rows test movement, and a volley spinning
   the hull at 0.5 rad/s would break `test_the_strongest_sector_turns_to_the_player_at_exactly_the_turn_rate` and `test_assault_enters_holds_bobs_and_never_moves_x`,
   and could disturb the other long movement rows (no translation, reposition, pick / critical, leash). Rows that read the `attacks` / `arena` snapshot use
   `_spawn` (shipped values), never `_mover_spawn`. The same quiet props go on t7's battery rows in `test_fortress_weapons.gd` that run long in `critical` (the
   30 s critical-fire row: the core ring would otherwise exhaust its never-returned pool and print a warning, the 1 MiB rule). Run them and watch the new ones fail.
2. Config group + `.tres` values.
3. The two scenes and the `HullBeams` / `PulseRing` nodes in `space_fortress.tscn`.
4. Root: `CoreRingPool`, `bind_geometry`, `_physics_process`, accessors.
5. Brain: settings, clocks, volleys + spin, ring, core ring, EMP / death / `tick_fades`, snapshots.
6. Run the new rows; measure density. If a ceiling fails, use the levers **in order** (`core_ring_period` 2.0 → 2.5, `critical_cooldown_factor` 0.6 → 0.7 with the
   five slots' `pool_period_factor` moved with it, `critical_max_concurrent_attacks` 3 → 2). Never widen a ceiling. Anything else: stop and ask.
7. Docs (review N5): invoke the `updating-project-docs` skill (new scenes, a new mechanic); `CLAUDE.md` gains a fortress-weapons line; `space_fortress/ENEMY.md` (weapons, measured density per phase at its worst position), `BEAMS.md` (the two fortress scenes), `docs/enemy-roster.md` line if
   it lists fortress weapons, `tests/README.md` gate-time row; `scripts/check-test-leaks.sh`; `bash /agent/verify.sh`.

## Test plan (`tests/integration/test_fortress_weapons.gd`, appended; both harnesses unless noted)
Hand-ticked rows use t7's helpers. `_tick_full` is the full `_physics_process` with the position integrated by hand, so the facing rule, spins and bob run.
Rounds go back to their pool at once.

7. `test_spokes_by_phase_period_and_spin`: with the shipped config, the ladder stepped by scripted kills.
   - `batteries`: no spoke leaves OFF for 20 s.
   - `shields_exposed`: volleys start at 8.0 s and 16.0 s (± one tick), each of exactly `Spoke0` + `Spoke1`.
   - `brain.spinning()` is true on exactly the ticks a volley spoke is ACTIVE, and the second volley spins the other way.
   - `critical`: all four spokes per volley, 6.0 s apart.
   - Also a scene row: each `SpokeN` sits at r 176 on local 270 / 90 / 0 / 180 degrees, and its beam's global +X points outward.
   **Real physics 8×**, `test_spokes_and_ring_hit_the_player_and_outsiders_never_the_owner_set`: **one shared real-physics world for spokes and ring (review
   B4)**, both harnesses, in `core_exposed` on the private config with `spoke_period` 0.3, `ring_period` 0.3 and a fixed `rng_seed`. Every battery is destroyed
   first by hand (`destroy()` on all five enters `shields_exposed` and keeps battery rounds off the player), then both generators (`core_exposed`).
   Placement (review N3): `core_exposed` presents the south side, so `Spoke1` (local 90°) faces the player. The player sits 400 px out on that bearing (inside
   500 px, so the 0.05 rad turned during `ignite_grace` keeps it inside `hit_half_width` + r_p). An owner-group fixture enemy sits 250 px out on the same line.
   An outsider fixture enemy (not in the owner group) sits 400 px out on a bearing away from every spoke. The row ends once the player has been hit by a spoke
   and by the ring and the outsider by the ring, and one full volley plus two rings have run (≈ 4.5 s sim, ≈ 0.6 s wall), capped at 10 s sim. Then it asserts:
   no `target_hit` names the owner-group fixture, the fortress or a part, and every part's HP is unchanged. A target inside one ring's gap is fine as long
   as one of the two rings hits it (the seed makes it deterministic).
8. `test_ring_pulse_by_phase_and_period`: no ring start in `batteries` / `shields_exposed` (20 s). In `core_exposed`, starts 6.0 s apart; in `critical`, 3.5 s
   apart; centred on the hull. The ring's real-physics hits are covered by the shared row under 7.
9. `test_core_ring_only_in_critical_precessing_from_the_parent_container`:
   - no core ring before `critical` (30 s in `core_exposed`); in `critical` one every 2.0 s, 12 bullets, `bullet_speed` 210, damage 10.
   - the bullets' parent is the fortress's parent; consecutive rings' bearings differ by 0.24 mod the spacing.
   - `CoreRingPool.pool_size` == 72 == `pool_size_for` recomputed from the scene, and 30 s of rings never exhaust it (bullets returned at their life, t7's `_expire`).
   - **Returning core-ring rounds (review B2):** t7's `_expire` only knows mount rounds, so this row records core-ring launches itself (the new entries of
     `core_ring_pool()._active` after each tick) and returns each at `life` = min(`max_time`, `max_distance` / `core_ring_speed`) = 11.43 s, read from
     `enemy_bullet.tscn` exactly as the root does. The margin is time, not rounds: ring 1 returns at 13.43 s, before ring 7 fires at 14.0 s. The row asserts the
     pool never `_warned_exhausted` and every ring put 12 rounds up.
   - **Lanes:** over 5 consecutive measured rings, the bullet bearings mod the spacing fall on 5 distinct lanes, and the largest lane gap is < 0.5 × the spacing
     (shipped: 0.375). Boundaries on the same predicate: a step of spacing / 2 and a step of spacing / 3 (re-treading lanes) each fail.
10. `test_emp_silences_and_death_cancels_the_geometry_weapons`:
   - **EMP:** with all three running in `critical`, spokes ACTIVE, the ring EXPANDING and a core ring in the air, `apply_emp`. Every spoke and the ring then reach
     OFF within `fade_seconds` + 1 tick of `f._physics_process` ticks. For the rest of the window no spoke or ring starts and no core-ring round is acquired.
     **Non-vacuous (review N2):** the EMP is long enough (`apply_emp(20.0)` → an 8 s window at `emp_factor` 0.4) that every countdown comes due inside it; the
     row asserts so from the brain's countdown accessors before the EMP (each < the window). Control: after the window they fire again.
   - **Death** (`death_duration` long): the same OFF-within-fade check while dying, every core-ring bullet in flight queued for deletion, and the pool's `_active` empty.
11. Fairness, read from instantiated nodes:
   - `test_spoke_fairness`: `beam_spin_rate` and `critical_spin_rate` × (`hull_radius()` + 250) ≤ 0.8 × `cruise_speed()` of both player scenes; spoke
     `telegraph_seconds` ≥ 1.0 and `telegraph_width` ≥ 3; `rehit_interval` > each player's `invincibility_sec`. The ring's `telegraph_seconds` ≥ 1.0 too.
   - `test_ring_gap_fairness_at_the_hull_edge`: `deg_to_rad(gap_deg) × (176 + r_p) ≥ 4 r_p` for both players. `r_p` is the hurtbox circle radius × the scale composed
     down the instantiated player's `HurtBox` / `CollisionShape2D` transforms (11 / 13.5 px). Boundary (review B3): the predicate is the **conjunction over
     both players** (as `test_energy_ring.gd::_player_r_p()` takes the larger radius). 15 degrees fails the conjunction: it fails for the Assault fighter
     (0.2618 × 189.5 = 49.6 < 54) and passes for the Open Space ship (48.96 ≥ 44). The row asserts both facts, so it cannot pass vacuously.
   - `test_assault_density_in_every_phase_at_five_positions` (Assault only): the real fortress at (640, 180), engaged, hand-ticked with `_tick_full`.
     - Phases and battery sets: `batteries` with all five; `shields_exposed`, `core_exposed` and `critical` with `battery_sweep` + `battery_missiles` destroyed
       (`critical` entered by core damage to 40 %). Review N1: the row destroys those two **first**, which itself enters `shields_exposed`; only then
       `_ladder_to`, which skips steps already reached and so never kills the artillery.
     - One fortress per phase. For each of S (640, 600), SW (240, 560), SE (1040, 560), W (160, 200) and E (1120, 200): stub there, 1 s settle, 10 s count.
     - **Counting:** launches per tick = the sum of `_active.size()` over every `BulletPool` child of the fortress after the tick. Then every active round
       `expired.emit()`s and is `_recycle()`d at once.
     - **Asserts:** no pool `_warned_exhausted`, every `shots_refused` / `rockets_refused` 0, mean ≤ 13.3 /s and peak half-open 2 s window ≤ 30, per phase and position.
     - The worst position per phase goes into the failure message and into `ENEMY.md`.
12. The §25 row (`test_space_fortress.gd`): ARENA joins `BUILT_KEYS`, and shields_exposed no longer exempts ATTACKS. Row 6 in this file asserts the full
    `attacks` and `arena` literals per phase: `[1.0, 2, 0, 0.0, false, 0.0]` / `[false, 0.0]`, then `[1.0, 2, 2, 8.0, false, 0.0]` / `[false, 0.0]`,
    `[1.0, 2, 2, 8.0, false, 0.0]` / `[true, 6.0]` and `[0.6, 3, 4, 6.0, true, 2.0]` / `[true, 3.5]`.
Plus `test_enemy_bullet_lifetime.gd` lists `core_ring_speed`.

## Gate time (review B4; allotment +3.0 s, escalation at 4.5 s or a 237 s mean)
Estimated per item, each measured as it lands; `test_space_fortress.gd` alone before / after build step 4 isolates the fixed cost.
- **Fixed cost per fortress instance:** 72 more pooled `EnemyBullet`s, 4 beams and 1 ring. t7's 68 rounds cost ≈ +0.75 s on `test_space_fortress.gd`; over
  the ≈ 130 spawns suite-wide this could reach ≈ 1.5 s. **Mitigation if step 4 measures more than +0.6 s on `test_space_fortress.gd`:** the pool node is still
  built in `_ready()` (named, parented, container resolved) but with its rounds not yet prewarmed; the root prewarms its 72 rounds on entering `core_exposed`,
  one boss phase before `critical`, the only phase that fires it (`BulletPool._prewarm()` is the existing loop: the root sets `pool_size` and calls it once).
  Logged in `DECISIONS.md` under `### Phase 11, built in t16` if taken.
- **Real-physics row:** one shared world for spokes and ring in both harnesses, ≈ 4.5 s sim at 8× ≈ 0.6 s wall each, so ≈ 1.2 s. It stops at first evidence
  once every hit it needs is seen. 16× only after the wall-vs-CPU check.
- **Hand-ticked rows 7–10:** negative windows ("nothing for 20 s / 30 s") tick at t7's coarse 0.05 s step (each is one countdown; no per-frame logic depends on
  1/60). Positive period rows tick at 1/60 and stop after the second start. ≈ 0.6 s for both harnesses.
- **Density rows:** Assault only, one fortress per phase, 5 × 11 s × 60 = 3300 full ticks per phase, 13 200 in all ≈ 1.0 s.
Total estimate ≈ 2.5–3.5 s without the prewarm mitigation, ≈ 2.0–2.5 s with it.

## Risks
- `critical` density may exceed a ceiling (planned 14.5 /s). The lever order above decides, and a change moves the literals in row 12 and the pool size.
- Gate time: the density rows run 13,200 full hand ticks. Mitigation: one fortress per phase, the five positions run in sequence on it, and Assault only (the plan's
  row is Assault). If it is over +3.0 s, coarsen nothing in the count (1/60 s is the stated tick) and look at the other rows first.
- Real-physics rows: the batteries also fire on the real player. Hits are read off `target_hit`, not the player's HP.

## Out of scope
Escort rounds in the density count (t8 lands escorts and records theirs beside it in `ENEMY.md`); art for beams (code-drawn); the sweep mount's arc on a spinning
hull (t7 follow-up, unchanged here).

## Revision 1 (answers review round 1)
- B1: edge-triggered spin bookkeeping (Design → Brain) and a quiet `_mover_spawn` (Build sequence 1).
- B2: core-ring rounds recorded and returned at 11.43 s (row 9).
- B3: the 15° boundary is the conjunction over both players, with both per-player facts asserted (row 11).
- B4: the *Gate time* section — one shared real-physics world, coarse negative windows, the prewarm contingency with its measured trigger.
- N1: the density row destroys sweep + missiles first. N2: an 8 s EMP window, with every countdown asserted due inside it. N3: player 400 px out on `Spoke1`.
- N4: quiet props on long critical rows. N5: the docs skill and the CLAUDE.md line.
