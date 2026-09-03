# Level 1 space-station mini-boss — completion report

**Epic id:** `station-mini-boss` · **Six sub-items, all `done`** · **2026-09-01 → 2026-09-03**
**Gate at close:** `bash /agent/verify.sh` → `GATE PASS`, **26 scripts / 253 tests / 253 passing /
950 asserts** (re-run 2026-09-03 while writing this report). Nine of those scripts and **93** of
those tests are this epic's.

Read [`PRD.md`](PRD.md) for what was asked and why, and [`SOURCES.md`](SOURCES.md) for where the
numbers came from. This file is what happened.

**One-line summary:** the encounter is built, gated, armed, reinforced and staged, and every part
of it is pinned by headless tests — but **no human has ever played it**, and one of its three
sprites is known to render as an opaque grey square. See *Known gaps*.

---

## What was built

### Sub-item 1 — the station and turrets exist as a destructible entity → `60a3d31`

`assault/scenes/enemies/space_station/`: `space_station.gd`/`.tscn` (`SpaceStation extends
BaseEnemy`), `station_turret.gd`/`.tscn` × 4 under a `Turrets` node, and
`space_station_config.gd`/`.tres`. Three PixelLab sprites in
`assault/assets/sprites/enemies/`: `station_core.png` (256×256), `station_turret.png` and
`station_turret_destroyed.png` (64×64).

The armour rule is the whole point of the sub-item: the core refuses **all** damage while any
turret lives, implemented as a `_on_received_damage` override that keeps the `HurtBox` **live**.
Disabling the hurtbox was rejected for two independent reasons — research says a shot passing
through a boss reads as a bug (`SOURCES.md`, Gradius rows), and `plasma_nova_module.gd:39-41` plus
`beam_behavior.gd:99-102` both emit `received_damage` **directly**, so a disabled hurtbox would
leak both weapons straight through. Plan and two review rounds:
[`docs/plans/station-mini-boss-destructible/`](../../plans/station-mini-boss-destructible/).

**Follow-up in the same day:** both turret sprites shipped as 3/4 views and were regenerated as
true top-down in `c60742b`. The root cause was the tool, not the prompt, and the fix is now
enforced by the `pixel-art-generation` skill — full write-up in the station's `ENEMY.md` →
*Sprite provenance*.

### Sub-item 2 — the encounter blocks level progress → `ad5c70f`

`station_assault` is Level 1's **third of five** sections
(`assault/scenes/levels/edelia/1/level_1_director.gd:199-241`), `ENEMIES_CLEARED`, with
`phases/phase_station_assault.tres`. Supporting changes, all in shared code:

