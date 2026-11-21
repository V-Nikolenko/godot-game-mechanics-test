# t7 — The Carrier fights back: side batteries, bow cannon, missile bank, anti-approach pulse, PANIC

Task `cmwafsrb900ajqs2yb5jcl5ij`, epic `cmug23oo90029m52wae4clve0` (Phase 10), epic plan §2.7 (+ §2.6.3, §2.8's emergency-deployment hook, §2.9, §2.16).
Context: `1-context.md`. This task implements an approved epic section; it does not redesign it. Where §2.7 leaves a detail open, the choice is
named below and logged in `DECISIONS.md` as a t7 note.

## Problem

Today the Carrier (t6) moves, lists and panics but never shoots: its two gun-battery parts have empty `MountSlots`, `HullMounts` is empty, and
nothing punishes a player who parks on its hull. The player should meet a capital ship that controls space:
- two side batteries, each covering only its own side (150°), so **killing one makes that side safe**;
- a bow heavy cannon (Heavy Shells) that only covers a 70° cone ahead;
- a dorsal missile bank that fires PURSUIT rockets only at a player **standing off beyond 450 px**;
- an **anti-approach pulse ring** (r 420) when the player comes within 340 px of the hull centre, with gaps to slip through;
- when the core is exposed it **panics**: the pulse recharges twice as fast, the batteries fire 1/0.7 as often, the core light flashes red, the
  hull light strobes, and (t8) the hangars deploy everything at once. In Assault every mount fires only while the hull centre is inside the view.

## Design

### Scene (`carrier.tscn`)
- `Modules/GunPort/MountSlots/Slot0` (`TurretMountSlot`, at the module's origin): `variant` BURST_CANNON, `rest_bearing_deg` 0 (port = local +x),
  `traverse_deg_override` 150. `Modules/GunStarboard/MountSlots/Slot0`: same with `rest_bearing_deg` 180.
- `HullMounts/Bow` (`TurretMountSlot`, position (0, 116), near the nose at local +y 140): `variant` HEAVY_CANNON, `rest_bearing_deg` 90,
  `traverse_deg_override` 70.
- `HullMounts/Dorsal` (`TurretMountSlot`, position (0, 64), between the core and the bow): `variant` ROCKET_BATTERY, `rest_bearing_deg` 90,
  `traverse_deg_override` -1 (the scene's 360).
- `AntiApproachRing` (instance of the new `carrier_pulse_ring.tscn`) at the root origin (the hull centre). Not `PulseRing`: that is Phase 7's
  visual class.
- `Modules/Core/Light` (`StateLight`, scale 3): OFF; flashes ARMED (red) in PANIC (§2.9 "core red flashing in PANIC"). The module already turns its
  `Light` OFF on destruction. No module position, shape or `HomingPoint` changes (t9 / t11 / t12 measure them).

### `carrier_pulse_ring.tscn`
An inherited scene of `energy_ring.tscn` (`[node name="CarrierPulseRing" instance=ExtResource(...)]`) overriding only exports: `max_radius` 420,
`telegraph_seconds` 1.0, `ring_speed` 360, `band` 24, `gap_count` 2, `gap_deg` 50, `damage` 14 (`gap_spin_deg` 30 and `fade_seconds` 0.15
inherited). No script.

### `CarrierConfig` — new `Weapons` group (flat floats; §2.16 starting values)
`pulse_trigger_range` 340, `pulse_cooldown` 5.0, `missile_min_range` 450, `missile_cooldown` 7.0, `missile_pursuit_chance` 1.0,
`panic_pulse_factor` 0.5, `panic_battery_factor` 0.7. Mount / ring *weapon* tuning stays in their scenes; these are the host's numbers §2.7
names (the plan states the missile bank's 7.0 s cooldown and PURSUIT kind for this host, not for every rocket battery).

### `Carrier` (root)
In `_ready()`, after the existing setup:
1. `var next := _hull.build_mounts(self, brain.rng, _owner_group)` (the module slots, indices 0..1), then for each `TurretMountSlot` child of
   `HullMounts` in tree order `TurretMountBuilder.build(self, slot, next, brain.rng, _owner_group)`, `next += 1` (pool names stay unique: §2.7
   "with the returned running index"). No telegraph gate (no budget).
2. The Dorsal mount gets `cooldown_seconds = config.missile_cooldown` and `pursuit_chance = config.missile_pursuit_chance` (a host write onto
   its own mount, the precedent §2.7 sets for the PANIC battery factor). Its pools were sized by `pool_specs()` at the scene's 5.5 s cooldown, i.e.
   for more salvos in flight than a 7.0 s bank can have: never too small.
3. `$AntiApproachRing.setup(self, _owner_group)`; `died` → `brain.cancel_pulse()`.
4. `brain.bind_weapons(bow_mount, dorsal_mount, ring)` alongside the existing `bind_hull(_hull)`.
New queries (read by tests and t8): `pulse_ring() -> EnergyRing`, `bow_mount()`, `missile_mount()`, `battery_mounts() -> Array[TurretMount]`.

### `CarrierBrain` — weapons
- **Tick order.** `tick()` keeps its movement step, then (every phase, both modes) `_tick_weapons(delta)`:
  - `target := TargetInfo.player(tree)`; `sees` = `can_see_player()` only inside a physics frame, else true (the gunship rule).
  - `in_view` = no view rect, or `EnemyWorld.view_rect(tree).has_point(actor.global_position)` (the Ph8 turret rule; Open Space has no rect).
  - `fighting` = Assault (CROSS / PANIC), or Open Space SCREEN / PANIC with a target. Otherwise every mount `scan(delta)` and no pulse starts.
  - Side batteries and bow: `mount.tick(delta, target, in_view and sees)` (their traverse refuses an off-arc target by itself).
  - Missile bank: `can_fire = in_view and dist(hull centre, player) > missile_min_range` (it fires past cover: `fires_past_cover()` is true, so
    `sees` is not required). A destroyed part's mounts are UNPOWERED by t3 and stay so whatever is passed.
  - **Pulse:** `_pulse_left -= delta` every tick (starts at 0). When `fighting`, `in_view`, the ring is OFF or FADE, `_pulse_left <= 1e-6`
    (the project's clock rule) and the player's distance to the hull centre is strictly below `pulse_trigger_range`: `ring.start(rng.randf_range(0, 360))` and `_pulse_left = pulse_cooldown ×
    (panic_pulse_factor if PANIC else 1)`. The ring is ticked `ring.tick(delta)` on every brain tick so a started ring always finishes (cooldown
    counted from `start()`; ring life 1.0 + 420/360 + 0.15 = 2.32 s < 2.5 s, so even PANIC never asks a busy ring to restart).
- **PANIC entry** (`enter_phase(PANIC)`, once): battery mounts `cooldown_seconds = base × panic_battery_factor` (base captured at bind time;
  the bow and the bank keep theirs, §2.7 says "battery"); `_pulse_left = minf(_pulse_left, pulse_cooldown × panic_pulse_factor)`;
  `_emergency_deploy()` — **the t8 hook**, a documented no-op in t7 that t8's `CarrierHangars` fills (§2.8: every live hangar that may still
  launch goes straight to LAUNCH).
- **Sway arc** (t6 constant `SWAY_ARC_HALF_DEG` 75): read from a live battery mount's `traverse_deg / 2` (t6's note "t7 reads it from the battery
  slot"); the constant stays as the fallback when no battery mount exists.
- **EMP** (`on_emp_started`, both modes, before t6's Assault boost): every mount `scan(0.0)` (a shown telegraph never lands, the gunship rule)
  and `_kill_ring()`: `ring.cancel()` and, if it is then in FADE, `ring.tick(fade_seconds)` so it goes OFF at once (the brain is not ticked
  during the window, and a ring left in TELEGRAPH / FADE would hang frozen on screen). Light OFF. `on_suspended()` does the same (a railed
  carrier fires nothing). `cancel_pulse()` (on `died`) is `_kill_ring()`.
- **Lights (§2.9).** Hull `StateLight`: CHARGING while any mount is in TELEGRAPH or the ring is in TELEGRAPH; else ARMED while any mount is in
  TRACK / FIRE / COOLDOWN or the ring is EXPANDING; else OFF. In PANIC the non-CHARGING state strobes (shown for the first half of each
  `PANIC_STROBE` 0.25 s, OFF for the second; a CHARGING telegraph is never hidden). Core `Light`: OFF until PANIC, then ARMED/OFF on the same
  strobe. Mount charge glows are the mounts' own (Ph8).

### Deviations logged in `DECISIONS.md` (t7 notes)
- The bank's 7.0 s cooldown and PURSUIT-only kind live in `CarrierConfig` and are written onto the built mount (not a mount-scene export: the
  "weapon tuning in mount scenes" rule bends for two numbers §2.7 sets for this host only).
- PANIC battery cooldown 2.2 × 0.7 = 1.54 s: the burst pool was sized by `pool_specs()` at the 2.96 s period from the round's `max_time` 8 s
  (4 × ceil(8 / 2.96) = 12); the Pulse round actually expires by `max_distance` 1400 / 300 = 4.67 s, so at the 2.30 s PANIC period 4 × ceil(4.67 /
  2.30) = 12 rounds are ever live: the pool is still big enough, no rebuild.
- The sway's arc half-width is read from a live battery mount (the t6 constant stays as the fallback).

### Rejected alternatives
- *A new `TurretMount.Variant` / mount scene for a PURSUIT-only, 7 s bank*: an append-only enum entry and a scene for two numbers one host uses.
  Host writes on its own mount are already the plan's mechanism for the PANIC factor.
- *The ring ticked from the root's `_physics_process`* (so it runs through an EMP): §2.7 says the brain owns and ticks it; killing the ring on
  EMP keeps the "brain not ticked" rule intact.
- *A `TurretMount` min-range export for the bank*: changes a shared t3 class; the brain's `can_fire` is the host's say by design.
- *The Ph8 `PulseRingMount` on a hull slot*: it owns a ring too, but with a fixed `ring_scene` export, a cooldown counted from the end of the
  expansion and a trigger measured from the mount pivot; §2.7 has the brain own the ring, cool down from `start()`, halve that in PANIC and trigger
  from the hull centre. Using it would need a variant and scene per host, as for the bank.

## Build sequence
1. Tests first: the `§weapons` rows below appended to `tests/integration/test_carrier.gd`; config pin extended; run, watch them fail.
2. `carrier_pulse_ring.tscn`; config fields + `.tres`.
3. `carrier.tscn`: slots, hull slots, `AntiApproachRing`, Core `Light`.
4. `carrier.gd`: mount building, missile write, ring setup, `died` hook, queries.
5. `carrier_brain.gd`: `bind_weapons`, `_tick_weapons`, pulse clock, PANIC effects + `_emergency_deploy()` hook, sway arc from the mount, EMP /
   suspend kill, lights.
6. Rows green; full suite (the carrier is spawned by `test_enemy_dual_mode.gd`, `test_base_enemy.gd` and the roster gates: they must stay green);
   `scripts/check-test-leaks.sh`; `scripts/gate-time.sh` × 2 before/after.
7. Docs (`updating-project-docs`: `ENEMY.md`, `assault.md`, `PROJECT.md`, `CLAUDE.md` carrier line), `DECISIONS.md` t7 notes, gate-time row in
   `tests/README.md`.

## Test plan (`tests/integration/test_carrier.gd`, new `§weapons` section; hand-ticked at 1/60, both harnesses via `use_parameters(MODES)` labels)

**Every weapons row pins the hull** (round-1 finding 1): after each `_tick(c)` the test writes back the row's fixed `global_position` (and, where
a row says so, `rotation`) and re-places the player relative to the pinned hull. Unpinned, an Open Space carrier backs out of a 300 px player at up
to 70 px/s and an Assault one descends 90 px/s out of the view, so no cooldown or interval could be observed. Distances are read from `SHIPPED`
(the `.tres`), never typed. A control row stops at its first evidence (an early `break`), not at the end of its window.

1. `test_a_dead_port_battery_leaves_the_port_side_safe(mode)`: `GunPort` destroyed; hull position pinned (Assault: inside the view); for 20 s the
   player stub is re-placed **every tick** at `carrier + port(c) × 400` (Open Space: the carrier keeps turning, so "port" is re-read every tick);
   **no battery round is fired**, and every round of any mount leaves with a carrier-local direction x ≤ 0. **Control** (both guns alive, same
   placement, stops at the first evidence): a port-battery round whose line passes within 24 px of the player's position at its fire time ("is
   hit": the stub has no hurtbox and a hand-ticked loop moves no bullet).
2. `test_the_bow_cannon_fires_only_inside_its_70_degree_arc(mode)`: hull pinned at rotation 0; player 600 px **from the bow mount's pivot** at
   nose-relative bearings measured **from that pivot** (finding 3): 0° and 30° (≥ 1 Heavy Shell within 4 s, stop at the first) and 40° and −40°
   (none in 4 s) — 30° / 40° straddle the ±35° arc edge by 5°. Every Heavy Shell leaves within 35° + half the fire cone of the nose.
3. `test_the_missile_bank_fires_only_beyond_its_min_range(mode)`: hull pinned; player straight ahead of the hull centre at
   `missile_min_range − 10` (outside `pulse_trigger_range`): no rocket in 8 s; at `missile_min_range + 10`: ≥ 1 rocket within 8 s (stop at the
   first), every one PURSUIT, the player's distance > `missile_min_range` at every launch. The live bank mount reads `cooldown_seconds` ==
   `SHIPPED.missile_cooldown` and `pursuit_chance` == `SHIPPED.missile_pursuit_chance` (a hand-ticked pool never recycles, so a second salvo cannot
   be observed; the cooldown is pinned on the mount instead).
4. `test_the_pulse_starts_on_approach_and_respects_its_cooldown(mode)`: hull pinned, player re-placed relative to it each tick. Player at
   `pulse_trigger_range + 10` for 1 s → no ring; moved to `pulse_trigger_range − 10` → the ring enters TELEGRAPH **on that tick** (cooldown 0 at
   spawn) and the hull `StateLight` reads CHARGING; held there: the next start comes on exactly the tick the summed delta reaches `pulse_cooldown`
   (`ceil(cooldown / DT − 1e-3)` ticks), never earlier; moved out to `pulse_trigger_range + 10` 0.5 s after that start and back to
   `pulse_trigger_range − 10` once the cooldown has run → starts on that tick. PANIC (three outer parts destroyed): the interval is exactly
   `pulse_cooldown × panic_pulse_factor` in ticks, and through the PANIC ring's TELEGRAPH the hull light reads CHARGING on every tick (the strobe
   never hides a telegraph).
5. `test_the_carrier_pulse_ring_is_fair()`: on an **instance** of `carrier_pulse_ring.tscn` (inherited exports resolve only on an instance): gap
   arc at `max_radius / 2` ≥ 3 · r_p (r_p from the real player scenes, the `test_energy_ring.gd` method), `telegraph_seconds` ≥ R 0.25, and the §2.7
   numbers 420 / 1.0 / 360 / 24 / 2 / 50 / 14. Boundary: the same predicate on that instance with `gap_deg` set to 15 fails.
6. `test_the_ring_spares_its_own_carrier_and_its_children_but_not_other_enemies(mode)`: hull pinned; every module set vulnerable; three outside
   fixture enemies (`fixture_enemy.tscn` + 14 px circle + group `enemies`) at 300 px on bearings 0/120/240° (two gaps 180° apart can cover at most one
   of them) and three "launched children" (the same fixture, also in `c.owner_group()`) at 320 px on the same bearings; the player at
   `pulse_trigger_range − 10` triggers one ring, ticked to OFF: every module's and the hull's health unchanged, `armor_deflected` never emitted
   (exempt, not refused), every child untouched, ≥ 2 outside fixtures took exactly the ring's `damage`.
7. `test_panic_entry_and_effects(mode)`: three outer parts destroyed → PANIC on the next tick (not PANIC right after the third destroy call); both
   battery mounts' `cooldown_seconds` = their pre-panic value × `panic_battery_factor`, the bow's and bank's unchanged; the core light shows both
   OFF and ARMED within 1 s. Open Space (not pinned, the player still at 500 px): distance to the player grows over 10 s and the hull never passes
   `leash_radius` + 50 from its anchor.
8. `test_in_assault_no_mount_or_pulse_fires_from_outside_the_view()`: hull pinned above the view (y −200), player straight ahead at
   `pulse_trigger_range − 10` (inside every range and the bow arc): no mount telegraph and no ring in 3 s; control pinned inside the view: both appear.
9. `test_an_emp_a_rail_or_death_ends_the_ring_at_once(mode)` (finding 5, 6): (a) ring in TELEGRAPH → `apply_emp(2.0)` → ring OFF, no mount in
   TELEGRAPH, light OFF; (b) ring EXPANDING → `apply_emp(2.0)` → ring OFF (the cancel-then-finish path); (c) ring in TELEGRAPH → `suspend_ai()` →
   ring OFF and no round in 3 s of `_tick`; (d) ring EXPANDING → core destroyed → right after the call the ring is OFF and not lethal.
10. The config pin row (`test_the_config_the_builder_and_the_phase_order`) gains the seven new fields.

## Risks
- **Battery reach vs. the screen band:** the batteries' `fire_range` 700 is shorter than the band's 950 top; the carrier fights mostly with the bow
  and the bank at range, with the batteries at the near edge. Accepted (plan numbers; t10 / t12 tune placement).
- **Own rockets vs. own parts:** `EnemyRocket` can hit layer-512 hurtboxes once armed (169 px + clearances from the centre: outside every part);
  a PURSUIT rocket curving back over the hull could hit a carrier part (Ph5 friendly-fire rule, as on the gunship). Low (target > 450 px away).
- **Existing carrier rows:** the carrier now fires in `test_enemy_dual_mode.gd`, `test_base_enemy.gd` and t6's rows; rounds are pooled children
  freed with each world. Watch for count- or leak-sensitive rows.
- **Gate time** (allotment 1.8 s): ~10 rows of 1–20 s hand-ticked; the 20 s rows dominate (4 × 1200 ticks). If over, share the control world.

## Out of scope
Hangar cycles and launches (t8: `_emergency_deploy()` stays a no-op), art (t9), hub / level placement (t10 / t12), EMP variant of the ring
(Ph18), enemy beams vs parts (Ph18 / Ph19).

## Response to round-1 review
| Finding | Change |
|---|---|
| 1 rows 4/6/7/9 drift | Every weapons row pins the hull and re-places the player relative to it (test-plan preamble). |
| 2 no trigger boundaries | Pulse at `pulse_trigger_range ± 10`, bank at `missile_min_range ± 10`, both read from `SHIPPED`. |
| 3 bow bearings from the centre | Bearings and distance from the bow pivot; 30° / 40° straddle the edge. |
| 4 clock rule | `_pulse_left <= 1e-6`, strict `<` trigger; row 4 asserts the exact tick. |
| 5 missing assertions | CHARGING light + strobe (row 4), EMP while EXPANDING and a rail (row 9), live bank cooldown / pursuit (row 3). |
| 6 death check | Row 9(d): ring OFF and not lethal right after the core's `destroy()`. |
| Minor | Pool reasoning and the config deviation logged; controls stop at first evidence; `PulseRingMount` rejection stated; fairness on an instance; node renamed `AntiApproachRing`. |
