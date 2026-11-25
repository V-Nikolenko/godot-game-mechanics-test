# Context — Enemy rework, phase 12: Dreadnought hunting boss

Research stage, task `cmug256th003pm52whp1pyy8c`, epic `cmug256tc003lm52wbdoxucrr`. Code read at `cf2562a` (agent/auto-dev, 2026-11-25). The scope check,
web findings and candidate approaches are in `2-research.md`; this file is what already exists and what constrains the design.

Read before this: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` → *Phase 10 - as built*, *Phase 11* (planned decisions) and *Phase 11 - as built*;
`docs/epics-done/cmug256so0031m52wbxomst72/REPORT.md` (Ph11) and `docs/epics-done/cmug23oo90029m52wae4clve0/REPORT.md` (Ph10).

## Requirements from the attached documents

Quoted briefly from `docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` (IDEAS). `ENEMIES.md` describes the pre-rework roster
and has nothing Dreadnought-specific; its relevant parts (the retired station's multi-part pattern) are superseded by the Ph11 fortress code.

| # | Requirement (IDEAS §) | Note |
|---|---|---|
| R1 | "Size 320–480 px" (§9, §21.3 "320–512 px = boss") | player ship is 64 px |
| R2 | "The opposite of the Space Fortress: a large ship that actively hunts the player" (§9 Role) | fortress = holds a zone; Dreadnought = pursues |
| R3 | "a central hull plus detachable weapon modules" — turret, missile, engine ×2 around a core hull (§9 diagram) | §14 module list shape |
| R4 | "uses long arcs around the player rather than tracking directly … two enormous bodies trying to change position relative to each other" (§9 Movement) | |
| R5 | Attacks: "broadside cannon sweep", "missile fan", "energy torpedo", "engine wake hazard", "heavy ram when critically damaged" (§9) | five distinct attacks |
| R6 | §24: "A Dreadnought uses broadside cannons." "A multi-engine boss leaves dangerous exhaust trails." | weapons from the geometry |
| R7 | "The player can choose what to disable first: weapons, engines, shields, core … without requiring a menu or weak-point prompt" (§9 Destruction order) | no phase locks on the four target classes |
| R8 | "When one engine is destroyed, the Dreadnought becomes asymmetrical and its movement visibly changes." (§9 Phase shift) | |
| R9 | "When both engines are destroyed, it becomes stationary but enters an extreme weapons phase." (§9) | |
| R10 | §10: "Dreadnought: launches interceptors when a weapon module is destroyed … destroying a module changes what the player has to fight next" | from *that* module |
| R11 | §25: every phase changes ≥ 2 of movement / attack pattern / vulnerable areas / arena control / reinforcement behaviour / visual state; example "PHASE 4 critical: engines overload, boss attempts a final ram" | gated by `test_boss_phase_rules.gd` |
| R12 | §26: "destroying a carrier engine changes its movement arc", "destroying a turret removes one attack angle", "destroying a missile rack causes missiles to stop" | applied to the Dreadnought |
| R13 | §22: "Build carriers and bosses from multiple coherent modules so the damage state can change the silhouette." §23: "Boss: destroyed modules visibly remain as wreckage." | art |
| R14 | §21: silhouette + faction accents + gameplay lights (red armed, yellow charging, white locked, cyan shield, orange overheating, dark destroyed); cool edge light; never recolour the whole hull | art |
| R15 | §40 Large enemies: "module death disables attack", "module death changes movement", "core becomes vulnerable only when intended", "destroyed components remain as wreckage"; Mode compatibility: tests in Open Space **and** Assault with the same spec | the epic adds: engine loss changing movement, module death disabling its attack, the critical ram |
| R16 | §41 Phase 5 item 2: "Dreadnought — use the new module architecture" | Ph10 `EnemyModule`/`ModularHull`, Ph11 `global/boss/` |
| R17 | Epic: "an Assault adaptation within the corridor constraint and an Open Space placement for testing and hub use" | §34 corridor, §20 "same machine in both modes" |
| R18 | §43 design checklist (silhouette, preferred distance, movement signature, telegraph, behaviour when approached from behind / when the player boosts away, deterministic tests) | Ph17 audits; Ph12 should answer it in ENEMY.md |
| R19 | §18.6: "A heavy dreadnought partially resists [a gravity well]" | `hazard_resistance` |
| R20 | §11.2/§11.3 families: torpedo is not in any family yet; "missile fan" reuses the rocket family | new projectile or a variant |

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/boss/boss_phase.gd`, `boss_phase_driver.gd` | `BossPhase` (Trigger START / PARTS_DESTROYED / HEALTH_AT_OR_BELOW; Change bit flags) and the **ordered, one-way** ladder: `evaluate()` only ever enters `_index + 1` (`boss_phase_driver.gd:52-59`), "a later phase never jumps its predecessor" | The Dreadnought's free destruction order does not fit one linear ladder (see `2-research.md` §3.1) |
| `global/boss/reinforcement_bay.gd`, `boss_reinforcements.gd` | Bays on parts; door cycle; caps; PERIODIC / ON_SECTOR_LOSS / ON_PHASE; `surge()`; `config_overrides`; escorts into `EscortContainer`, `EventBus.boss_escort_spawned` | **A bay whose part is destroyed is killed in the same call** (`boss_reinforcements.gd:372-379` `_on_module_destroyed` → `_kill`) — R10 "launch from the destroyed module" needs a new rule |
| `global/boss/shield_sector.gd` | generator part + protected parts, one 360° `EnemyShield` bubble each, exposed for good on the generator's death | the "shields" destruction choice |
| `global/boss/escort_container.gd`, `boss_death_sequence.gd` | lazy `<boss>Escorts` sibling; the shared death spectacle (host contract `death_started`, `death_duration`, `config.death_blast_count`) | reused unchanged |
| `global/components/enemy_module.gd`, `modular_hull.gd` | parts (`Role { WEAPON, ENGINE, HANGAR, CORE, WEAK_POINT }`), wreckage that stays, locked parts, killing-shot rule; `build_mounts()`, `live(role)`, `destroyed_count()`, `mounts_of()` | every Dreadnought part |
| `assault/scenes/enemies/space_fortress/*` | the only boss on the machinery: armoured r 176 hull (`deflects_hit`/`is_armored` true), core death = boss death, two `ShieldSector`s, 4-phase ladder, `phase_snapshot()` (six keys from phase-driven state only), bays, geometry weapons, EMP factor, death order | the template for the Dreadnought root (`space_fortress.gd` is 519 lines) |
| `assault/scenes/enemies/carrier/carrier_brain.gd` | **engine-loss movement already exists**: `turn_factor()` / `speed_factor()` / `sway_factor()` keyed on `engines_alive`, and a *list* (`_face()` sags the facing toward the dead side at `list_rate` until `list_hold_deg`, lines 378-397) | closest prior art for R8; note it bends the **facing**, not the path |
| `assault/scenes/enemies/heavy_gunship/heavy_gunship_brain.gd` | BROADSIDE: a wide orbit about the player at held range, reversing every few s, a battery side turned to the player; the chosen side kept while its battery lives | closest prior art for R4/R5 broadside |
| `assault/scenes/enemies/ram_corvette/ram_corvette_brain.gd` | LINE_UP → WIND_UP (aim tracks for a fraction, then freezes) → CHARGE (`mover.boost` to `overshoot` past the frozen point, ≤ `charge_max_time`) → WIDE_TURN; Assault diagonal charge; STAGGER | the critical ram's state shape (config: wind-up 0.65 s, charge 620 px/s, overshoot 220 px) |
| `global/enemy_ai/enemy_mover.gd`, `steering.gd`, `dubins_path.gd` | the single writer of motion; `boost()` skips avoidance and accel (the Ph6 "committed run" rule); `Steering.turn_toward()` is **the only way a brain bends a path** (DECISIONS Ph2: `max_turn_rate` turns the sprite only, "Dreadnought arcs must use this"); `DubinsPath` plans min-radius paths | R4 arcs, R8 lopsided arcs |
| `global/enemy_ai/anchor_idle.gd`, `target_info.gd`, `engagement_budget.gd`, `line_of_sight.gd` | hub idle handover; prediction (`predicted_position`, `intercept`); Assault budget (bosses have none); LOS on physics step only | hub idle; ram / torpedo lead |
| `global/hazards/hazards.gd`, `hazard_info.gd`, `hazard_field.gd`, `assault/scenes/hazards/reactor_field/` | registry sampled by bodies; `HazardField` with `duration`, hull stress via `Hazards.pulse_damage` (centre distance, groups `enemies` + `player`, bypasses `EnemyShield`), `spawn_into()` deferred into `Hazards.container(tree)`; `ReactorField` = a timed stress-only field with a drawn ring at its full radius; `HazardInfo.segment_half` (wall) and `exempt_group` (avoidance only) | the engine wake (R5/R6) |
| `assault/scenes/hazards/wreck/debris_fragment.gd`, `ram_fragment.tscn` | a drifting collision hazard (not cover, no LOS), `source` keeps it from hitting the ship it broke off, self-freeing | "modules detach" (R3/R13) without Ph19 LOS work |
| `assault/scenes/enemies/defense_turret/mounts/*` | `TurretMount` cycle + variants (`BURST_CANNON`, `SWEEP_BEAM`, `ROCKET_BATTERY`, `PULSE_RING`, `LANCE`, `BEAM_CANNON`, `HEAVY_CANNON`, `SPREAD_CANNON`, `RAPID_PULSE`), `traverse_deg`, `telegraph_gate`, `pool_period_factor`; `TurretMountBuilder.build()` | broadside batteries, missile rack, torpedo tube |
| `.../mounts/rocket_battery_mount.gd` | a salvo of `salvo_count` rockets `salvo_gap` apart along the barrel, DUMB / PURSUIT by `pursuit_chance`; pools persist | "missile fan" = this plus a spread (it has no fan today) |
| `assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd` (+ `cluster_rocket.tscn`) | `Kind { DUMB, PURSUIT, CLUSTER, WARHEAD, SUBMUNITION }`, shot down by one bullet, blast-only damage to the player, `persist`ed pools; Cluster = a 36° fan of 4 submunitions | missile fan; torpedo candidate |
| `assault/scenes/projectiles/enemy_ordnance/enemy_ordnance.gd` (+ `pursuit_bomb.tscn`) | `Kind { GRAVITY_BOMB, MINE, PURSUIT_BOMB }`: shootable (`Health`), proximity trigger, `ContactBlast`; the pursuit bomb steers 1.5 s at 1.2 rad/s then accelerates to 380 px/s | torpedo candidate |
| `assault/scenes/projectiles/enemy_bullet/rounds/` | Pulse, Scatter, Gatling Stream, Heavy Shell (220 px/s), Rail; `EnemyRounds.pool_size_for()` | broadside rounds |
| `assault/scenes/projectiles/enemy_beams/*` | `EnemyBeam` (owner-ticked), `EnergyRing`, `EnergyHitScan` (`VICTIM_GROUPS` player / allies / enemies / asteroids, owner set exempt; never reaches parts — Ph18/19) | only if the plan picks a beam weapon |
| `global/components/contact_profile.gd` | `Mode { NONE, COLLISION, RAMMING, EXPLOSIVE, ARMOR }`; **damage is always `config.collision_damage` in every mode** (`test_enemy_contact_damage.gd`'s one rule); ARMOR shoves via `apply_knockback` | a ram that hurts more than a touch needs a second box or one number (`2-research.md` §3.6) |
| `assault/scenes/systems/wave_builder.gd` | `space_fortress()` / `SPACE_FORTRESS` (line 144 / 320) | `dreadnought()` / `DREADNOUGHT` |
| `assault/scenes/systems/assault_corridor_constraint.gd`, `arena_camera.gd` | velocity filter over the 1480 × 1480 world rect (soft band 120, hard band 450, edge pressure 200); view 1280 × 720 | R17: a 400 px hull is ~27 % of the corridor's width |
| `assault/scenes/levels/edelia/1/level_1_director.gd` | level 1; `station_assault` holds the fortress (240 s) | whether the Dreadnought is placed in a level is an owner choice (`2-research.md` §1) |
| `open_space/scenes/levels/sector_hub.gd` | draws 1–21 appended in order (fortress draw 21: 4200 ring, −45°), `HazardContainer` present | draw 22 |
| `tests/integration/test_sector_hub_patrol.gd` | `_patrol_groups()` clearance sweep, sweeps A/B/C, hard live-child counts | the hub placement must pass it; a hunter's footprint is its leash |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `SpaceFortress` root pattern | armoured hull, `_apply_config()` writing part HP, core death → `health.set_health(0)`, `_on_health_changed` death latch, `_make_corpse_harmless()`, `_finish_death()` with a `Timer` node (the leak rule), `answers_emp()` true while dying, `apply_emp × emp_factor`, `homing_point()`, `deflects_hit` / `is_armored` / `is_laser_blocking` false / `accepts_ward` false / `launch_velocity` / `rocket_clear_radius`, `phase_snapshot()` six keys |
| `BossPhaseDriver` / `BossPhase` | the ladder and the §25 gate (`test_boss_phase_rules.gd` already collects **every** driver in an instantiated boss, `_drivers_of()`), so two drivers on one host are gate-compatible |
| `BossReinforcements` + `ReinforcementBay` | doors, caps (`escort_cap_*`), `assault_count`/`assault_period`, `config_overrides` (make escorts fire within 3 s), `surge()`, escorts scuttled on death, scoring path |
| `ShieldSector` | generator → bubbles; `StateLight.SHIELDED` |
| `ModularHull.build_mounts()` / `TurretMountBuilder` | every mount on a part, pools as root children, UNPOWERED on part death (R12 "module death disables attack" is free) |
| `TurretMount.traverse_deg` | a broadside battery that covers only its own beam (Carrier: 150° per side) |
| `BurstCannonMount.pellets` / `pellet_spread_deg` (Ph11 t3) | the pattern to copy for a rocket fan (`RocketBatteryMount` has no spread) |
| `CarrierBrain` engine factors and list | engine-count-keyed limits; list sign from which engine died |
| `RamCorvetteBrain` | the line-up / wind-up (track then freeze) / boost-through / overshoot / wide-turn cycle and its budget / gate rules |
| `Steering.turn_toward`, `Steering.clamped_lead_time`, `DubinsPath` | arcs and the ram lead |
| `HazardField` + `ReactorField` + `Hazards.pulse_damage` | a timed, drawn, stress-damage field spawned deferred into the hazard container: an engine-wake "puff" with no new damage path |
| `DebrisFragment` / `ram_fragment.tscn` with `source` | a module chunk flung off on destruction that never hits its own ship |
| `StateLight` states (OFF, ARMED, CHARGING, COMMIT, VENTING, SHIELDED) | gameplay lights per part (R14) |
| `AnchorIdle` | hub idle → combat handover (`start_engaged` skips it) |
| `tests/helpers/enemy_ai_harness.gd`, `fixture_modular_host.tscn`, `fixture_boss_host.tscn` | both-harness tests (`use_parameters(MODES)`), boss machinery fixtures |
| `test_fortress_weapons.gd` density method | count launches, return each round at once, fail if a pool reported empty (the Ph11 density method; DECISIONS says "Later bosses (Ph12 Dreadnought) measure the same way") |

## Conventions that constrain this

- **Composition, config-driven, flat config.** `DreadnoughtConfig extends ShipConfig`, flat (no nested resources: `test_config_instance_isolation.gd`), private copy via
  `privatise()`; the config wins over scene `Health`; `contact_hit_box.damage = cfg.collision_damage` in `_ready()`.
- **Brain requests, mover writes** (`test_enemy_mover_single_writer.gd`): the brain never writes `velocity` / `rotation` / `move_and_slide()`; arcs bend through
  `Steering.turn_toward` on the brain side; committed runs (the ram) are `mover.boost()` and ignore hazard avoidance (Ph6). A brain that faces a point authors
  `EnemyMover.turn_lerp = 0` (Ph11).
- **Parts under `Modules`**, never root children; each part one `HurtBox` shape; destroyed = wreckage that stays (visual only; LOS-blocking wreckage is Ph19).
- **Pick one hull rule per boss** (Ph10): *vulnerable hull* (root `Health` is the phase bar; flush-edge rule) or *armoured hull* (root refuses damage; death = CORE's).
- **§25 snapshot from phase-driven state only** (Ph11 R1): the hit that triggers a phase never counts as one of its changes; a declared change that cannot happen on some path
  gets its own row asserting ≥ 2 changes.
- **Fairness from instantiated nodes + measured Assault density in every boss phase**: fortress ceilings mean ≤ 13.3 rounds/s, peak ≤ 30 per half-open 2 s window,
  ≤ 2 committed attacks (3 in critical); hand-ticked density rows count launches and return rounds at once; tune in a stated lever order, never widen a ceiling.
- **Every projectile has one owner**; persistent ordnance through `persist_after_owner_death`. A boss in an `ENEMIES_CLEARED` section with persisting pools is a **third**
  exception and must be added to `test_engagement_deadline.gd`'s allowlist deliberately.
- **Boss escorts** come out of a bay on a part with a door telegraph, into `<boss>Escorts`, announced on `EventBus.boss_escort_spawned`, never `enemy_spawned_orphan`; scuttled on
  the boss's death; nothing writes their `counts_toward_wave_clear` / `counts_as_escape`.
- **Clocks** are accumulated `delta` (`x -= delta`, over at `x <= 1e-6`); no `Timer` / `create_timer` in weapons or brains; a `Timer` *node* for the death free (leak trap).
- **Design units:** Assault spawns at `.at(x, y)` in 640×360, scaled by `ArenaCamera.WORLD_SCALE`; `world_anchored_x` (Carrier / fortress rule) for a boss.
- **EMP:** `BaseEnemy.answers_emp()` routing; bosses scale every source by `emp_factor` (Ph11 owner choice 6); a boss keeps answering while dying.
- **Naming:** never "station" for a boss. Signals declare what they emit; per-frame prints behind `OS.is_stdout_verbose()`.
- **Hub draws are appended** (draw 22) so every earlier seed is unchanged; `patrol_anchor` / `rng_seed` set before `add_child()`.
- **Exit-probe calls** for a new Assault enemy go through a `tests/helpers/phN_exit_keys.gd` helper (Ph8–Ph10 rule) — only if the Dreadnought ever exits (a boss does not).
- **Art:** `pixel-art-generation` skill; strict top-down; textures at scale 1 and the size of their hurtboxes (Ph10 t9 / Ph11 t9); ≤ 90 % opaque
  (`test_entity_sprite_transparency.gd` walks every `Texture2D` property); `create_map_object` above 40 000 px paints a background (strip it).

## Dependencies and blast radius

- **Shared machinery changes** (each must be bit-identical for the fortress, gated by its existing suites): a non-linear phase rule (§3.1 of the research), a
  "launch on own destruction" bay trigger (§3.4), a rocket fan on `RocketBatteryMount` (§3.3), possibly a torpedo kind (§3.3). These touch `global/boss/`, the mount
  family and the rocket/ordnance family — every fortress, carrier, gunship, turret and corvette test is the regression net.
- **New scene family** `assault/scenes/enemies/dreadnought/` joins every roster sweep: `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`,
  `test_enemy_hurtbox_geometry.gd` (+ the three roster-completeness guards), `test_config_instance_isolation.gd`, `test_base_enemy.gd` (`_MIN_ROSTER_SIZE`, excluded-from-generic
  flow, authored contact modes, tow refusers), `test_entity_sprite_transparency.gd`, `test_signal_emit_arity.gd`, `test_enemy_mover_single_writer.gd`,
  `test_collision_layer_names.gd`, `test_project_load_integrity.gd`, `test_resource_uid_integrity.gd`, `test_boss_phase_rules.gd`, `test_enemy_bullet_lifetime.gd` (any new round
  speed source), `test_explosion_effect_placement.gd`.
- **Hub**: `test_sector_hub_patrol.gd` hard counts move by one (Ph11 t13 precedent); the hunter's leash is its footprint for sweep B.
- **Level 1** only if the owner chooses a placement (`station_assault` and the fortress tests, the deadline allowlist).
- **Docs** (`updating-project-docs`): `docs/architecture/modules/global.md` (boss machinery additions), `assault.md`, `docs/enemy-roster.md`, a new `dreadnought/ENEMY.md`,
  `PROJECT.md` conventions, `CLAUDE.md` gate list, `tests/README.md` gate time.
- **Gate time**: GUT ≈ 225.2 s after Ph11 t11 (`tests/README.md` → *Gate time*), ceiling 240 s, Ph11 escalation at a 237 s two-run mean. Ph11 spent +18.1 s of allotments;
  Ph12 has ≈ 12–15 s before the escalation line, so either a gate-room task first (Ph10 t1 freed 32.6 s by moving paced files to 16×) or a ≤ 10 s total allotment.

## Risks, edge cases, testing requirements

- **Free order vs a linear ladder**: with one ordered ladder, a `critical` phase behind the engine phases would be unreachable by a player who goes core-first; a ladder in
  any fixed order contradicts R7. Edge: core critical *and* both engines dead → no ram is possible (a stationary hull cannot ram), so the two end states are exclusive and
  both need ≥ 2 changes.
- **Ram fairness on a 400 px body**: the swept lane is the hull's width; the player must clear half the hull width + its own radius during the telegraph; a frozen line
  (Ram Corvette rule) and a drawn lane are required. The player has 50 HP (`player_ship.tscn:224`, `player_fighter.tscn:295`); the Ram Corvette's 50 contact damage is a
  one-shot without shields, so a boss ram near that is a design decision, not a default.
- **Hunting in the hub**: a hunter that follows the player to mission triggers or the spawn breaks the hub; it needs a leash / hunting zone and must give up (RETURNING) —
  the sweep B footprint is the leash radius plus the arc radius.
- **Engine wake**: `Hazards.pulse_damage` hits every `enemies`/`player` node by centre distance — the boss's own escorts and other hub patrols too (friendly fire, like the
  Carrier ring, owner choice 8 of Ph10, or exempt the owner group); invisible damage if the drawn trail is not exactly the damage radius; hazard count growth (one
  registered node per puff; every enemy mover queries `Hazards.around()` each step); the wake must spawn only on the physics step, deferred (`spawn_into`), and never with no
  hazard container (tests must add one).
- **Self-damage**: the boss must not take its own torpedo / rockets / wake (`rocket_clear_radius`, owner group, the wake behind the hull; centre-distance damage means the
  root centre must never be inside a wake's `damage_radius`).
- **Interceptors on weapon death**: the launch must happen although its part is a wreck (current bays die with their part); cap, Assault launch limit, scuttle on boss death,
  a weapon part destroyed during the death sequence must launch nothing.
- **Asymmetric movement readability**: the Carrier's list is a *facing* sag; R8 asks the *movement* to change (path curvature / turn asymmetry), and Ph2 says only brain-side
  `turn_toward` bends a path. A row must measure the path (turn radius left vs right), not the sprite.
- **Stationary + extreme weapons**: density ceiling still applies (measured), pools sized with `pool_period_factor`; a stationary hull must still turn (rotation only) or a player
  sitting in a dead arc is safe forever.
- **Assault**: a hunter in a 1480-wide corridor; no budget, no exit (a boss); the ram must stay inside the corridor (constraint still filters `boost`); wakes persist in world
  space while the camera pans; spawning above the view with `world_anchored_x`.
- **Determinism**: brain rng seeded; hand-ticked rows use `_fresh_idle_delta()` where a boost is involved (Ph10 rule: a hand-ticked `move_and_slide()` moves by the idle delta).
- **Testing (both harnesses, `use_parameters(MODES)`)**, at minimum: engine loss changes the measured path (one engine → asymmetric turn radius / drift side; two →
  speed 0); a destroyed weapon module's mount is UNPOWERED and never fires again while the others do; the critical ram: telegraph ≥ its fairness bound, frozen line,
  overshoot, contact only while charging, no ram with both engines dead; interceptors launched from the destroyed module (position, count, cap, Assault limit, none
  while dying); §25 rows for every phase on every reachable path; density rows per phase; wake: lifetime, damage radius = drawn radius, no damage to the boss itself;
  hub sweep; art sizes and transparency.

## Open questions for the plan

1. **Phase structure for free order** — two drivers (engine track + hull track), an unordered driver mode, or engines outside the ladder (`2-research.md` §3.1).
2. **Hull rule** — armoured hull + core part (fortress) or vulnerable hull with HP-bar phases (gunship)? Research recommends armoured (§3.2).
3. **What "shields" protects** — bubbles on the weapons, on the core, or a directional bow shield; and whether the core starts vulnerable (R7 says no lock).
4. **Torpedo** — a new `EnemyRocket.Kind`, a new `EnemyOrdnance.Kind`, or a dedicated scene; shootable by how many hits; steering or straight.
5. **Ram damage** — one `collision_damage` (touch = ram) or a separate bow ram box with its own config field (contact-damage gate rule).
6. **Interceptor payload** — Gatling Interceptor pair, Razor Drone, or per-module (owner choice); the bay trigger change to the Ph11 convention.
7. **Level placement** — Assault adaptation tested in the harness only, or placed in a level (level 1 after the fortress, level 2 — not in the game flow — or a new section)?
8. **Wake friendly fire** — hurts other enemies (bait-able, IDEAS §18.6 spirit) or exempts the owner group.
9. **Gate time** — a gate-room task first, or a tight allotment.