- **New `LevelSection.enemies_cleared_timeout`**, defaulting to `10.0` so `cloud_descent` is
  bit-identical; the station sets `180.0` (G-Darius's boss-timer floor — `SOURCES.md`).
- **`LevelDirector` now frees leftover container children on expiry** instead of advancing the
  level with the boss still parented to `enemy_container`. That was a pre-existing bug the
  research identified, not a new feature: a timeout that leaves the boss alive matches nothing in
  the genre (`level_director.gd:104-118`).
- `WaveBuilder.space_station()`, and a `_build_sections()` refactor that makes the section order
  assertable without booting the level.

Three details in `_build_station_assault()` are load-bearing and carry a comment block saying so:
**no `.delay()`** (`waves_complete` fires when the last wave *triggers*, so a delayed wave lets the
director see an empty container and advance instantly), **no `.move()`** (a `MovementResource`
would attach an `EnemyPathMover` and fly the boss off screen mid-fight), and the 180 s timeout as a
safety net rather than a balance knob. Plan and two review rounds:
[`docs/plans/station-assault-section/`](../../plans/station-assault-section/).

### Sub-item 3 — the laser phase → planned in `479a66d` (**no code**), shipped in `20bb290`

`station_laser_phase.gd`, wired into `space_station.tscn` as `LaserPhase`. A zero-arg
`SpaceStation.armor_broken` signal with a once-only latch is the phase's trigger; five laser fields
on `SpaceStationConfig` and the `.tres`; and an **additive** `LaserRay.hit_mask_override` export on
the shared hazard (`0` means "unchanged", so every existing `LaserRay` behaves exactly as before).
The hull rotates only while the phase is active. Plan and **three** review rounds:
[`docs/plans/station-laser-phase/`](../../plans/station-laser-phase/).

**This sub-item took two cycles.** The first ended with `2-research.md`, `3-plan.md` and two
CHANGES_REQUESTED reviews and shipped **zero lines of production code** (`479a66d` — the commit
message says so in its subject line). See *Decisions and course changes*.

### Sub-item 4a — the station shoots back → `4762c42`

`station_gunnery.gd` as a sibling node of `LaserPhase`, driving a new shared resource
`global/resources/attack/radial_attack_pattern.gd` (`RadialAttackPattern` — **one** resource
covering both the core's full ring and the turrets' aimed fan, alongside the three concrete patterns
that already existed). Ten new `SpaceStationConfig` fields; a `BulletPool` (`pool_size = 48`) and
the `Gunnery` node authored into `space_station.tscn`. Every live turret fires an aimed 3-bullet
fan on a shared tick; killing a turret removes its gun from the volley; the core starts its
precessing ring only once the armour breaks. Plan and two review rounds:
[`docs/plans/station-bullet-hell/`](../../plans/station-bullet-hell/).

Two scene-level constraints that a future cycle should not have to rediscover, both recorded in
`ENEMY.md` and in `space_station.tscn`'s own comments: the `BulletPool` **must** stay a direct
child of `SpaceStation`, because `bullet_pool.gd:47` hardcodes `get_parent().get_parent()` and
anywhere else the entire bullet field rotates with the hull; and the `Gunnery` node needs a
`node_paths=` tag in the text scene or its exported reference is silently left `null` **with the
gate still green**.

### Sub-item 4b — reinforcements → `9079a20`

`station_reinforcements.gd` as a third sibling node. `space_station.gd` gained **nothing** for it,
not even an accessor. Squads cycle `LEFT → RIGHT → BOTTOM → TOP` — **four** edges, where the
done-condition asked for three: 2 × `interceptor` from either side, 2 × `kamikaze_drone` from
below, 2 × `fighter` with `.shoot_forward()` from above, all authored through `WaveBuilder`'s own
fluent API in 640×360 design units. Three new config fields (8 s first delay / 10 s interval / cap
4). Plan and two review rounds:
[`docs/plans/station-reinforcements/`](../../plans/station-reinforcements/).

Both warnings the backlog attached to this item were honoured: reinforcements come from a
station-owned node rather than the station's own wave, and stopping on `armor_broken` plus
`FREE_ON_DURATION` means nothing can be left alive to hold `ENEMIES_CLEARED` open after the boss
dies. Four traps are recorded in `ENEMY.md`: reinforcements must be **siblings** of the station and
never children; `FREE_ON_SCREEN_EXIT` cannot be used for an off-screen spawn because it only culls
a ship that has already been on screen once; the station's `died` signal cannot be tested without
unhooking `armor_broken` first, because the armour rule makes `armor_broken` the only route to it;
and a ship's **runtime** HurtBox mask comes from `base_enemy.gd:25`, never from the value authored
in its `.tscn`.

### Sub-item 5 — destruction hands off to the planet approach → `66862bd`

`station_death_sequence.gd` as a fifth sibling node. `space_station.gd` gained a `death_started`
signal, a public `death_duration`, a `_dying` latch and an `_on_health_changed` override that moves
**only** `queue_free()` — the split is deliberate and documented in `ENEMY.md`: the station owns
*lifetime*, the sequence node owns *spectacle*, so a station whose `DeathSequence` node is renamed
or deleted still dies correctly. Additive support in shared components:
`BulletPool.cancel_active()` (extracted from `_exit_tree()`) and `ExplosionEffect.explode(at)` (the
position argument is optional and the default preserves today's behaviour exactly). Two new config
fields. Plan and two review rounds:
[`docs/plans/station-death-handoff/`](../../plans/station-death-handoff/).

The handoff itself needed **no `LevelDirector` change at all**: `_wait_enemies_cleared()` already
polls the container's child count, so a lingering wreck holds its section open for free.

### Post-epic

`4000f6e` ("Shared-component hygiene") landed after all six sub-items and touched
`space_station.gd`, `station_laser_phase.gd`, `station_turret.gd` and `test_space_station.gd` to
bring their signal declarations in line with the project's arity convention. It is not epic work,
but it is why the current gate reads 253 tests rather than sub-item 5's 249.

---

## How it was verified

Every cycle ran `bash /agent/verify.sh` — three steps: `godot --headless --import`, a headless boot
of the project (autoloads + main scene compile), then the full GUT suite via
`godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`. Per-cycle
figures, from each plan's `STATUS.md`:

| Sub-item | Commit | Gate at close |
|---|---|---|
| 1 | `60a3d31` | 18 scripts / 165 tests / 527 asserts |
| 2 | `ad5c70f` | 19 scripts / 172 tests / 551 asserts |
| 3 (plan only) | `479a66d` | 19 scripts / 172 tests / 551 asserts (unchanged — no code) |
| 3 | `20bb290` | 21 scripts / 188 tests / 605 asserts |
| 4a | `4762c42` | 23 scripts / 214 tests / 767 asserts |
| 4b | `9079a20` | 24 scripts / 232 tests / 868 asserts |
| 5 | `66862bd` | 26 scripts / 249 tests / 941 asserts |
| today | — | 26 scripts / **253 tests / 950 asserts**, `GATE PASS` |

Unlike the rest of the suite, **the station family asserts intent, not current behaviour** — it is
new code, so the tests are the specification. `CLAUDE.md` and `tests/README.md` both say so.

### The nine test scripts, and what each actually proves

| Script | Tests | Headline coverage |
|---|---|---|
| `tests/integration/test_space_station.gd` | 9 | The armour rule end to end: `test_core_ignores_damage_while_any_turret_lives`, `test_core_becomes_damageable_after_last_turret_dies`, `test_armored_core_emits_armor_deflected_and_keeps_full_health` (the hit *registers*, the HP does not move), `test_turret_damage_does_not_leak_into_core_health`, `test_config_max_health_wins_over_scene_health_node`. |
| `tests/integration/test_station_assault_section.gd` | 7 | The gate: `test_section_does_not_advance_while_an_enemy_lives`, `test_section_advances_when_the_last_enemy_is_freed`, `test_timeout_frees_leftover_enemies_then_advances`, `test_enemies_cleared_timeout_defaults_to_ten_seconds` (pins `cloud_descent` unchanged), `test_level_1_sections_are_in_order_with_station_assault_third`, `test_station_assault_spawns_one_station_at_zero_delay_with_no_movement` (pins the two load-bearing omissions). |
| `tests/integration/test_station_laser_phase.gd` | 12 | The fairness contract: `test_beam_is_not_lethal_during_the_warning_window` and `test_beam_damages_the_player_during_the_active_window` — the pair the user's done-condition asked for — plus `test_armor_broken_emits_exactly_once`, `test_beam_does_not_damage_the_station_that_fires_it`, `test_station_rotates_only_during_the_laser_phase`, `test_volley_angles_are_deterministic`, `test_beams_stop_and_do_not_outlive_the_station`. |
| `tests/integration/test_laser_ray_hit_mask.gd` | 4 | That the shared-hazard extension is genuinely additive: `test_default_hit_mask_is_unchanged_when_override_is_zero`, `test_zero_means_default_and_never_an_inert_beam`. |
| `tests/integration/test_station_gunnery.gd` | 18 | `test_a_volley_fires_one_fan_per_live_turret`, `test_destroying_turrets_removes_their_guns`, `test_turret_bullets_are_aimed_at_the_player`, `test_the_core_does_not_fire_until_the_armor_breaks`, `test_the_pool_is_a_direct_child_of_the_station`, `test_bullets_live_in_the_enemy_container_not_in_the_station`, `test_the_timers_actually_run`, and **`test_the_ring_step_leaves_no_permanent_safe_lane`** — which reads the step off the live node, so it locks the shipped `.tres` rather than a literal. |
| `tests/integration/test_radial_attack_pattern.gd` | 10 | The new shared resource on its own, including its degenerate inputs: `test_a_single_bullet_arc_does_not_divide_by_zero`, `test_a_zero_bullet_count_fires_nothing`, `test_aim_at_player_falls_back_to_down_with_no_player`, `test_the_pattern_ignores_ship_rotation`, `test_it_returns_quietly_when_the_pool_is_exhausted`. |
| `tests/integration/test_station_reinforcements.gd` | 18 | `test_the_squads_cover_four_distinct_screen_edges`, `test_every_entry_clears_the_off_screen_spawn_margin`, `test_squads_cycle_left_right_bottom_top_and_then_repeat`, `test_breaking_the_armour_stops_reinforcements`, `test_the_cap_skips_a_whole_squad_and_recovers_when_ships_are_freed`, `test_no_squad_uses_a_self_managed_ai_enemy`, **`test_every_squad_ship_can_be_hit_by_the_players_primary_weapon`** (so the `ram_ship` class of mistake cannot recur silently), and `test_a_squad_that_flies_through_costs_two_escape_combo_penalties` (pins a known, accepted wart — see *Known gaps*). |
| `tests/integration/test_station_death_sequence.gd` | 14 | `test_the_wreck_stays_in_the_tree_after_hp_reaches_zero`, `test_died_and_was_killed_fire_at_the_moment_hp_reaches_zero`, `test_the_corpse_cannot_ram_the_player`, `test_the_blast_chain_rolls_across_the_hull_rather_than_detonating_at_its_centre`, `test_the_spin_decays_rather_than_staying_constant`, `test_death_sequence_duration_zero_keeps_the_base_enemy_behaviour` (the boundary that proves the change is additive), `test_shortening_the_station_duration_does_not_write_back_to_the_shared_config`. |
| `tests/integration/test_level_1_sequence.gd` | 1 | `test_level_1_runs_all_five_sections_end_to_end_with_a_real_station` — the user's done-condition for sub-item 5, and the only test in the epic that exercises the whole level. |

### What the gate cannot tell you

- **Nothing here is visual.** No test renders a frame. A sprite with an opaque background, a
  turret barrel pointing the wrong way, or a blast chain that reads as a stutter all pass the gate
  silently — and two of those three are *known present* (see *Known gaps*).
- **Collision layers are only half proven.** `test_space_station.gd` drives damage by emitting
  `received_damage` directly, so it proves the armour *logic* and nothing about whether a player
  bullet can physically reach a turret. `test_station_laser_phase.gd` does exercise a **real**
  physics overlap — a layer-128 stub `HurtBox` placed in a beam's path, found by the beam's own
  `Area2D` — but only for the *player* layer and only against a `LaserRay`. Filed as two open
  code-health tasks.
- **Feel is entirely unverified.** Whether 1.4 s of telegraph reads as fair, whether four turrets
  is interesting or tedious, whether 6.7 bullets/s is pressure or noise — the gate has no opinion.

---

## Decisions and course changes

The review stage is the reason this epic is worth reading. **Thirteen review rounds across six
plans; seven returned CHANGES_REQUESTED.** No plan was ever implemented without an `APPROVED`
verdict, and the reviewer reproduced findings at runtime rather than reading the plan, which is
what made them stick.

### The laser phase burned a whole cycle at review, on purpose → `479a66d`

Sub-item 3's first cycle produced research, a plan and **two** CHANGES_REQUESTED rounds, then
stopped: the gate allows two rounds, so implementation did not start. **Zero production code.** It
is the clearest case in the epic of the pipeline doing its job, because both blocking findings
would each have cost a session:

- **Round 1, finding 2** — the *headline* regression test, the one proving the boss does not kill
  itself with its own beam, **could not fail as specified**. At `emitter_radius = 140` only the
  *diagonal* volley angles overlap the core hurtbox; volley 0 is axis-aligned and misses by 20 px.
  The test would have gone green with the fix reverted.
- **Round 2, D1** — `SpaceStation.config` is a **process-wide shared resource**
  (`space_station.gd:24` `load()`s it and `ResourceLoader` caches, so it is the same object
  `preload()` hands a test). The test plan said to shorten the timings "on the instance", which
  would have permanently rewritten the shipped `.tres` values in memory — and the test that
  asserts those values runs *last in the same file*. A guaranteed red gate at the end of a session.

Round 2 closed with "the design is settled… round 3 needs only D1, D2 and the nits — no new
research, no design change", and the next cycle's single round-3 verification review approved it
and shipped `20bb290`. The corrected time-to-lethal formula (`warn + 0.56 s`, **not**
`0.2 + warn + 0.56` — `laser_ray.gd:155-161` starts the warn timer in the same call that plays the
init frame) was propagated back into `1-context.md` and `2-research.md` so no artifact still
carries the wrong arithmetic.

### A review round withdrew its own blocking finding — and that was the most useful thing sub-item 2 produced

Sub-item 2's round 1 filed **B1: the done-condition is unsatisfiable, because the core's 240×240
`HurtBox` shadows all four turret hurtboxes**, and required a dedicated 88×240 core shape. It was
accepted, and revision 1 of the plan grew a whole §0 to implement it. **Round 2 withdrew it.**

The withdrawal rested on a fact both reviews had got wrong in the same direction: they had assumed
a player bullet dies on its first hurtbox overlap. It does not. `BulletPool` is never constructed
by the player; `bullet.gd:84` emits `expired` **without** `queue_free()`; the only `queue_free()`
is gated on `range_px > 0.0`, which `weapons/modes/default.tres` sets to `0.0`. So a default player
bullet flies on with a live HitBox and damages every hurtbox in its lane — the overlapping core
hurtbox does not block anything. The narrowed shape was dropped, and the *design* question of
whether to narrow it anyway was filed rather than smuggled in as a bug fix (open code-health task:
*Should the station's core hurtbox be narrowed to 88 × 240?*). The bullet-lifetime finding itself is
filed too, because it means the player's default shot is effectively **infinitely piercing against
stacked hurtboxes**, which makes `PierceModule` look like it exists to *limit* damage.

### `core_ring_step`: 0.21 → 0.24, caught before it shipped

Sub-item 4a's round 1 found that the planned `core_ring_step = 0.21` had **exactly** the defect its
own research said to avoid: `3 × 0.21 = 0.63` against a `TAU/10 = 0.6283` ring spacing, so
successive rings re-tread three radial lanes and leave a permanent safe lane the player can park
in. Measured over 20 rings, `0.21` leaves a largest lane gap of **31.8 %** of the spacing; the
shipped golden-angle `0.24` leaves **9.0 %**. `test_the_ring_step_leaves_no_permanent_safe_lane`
rejects anything above 25 %.

The same round caught that the plan's `_station.add_child(_pool)` from the gunnery's `_ready()`
**cannot work** — `_propagate_ready()` blocks the parent while it readies its children.

### The reinforcement squad that would have been two indestructible obstacles

Sub-item 4b's round 1 found that the planned top squad, `ram_ship`, is **immune to the player's
primary weapon**: `ram_ship.gd:19` narrows its HurtBox mask to `33` after `BaseEnemy._ready()` set
the normal `97 | 1024`, and the player's bullet is `collision_layer = 64`. Two indestructible
obstacles, by accident. The squad was swapped to `fighter`, and
`test_every_squad_ship_can_be_hit_by_the_players_primary_weapon` now makes the whole class of
mistake impossible to repeat quietly. `ram_ship`'s own immunity — plus the dead `max_health = 999`
in its config that nothing applies — is filed as a design call, not fixed here.

The same round found that registering adds with `ScoreTracker` also opts them into the 0.75×
escape-combo penalty. **Accepted deliberately** (see *Known gaps*).

### Sub-item 5's round 1 rejected the test plan, not the design — three times over

- The headline "the blasts land in the container" test **could not fail for the right reason**:
  `hit_effect.gd:21,34` keeps a permanent `CPUParticles2D` under every `BaseEnemy`, so a recursive
  search always finds one and a direct search is vacuously true.
- The determinism test compared **world** offsets, while the same plan rotates the hull — a frame-
  timing race dressed as an assertion.
- The end-to-end test would have **leaked `SceneTreeTimer`s with the gate green**. Compressing
  Level 1 for a test needs `stagger_delay` zeroed as well as `spawn_delay`, because every formation
  type staggers its own slots.

Round 2 approved with one blocking pre-condition, also correct: the `ExplosionEffect` must be a
child of the **station**, never of the sequence node, because `explosion_effect.gd` resolves its
container as `get_parent().get_parent()` — one hop too deep and every blast is created *inside* the
rotating hull, freed with the wreck and invisible to the container the director polls. It must also
be added in the `death_started` handler rather than `_ready()`, for the same `_propagate_ready()`
reason as the bullet pool.

### Two design choices taken against the research, on purpose

- **No escalating fire rate for surviving turrets.** The Gradius pattern ("the more cores and
  turrets you have destroyed, the fiercer the rate of fire of the remaining ones") was found in
  research twice and rejected both times: the 4→3→2→1 quietening *is* the player's reward for
  shooting the right thing, and speeding up the survivors would cancel out the feedback loop the
  armour rule exists to teach.
- **No `Engine.time_scale` on the death blow**, despite two sources asking for hitstop and a
  screen-flooding slowdown. `LevelDirector`'s progression runs on `get_tree().create_timer()`, as
  do every gunnery and laser timer, so a global time scale would slow the level's state machine
  along with the spectacle. Recorded as a follow-up, not built.

### One split

Sub-item 4 was split into **4a** (the station's own fire) and **4b** (reinforcements) during the
laser-phase cycle on 2026-09-02. As written it bundled two independent systems with separate
research questions, each about one session.

---

## Numbers

Full per-field rationale lives in
[`ENEMY.md` → *Config exports*](../../../assault/scenes/enemies/space_station/ENEMY.md). This is
the provenance summary — **R** = from research, **C** = derived from existing code/geometry in this
project, **J** = judgement call with no citable source.

| Value | Shipped | Src | Where it came from |
|---|---|---|---|
| Turret count | **4** (scene children, no export) | R | Top of the shipped 1–4 guarded-core range (Gradius); 6 is a cited pain point (Star Fox). Also places symmetrically on a square hull. |
| `max_health` | 600 | J/C | Set *together* with turret HP against a 30–60 s fight, because HP-as-difficulty is the named damage-sponge failure mode. |
| `turret_health` | 120 × 4 | J/C | Same. |
| `collision_damage` | 40 | C | Re-applied to the `HitBox` after `super._ready()`, which would otherwise leave `BaseEnemy`'s hardcoded 20. |
| `score_value` | 1000 | J | Core only; turrets award nothing. |
| `laser_warn_duration` | **1.4** | R | Danmakufu's 120-frame (2.0 s) delay laser, converted through `LaserRay`'s own 0.56 s charge-up → 1.9–2.0 s measured to lethal. ~6× the 200–300 ms reaction floor. Deliberately below the 3.0 s Level 1's static laser columns use, which would not fit twice in a volley cycle. |
| `laser_active_duration` | 2.0 | R | The 120-frame Master Spark. |
| `laser_volley_interval` | 6.5 | R/C | Inside the 5–10 s attack-switch band, and must exceed the full beam lifetime (`warn + 0.56 + active + 0.84` dissolve ≈ 4.8 s), leaving ~1.7 s of clear screen. |
| `laser_rotation_speed` | 0.5 rad/s | **J** | **No source gives degrees/second.** Research gave only "constant angular velocity". Derived: at the ~400 px the player sits from the hull, `ω·r` = 200 px/s = half the player's 400 px/s top speed (`move_state.gd:21`). |
| `laser_beam_count` | 2, opposed | R | Bounded by "the swept region must not be the whole screen"; two beams always leave two large clear quadrants, four at 90° leave nowhere to stand. |
| `emitter_radius` | 140 (on the node, not the config) | C | Scene geometry in final on-screen pixels, so it is an export on `StationLaserPhase`. |
| `turret_fire_interval` | 1.8 | R/C | 4 × 3 / 1.8 s = 6.7 bullets/s at full strength, decaying to 1.7 with one gun left. |
| `turret_burst_count` | 3 | R | The chunking rule — the smallest chunk that reads as a line rather than a stray shot. |
| `turret_burst_arc` | 0.35 rad (~20°) | J | Wide enough that strafing does not dodge all three, narrow enough to read as one fan. |
| `turret_bullet_damage` | 12 | C | Between the interceptor's 4 and the gunship's 15; four turrets at once must not out-damage the station's own 40-damage contact hit. |
| `turret_bullet_speed` | 240 px/s | R/C | 60 % of player speed, inside the shipped 220–260 band and the Touhou 70–90 %-slower benchmark. |
| `core_ring_interval` | 2.0 | R | Phase 2 changes every ~2 s against the 6.5 s laser cycle. |
| `core_ring_count` | 10 | R/C | ≥3 per ring (Sparen); spacing `TAU/10` = 36° ≈ a 188 px gap at 300 px, dodgeable at 400 px/s. |
| **`core_ring_step`** | **0.24** | **R** | Golden angle: `spacing × 0.381966`. **Load-bearing and test-pinned.** See *Decisions* for what 0.21 would have done. |
| `core_bullet_damage` | 10 | J | Softer than the turret fan, because ring bullets cannot be avoided by position alone. |
| `core_bullet_speed` | 210 px/s | R/C | 52 % of player speed — the slowest of the three, because phase 2 already has beams to dodge. |
| `pool_size` | 48 | C | Derived from the phase-1 peak (6.7 bullets/s × ~4.1 s of flight ≈ 37) with ~11 of headroom. |
| `reinforcement_first_delay` | 8.0 | R/J | The opening belongs to the boss alone — adds during a boss's introduction are the main way it ends up overshadowed. ~two turret volleys. |
| `reinforcement_interval` | 10.0 | R | Top of the 5–10 s band, so a squad is an *event* punctuating the 1.8 s turret cadence. 2–3 squads over a ~25–35 s phase 1. |
| `reinforcement_max_alive` | 4 | J | Two squads. A squad is skipped **whole** rather than partially, so the ceiling is exact. |
| `reinforcement_lifetime` | 7.0 s (on the node) | C | Geometry-adjacent, so it lives with the squad table rather than in the config. |
| Spawn margins | design x ±440, y ±290 | R/C | Against `ArenaCamera` (`SCREEN_W 1280`, `H_LIMIT 100`, `V_LIMIT 380`, `WORLD_SCALE 2.0`) and the largest reinforcement sprite (interceptor, 64×74, half-extent 37). Horizontal has 103 px of headroom; **vertical knowingly ignores camera pan** — see *Known gaps*. |
| `death_sequence_duration` | 1.8 (script default 0.0) | **J** | No source gives a number. Short enough not to be resented on a fifth retry; inside the 180 s section timeout so it can never race the safety net. The `0.0` script default is the honest fallback — identical to `BaseEnemy`. |
| `death_blast_count` | 7 (script default 3) | **J** | Seven reads as a chain, three reads as a hiccup. |
| `death_spin` | 1.2 rad/s decaying to 0 | R/J | The wreck should visibly degrade rather than stop dead; the hull is already rotating, so letting the spin die away is the cheapest legible degradation. |
| Shake | 1.0 at the final blast, 0.25 per chained blast | R/C | Resolves a genuine source disagreement by counting call sites: all four existing `CameraShake` calls are the player's own ship, so a boss-death shake is unambiguously rare here. **Measured caveat:** `camera_shake.gd:24` decays at 1.5/s, so a 0.25 blast is fully decayed inside the blast interval — the chain never accumulates and contributes ~0.5 px. That is intended ("a whisper for the chain, a spike for the finale"); do not "fix" the invisibility by raising it without re-reading `station-death-handoff/2-research.md`. |
| `enemies_cleared_timeout` | 180 (station) / 10.0 (default) | R | G-Darius's per-boss timer as the genre floor. The default keeps `cloud_descent` bit-identical. |
| Spawn placement | `at(0, -90)` → world (640, 180) | C | 640×360 design units × `WORLD_SCALE` 2.0. The 256 px hull then spans world y 52–308, leaving ~412 px of play space below. |
| Sprite sizes | 256×256 hull, 64×64 turrets, `scale = 1` | R/C | 4× the 64×64 player. Authored at **final on-screen pixels** — `WORLD_SCALE` applies to spawn offsets and paths, never to sprites. Fits `create_image_pixflux`'s 400 px limit at 1 generation. |

---

## Known gaps

Ordered by how likely each is to bite. **The first one subsumes most of the others.**

1. **Nobody has ever played this fight.** Not once, not partially. There is no GUI in the build
   container, so every claim in this dossier about how the encounter *feels* — that 1.4 s of
   telegraph is fair, that four turrets is interesting rather than tedious, that 6.7 bullets/s is
   pressure rather than noise, that the two-phase flip lands as an escalation, that a 1.8 s death
   reads as a chain rather than a stutter — is an inference from research and arithmetic. All of it
   is a first pass awaiting a human at a keyboard. **This is the single most valuable thing a human
   could do with this epic.**
2. **`station_core.png` renders as an opaque grey square.** Measured: **65536/65536 pixels at alpha
   1.0**, corner alpha `1.00` — against `station_turret.png`'s 54.7 % opaque and corner alpha
   `0.00`. Cause: `create_image_pixflux`'s `no_background` defaults to unset and paints a
   background unless you pass `no_background=True`. Nobody saw it because the station is never
   drawn against the starfield in any test; it only surfaced when the core and turrets were
   composited for a visual check. **The boss is therefore known to look wrong on screen right
   now.** Fix: regenerate with `create_map_object` (400×400 max, so 256×256 fits) or alpha-key the
   existing grey. Filed as an open code-health task.
3. **Turret barrels point away from the player.** `space_station.tscn` places every turret
   instance at `rotation = 0`, so all four barrels point toward the top of the screen — away from
   the player, who is always below the station. `StationGunnery.fire_turret_volley()` sets each
   firing turret's `global_rotation` at the moment it fires, so barrels *snap* to the player rather
   than tracking, and the resting pose is wrong. Filed as an open code-health task; `test_turret_barrels_face_the_player_when_firing` pins the firing behaviour, not the resting
   pose.
4. **Collision layers are still only half proven.** Nothing yet demonstrates that a player
   **bullet** can physically reach the core's layer-512 hurtbox or a turret's.
   `test_space_station.gd` emits `received_damage` directly; `test_station_laser_phase.gd` proves a
   real physics overlap but only for the *player* layer against a `LaserRay`. Closing it needs a
   test that instances `assault/scenes/projectiles/bullets/bullet.tscn`, positions it in a turret
   lane and steps physics — the suite has **no precedent** for physics-overlap tests, so budget for
   the technique. Two open code-health tasks track this; it has now been deferred across three
   sub-items, which is long enough to call it a pattern rather than a scheduling accident.
5. **No boss-arrival beat.** The genre-standard "WARNING! A HUGE BATTLESHIP IS APPROACHING"
   framing (Darius 1987 onward) was researched, found to be standard, and deliberately left
   unbuilt as scope creep. It is still unbuilt — nothing in `EventBus` or `LevelDirector` announces
   a boss. Research also warns why it matters: a *stationary* boss with no arrival framing reads as
   **scenery rather than a boss**. This is the largest missing piece of presentation and the most
   likely reason a first playtest reports "I didn't realise that was a boss".
6. **Ignoring a reinforcement squad costs the player score, deliberately.**
   `score_tracker.gd:211` applies the 0.75× escape-combo multiplier **outside** its
   `if counts_in_wave:` block, so a `wave_index` of `-1` is not exempt. A player who correctly
   ignores a squad to focus the boss pays 0.75 twice per squad (0.5625) and floors their multiplier
   after about three. 4b accepted this — the alternative is that killing a reinforcement awards
   *nothing*, which reads as a bug — and pinned the exact number in
   `test_a_squad_that_flies_through_costs_two_escape_combo_penalties`. Filed so the user can
   overrule; the real fix is a `counts_as_escape` flag on the spawn, not a special case.
7. **Phase 2 has no aimed component.** The core ring is fixed-angle and the beams are static in
   kind, so nothing in phase 2 tracks the player. Recorded as a risk in
   `station-bullet-hell/3-plan.md`, justified only because the hull rotates, the ring precesses and
   the beams sweep — so no position is safe *over time*. Unverified in play, and the first thing to
   re-examine if phase 2 turns out to have a safe spot.
8. **The core hurtbox spans the whole hull.** `space_station.tscn:16-17` uses one 240×240
   `RectangleShape2D` for both the body collider and the core `HurtBox`, so the four turret
   hurtboxes sit strictly inside it. Not a reachability bug (see *Decisions*), but shooting the
   hull shoulders registers as a *deflected core hit* rather than a miss, and a shot up a turret
   lane triggers a core deflection before it reaches the turret. Needs a deliberate design call;
   cost is one `sub_resource` and one node property.
9. **The vertical spawn margin cannot survive a full camera pan.** Reinforcements spawn at design
   y ±290 (580 world px) against a strict requirement of 360 + `V_LIMIT` 380 + 37 = 777. This is a
   deliberate match to the project-wide convention that every spawn resolves against
   `cam.global_position` (the *fixed* centre) rather than the panned view — so it is a pre-existing
   project property, filed as its own code-health task, not something 4b introduced.
10. **`ram_ship` remains unkillable by the primary weapon**, and its config `max_health = 999` is
    dead code. 4b routed around it rather than fixing it, because whether the immunity is intended
    is a design call. Filed.
11. **The player's default shot is effectively infinitely piercing.** Discovered while
    relitigating sub-item 2's B1 (see *Decisions*). It makes `PierceModule` look like it exists to
    *limit* damage rather than add it, and it is a real balance question for any multi-part target
    — this boss most of all. Filed, not acted on.

---

## Links

- **Epic id:** `station-mini-boss` (6/6 tasks `done`; epic status `done` in `BACKLOG.json`).
- **Plan directories** — the audit trail, including all thirteen review rounds:
  [`station-mini-boss-destructible`](../../plans/station-mini-boss-destructible/) ·
  [`station-assault-section`](../../plans/station-assault-section/) ·
  [`station-laser-phase`](../../plans/station-laser-phase/) ·
  [`station-bullet-hell`](../../plans/station-bullet-hell/) ·
  [`station-reinforcements`](../../plans/station-reinforcements/) ·
  [`station-death-handoff`](../../plans/station-death-handoff/)
- **Commits:** `60a3d31` (1) · `c60742b` (turret sprite regeneration) · `ad5c70f` (2) ·
  `479a66d` (3, plan only — blocked at review, no code) · `20bb290` (3) · `4762c42` (4a) ·
  `9079a20` (4b) · `66862bd` (5) · `4000f6e` (post-epic signal-arity hygiene).
- **Entity doc:** [`assault/scenes/enemies/space_station/ENEMY.md`](../../../assault/scenes/enemies/space_station/ENEMY.md)
  — the per-node walkthrough, the traps, and the per-field tuning rationale.
- **Module docs touched:** `docs/architecture/PROJECT.md`, `docs/architecture/modules/assault.md`,
  `docs/architecture/modules/global.md`, `docs/BULLET_POOL.md`, `docs/enemy-roster.md`,
  `tests/README.md`.
