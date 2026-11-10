# Enemy rework, phase 10: modular damage, Heavy Gunship and Carrier

Revision 2 (2026-11-10), answering the round-1 plan review (`4-review.md`, CHANGES_REQUESTED, 17 findings; §8 says what changed for each). Epic
`cmug23oo90029m52wae4clve0`, phase 10 of the enemy rework (idea `docs/ideas/cmufkkgmx0001o02y6bnf52bq/`). **This directory has no `1-context.md` /
`2-research.md`:** the research task is marked done but left no files, so the plan stage gathered the context itself and records it here (§1.1 scope check, §1.2
research findings, §1.3 code facts). Code facts were read on `agent/auto-dev` @ `58a2b04`.

## Summary for the owner

- **For the player:** big ships stop being health bars. You take them apart: each gun, engine, hangar and missile pod has its own health, goes dark and stays on the hull as visible wreckage when destroyed, and losing it changes the fight.
- **Heavy Gunship (reworked):** no longer parks at the top of the screen. It keeps its distance, turns side-on so a gun battery faces you, sweeps wide arcs and boosts away if you rush it. Kill a side battery and that gun is gone for good, so it turns its other side to you. Its parts sit on the edge of the hull, so you hit them by aiming at the edge they face you with. Below 60% it overheats and has to vent: glowing vents open on its flanks and shots into them hurt double. Below 30% it boosts away and fires rear missiles at whoever chases it, but it stays in the fight instead of flying off and vanishing.
- **Carrier (new, the largest ship so far):** an armoured hull (shots glance off it) carrying two engines, two side gun batteries, two hangars and a core. Engines lost: it turns slower and lists. A battery lost: that side is safe from battery fire. A hangar lost: no more launches from it (and a hangar can only be hit while its doors are open). After any three of those six are destroyed the core's plating opens; the carrier panics (launches everything left, pulses faster, tries to escape) and dies when the core does. It also has a bow heavy cannon, a missile bank and a pulse ring that punishes hugging the hull.
- **Where:** level 1's four old gunships become Heavy Gunships; one Carrier crosses Planet Approach slowly between two laser-column volleys; both ships also patrol the Open Space hub.
- **Built for the bosses to come:** the part system, guns mountable on ships (with limited firing arcs) and the heavy cannon are shared pieces the fortress and dreadnought phases reuse.
- **Left out:** hangar launches and phases driven by the shared boss machinery (phase 18), enemy energy beams hurting parts, wrecks you can hide behind and heavy ships' mass rules (phase 19), EMP on the station and the phase 8 turrets (phase 11), encounter design (phases 13–14), sound (phase 17), score for individual parts.
- **Main risks:** the test suite is close to its time ceiling, so the first task must win back at least 12 s; level 1's laser columns and opening laser wall kill anything they touch, so the deep-space gunship and the Carrier are placed and checked by replays that really light the lasers; Cloud Descent's gunships must attack and leave inside its 10 s end window, which gives them a shorter fight (9 s) than elsewhere; Cloud Descent gets harder (its three old gunships never actually fired).
- **Choices for you (default in brackets):**
  1. When does the Carrier's core open: after any three of its six outer parts are destroyed, or only after both hangars? [any three]
  2. Cloud Descent's three old gunships never fired (a rail switched their brain off). Replace all three with firing Heavy Gunships, or only the first? [all three; if their exit cannot be made fast enough the task stops and asks you]
  3. Does a hit on a Heavy Gunship's part also wear down its hull (one damage pool for its phases, parts on top)? [yes]
  4. Can a hangar only be damaged while its doors are open? [yes]
  5. The Carrier's anti-approach pulse: a damaging ring now, or also an ability-locking EMP (phase 18)? [ring now, EMP later]
  6. In Assault the Carrier launches only swarm drones (fighters only in the hub), to keep level 1's fighter fire density unchanged? [yes]
  7. May the Support Ship shield a Heavy Gunship (it never shields the Carrier, whose armoured hull makes a shield useless)? [yes]
  8. The Carrier's pulse ring can hurt other enemies it touches (the jammer that shares its stretch of Planet Approach), the same friendly fire every enemy laser already has. Keep it? [yes]

## For every task

Phase 10 of the enemy rework. Read `CLAUDE.md`. Earlier phases' rules in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` stand unless a line here changes them.
- **`EnemyModule`** (`global/components/enemy_module.gd`, `Node2D`, group `&"enemy_parts"`): one destructible part. Children `Sprite` (`Sprite2D`), `HurtBox` (layer 512),
  `Health` (omitted or ignored when `max_health` is 0), optional `DefenseProfile` (its `_ready()` calls `apply_to($HurtBox)` itself), optional `MountSlots`, optional
  `HomingPoint` (`Marker2D`), optional `Light`. `enum Role { WEAPON, ENGINE, HANGAR, CORE, WEAK_POINT }`, `enum VisualState { INTACT, DAMAGED, WRECK }` (both append-only).
  Exports `module_id`, `role`, `max_health` (0 = indestructible), `starts_vulnerable := true`, `hull_share := 0.0`, `intact_texture`, `wreck_texture`, `damaged_ratio := 0.5`. API
  `is_destroyed()`, `is_vulnerable()`, `set_vulnerable(on)`, `deflects_hit(hit_box) -> bool`, `destroy()`, `mounts()`, `attach_mount(mount)`, `visual_state()`, `homing_point() ->
  Vector2`. Signals `damaged(module: EnemyModule, amount: int)`, `destroyed(module: EnemyModule)`, `deflected(module: EnemyModule)`, `vulnerability_changed(module:
  EnemyModule, vulnerable: bool)`. **Damage only through its `HurtBox.received_damage`** (after the type filter and the absorber slot); a non-vulnerable module ignores
  every damage, so direct emitters (player beam, nova, a level `LaserRay`) cannot hurt a locked part. Deflect decision cached per HitBox id; a module destroyed this physics
  frame still consumes the killing shot. **Destroyed = wreckage that stays** (hurtbox off deferred, wreck texture on the `Sprite` child, mounts UNPOWERED, out of
  `enemy_parts`, freed only with its host). Modules sit under a `Modules` `Node2D`, never direct children of the enemy root.
- **`ModularHull`** (`global/components/modular_hull.gd`, `Node` child of the host root): collects `Modules/*`, `build_mounts(...)` through `TurretMountBuilder` (pools are
  **host root children**), forwards `hull_share × amount` to the host `Health`, re-emits `module_destroyed(module)` / `module_damaged(module, amount)`; queries `module(id)`,
  `modules()`, `live(role)`, `destroyed_count(roles)`, `mounts_of(id)`. It holds no gameplay rule of either heavy (the Ph18 seam).
- **Two hull rules.** *Vulnerable hull* (Heavy Gunship): root `Health` is the phase bar. **Flush-edge rule:** every Gunship part a projectile must reach has its HurtBox's
  outer side flush (± 2 px) with the root HurtBox outline along a straight segment (the part's *exposed edge*), so a shot entering the outline through that segment overlaps
  part and hull in the same physics step and both take it (bullets free deferred). A shot entering elsewhere hits only the hull. Root body / hurtbox / contact box are one
  `RectangleShape2D`. *Armoured hull* (Carrier): `deflects_hit` / `is_armored` true, damage refused, so projectiles cross it to the parts; death = the CORE module's death.
  Every modular host answers `is_laser_blocking() == false`, `launch_velocity()`, `rocket_clear_radius()` and `homing_point(from)` = the nearest live vulnerable module's
  `homing_point()` (its `HomingPoint` marker: the exposed-edge midpoint on the Gunship, the part centre on the Carrier), else the hull centre.
- **Player direct emitters reach parts:** `beam_behavior.gd` and `plasma_nova_module.gd` add group `&"enemy_parts"` to their targets. **Enemy energy weapons do not**
  (`EnergyHitScan.VICTIM_GROUPS` is unchanged: an `EnemyBeam` / `EnergyRing` hurts a heavy's root only, so the Carrier's ring never hurts its own parts). Level `LaserRay`s hit
  parts (layer 512, 9999 damage): any static or slow heavy in level 1 must be checked against lit columns and the level-start `LaserWallWave`.
- **`TurretMount`:** `traverse_deg := 360.0` (360 = today, bit-identical) + `TurretMountSlot.traverse_deg_override := -1.0`; never aims, scans or fires outside
  `rest ± traverse/2` and turns **along the arc**, never through the blocked sector. Appended `Variant.HEAVY_CANNON` (`heavy_cannon_mount.tscn`, `BurstCannonMount` +
  `EnemyRounds.HEAVY_SHELL`). `TurretMountBuilder.build(...)` (static) is the one place mounts and pools are built.
- **New names and places:** `assault/scenes/enemies/heavy_gunship/` (a `git mv` of `gunship/`: `HeavyGunship`, `HeavyGunshipBrain`, flat `HeavyGunshipConfig`);
  `assault/scenes/enemies/carrier/` (`Carrier`, `CarrierBrain`, `CarrierHangars`, flat `CarrierConfig`, `carrier_pulse_ring.tscn`). `WaveBuilder.heavy_gunship()` /
  `HEAVY_GUNSHIP` (old `gunship()` / `GUNSHIP` removed, every caller incl. `level_2_waves.gd` moved) and `carrier()` / `CARRIER`. One `*config*.tres` per enemy directory.
- **Conventions kept:** brains tick on physics through `BaseEnemy._physics_process`; only `EnemyMover` writes an AI body's velocity / rotation (single-writer gate); a brain may
  write mover limits (`max_speed`, `hazard_avoidance`, the precedent); committed moves are `mover.boost()`; randomness only from `brain.rng`; `TargetInfo` for the player; mounts
  write only their own rotation; hull art nose-down (`sprite_forward_angle` `PI/2`); flat `@export_group` configs; weapon tuning in weapon / mount scene exports; state shows
  on a light or a part (orange venting, yellow charging / doors opening, white locked, red armed, cyan shield, dark destroyed), never a recoloured hull; signals declared with
  arity; per-frame prints behind `OS.is_stdout_verbose()`; never hand-type a `uid://`, never run `update_project_uids`; art only via the `pixel-art-generation` skill and
  `./scripts/pixellab.sh`. **`enemy_mine.gd` never names its own `class_name`.**
- **Assault life:** the Heavy Gunship has an `EngagementBudget` (`engage_seconds` 9.0, derived from the Cloud Descent deadline), a measured exit and an attack gate; its rear
  Missiles mount is open in Assault **only while the budget runs** (closed at DISENGAGE; rockets persist ≤ their scene `max_time`, a term in every deadline row). The Carrier
  has no budget: its Assault life is a constant-speed crossing that an EMP does not stop. **No Carrier in an `ENEMIES_CLEARED` section** (guard row). Exit probes only through
  `tests/helpers/ph10_exit_keys.gd` (static `prepare_probe`, never a lambda; the Ph8 / Ph9 memo rule).
- **Not in this phase:** module-tied launches / phase rules on the boss machinery (Ph18), enemy beams vs parts (Ph18 / Ph19), LOS-blocking or death wrecks (`wreck_chance` 0)
  and mass rules (Ph19), EMP on the station / Ph8 structures (Ph11), encounters (Ph13 / Ph14), audio and part score (Ph17).
- **Tests first, GUT.** Behaviour specs run in both harnesses (`tests/helpers/enemy_ai_harness.gd`, `open_space()` / `assault()`, label-parameterised, never
  `use_parameters([HARNESS…])`), hand-ticked at 1/60; projectile / LOS rows on real physics at the 8× clock (`_scale_clock()` / `_restore_clock()` from
  `test_level1_drone_exit.gd`: ticks per second are scaled, so a step is still 1/60 s). Per-tick drivers are a child `_Ticker` node. Run `scripts/check-test-leaks.sh` after
  anything that awaits.
- **Gate time is a budget:** GUT ≈ 225 s at the Ph9 close (ceiling 240 s). **t1 frees ≥ 12 s first** (hard floor; below it `Result: ESCALATE`). Allotments (new GUT s): t2 2.0 ·
  t3 0.8 · t4 3.5 · t5 2.5 · t6 2.0 · t7 1.8 · t8 2.2 · t9 0.4 · t10 0.8 · t11 3.0 · t12 2.5 · t13 0 = 21.5 s, so the phase ends ≤ 234.5 s. Measure every task with
  `scripts/gate-time.sh` (two runs, mean) before and after, and its own new / changed files' summed time; add a row to `tests/README.md` → Gate time. Fix an overrun by sharing a
  scenario, the 8× / 16× clock or a memoised probe, never by cutting an assertion. A task escalates when the two-run mean passes 237 s or its own files exceed 1.5× its allotment.
- **Task order:** `enemy_module.gd` / `modular_hull.gd` t2 → t3 (later tasks change them only with a DECISIONS note); t5 ∥ t6; roster gates (`test_enemy_contact_damage.gd`,
  `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`, `test_base_enemy.gd`, `test_enemy_dual_mode.gd`) and `wave_builder.gd` t4 → t6; carrier files t6 → t7 → t8;
  `sector_hub.*` / `test_sector_hub_patrol.gd` only t10; `level_1_director.gd`, `level1_slice_replay.gd`, `test_level1_heavy_spawns.gd` t11 → t12. **t9 never changes a collision
  shape, hurtbox, module position or `HomingPoint`** (t11 / t12 measure against them). `DECISIONS.md` and the gate table are append-only and shared.
- Numbers marked *starting value* (§2.16) are judgement; keep them unless a row forces a change, and log a change in `DECISIONS.md`. Every task appends its
  "Phase 10, built in tN" notes and any deviation to `DECISIONS.md`. Finish with `bash /agent/verify.sh` green. Stay on `agent/auto-dev`.

## 1. Problem

Large enemies today are single health bars with an Assault-only script. The Gunship (`assault/scenes/enemies/gunship/gunship.gd`) drops in from the top, parks a
fixed distance below the screen edge, tracks the player on the x axis only, and below 30% HP flies off the top and frees itself (an escape, not a kill). It is the
last legacy enum-phase enemy with no brain or mover, so it cannot work in Open Space at all. Three of level 1's four gunships are spawned on rails (`.move()`), which
switches their script off: **they never fire**. The deep-space one never leaves the screen and can carry over into the station boss section.

The idea (`docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §7, §6.11, §13.3, §14, §22–23, §26, §38, §40) asks for large enemies built from
parts that each have health, armour, accepted damage types, a disabled state, a visual state (dark wreckage that stays) and a gameplay consequence; small weak points
found by looking; a Heavy Gunship that is a mobile broadside gun platform with controlled → overheat-and-vent → emergency phases whose retreat keeps it in the
fight; a Carrier whose engines, guns, hangars and core change its movement, safe sides, launches and state; ship-mounted turrets; both ships' multi-part art and
damage states; placement in level 1 and the hub; and tests in both modes for "module death disables an attack / changes movement", "the core becomes vulnerable only
when intended", "destroyed components remain as wreckage" and "a destroyed hangar stops launches".

### 1.1 Scope check (re-validated against the code @ `58a2b04`)

| # | Finding | Effect on this phase |
|---|---|---|
| S1 | No module / part / weak-point concept exists in game code. Precedents: `StationTurret` (own `HurtBox`/`Health`, texture swap to `station_turret_destroyed.png`, stays in the tree, `destroyed(turret)`), `ArmorPlate` (hit-aware `_resolve` cached per HitBox id; freed on break), `EnemyShield` "local module" mode (fixture-proven, no shipped consumer), `TurretMount` (host-agnostic aim-and-fire, writes only its own rotation). | Build **one** reusable `EnemyModule` composing these ideas (§2.1). `ArmorPlate` stays the Ram's breakable plate; `StationTurret` stays byte-identical (Ph11 reworks the station). |
| S2 | Ph4 recorded "Ph10 modular damage should extend or compose `ArmorPlate`". `ArmorPlate` damages itself in its own `area_entered`, so a shield can never cover it (Ph5 deviation 6), it is freed on break (no wreckage) and it only breaks on rockets / high impact. | **Changed, with reason:** `EnemyModule` takes the plate's *resolve-once* rule but damages from `received_damage` (so Ph5 "module shields must sit on a plain part's `HurtBox`" holds) and keeps its wreckage. Recorded in DECISIONS. |
| S3 | Player direct emitters (`beam_behavior.gd:72-98`, `plasma_nova_module.gd:34-41`) only look at nodes in groups `enemies` / `asteroids` and their child `HurtBox`. The nova hits **every** enemy on the map; the beam hits a target whose centre is within 12 px of its line. Enemy energy weapons (`EnergyHitScan.VICTIM_GROUPS` = player, allies, enemies, asteroids) never see a part. The player's dash does not target parts. | Modules join `&"enemy_parts"`; the beam and the nova add that group (§2.1). Enemy energy weapons stay as they are: they cannot hurt parts in Ph10 (so the Carrier's own ring cannot either). Station turrets and plates are not in the group. |
| S4 | `TurretMount` tracks without limit and turns by `rotate_toward` (the shortest way, `turret_mount.gd:316`); a host cannot make "one side safe". | Append `traverse_deg` (default 360, bit-identical) and a slot override; limited mounts turn along the arc (§2.3). |
| S5 | `DefenseTurret._build_mounts()` holds the only mount-building code (pools as root children so their container is the enemy container). | Extract `TurretMountBuilder` (behaviour-identical, Ph8 rows guard it) and reuse it for modules (§2.3). `BulletPool` container injection stays unneeded and **deferred again**. |
| S6 | `EnemyRounds.HEAVY_SHELL` (speed 160, 20 dmg, 12 s / 1800 px) has no consumer; Ph3/Ph4/Ph8 assigned it to the Heavy Gunship. | `HEAVY_CANNON` mount variant fires it (§2.3); the Carrier's bow cannon reuses it. |
| S7 | Gunship: `extends BaseEnemy`, enum `ENTER/HOLD/RETREAT`, own `_physics_process`, no brain / mover, 200 HP, contact 30, `heave_gunship.png` 92×84. Tests use it as the canonical legacy / config-isolation subject (`test_config_instance_isolation.gd`, `test_base_enemy.gd` legacy rows, `test_enemy_emp.gd`, `test_emp_blast_module.gd`, `test_support_ship.gd`, `test_explosion_effect_placement.gd`, `test_enemy_bullet_lifetime.gd` bullet speed 260); `test_station_reinforcements.gd:363` asserts no squad uses `WaveBuilder.GUNSHIP`. | t4 rewrites it in place (`git mv gunship/ heavy_gunship/`), moves every legacy-subject row to the Bonus Drone, and renames the station-reinforcement assertion to `HEAVY_GUNSHIP` (§2.4.6). |
| S8 | Level 1 gunship rows: deep_space 3.5 s `b.gunship().at(0, -500)` (DURATION 30 s); cloud_descent (ENEMIES_CLEARED, timeout 10.0 s, last trigger 76.0 s) 50.0 s `.at(0, -400).move(b.straight(42))` and 62.0 s `.at(∓100, -400).move(b.straight(36))` (second `.delay(0.8)`). **The cloud_descent three never fire** (the rail disables `_physics_process`). No level-1 gate counts gunships. **Level 2:** `level_2_waves.gd:34` calls `builder.gunship()` on a typed `WaveBuilder` and `level_2.tscn:5` loads that script, so the project-load gate compiles it (the level is not in the game flow). | t4 moves Level 2's one live row to `builder.heavy_gunship()` with its rail kept (its commented `builder.GUNSHIP` lines to `HEAVY_GUNSHIP`); t11 replaces level 1's four (owner choice 2) and adds a heavy count gate frozen at the legacy peaks (§2.12). |
| S9 | Level-1 lasers emit `_KILL_DAMAGE` 9999 on every layer-128 / 256 / 512 hurtbox they touch, modules included. Lit columns register `&"laser_wall"` hazards the mover avoids. `laser_column_schedule()`: deep_space 6.0 / 14.0 / 22.0 s; planet_approach 10 / 25 / 38 / 55 / 78 / 98 s; cloud_descent 8 / 18 / 34 s. **Plus the level-start `LaserWallWave`** (`level_1.tscn`, at (0, −380), 12 vertical rays over world x 0–672, lit at level start; not in the schedule; its rays register hazards). | The deep_space heavy (3.5 s) faces the wall and all three column sets; the cloud_descent heavies (≥ 50 s) face no column (the last set, 34 s, is dark long before); the Carrier faces planet_approach columns. Checked by replays that light the real lasers (§2.12, §2.13). |
| S10 | Specialist gate: deep_space 12 of 12.5, planet_approach 7 of 7.5 (peaks 28.4–32.0 s and 98.0 s), cloud_descent 6 of 10. Fighter density gates count fighters + Gatlings spawned by waves only. | Heavies and the Carrier are **not** specialists; they get their own count rule. Carrier launches in Assault are swarm drones only (owner choice 6) and are counted in the drone gate (§2.13). |
| S11 | `LaserTender.launch_pair()` and `TurretGroup.spawn_members()` set the pattern for runtime children: siblings in the spawner's parent, `EventBus.enemy_spawned_orphan.emit(node)`, synchronous from the physics step. A freed-not-killed child with `counts_as_escape` true costs combo. | Hangars launch the same way and never dock (§2.8). |
| S12 | Ph9: a brain-driven enemy answers EMP automatically (`answers_emp()` = `is_ai_driven()`); `apply_emp` halts the mover and the brain is not ticked for the window (`base_enemy.gd:126-190`). Ph9 handed "EMP on structures and legacy enemies (gunship, bonus drone, station, Ph8 turrets / fences)" to Ph10 / Ph11 (DECISIONS.md:3533). | Both heavies get EMP for free; the gunship part of that deferral is closed by the rework. The Carrier keeps crossing through an EMP in Assault (§2.6.3). **The bonus drone, the station and the Ph8 turrets / fences go to Ph11** (the station rework; §6). Ship-mounted EMP stays Ph18 (owner choice 5). |
| S13 | Ph1 roadmap: Ph18 moves the Carrier's hangar-tied launches and the Gunship's battery-loss phases onto Ph11's boss machinery; Ph19 owns LOS-blocking wreckage, capital wrecks and heavy mass rules. | Ph10 builds the consequences directly in the two brains behind `ModularHull` signals, so Ph18 can swap the driver without touching the parts. Destroyed modules here are **visual** wreckage only. |
| S14 | GUT ≈ 225 s at the Ph9 close (`verify.sh` 225.05 s, 2888 tests), 240 s ceiling; earlier gate rooms freed 13.8 s (Ph7 t1). | t1 gate room first, ≥ 12 s (§2.15). |

### 1.2 Research findings (the research stage left no file; done in this stage)

| Finding | Tradeoff | Typical values / decision | Source |
|---|---|---|---|
| Fewer, clearer hitboxes make a multi-part boss better: X-Morph: Defense's KM-2 Redwing "severely reduced" its hitboxes and distractors after playtests; component damage changed the attack pattern (engine damage → more aggressive, wings → heavier barrages), and losing all weapons triggered a last stand. | Each extra part is a target the player must read; too many and the fight is noise. | Gunship 6 parts (4 weapons, 2 vents), Carrier 7. Every part loss changes one visible thing. | gamedeveloper.com, "11 Boss Battles of X-Morph: Defense part 5 – KM-2 Redwing" |
| Locked parts plus a backstop: Battle Garegga's propeller turrets stay invulnerable until the wing turrets on that wing die; DonPachi's core changes pattern when its four turrets die and fires a deadly pattern if the player stalls. | A locked part needs a visible tell, or the player wastes shots. | Carrier core plated (deflects with a ping) until 3 outer parts die; hangars hittable only with doors open. The Assault crossing is the stall backstop (it leaves). | shmups.wiki Battle Garegga / DonPachi pages |
| Separate "hard points", "weak points" (type-specific) and "critical points" (bonus damage) (Madhead, *The Alpha*); weak points placed where the boss attacks from push aggressive play (Bloodborne's Amygdala). | Bonus-damage spots must be readable at a glance, not a menu. | Gunship vents: hull damage ×2, open only while venting, orange glow, on the hull's edge. | madheadgames.com "The Alpha: an apex of aggression"; lizard-error.pages.dev on Amygdala |
| Subsystem damage that impairs the enemy physically (FTL engines → evasion, weapons → charge) gives the player a strategic reason to aim somewhere specific. | Impairment must stay readable and bounded. | Carrier engines → turn rate ×0.5 / ×0.15 and a list; a battery → one side safe. | ftl.fandom.com "Ship"; vigaroeentertainment.blogspot.com "FTL Analysis: Subsystems" |
| A carrier the player cannot finally damage is the classic complaint (an itch.io shmup thread); Raiden Fighters' carrier stage makes the hull an arena of many turrets while support craft keep coming. | The core must always become reachable. | Core exposure after any 3 of 6; launches are capped so the arena never floods. | itch.io post 6895475; breezewiki Raiden "Carrier Ship" |

`moddb.com/features/destroying-procedural-carriers` (403 to WebFetch, read through `scripts/fetch-page.sh`) only covered death explosions; not used. Every number in §2.16
not tied to a source above is **judgement**, labelled so.

### 1.3 Code facts every design section relies on

- `BaseEnemy` (`assault/scenes/enemies/base_enemy.gd`): root `$HurtBox` / `$Health` / optional `ContactHitBox`; `DefenseProfile` / `ContactProfile` resolved from children
  and `defense_profile.apply_to(hurt_box)` on the **root** hurtbox only (`:89-90`); `_physics_process` ticks `brain.tick` then `mover.step`; virtual `_on_received_damage(damage)` /
  `_on_health_changed(current)`; death = `was_killed`, `died`, explosion, `_maybe_leave_wreck()`, `queue_free()` in one call. `answers_emp()`, `apply_emp()` (halts the
  mover, calls `brain.on_emp_started()` once, the brain is not ticked for the window, the mover still steps with no request), `suspend_ai()`, `is_ai_driven()`, `accept_tow()`, `repair()`.
- `HurtBox._on_area_entered`: HitBox → `accepted_damage_types` filter → absorber (`absorbs_hit`, emits `hit_absorbed`) → else `received_damage.emit(hb.damage)`.
  `received_damage` carries no type and no hit identity. `Health._ready()` clamps `current_health` to `max_health`, so a 0-max `Health` reads dead.
- **Projectile consumption:** a player `Bullet` asks `ArmorQuery.deflects(area, hit_box)` (`deflects_hit` on the hurtbox's parent, else `is_armored()`); on false it emits
  `expired`, connected to `queue_free` (deferred), so **every hurtbox the bullet overlaps in that physics step still receives the hit**; on true it flies on. A player
  homing rocket does the same and `_finish()`es on the first non-deflected hit (`homing_missile.gd:273-300`), steering to the target's `homing_point(from)` when it has one.
- `EnemyRocket`: HitBox layer 32, **mask 128 | 512** (so a rocket can hit enemy hurtboxes, its own launcher's included), opened only once clear of its launcher by
  `rocket_clear_radius() + body radius + arm clearance`; scene `max_time` DUMB 4.0, PURSUIT 6.0, CLUSTER 4.0, WARHEAD 7.0 s. `RocketBatteryMount.pool_specs()` pools have
  `persist: true` (rockets outlive their ship; pinned by `test_level1_specialist_spawns.gd`).
- `TurretMount` (`setup(host, pools, owner_group)`, `tick(delta, target, can_fire)`, `scan(delta)`, `power_down()` (UNPOWERED for good, `UNPOWERED_TINT`), `pool_specs()`,
  `is_committed()`, `telegraph_gate`, `rest_bearing_deg`, `_turn_toward` = `rotate_toward` shortest way); `BurstCannonMount` (`round_scene`, `round_speed`, `burst_count` 4,
  `burst_gap` 0.12, `charge_seconds` 0.4; **losing `can_fire` stops a burst**), `RocketBatteryMount` (DUMB / PURSUIT; asks the host `launch_velocity()` / `rocket_clear_radius()`),
  `PulseRingMount`, beams. `TurretMountScenes.scene_for/export_of/reach_of`.
- `EnergyRing` (`assault/scenes/projectiles/enemy_beams/energy_ring.gd`): `setup(host, owner_group)`, `start(gap_start_deg)`, `tick(delta)`, `cancel()`; exports
  `telegraph_seconds` 0.8, `ring_speed` 360, `max_radius` 280, `band` 24, `gap_count` 2, `gap_deg` 45, `gap_spin_deg` 30, `damage` 12; hits through `EnergyHitScan` (groups
  player / allies / enemies / asteroids, owner set exempt, direct emit on the target's root `HurtBox`).
- `EnemyShield` (`global/components/enemy_shield.gd`): `attach(hurt_box)` takes the hurtbox's absorber slot (never displaces one already there); host = `hurt_box.get_parent()`;
  never absorbs while the host answers `is_armored() == true`; `face()` / `set_threat_point()` turn its arc.
- `EnemyMover`: `request_velocity(v)` capped at `max_speed`, then hazard slow (`hazard_resistance`) and context avoidance (`hazard_avoidance`, `hazard_margin`); `boost(dir, speed,
  duration)` is committed (ignores `max_speed` and the accel limits; replaces a current boost; `halt()` ends it). `ShipConfig` hazard defaults 1.0 / 60 / 0.0, copied onto the
  mover by `BaseEnemy._ready()`; `test_enemy_dual_mode.gd::HAZARD_PROFILES` pins each AI enemy's three values.
- **Lasers:** `LaserRay` (`assault/scenes/hazards/laser_ray/laser_ray.gd`): `_BEAM_WIDTH` 56, `_HAZARD_PAD` 24, mask 128 | 256 | 512, phases INIT → (warn timer) → INCREASE
  animation → IDLE (lethal, `active_duration`) → DISSOLVE animation; `warn_duration` export default 0. `Level1Director._spawn_laser_columns(columns, warn = 3.0, active = 4.0)` sets
  them per column at world (x, −380), `registers_hazard` true. `test_level1_specialist_spawns.gd::_wall_wave_row()` reads the wall's ray x from `level_1.tscn`; `_column_conflicts()`
  checks static x against every column **starting** before a life ends (no start-of-life filter). `tests/helpers/level1_slice_replay.gd` lights **no** lasers;
  `tests/helpers/level1_column_replay_worker.gd` (manual) lights them through the director's own `_spawn_laser_columns()`.
- `tests/integration/test_engagement_deadline.gd`: `_deadline_rows(section, scene, tail)` → `computed = rel + tail`, `over = computed >= enemies_cleared_timeout`, `rel` = spawn
  time − the section's last effective trigger, `MARGIN` 0.5 inside the tail; the corvette rocket boundary
  `test_a_corvette_in_cloud_descents_last_wave_misses_the_timeout_on_the_rocket_term_alone` is the pattern for a rocket term.
- `test_entity_sprite_transparency.gd::_collect_textures()` reads only `Sprite2D.texture` and `AnimatedSprite2D.sprite_frames` from each scene's `SceneState`.
- `ArenaCamera`: world (projectile) rect y −444 .. 1164 (view ± 64 px), `V_LIMIT` 380; `test_level1_specialist_spawns.gd::_static_life()` is the worst-case drift life (spawned at
  the highest view, shake included, freed below the world rect).
- Hub (`open_space/scenes/levels/sector_hub.gd`): 18 seeded draws appended in order; `test_sector_hub_patrol.gd::_patrol_groups()` entries are `label: [anchor, idle_radius,
  perceive_radius]` and every sweep covers them; `_expected_seeds()` lists every draw. On the 2600 ring 22.5° is ≈ 120 px from `HubDefenseSite` / `SectorJammer` (unusable).

## 2. Design

### 2.1 `EnemyModule`: a destructible part (R10.1–R10.6; t2)

`global/components/enemy_module.gd`, `class_name EnemyModule extends Node2D`, joins group `&"enemy_parts"` in `_ready()`. One file, used by both heavies and by the Ph11 /
Ph12 bosses. It never reads its host's type.

**Scene shape** (authored in the host scene under a `Modules` `Node2D`, never a direct child of the enemy root):
```
Modules/<Name> (EnemyModule)
  Sprite (Sprite2D)            intact_texture; wreck_texture after destruction (the wreck tint goes on this child, never on the module or the host)
  HurtBox (HurtBox, layer 512)  one CollisionShape2D (circle or rectangle)
  Health                       skipped when max_health == 0
  DefenseProfile (optional)    mask and accepted_damage_types; EnemyModule._ready() calls DefenseProfile.apply_to($HurtBox) (BaseEnemy applies only the root's);
                               without one the mask is PLAYER_HITBOX | PLAYER_ROCKETS | HAZARD_CONTACT, all damage types
  MountSlots (optional)        TurretMountSlot children; mounts are built by ModularHull.build_mounts() (t3)
  HomingPoint (optional)       Marker2D; homing_point() returns its global position, else the module's
  Light (optional)             the part's state light (§2.9)
```

**Exports:** `module_id: StringName` (unique within the host, e.g. `&"battery_port"`), `role: Role` (`enum Role { WEAPON, ENGINE, HANGAR, CORE, WEAK_POINT }`, append-only),
`max_health: int` (written into `Health` in `_ready()`; **0 = indestructible**: `Health` is not consulted, damage is still emitted and forwarded, it is never destroyed),
`starts_vulnerable: bool = true`, `hull_share: float = 0.0`, `intact_texture: Texture2D`, `wreck_texture: Texture2D` (null → the intact texture with `WRECK_TINT`
`Color(0.35, 0.35, 0.4)` on the `Sprite` child — the player beam writes its heat tint on the module node itself, `beam_behavior.gd:105`, so the wreck tint must live a level
below), `damaged_ratio: float = 0.5` (VisualState DAMAGED at or below this health fraction).

**Hit rule (the one decision point):**
- `deflects_hit(hit_box) -> bool` = `_resolve(hit_box)`, cached per HitBox instance id and erased on the hurtbox's `area_exited` (the `ArmorPlate` shape), computed as:
  **deflect** when the module is a wreck from an earlier physics frame (`_destroyed_frame < Engine.get_physics_frames()`), or not vulnerable, or the hit's type is not
  in the profile's `accepted_damage_types` (empty = all); **consume** otherwise. A module destroyed this physics frame still answers consume, so the killing shot is
  consumed whatever order Godot calls the bullet's and the hurtbox's `area_entered` in.
- **Damage comes only through `HurtBox.received_damage(damage)`**, i.e. after the hurtbox's own type filter and absorber slot, so an `EnemyShield` attached to a module's
  `HurtBox` absorbs first (Ph5's local-module shield, shipped on the Gunship's cannon, §2.5). The handler: destroyed → ignore; **not vulnerable → `deflected.emit(self)`, a white
  ping, no damage** (this is the only guard against the direct emitters — the player beam, the nova and a level `LaserRay` never ask `deflects_hit`); else `Health.decrease(damage)`
  (skipped when `max_health == 0`), `damaged.emit(self, damage)`, `HitEffect.burst()`.
- A module is never armour for its host: the host's root hurtbox and the module's hurtbox are separate areas, and each answers its own `deflects_hit`. Whether a projectile
  reaches a part at all is the **host's** geometry rule (Gunship flush-edge rule §2.4.1; Carrier armoured hull §2.6.2).

**Destruction (`Health` reaches 0, or `destroy()`):** once only. `_destroyed_frame = Engine.get_physics_frames()`; `remove_from_group(&"enemy_parts")`; the hurtbox's
`monitoring` / `monitorable` and shape go off **deferred**; every attached mount `power_down()` (droops, dark, never fires again); the `Sprite` swaps to `wreck_texture`
(VisualState WRECK) and the light goes OFF; an `ExplosionEffect` bursts into the host's parent (the `StationTurret` re-homing, so it neither rotates with the hull nor dies
with it); `destroyed.emit(self)`. **The node stays in the tree** for the host's whole life and is freed with it: that is the wreckage (IDEAS §23 "destroyed modules visibly
remain"). It is not a `Wreck` body and blocks nothing (Ph19).

**Vulnerability:** `set_vulnerable(on)` (no-op on a wreck), emits `vulnerability_changed(self, on)` on a change. A host changes it from its brain or deferred
(`call_deferred`) when the change is caused inside a physics callback (the Ram `_expose` rule).

**Visual state:** `visual_state()` → `INTACT`, `DAMAGED` (health ≤ `damaged_ratio` · max; a code-drawn spark flicker on the sprite, IDEAS §23 "damaged weapon banks spark"),
`WRECK`. No recolouring of the hull; the part's own sprite and light carry it.

**Player direct emitters:** `beam_behavior.gd` appends `get_nodes_in_group("enemy_parts")` to its target list and `plasma_nova_module.gd` does the same; both find the `HurtBox`
child by name and emit `received_damage` directly. The beam burns a part whose centre lies within 12 px of its line (as for enemies); the host root answers
`is_laser_blocking() == false`, so the beam passes over the hull. **The nova damages every enemy and every live part on the map** (it is map-wide, not ranged). The player's dash
does not target parts (unchanged). Enemy energy weapons do not reach parts (§1.1 S3).

**Test rows** (`tests/integration/test_enemy_module.gd`, fixture host `tests/helpers/fixture_modular_host.tscn` — a `BaseEnemy` with a `ModularHull` and three modules:
`Open` (vulnerable), `Locked` (`starts_vulnerable` false) and `Laser` (`accepted_damage_types` LASER only), its root hull armoured (`deflects_hit` true, damage refused) so a
projectile always reaches the module it is aimed at; real physics at 8× for projectile rows, both harnesses where the host moves):
- a player bullet into `Open`: consumed, module health −damage, host `Health` unchanged (`hull_share` 0);
- into `Locked`: passes through (not consumed, no `expired`), module health unchanged, `deflected` once; after `set_vulnerable(true)` the next bullet is consumed and damages it;
- a rocket against `Laser`: deflected, no damage;
- **the killing shot is consumed** under both callback orders (the row forces each order by calling `deflects_hit` before / after `received_damage`);
- **wreckage stays:** after destruction the node is still a child of `Modules` 2 s later, `visual_state() == WRECK`, its `Sprite` texture is `wreck_texture`, it is out of
  `enemy_parts`, its hurtbox no longer monitors, a later bullet passes through it, `destroyed` fired exactly once, the host is still alive; a beam on the wreck afterwards leaves
  the `Sprite` child's wreck tint in place;
- `max_health` 0: never destroyed (`is_destroyed()` false after 10 000 damage), damage still emitted and forwarded;
- `hull_share` 1.0: the host's `Health` drops by the same amount (forwarded by `ModularHull`);
- a module with its own `DefenseProfile` gets that profile's mask and types on its `HurtBox` (`apply_to` ran);
- a local `EnemyShield` attached to `Open`'s hurtbox absorbs a frontal bullet (consumed, module health unchanged) and not a rear one;
- **direct emitters against a locked part:** the player's beam (`BeamBehavior` on a real Assault player) held on `Locked` for 2 s and one nova leave `Locked`'s health
  unchanged (`deflected` emitted) while the same beam / nova damage `Open`; the armoured fixture root takes nothing;
- the nova damages every live module on the map (two fixture hosts, both sets of `Open` modules);
- a level `LaserRay` lit across `Open` destroys it through `received_damage` (the column-kill fact §2.12 / §2.13 rely on), and one lit across `Locked` leaves it intact;
- an `EnergyRing` and an `EnemyBeam` swept across the fixture (host not in their owner set) leave every module's health unchanged (enemy energy weapons never reach parts).

### 2.2 `ModularHull`: the host's coordinator (R10.1, R10.7; t2, `build_mounts` t3)

`global/components/modular_hull.gd`, `class_name ModularHull extends Node`, a child of the host root named `ModularHull`. In `_ready()` (after the host's other children) it
collects every `EnemyModule` under the sibling `Modules` node, in tree order, and connects their signals. It is the seam Ph18 replaces the consequence driver behind; it
holds no gameplay rules of either heavy.

- `signal module_destroyed(module: EnemyModule)`, `signal module_damaged(module: EnemyModule, amount: int)`.
- Forwarding: on `damaged(module, amount)`, if `module.hull_share > 0` and the host has a `Health`, `host.health.decrease(roundi(amount * module.hull_share))`.
- Queries: `modules()`, `module(id) -> EnemyModule` (null if none), `live(role) -> Array[EnemyModule]`, `destroyed_count(roles: Array) -> int`, `mounts_of(id) -> Array[TurretMount]`.
- **Added by t3:** `build_mounts(host: Node2D, rng: RandomNumberGenerator, owner_group: StringName, telegraph_gate := Callable(), first_index := 0) -> int`: for every module, every
  `TurretMountSlot` under its `MountSlots`, `TurretMountBuilder.build(host, slot, index, rng, owner_group, telegraph_gate)` with one running `index` across the host (unique pool
  names), then `module.attach_mount(mount)`; returns the next free index (so a host with hull-mounted slots continues the count). Pools are **host root children**, so their
  container is the host's parent.
- t2 rows (`test_enemy_module.gd`): collection order, forwarding, `destroyed_count` over role sets, `module_destroyed` re-emitted once, `live(role)` drops a wreck.
- t3 rows (`test_enemy_module.gd`): unique pool names over 3 modules × 2 slots plus a continuing hull index; a module's mounts are UNPOWERED from its destroy call and never fire
  again (60 s hand-ticked with the player in range).

### 2.3 Ship-mounted turrets: traverse limits, the builder and the heavy cannon (R10.8, S4–S6; t3)

**`TurretMountBuilder`** (`assault/scenes/enemies/defense_turret/mounts/turret_mount_builder.gd`, static, `RefCounted`):
`build(host: Node2D, slot: TurretMountSlot, index: int, rng: RandomNumberGenerator, owner_group: StringName, telegraph_gate := Callable(), variant_override := -1,
bearing_override := NAN) -> TurretMount` — exactly today's `DefenseTurret._build_mounts()` loop body (variant, `rest_bearing_deg`, `turn_rate_override`, the new
`traverse_deg_override`, rng, gate, `slot.add_child(mount)`, one `BulletPool` per `pool_specs()` entry added to `host` named `"%s_%d" % [spec.name, index]`, `setup()`).
`DefenseTurret._build_mounts()` calls it; every Ph8 turret, heavy emplacement and turret-group row must stay green unchanged.

**Traverse:** `TurretMount` export `traverse_deg: float = 360.0`; `TurretMountSlot` export `traverse_deg_override: float = -1.0` (≥ 0 replaces it). With `traverse_deg < 360`:
- the mount works in **offsets from rest** (`wrapf(angle − rest, −PI, PI)`); the desired offset is clamped into `± traverse_deg / 2`, and the turn moves the current offset toward
  the clamped desired offset **linearly** (`move_toward` on the offset, `turn_rate · delta`), never through the blocked sector — `rotate_toward`'s shortest way would cross it for
  any arc wider than 180°;
- the scan arc is clamped into the same range;
- TRACK → TELEGRAPH and every `_fire_tick` additionally require the target's bearing to lie inside the arc (outside it the mount behaves as if `can_fire` were false).
At 360 every new code path is skipped, so all Ph8 rows are bit-identical (a row asserts a recorded 10 s mount trace is unchanged with `traverse_deg` 360).

**HEAVY_CANNON:** append `Variant.HEAVY_CANNON` to `TurretMount.Variant` and `TurretMountScenes` (`heavy_cannon_mount.tscn`, script `BurstCannonMount`, `round_scene =
EnemyRounds.HEAVY_SHELL`, `burst_count` 2, `burst_gap` 0.35 s, `charge_seconds` 0.7 s (yellow), `round_speed` 220 px/s, `cooldown_seconds` 3.2 s, `fire_range` 900 px,
`turn_rate` 0.9 rad/s, `fire_cone_deg` 6, `traverse_deg` 70). Starting values. The round lifetime sweep (`test_enemy_bullet_lifetime.gd`) adds the mount's `round_speed`
as a Heavy Shell speed source: 1800 / 220 = 8.2 s ≤ 12 s.

**A mount on a moving, rotating host** already compensates its parent's `global_rotation` (`turret_mount.gd` `_parent_rotation()`); rocket mounts ask the host's
`launch_velocity()` (the heavies answer their `velocity`) and `rocket_clear_radius()` (the hull's half-diagonal + 4 px, so a rocket never arms inside its own hull).

**Rows** (`tests/integration/test_turret_mount_traverse.gd`, hand-ticked): a 120° mount never rotates outside its arc while the target circles it (sampled 600 ticks), never
fires a round with the target outside the arc, fires normally with the target inside; **a 300° mount** with the target circling through its blocked 60° stays within ±150° of rest
on every one of 600 ticks and reaches the far side of the arc by turning the long way; a 360° mount's 10 s trace equals the recorded pre-change trace; the builder gives a
`DefenseTurret` the same pool names, sizes and mount exports as before (heavy emplacement too); a `HEAVY_CANNON` mount fires two Heavy Shells at 220 px/s after a 0.7 s charge;
`TurretMountScenes.scene_for(HEAVY_CANNON)` is not null and every variant sweep includes it. Plus the §2.2 t3 rows.

### 2.4 Heavy Gunship: shell, movement and Assault life (R10.9–R10.12, R10.17; t4)

#### 2.4.1 Files, scene and the flush-edge rule
`git mv assault/scenes/enemies/gunship assault/scenes/enemies/heavy_gunship`; rename to `heavy_gunship.tscn` / `.gd`, `heavy_gunship_brain.gd`, `heavy_gunship_config.gd` /
`.tres`, `ENEMY.md` rewritten. `class_name HeavyGunship extends BaseEnemy`; `HeavyGunshipBrain extends EnemyBrain`; `HeavyGunshipConfig extends ShipConfig` (flat,
`@export_group` Movement / Attack / Phases / Defense / Tactics / Scoring / Hazards; the old fields `entry_speed`, `hold_y_offset`, `track_speed`, `track_player`,
`retreat_hp_ratio`, `burst_interval`, `burst_gap`, `bullet_damage`, `bullet_speed` are deleted). `WaveBuilder.heavy_gunship()` replaces `gunship()`; the `GUNSHIP` const becomes
`HEAVY_GUNSHIP`. The old textures `heave_gunship.png` / `heavy_gunship_non_shielded.png` (and the `.pdn`) are deleted once t9's art lands (t4 keeps them as placeholders).

```
HeavyGunship (HeavyGunship, CharacterBody2D)   body: one RectangleShape2D 112 × 144 px, layer ENEMY_HITBOX, mask ENVIRONMENT
  Sprite2D (hull)   CollisionShape2D   HurtBox (root, the same rectangle; covers the body)   Health (hull, max = config.max_health)
  HitFlashAnimationPlayer   ContactHitBox (same shape id and scale as the body)   ContactProfile (COLLISION)
  Brain (HeavyGunshipBrain)   Mover (EnemyMover)   ModularHull   StateLight
  Modules (Node2D)
    BatteryPort      (WEAPON, 160 HP)  32 × 40 rect, outer side flush with the port flank; MountSlots/Slot0 BURST_CANNON, rest = port, traverse 160°
    BatteryStarboard (WEAPON, 160 HP)  mirror on the starboard flank
    Cannon           (WEAPON, 200 HP)  32 × 24 rect, outer side flush with the nose edge; MountSlots/Slot0 HEAVY_CANNON, forward, traverse 70°; local EnemyShield (§2.5)
    Missiles         (WEAPON, 140 HP)  40 × 24 rect, outer side flush with the aft edge; MountSlots/Slot0 ROCKET_BATTERY, rear, traverse 360°
    VentPort / VentStarboard (WEAK_POINT, max_health 0, starts_vulnerable false, hull_share 1.0)  16 × 24 rects flush with each flank, aft of the battery
  (every module carries a HomingPoint marker at the midpoint of its exposed edge)
```
**Flush-edge rule** (review finding 1): the hull is vulnerable and covers the whole body, and a projectile is spent on the first damaging overlap, so a part fully inside the
outline could never be hit. Every Gunship module's HurtBox is a rectangle whose outer side lies on the root rectangle's side (± 2 px) along the module's whole width — its
*exposed edge*. A shot that enters the outline through that segment overlaps the module and the hull in the **same** physics step, and both receive it (a bullet frees
deferred, `Bullet` emits `expired` only once); a shot that enters elsewhere hits only the hull. So a part hit is also a hull hit (owner choice 3) without any forwarding, and
`hull_share` stays 0 on every Gunship part except the vents. `homing_point(from)` is the nearest live vulnerable module's `HomingPoint` (its exposed-edge midpoint), so a player
homing rocket enters through the part's edge. The rule is a geometry gate (§2.4.5), checked again whenever art lands (t9 may not move or resize a shape).

Contact: `ContactProfile` COLLISION, `collision_damage` 30 (kept, so `test_gunship_rams_for_its_configured_collision_damage` survives renamed). `counts_as_escape` true.
`is_laser_blocking()` false. `accepts_tow()` false in every phase (a heavy is not towed); `can_be_repaired()` true. Hazards (config, explicit): `hazard_avoidance` 1.0,
`hazard_margin` 90 (≥ the hull half-width 56 + the laser pad), `hazard_resistance` 0.6 (heavier than the Ram's 0.5; the full mass model is Ph19).

#### 2.4.2 Movement (Open Space is the source of truth)
`HeavyGunshipBrain.Phase { APPROACH, BROADSIDE, BREAK_AWAY, VENT, EMERGENCY, DISENGAGE, IDLE, NOTICING, RETURNING }` (append-only; VENT and EMERGENCY are filled in by t5,
t4 ships them as no-op stubs that fall back to BROADSIDE).
- **APPROACH:** `arrive` toward the point at `preferred_range()` on the line to the player; BROADSIDE inside `range_tolerance`.
- **BROADSIDE** (IDEAS §7 "maintain distance, rotate to broadside, strafe a wide arc"): `orbit` the player at `preferred_range()` (± `range_drift` over 7–10 s) at
  `orbit_angular_speed`, reversing every `reversal_min`..`reversal_max` s (drawn from `brain.rng`). **Facing:** `face_toward` a point that turns the chosen side to the player:
  heading = bearing to player ∓ 90° for the port / starboard side. **The chosen side** is the side whose battery is alive (both alive: the side already nearer, so it never
  flips needlessly; switching sides swings the nose through the shorter way at `max_turn_rate`); no live battery → nose (the cannon) to the player; nothing armed but the
  missiles → keep the range, nose away.
- **BREAK_AWAY:** player inside `min_range` → one committed `mover.boost` (`break_speed`, `break_seconds`) along `Steering.break_contact` with side `-orbit_dir`
  (the Ph5 sign), then BROADSIDE; rearm `break_rearm`. This is "occasionally boost away".
- **Heavy feel:** `max_speed` 140, `acceleration` 120, `max_turn_rate` 0.9 rad/s (a full side swap takes ≈ 3.5 s, readable).
- **Hub idle:** `AnchorIdle` round `patrol_anchor` (`idle_radius` 180, `perceive_radius` 900, `lose_radius` 1500, `notice_time` 0.6 s); RETURNING never cuts a committed
  boost. `start_engaged` skips it (tests, launches).
- **Low health never despawns it** (IDEAS §7, §38): EMERGENCY (t5) keeps it in the encounter in Open Space; there is no off-the-top retreat anywhere.

#### 2.4.3 Assault
The same brain under `AssaultCorridorConstraint` (constraint_mode AUTO): `preferred_range()` = `assault_preferred_range` 420; the arc is clamped by the corridor, so it
swings side to side above or beside the player rather than parking. **The three Assault-only assumptions are gone:** no hold-y computed from the camera, no x-only
tracking, no fly-off-the-top retreat.
- **Budget:** `EngagementBudget` `engage_seconds` **9.0 s** (starting value, **derived from the Cloud Descent deadline**: the 62.0 + 0.8 s heavy sits at rel −13.2 s, so
  `engage + attack_window + exit + MARGIN 0.5 < 23.2 s`; with `attack_window()` ≈ 1.05 s that leaves ≤ 12.6 s for the measured exit). → DISENGAGE: the Missile Corvette's exit
  (curve to the nearest corridor edge, release the constraint, freed outside the projectile rect) at `exit_speed` 300 px/s with `exit_acceleration` 240 px/s² (the brain writes
  both onto the mover in DISENGAGE; the heavy's 120 px/s² cruise acceleration would make the exit too slow).
- **Attack gate:** a battery / cannon telegraph starts only with `budget.remaining() ≥ attack_window() + 0.05`, `attack_window()` = the longest `charge_seconds + (burst_count −
  1) · burst_gap` over its live gun mounts; a started burst finishes (deferral ≤ `attack_window()`). The rear Missiles mount is §2.5's rule (closed at budget end).
- **Pre-approved levers if the deadline row (§2.12) fails, in order, each legal only while every attack-in-budget row stays green:** (1) `exit_speed` up to 360 and
  `exit_acceleration` up to 320; (2) `engage_seconds` down to a floor of 7.0 s. Neither fits → `Result: ESCALATE` with the measured exit (the owner then picks owner choice 2's
  alternative, one Cloud Descent heavy, or moves the late pair).
- The Assault corridor exit is measured once per GUT run through `tests/helpers/ph10_exit_keys.gd::heavy_gunship_exit()` (the `SpecialistExitProbe` memo over the probe's view
  grid and `corridor_starts()`; the curved exit, never a straight line).

#### 2.4.4 Weapons in t4
All four mounts are built by `ModularHull.build_mounts()` (t3). The brain ticks them every tick with `TargetInfo.player(tree)` and `can_fire = can_see_player() or
mount.fires_past_cover()`, and passes `can_fire` false to the Missiles mount outside EMERGENCY (t5 opens it). Battery rounds are Pulse rounds (the mount default).

#### 2.4.5 Rows (t4; `tests/integration/test_heavy_gunship.gd`, both harnesses)
- spawn: 6 modules, 4 mounts with the authored variants and traverses, hull `Health` = config, contact damage 30, `is_ai_driven()` true, `answers_emp()` true;
- **flush-edge geometry (static):** for every module, its HurtBox rectangle's outer side lies within 2 px of the root HurtBox rectangle's side over the module's whole width, and
  its `HomingPoint` is the midpoint of that side;
- **every part is reachable (real physics, 8×, both harnesses):** for each of the six modules, a player bullet fired along the inward normal at its `HomingPoint` damages that
  module (vents: opened for the row) and the hull by the bullet's damage, each exactly once; a control bullet into the hull between two parts damages only the hull; a player
  homing rocket locked on the gunship from the port side damages `BatteryPort` (it steers to `homing_point`);
- holds `preferred_range` ± (`range_drift` + `range_tolerance`) over 20 s against a still player and against a 200 px/s circling player;
- **broadside:** with both batteries alive, the angle between the hull heading and the bearing to the player stays within 90° ± 20° for ≥ 80% of 20 s of BROADSIDE;
- **module death changes movement:** destroy `BatteryPort` while the port side faces the player → within 5 s the starboard side faces the player and stays (the swap);
  both batteries destroyed → the nose faces the player (± 20°);
- BREAK_AWAY: a 300 px/s rusher inside `min_range` triggers one boost away; the rearm holds a second one;
- **Assault:** never parks — over 9 s its y spread is ≥ 120 px and it never holds a y within 8 px for more than 2 s while the player moves; never leaves the corridor's outer band
  before DISENGAGE; frees after DISENGAGE within the measured exit; a 1 s budget boundary row ends in DISENGAGE; no telegraph starts with less than `attack_window() + 0.05` left;
- hub idle: orbits its anchor, notices at `perceive_radius`, returns after `lose_radius`;
- `HAZARD_PROFILES` row in `test_enemy_dual_mode.gd`: `heavy_gunship` 1.0 / 90 / 0.6.

#### 2.4.6 Gates, legacy rows and callers moved
- Roster entries renamed in `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd` (the old 1 px gap goes away with the new shape),
  `test_base_enemy.gd` (roster; tow table: refuses in every phase), `test_enemy_dual_mode.gd` (one spawn row + the hazard row), `test_explosion_effect_placement.gd` (scene path).
- **Legacy-subject rows move off the gunship:** `test_base_enemy.gd::test_legacy_enemies_are_not_ai_driven` keeps the Bonus Drone only; `test_enemy_emp.gd`'s legacy rows and
  `test_emp_blast_module.gd`'s legacy process-disable row use the Bonus Drone (legacy, non-brain; the row asserts the same thing); `test_config_instance_isolation.gd` keeps the
  gunship as its canonical subject under the new path (any flat config works); `test_enemy_bullet_lifetime.gd` drops `gunship_cfg.bullet_speed` (no enemy fires plain bullets at
  260 any more; the derived defaults do not change because 150 stays the minimum).
- **`test_support_ship.gd`'s gunship row flips (owner choice 7):** the Heavy Gunship is AI-driven and outscores a fighter, so it is now a legal ward (the support shields its hull
  and interposes; the tow is refused by the brain).
- **Callers:** `level_2_waves.gd:34` `builder.gunship()` → `builder.heavy_gunship()` with its `.move(builder.straight(55))` rail kept (a rail suspends the brain, as before:
  it rides and does not fire); its commented `builder.GUNSHIP` lines → `HEAVY_GUNSHIP`. `test_station_reinforcements.gd:363` asserts `WaveBuilder.HEAVY_GUNSHIP` (message
  "heavy gunship is AI and must never get a mover"). `level_1_director.gd`'s four rows call `b.heavy_gunship()` with every other part of the row unchanged (the rails stay
  until t11; the deep_space 3.5 s row has none, so that heavy is AI-driven from t4 on).
- **Every level-1 gate and replay stays green**, including `test_level1_ph8_attacks.gd` (its deep_space 3.0 s slice now also replays the 3.5 s heavy), the fighter density
  schedule row, the specialist and drone gates. `docs/enemy-roster.md` loses every "never `.move()` the gunship" line in t13.

### 2.5 Heavy Gunship: phases, overheat-and-vent, weak points, emergency and rear missiles (R10.10–R10.13; t5)

**Hull phases** read the root `Health` fraction (owner choice 3: a hit on a part also hits the hull, because every part is flush with the hull's outline, §2.4.1):
`CONTROLLED` ≥ `overheat_ratio` 0.6 > `OVERHEAT` ≥ `emergency_ratio` 0.3 > `EMERGENCY`. Entering a band is one-way (a `repair()` from a Support Ship never steps back).
`signal hull_phase_changed(hull_phase: int)` on the brain.

- **CONTROLLED** (defensive): BROADSIDE / BREAK_AWAY as in §2.4.2; battery cooldown 2.2 s (the mount's).
- **OVERHEAT:** each battery or cannon burst adds 1 heat **when it ends**; at `heat_limit` 4 the brain enters **VENT** for `vent_seconds` 2.2 s: every gun mount is ticked with
  `can_fire = mount.is_committed()` (a burst already started finishes — `BurstCannonMount` stops a burst the moment `can_fire` drops — and none starts), `max_speed` × 0.6,
  the vents' lights glow orange and `VentPort` / `VentStarboard` become vulnerable (`set_vulnerable(true)`), heat resets; at the end the vents close (`set_vulnerable(false)`).
  Attack windows become shorter (four bursts, then a vent) and the player gets a timed weak-point window. An open vent is on the flank edge (§2.4.1), so a shot into it hits the
  vent and the hull in one step: the hull takes the hit, and the vent (indestructible, `hull_share` 1.0) forwards it again — **double damage**. A closed vent deflects, so the
  same shot hits the hull once.
- **EMERGENCY:** "emergency boost pattern, aggressive retreat, rear missile launches". Every `emergency_period` 5.0 s: one `mover.boost` away from the player
  (`emergency_boost_speed` 420 px/s, 0.9 s, along `break_contact`), then the `Missiles` mount is allowed to fire for `missile_window` 2.0 s at a player who is behind the
  gunship (inside the rear 200° — the pursuer); the batteries keep firing. Between boosts it holds BROADSIDE at `emergency_range` 800 px (Open Space) /
  `assault_preferred_range` + 120 (Assault). **It never despawns because of health**: in Open Space it stays in the encounter until killed (Ph13 owns leash / cleanup). Venting
  stops in EMERGENCY (the vents stay closed).
- **Rear missiles in Assault (review finding 3):** rockets persist after their ship (`persist: true` pools; Ph5 rule). In Assault the Missiles mount gets `can_fire` true only
  while the `EngagementBudget` runs; at DISENGAGE it is closed (a salvo in progress is cut; rockets already launched fly on). So every rocket is launched before the budget
  ends and lives ≤ the longest `max_time` of the mount's pool scenes (read from the scenes, never typed: PURSUIT 6.0 s), and the deadline row (§2.12) carries a **rocket term**
  `engage_seconds + rocket max_time + MARGIN` beside the exit term. This is a deliberate exception to "persistent ordnance stays out of `ENEMIES_CLEARED` sections"
  (DECISIONS.md, Ph4 / Ph5 / Ph7), bounded by that term; recorded in DECISIONS.
- **Own rockets:** an `EnemyRocket`'s HitBox sees layer 512, so a rocket curving back could hit its own gunship's hull or parts — the same as the Missile Corvette since Ph5, and
  rare here (it arms only clear of `rocket_clear_radius()` and fires only at a pursuer behind). Accepted; the EMERGENCY row asserts no self-hit in its 60 s scenario. If that row
  shows one, the task adds a launcher exemption to `enemy_rocket.gd` (skip a hurtbox whose parent is the launcher or an `EnemyModule` under it) and logs it.
- **Cannon shield (the first shipped local-module shield, Ph5's open item):** an `EnemyShield` child of `Modules/Cannon`, attached to the Cannon's `HurtBox`: `arc_deg` 120 facing
  the hull's nose (the brain calls `face()` / `set_threat_point()` every tick so it tracks the nose), `capacity` 60, `regen_delay` 2.0, `regen_seconds` 4.0, `reboot_seconds`
  5.0. **It protects only the cannon's own HP:** a head-on bullet is absorbed by the cannon's hurtbox but still damages the hull through the overlapping root hurtbox (the flush
  edge). From the flank the cannon takes damage. The shield does not cover the hull or the batteries.
- **Battery loss removes the attack for good:** the module's mount is UNPOWERED from the destroy call on; the brain picks the other side (§2.4.2). Cannon lost → the nose
  no longer fires; Missiles lost → EMERGENCY boosts without missiles.

Rows (`test_heavy_gunship.gd` §phases, both harnesses):
- hull 61% → CONTROLLED, 59% → OVERHEAT, 29% → EMERGENCY; a `repair()` back to 70% stays in EMERGENCY;
- OVERHEAT: a burst in progress when VENT starts finishes all its rounds; from the end of the longest such burst to VENT's end no round leaves any mount; the vents are vulnerable
  only inside VENT (**weak point vulnerable only when intended**); real physics: a bullet into a closed vent is consumed by the hull (1× hull damage, no vent `damaged`); into an
  open vent it deals 2× to the hull; **the player's beam held on a closed vent and a nova during CONTROLLED deal no vent damage and forward nothing** (`deflected`);
- EMERGENCY: boosts away every 5 s; the Missiles mount fires only in its window and only at a player behind it; Open Space: still alive and in the encounter 60 s after entering
  EMERGENCY with the player chasing at 300 px/s (never freed, never flagged an escape), and no damage to its own hull or parts from its own rockets in that run;
- **Assault missiles:** the Missiles mount fires no rocket after the budget expires (a heavy forced to EMERGENCY 1 s before expiry launches at most one salvo and nothing after);
- **module death disables an attack:** destroy `BatteryStarboard` → over the next 30 s (the player stub kept on the starboard side), no round leaves that mount and the mount is
  UNPOWERED; destroy `Missiles` in EMERGENCY → no rocket ever leaves;
- cannon shield: a frontal real-physics bullet is consumed, the Cannon's health is unchanged and the hull's drops; a flank bullet into the cannon's edge damages the cannon; the
  shield's arc follows the nose;
- the cannon fires Heavy Shells (`EnemyRounds.HEAVY_SHELL`) at 220 px/s.

### 2.6 Carrier: shell, modules, core exposure, movement in both modes (R10.14–R10.16, R10.18; t6)

#### 2.6.1 Files and scene
`assault/scenes/enemies/carrier/`: `carrier.tscn`, `carrier.gd` (`class_name Carrier extends BaseEnemy`), `carrier_brain.gd` (`CarrierBrain extends EnemyBrain`),
`carrier_config.gd` / `.tres` (`CarrierConfig extends ShipConfig`, flat), `ENEMY.md`. `WaveBuilder.carrier()` / `CARRIER`.

```
Carrier (Carrier, CharacterBody2D)   body: RectangleShape2D ≈ 176 × 280 px (hull 192 × 288 art, nose-down), layer ENEMY_HITBOX, mask 0 (ploughs through, the station's rule)
  Sprite2D (hull)   CollisionShape2D   HurtBox (root, covers the body)   Health (hull; refuses damage, see below)
  HitFlashAnimationPlayer   ContactHitBox (same shape)   ContactProfile (ARMOR, shove_speed 220)
  Brain (CarrierBrain)   Mover (EnemyMover)   ModularHull   StateLight   HullMounts (TurretMountSlots for hull systems, §2.7)
  Modules (Node2D)
    EnginePort / EngineStarboard   (ENGINE, 180 HP, aft)
    GunPort / GunStarboard          (WEAPON, 160 HP, amidships, one BURST_CANNON slot each, traverse 150° to its own side)
    HangarPort / HangarStarboard    (HANGAR, 220 HP, starts_vulnerable false — vulnerable only while its doors are open, §2.8)
    Core                            (CORE, 600 HP, starts_vulnerable false, centre)
```
**Module x extent:** every module hurtbox stays within x ±100 px of the hull centre (`CarrierConfig.module_x_extent` 100, asserted by a row): the level-1 lane math (§2.13)
depends on it. `collision_damage` 15 (the ARMOR shove's touch damage). `score_value` 600, `counts_as_escape` true, `wreck_chance` 0 (Ph19). `is_laser_blocking()` false.
`accepts_tow()` false. `can_be_repaired()` false. Duck-typed `accepts_ward() -> false` (owner choice 7): `SupportShipBrain`'s ward filter adds "skip a candidate that
answers `accepts_ward() == false`" (a shield on an `is_armored()` hull would never absorb). **Hazards (config, explicit):** `hazard_avoidance` 0.5, `hazard_margin` 120,
`hazard_resistance` 1.0 (a capital ship shrugs off pull and slow; Ph19 owns the mass model); in Assault CROSS the brain writes `mover.hazard_avoidance = 0` (its x is placed
by measurement, never steered, §2.6.3).

#### 2.6.2 The armoured hull and the core
- `homing_point(from)`: the live vulnerable module nearest `from` (its `HomingPoint`, else its centre), else the hull centre (player homing rockets otherwise park on the
  armoured hull; the Ph4 rule). The Heavy Gunship answers the same.
- The hull is armour: `Carrier.deflects_hit(_hb)` → true and `is_armored()` → true always, so every player projectile crossing the hull overlaps it without being consumed
  and reaches the parts wherever they sit; `_on_received_damage` is overridden to refuse (white flash, `armor_deflected(damage: int)` signal), so neither bullets nor the beam
  nor the nova nor a level laser ever lower the hull `Health`.
- **Core exposure (owner choice 1):** when `ModularHull.destroyed_count([ENGINE, WEAPON, HANGAR]) ≥ config.core_exposure_count` (3), `Core.set_vulnerable(true)`
  deferred, the core's plating art opens (VisualState change on the core sprite) and the brain enters **PANIC** (§2.7). Before that a hit on the core pings (`deflected`)
  and does nothing — the core is vulnerable **only when intended**, against bullets, rockets, the beam and the nova alike (the module's own vulnerability check, §2.1).
- **Death:** `Core.destroyed` → `health.set_health(0)`, which runs the normal `BaseEnemy` death (was_killed, `died`, explosion, free); every module wreck goes with the hull.

#### 2.6.3 Movement
`CarrierBrain.Phase { CRUISE, SCREEN, PANIC, CROSS, IDLE, NOTICING, RETURNING }` (append-only). IDEAS §6.11 / §1.2: "a carrier does not chase the player; it controls space".
- **Open Space SCREEN** (engaged): holds the player in a band `screen_range_min` 600 .. `screen_range_max` 950 px — `arrive` toward the band's middle on the line to the player
  only when outside it, never closer; it never moves more than `leash_radius` 900 px from `patrol_anchor` (beyond it, `arrive` back while still turning). **Facing:** the side
  with a live gun battery toward the player (heading = bearing ∓ 90°), the nearer side when both live; no live battery → bow (the heavy cannon) to the player.
- **Engines (module death changes movement):** base `max_turn_rate` 0.35 rad/s, `max_speed` 70, `acceleration` 40. One engine lost: turn rate × `one_engine_turn` 0.5, speed ×
  0.8, and a constant yaw bias of `list_rate` 0.06 rad/s toward the dead side added to every facing request (it lists); both lost: turn rate × `no_engine_turn` 0.15, speed ×
  0.4. Engine plumes (code-drawn) go out with the engine.
- **CRUISE** (Open Space, not engaged): `AnchorIdle` slow orbit (`idle_radius` 220, `perceive_radius` 1100, `lose_radius` 1800).
- **PANIC in Open Space:** `retreat_from` the player, but the retreat target is clamped onto the `leash_radius` circle round `patrol_anchor` — **the leash wins** (it ends up on the
  far side of its anchor from the player, never beyond 900 px), still facing a live battery to the player.
- **Assault CROSS** (IDEAS §6.11 "moves vertically through the corridor at a controlled speed; its body becomes a moving arena"): `constraint_mode` NONE (it enters from
  above and leaves below; the corridor would force it back), nose-down and never rotated (`face_toward` straight down every tick), `mover.hazard_avoidance` 0, the Assault speed
  cap `assault_max_speed` 110 px/s written onto the mover (≥ the hypotenuse of the crossing and the sway, so the cap never slows the descent).
  - **Vertical speed is constant**, `assault_cross_speed` 90 px/s (starting value), independent of engines, panic and hazards (`hazard_resistance` 1.0).
  - **An EMP does not stop the crossing:** `CarrierBrain.on_emp_started()` in CROSS commits `mover.boost(Vector2.DOWN, assault_cross_speed, window)` for the EMP window
    (`window` read from a new read-only `BaseEnemy.emp_seconds_left()`), so weapons and hangars pause (the brain is not ticked) while the hull keeps descending. Open Space
    keeps the Ph9 halt.
  - **Lateral sway** keeps the player inside a live battery's arc: `request_velocity` x toward that, capped at `assault_sway_speed` 30 px/s × the engine factor (1 / 0.5 /
    0.1) and **leashed to `assault_sway_leash` 30 px around the anchored spawn x** (never the view: the column lanes of §2.13 are narrow).
  - A wave spawn sets `world_anchored_x` true (the Ph8 rule, `EnemyWorld.view_rect()` / `projectile_world_rect()` centres, once in `_ready()`), so its world x is `640 + 2 · design_x`.
  - It frees itself once its top edge is below the projectile world rect (`EnemyWorld.projectile_world_rect(tree).end.y + hull half-height`). **Its Assault life is therefore
    fixed** by spawn y and speed: worst case (spawned at the highest view, shake included, the `_static_life()` rule) from design y −260 ≈ (1308 + 548) / 90 ≈ 20.6 s.
- **No budget, no DISENGAGE** in Assault: the crossing is its life.

#### 2.6.4 Rows (t6; `tests/integration/test_carrier.gd`, both harnesses)
- spawn: 7 modules with roles, HP and vulnerability as authored; every module within `module_x_extent` of the centre; hull refuses a bullet (not consumed,
  `armor_deflected`), the beam and the nova (hull `Health` unchanged);
- **core vulnerable only when intended:** with 0, 1 and 2 outer modules destroyed (each of three combinations: two engines, a gun and a hangar, an engine and a gun) a
  real-physics bullet on the core passes and the core's health is unchanged, **and the player's beam held on the core for 2 s and a nova leave it unchanged** (`deflected`);
  after the 3rd, from the next physics frame, bullets, beam and nova damage it; destroying the core kills the carrier (`died`, `was_killed`); boundary: `core_exposure_count` 3
  read from the `.tres`, never typed;
- **closed hangar:** a bullet, the beam and a nova against a closed hangar leave its health unchanged (the hangar rows proper are §2.8's);
- **module death changes movement:** with both engines alive the hull turns 90° in t; with one engine dead it takes ≥ 1.8 t and lists toward the dead side (a still player:
  the heading drifts by ≥ 0.05 rad/s with no turn request); both dead: ≥ 5 t. Assault: the lateral sway speed caps at 30 / 15 / 3 px/s;
- Open Space SCREEN: never closes inside 600 px of a still player; never leaves `leash_radius` + 50 px of its anchor while chasing a fleeing player for 30 s; in PANIC it never
  passes `leash_radius` + 50 px either;
- **wreckage stays:** destroy four modules over 10 s; each stays in the tree with its wreck texture until the carrier dies, and the carrier's silhouette (the set of
  visible module sprites with intact textures) changes with each loss;
- **Assault CROSS:** y advances at 90 px/s ± 1 with any combination of engines alive, in PANIC, inside a slow hazard field and **through a 5 s EMP**; **with the player stub held at
  the left view edge, then at the right view edge, for the whole crossing, x never leaves spawn x ± 30 px**; freed below the projectile rect; never rotates;
- `HAZARD_PROFILES` row in `test_enemy_dual_mode.gd`: `carrier` 0.5 / 120 / 1.0; in CROSS the mover's avoidance reads 0;
- contact: touching the hull shoves the real player (ARMOR) and deals 15.

### 2.7 Carrier weapons: side batteries, bow cannon, missile bank, anti-approach pulse, panic (R10.15, R10.16; t7)

- **Side batteries** (`GunPort` / `GunStarboard`, BURST_CANNON, traverse 150° centred on their own side): "a gun destroyed → one side becomes safe". With the port battery
  dead, no battery round ever leaves toward the port half-plane (the traverse keeps the starboard battery on its side).
- **Bow heavy cannon** (hull-mounted, `HullMounts/Bow`, HEAVY_CANNON, traverse 70°, forward): a hull system, not a module (it falls silent only when the carrier dies;
  Ph18 may tie it to a module). Heavy Shells.
- **Missile bank** (hull-mounted, `HullMounts/Dorsal`, ROCKET_BATTERY, traverse 360°, PURSUIT rockets, `cooldown_seconds` 7.0): fires at a player beyond
  `missile_min_range` 450 px (rockets punish standing off, the pulse punishes hugging). Its rockets persist (Ph5), which is one more reason no Carrier enters an
  `ENEMIES_CLEARED` section.
- **Anti-approach pulse:** `carrier_pulse_ring.tscn` (an inherited `energy_ring.tscn`: `max_radius` 420, `telegraph_seconds` 1.0, `ring_speed` 360, `band` 24, `gap_count` 2,
  `gap_deg` 50, `damage` 14) owned and ticked by `CarrierBrain` (`setup(carrier, owner_group)`; `start()` when the player's distance to the hull centre < `pulse_trigger_range`
  340 px and `pulse_cooldown` 5.0 s has run out; `cancel()` on the carrier's death). The ring's fairness rule (Ph8: gap arc at `max_radius / 2` ≥ 3 · r_player) is asserted for
  this scene too. **What it hits:** through `EnergyHitScan` — the player, allies, and enemies and asteroids **outside** the carrier's owner group (its launched children are in
  that group, §2.8, so it passes them); it never reaches any module (enemy energy weapons do not target `enemy_parts`, §2.1), so it cannot hurt its own parts. It **can** hurt
  another enemy it sweeps (e.g. level 1's jammer): the same friendly fire every Ph8 enemy beam has (owner choice 8). Damaging only (owner choice 5; an EMP variant is Ph18).
- **Hull mounts** are built from `HullMounts/*` slots by the same `TurretMountBuilder` (the carrier calls `ModularHull.build_mounts()` for the module slots first, then the
  builder for the hull slots with the returned running index).
- **PANIC** (core exposed): emergency deployment (every live hangar launches its full payload at once, §2.8), `pulse_cooldown` × 0.5, battery `cooldown_seconds` × 0.7 (set on the
  mounts), Open Space: the leash-clamped retreat of §2.6.3; Assault: unchanged crossing speed. Core light flashes red; hull running lights strobe.
- The brain ticks every mount with `can_fire = can_see_player() or fires_past_cover()`; in Assault mounts fire only while the carrier's centre is inside `EnemyWorld.view_rect()`
  (the Ph8 turret rule) — the crossing is its attack gate.

Rows (`tests/integration/test_carrier.gd` §weapons, both harnesses):
- **module death disables an attack / one side safe:** destroy `GunPort`; with the player stub **re-placed every tick on the carrier's current port side** (bearing = heading −
  90°, 400 px out, so the carrier's turn toward its live battery cannot bring the player into the starboard arc) for 20 s, no battery round is fired and none lands in the port
  half-plane; a control with both guns alive is hit;
- the bow cannon fires Heavy Shells only inside its 70° arc; the missile bank fires only beyond 450 px;
- the pulse starts within one tick of the player entering 340 px after the cooldown, never before the cooldown, and the ring's gap rule holds for `carrier_pulse_ring.tscn`;
- **the ring never damages its own carrier's parts or hull:** a ring swept over the carrier with every module vulnerable leaves every module's and the hull's health unchanged; a
  fixture enemy outside the owner group inside 420 px is damaged (control); a launched child (owner group) is not;
- PANIC: entered on the tick after exposure; pulse cooldown halves; battery cooldown × 0.7; Open Space: distance to the player grows while it lasts, within the leash.

### 2.8 Carrier hangars: doors, launches, caps, emergency deployment (R10.16, R10.19; t8)

`assault/scenes/enemies/carrier/carrier_hangars.gd` (`class_name CarrierHangars extends RefCounted`, held by `CarrierBrain`; one per carrier), driving the two HANGAR modules.
- **Payload** per hangar, read from the config: `hangar_port_scene` / `hangar_starboard_scene` (string paths in the flat config: Open Space swarm drones port, fighters
  starboard; `assault_hangar_scene` swarm drone for both, owner choice 6), `launch_count` 2 per launch (`assault_launch_count` 2).
- **Cycle:** `CLOSED` → `OPENING` (`door_open_seconds` 0.8 s: doors animate open, the hangar's light yellow, **the HANGAR module becomes vulnerable** — owner choice 4) →
  `LAUNCH` (children spawned) → `OPEN` (`door_hold_seconds` 2.0 s, still vulnerable) → `CLOSED` (invulnerable again). Open Space: a launch every `launch_period` 9.0 s while
  engaged, only while that hangar's live children < `hangar_live_cap` 3 and the carrier's total < `carrier_live_cap` 6. Assault: **one launch per hangar per life**: the port
  hangar's OPENING starts `assault_first_launch` 3.0 s after the carrier's centre enters the view, the starboard hangar's 4.0 s after that (7.0 s).
- **Spawning** (the `LaserTender.launch_pair()` rule): synchronous from the brain's physics tick; each child is instantiated at the hangar's mouth marker, given
  `start_engaged = true` where its brain has it, a seeded `rng_seed` from `brain.rng`, a squad (`SquadController`, one per carrier per payload kind, held by
  `CarrierHangars`), added to the carrier's `owner_group` (the ring passes it), added as a **sibling** in the carrier's parent, a collision exception with the carrier,
  given an outward `mover.boost` (300 px/s, 0.4 s) on its first tick, and announced with `EventBus.enemy_spawned_orphan.emit(child)`. Children keep their own config (score,
  escape flag, Assault budget from spawn). They never dock, so a launch never costs combo by itself.
- **A destroyed hangar never launches again** (its cycle stops in whatever state, its wreck doors hang open). If it dies mid-OPENING, nothing launches.
- **Emergency deployment** (PANIC entry): every **live** hangar that may still launch (Open Space: under its caps; Assault: not launched yet) goes straight to LAUNCH without the
  door telegraph, once. A destroyed hangar deploys nothing.
- Rows (`tests/integration/test_carrier_hangars.gd`, both harnesses unless marked):
  - doors open 0.8 s before children appear; the hangar is hittable (bullet consumed, health drops) only from OPENING to the end of OPEN, and deflects before and after;
  - Open Space: launch period and caps over 60 s with the player still (never more than 3 live per hangar or 6 total);
  - **a destroyed hangar stops launching (Open Space):** destroy `HangarPort` mid-CLOSED: over the next 40 s every new child came out of `HangarStarboard`; destroy both: no new
    child ever, the carrier keeps fighting; destroyed mid-OPENING → no launch;
  - **a destroyed hangar stops launching (Assault):** `HangarPort` destroyed (doors forced open by a test hook, then shot) 2.0 s after the carrier enters the view → no launch
    at 3.0 s, the starboard launch still comes at 7.0 s, total children 2; both destroyed before 3.0 s → no child in the whole crossing; undisturbed → exactly one launch per
    hangar, 4 children, never more;
  - **emergency deployment:** PANIC with both hangars live and unlaunched → both deploy at once; **PANIC with `HangarPort` destroyed → only the starboard hangar deploys**; a
    hangar that already launched in Assault deploys nothing;
  - children are siblings, announced once through `enemy_spawned_orphan` (a spy on the EventBus), in the carrier's owner group (the carrier's ring passes through them), and
    outlive the carrier.

### 2.9 Visual states and light vocabulary (R10.20, R10.21; t5, t6, t7, t8, t9)

Every state is a light or a part, never a hull recolour (IDEAS §21): `StateLight` on each hull (the Ph5 component: OFF / CHARGING yellow / ARMED red / LOCKED white); module
lights: vents **orange** while venting, battery / cannon yellow while charging, hangar yellow while the doors open, core **red flashing** in PANIC, everything **dark** on a
wreck; the cannon's shield is cyan (the `EnemyShield` drawing). Damage: DAMAGED parts spark (code-drawn); wrecks swap to their wreck texture and keep their place; the
Carrier's silhouette changes as parts break (wreck sprites are visibly smaller / torn), its hangar doors read closed / open / broken, its core plating closed / open.
Engine plumes are code-drawn and go out with the engine. A deflected hit on a locked part (closed vent, closed hangar, plated core) shows a white ping on the part.

### 2.10 Art (R10.21; IDEAS §21–23; t9)

Every sprite through the `pixel-art-generation` skill (strict top-down, `view: "high top-down"`, `isometric: false`), saved with `./scripts/pixellab.sh`, opened and checked.
Faction palette: dark navy hull, red / maroon accents, a cool blue edge light. Hulls are drawn with **empty sockets** where the parts sit, so a wreck reads as damage to a part,
not a hole in the art. If the generator caps the canvas below a hull's size, generate at the largest supported size and scale by an integer factor only. **Art is drawn to the
authored geometry: t9 changes no collision shape, hurtbox, module position, `HomingPoint` or body size** (the Gunship's flush-edge rule and the level-1 lane and column
measurements depend on them); a sprite that needs a different footprint is redrawn, not the shape moved.

| Asset | Size | Notes |
|---|---|---|
| Heavy Gunship hull | 112 × 144 | wide, slab-sided rectangle, nose-down; edge sockets for 2 side batteries, a nose cannon, a rear missile pod, 2 flank vents |
| Gunship battery (intact / wreck) | 32 × 40 each | one sprite, mirrored for the other side; the mount head stays code-drawn |
| Gunship nose cannon (intact / wreck) | 32 × 24 each | barrel housing on the nose edge |
| Gunship missile pod (intact / wreck) | 40 × 24 each | 4 tube mouths |
| Gunship vent | 16 × 24 | grille; the orange glow is code-drawn |
| Carrier hull | 192 × 288 | long flight-deck carrier, nose-down, sockets for every part, hangar bays port / starboard, bow cannon housing |
| Carrier engine (intact / wreck) | 48 × 48 each | |
| Carrier gun battery (intact / wreck) | 48 × 48 each | |
| Carrier hangar (closed / open / wreck) | 64 × 56 each | the door states |
| Carrier core (plated / exposed / wreck) | 64 × 64 each | plating panels open on exposure |

**Transparency (review finding 10):** `test_entity_sprite_transparency.gd::_collect_textures()` only reads `Sprite2D.texture` and `AnimatedSprite2D.sprite_frames`, so a texture
held in an export (`EnemyModule.intact_texture` / `wreck_texture`, the hangar door and core plating textures) is never checked. t9 **extends the walk**: every `Texture2D`-valued
property of every node in each in-scope scene's `SceneState` is registered (instance nodes included, without recursing into their sub-scene). If the wider walk flags a texture
that predates Phase 10, fix it with `./scripts/strip-sprite-bg.sh` when it is an entity sprite drawn over the world; if it is not (a UI or icon texture), stop widening and instead run
the same opaque-fraction check over every Phase 10 export texture inside `test_ph10_sprites.gd`, and record which was done in DECISIONS.

Rows (`tests/integration/test_ph10_sprites.gd`, no physics): every scene's hull texture is assigned and has the planned size (± the generator's proportion, as Ph5 allowed);
every module has `intact_texture` and `wreck_texture` set and different; the hangar has three door textures and the core two plating textures; destroying a module in a
hand-ticked instance swaps its `Sprite` texture to `wreck_texture`; **every one of those textures is ≤ 90% opaque** (through the widened sweep, or this file's own check); the
Gunship flush-edge static row (§2.4.5) and the Carrier `module_x_extent` row (§2.6.4) still pass on the art-bearing scenes.

### 2.11 Roster gates every new scene joins (t4, t6)

`heavy_gunship/` (renamed) and `carrier/` are in: `test_enemy_contact_damage.gd` `ROSTER` (30 and 15), `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`
(the root hurtbox covers the body; parts are under `Modules`), `test_config_instance_isolation.gd` (directory sweep, automatic; both configs flat), `test_entity_sprite_transparency.gd`
and `test_project_load_integrity.gd` (automatic), `test_base_enemy.gd` (roster, tow table: both refuse), `test_enemy_dual_mode.gd` (one spawn row each and a `HAZARD_PROFILES`
row each: heavy_gunship 1.0 / 90 / 0.6, carrier 0.5 / 120 / 1.0), `test_enemy_mover_single_writer.gd` (automatic for both brains and roots; `enemy_module.gd` / `modular_hull.gd`
are under `global/components/` and write no motion), `test_signal_emit_arity.gd` (automatic). `carrier_pulse_ring.tscn` joins the Ph8 ring fairness rows; `heavy_cannon_mount.tscn`
joins the mount variant sweeps and the round lifetime sweep.

### 2.12 Level 1: the Heavy Gunship replaces the four gunship rows (R10.22; t11)

`assault/scenes/levels/edelia/1/level_1_director.gd`. **Triggers, delays and list order stay** (the deep_space 3.5 s wave's position is pinned by
`test_level1_fighter_fire_density.gd::test_waves_trigger_on_the_shipped_schedule`, the "wave-order quirk").
- deep_space 3.5 s: `b.heavy_gunship().at(0, -500)` (already switched by t4; no rail).
- cloud_descent 50.0 s: `.at(0, -400).move(b.straight(42))` → `b.heavy_gunship().at(0, -400)` (no rail).
- cloud_descent 62.0 s: both rows → `b.heavy_gunship().at(-100, -400)` and `.at(100, -400).delay(0.8)` (no rail). Owner choice 2 (default: all three).

**The lasers each heavy meets.** The cloud_descent heavies spawn at ≥ 50 s; its last column set (34 s) is dark long before, so **they meet no laser**. The deep_space heavy
(3.5 s, x 640, life ≈ 3.5 → 25 s) meets **the level-start `LaserWallWave`** (`level_1.tscn`, 12 vertical rays over world x 0–672 from y −380, lit at level start, not in the
schedule) and all three deep_space column sets (6.0 s at x 128 / 640 / 1152, 14.0 s at 384 / 896, 22.0 s at 256 / 640 / 1024). A heavy is mobile, so its x is not a static check:
**the lit replay below is the test**.

**Lit slice replay (review finding 6).** t11 extends `tests/helpers/level1_slice_replay.gd` with an opt-in `light_lasers: bool` (default false: every existing replay is
unchanged). When on, the replay adds a spawner node carrying `Level1Director`'s script (the technique of `tests/helpers/level1_column_replay_worker.gd`) and calls its real
`_spawn_laser_columns(row["columns"])` at each `laser_column_schedule()` row's section time on the slice timeline (a row whose lit window began before the slice start is lit at
the slice start with its remaining time), and, for a deep_space slice that starts before the wall is dark, instantiates `laser_wall.tscn` at the `LaserWallWave` position read from
`level_1.tscn` (`_wall_wave_row()`'s source). It reports every hull `died` and every `EnemyModule.destroyed` of the target scene, with the time and whether a lit ray covered it.
To keep the director's defaults in one place t11 hoists them into `Level1Director.COLUMN_WARN_SECONDS` 3.0 and `COLUMN_ACTIVE_SECONDS` 4.0 (used as `_spawn_laser_columns`'s
defaults; behaviour-identical) — t12 reads them for its lit windows.

**Gates** (`tests/integration/test_level1_heavy_spawns.gd`, new):
- **pin** the four rows (section, trigger, offset, delay, scene) as `EXPECTED_PH10_GUNSHIPS`, with mutation boundary rows (a changed delay, a `.move()` put back);
- **count:** `_LEGACY_PEAK_HEAVIES` is **computed once from the pre-change rows and frozen** (deep_space 1; cloud_descent: the 50 s rail gunship is culled ≈ 14.8 s after
  spawning, so with the 62.0 / 62.8 s pair the legacy peak is 3 — the task recomputes it from the old rail speeds and records the figure); peak alive Heavy Gunships per section
  ≤ 1.0 × the frozen value (a section without a frozen value may hold none), lives = spawn + `engage_seconds` + `attack_window()` + measured exit. **Boundary:** one extra heavy
  added at the section's measured peak time fails;
- **deadline** (`test_engagement_deadline.gd`, per-entry rows through `_deadline_rows`): each cloud_descent heavy's `computed = rel + max(engage_seconds + attack_window() +
  measured exit, engage_seconds + rocket max_time) + MARGIN` < 10.0 s (the exit term from `ph10_exit_keys.gd`, the rocket term from the Missiles mount's pool scenes). The tightest
  row is the 62.0 + 0.8 s heavy at rel −13.2 s. **Boundaries derived from the config, not typed:** (a) a heavy added to the last wave at delay `10.0 − tail + 0.05` is over and one
  at `10.0 − tail − 0.05` is not; (b) **the rocket term:** with the Missiles mount left open through DISENGAGE (rockets launched until the end of the exit), the 62.8 s heavy's
  `rel + engage + exit + rocket max_time + MARGIN` misses the timeout — the closure is what keeps it in (the corvette rocket-term pattern);
- **spill-over** (the Ph5 pattern, in `test_level1_heavy_spawns.gd`): no Heavy Gunship, its last rocket (`+ rocket max_time`) or any carrier child outlives the next
  `ENEMIES_CLEARED` section's last trigger; the deep_space heavy's whole life (and rockets) ends before 30.0 s (it no longer carries into the station section), with a boundary
  that a 20 s budget would not;
- **lasers (lit replay at 16×):** the deep_space heavy's window (3.5 s − 1 → its freed time) with `light_lasers` on: **no module and no hull of a Heavy Gunship dies**. **Boundary
  (proves a kill is detected):** the same replay with the heavy's mover `hazard_avoidance` 0 and its spawn at `.at(0, -500)` held on x 640 by a test hook through the 6.0 s
  column's lit window reports a death under a lit ray;
- **attack-in-budget:** each placed heavy reaches a battery FIRE before its budget expires (slice replay at 16×);
- **heavy fire density (measured, reported, ungated):** the peak heavy rounds in any 2 s window per section from the attack replays, printed and recorded in DECISIONS
  (`test_level1_fighter_fire_density.gd` counts only fighters and Gatlings; this is the record a later phase gates against);
- the existing specialist, fighter, fire-density, drone, Ph8 and Ph9 attack replays stay green (heavies are counted only by the new gate).

**Pre-approved levers, in order, if the lit replay shows a death:** (1) `hazard_margin` up to 110; (2) the deep_space offset to `.at(160, -500)` (world x 960, clear of the wall;
**never −160**, which is x 320, inside the wall); (3) `assault_preferred_range` 420 → 480; (4) the heavy's Assault orbit speed halved. **If the deadline row fails:** §2.4.3's levers
(exit speed / acceleration, then `engage_seconds` to 7.0). None fits → `Result: ESCALATE` with the replay log and the measured figures.

### 2.13 Level 1: the Carrier crosses Planet Approach (R10.23; t12)

`planet_approach` (DURATION 110 s). Every number below is computed by the task from the code, never typed; the figures here are the plan's estimates.

**Lit windows (review finding 7).** A column row at section time `t` is **lit** (telegraphed, then lethal) over `[t, t + COLUMN_WARN_SECONDS + increase + COLUMN_ACTIVE_SECONDS +
dissolve]`, with `COLUMN_WARN_SECONDS` 3.0 / `COLUMN_ACTIVE_SECONDS` 4.0 from `Level1Director` (t11's hoist; **not** `LaserRay.warn_duration`, whose export default is 0) and
`increase` / `dissolve` the laser scene's `laser_increase` / `laser_dissolve` animation lengths (frames ÷ speed, read from its `SpriteFrames`). A sanity row runs one real `LaserRay`
with those settings at 8× and asserts `is_lethal_now()` is false from the computed end on. Estimated: the 55.0 s set lit 55 → ≈ 63 s, the 78.0 s set 78 → ≈ 86 s, the 98.0 s set
98 → ≈ 106 s.

**Hard constraints:**
1. **Per-column overlap:** for every column whose lit window overlaps the carrier's Assault life `[spawn, spawn + worst life]` (worst life from §2.6.3: highest view, shake
   included; the crossing is EMP-proof, so no EMP term), the carrier's swept x range `spawn x ± (assault_sway_leash 30 + module_x_extent 100)` must clear the column's centre by
   `LaserRay._BEAM_WIDTH / 2` (28) + 28 px margin. A new helper `_carrier_column_conflicts()` does this; the existing `_column_conflicts()` (no start filter, static members only) is
   **not** reused.
2. The carrier and every launched child are gone before the section ends (110.0 s): children's lives = launch time + their own `engage_seconds` + deferral + measured exit.
3. The carrier's ≤ 4 launched swarm drones are counted in `test_level1_drone_spawns.gd`'s concurrency gate as intervals (launch time + their own life as in constraint 2): the
   all-drones peak stays ≤ 2.5× and the attack-capable peak ≤ 2.0× the frozen legacy peaks. Lever if it fails: `assault_launch_count` 2 → 1.
4. The specialist count (planet_approach 7 of 7.5) is unchanged (the carrier and its drones are not specialists); at most one carrier alive in the level; no Heavy Gunship in
   planet_approach. **Friendly fire:** the carrier's pulse ring hurts enemies outside its owner group (owner choice 8). Level 1's jammer (world x 480, alive 62.00–89.23 s) can be
   inside its 420 px reach; the ring only fires when the player is within 340 px of the carrier, and a kill can only shorten the jammer's life, which no ceiling gate is hurt by.
   `test_level1_ph9_attacks.gd` (whose jammer slice now replays the carrier too) must stay green; if the carrier's ring kills the jammer there before its attack, take option B.

**Ordered placement options (pre-approved; take the first that meets 1–4 and record the measured life, x span, lit windows and peaks):**
- **A (default):** inside the existing **65.0 s** wave (no new wave, so no later wave's effective trigger moves), `b.carrier().at(55, -260)` → world x 750 (world-anchored),
  `assault_cross_speed` 90. Life ≈ 65.0 → 85.6 s: starts after the 55.0 s set is dark (≈ 63 s; asserted), overlaps the 78.0 s set (x 150 / 550 / 950), and x 750 ± 130 (620–880)
  clears 550 and 950 by ≥ 70 px against the 56 px needed; ends before the 98.0 s set lights. Ring reach to the jammer: ≥ 240 px of x distance (friendly fire possible, accepted).
- **B:** option A at `.at(-145, -260)` (world x 350, lane between 150 and 550; also only the 78.0 s set) — closer to the jammer (≈ 130 px), so second.
- **C:** inside the **88.0 s** wave, `.at(5, -260)` (world x 650): life ≈ 88 → 108.6 s overlaps only the 98.0 s set (x 450 / 850); constraint 2 is tight (the section ends at 110 s).
- **None fits:** `Result: ESCALATE` with the measured timeline; never change a frozen `_LEGACY_PEAK_*`, never put the carrier in an `ENEMIES_CLEARED` section.

**Rows** (`test_level1_heavy_spawns.gd` unless named):
- pin `EXPECTED_PH10_CARRIER` (section, trigger, delay, offset, scene);
- constraint 1 through `_carrier_column_conflicts()`: no conflict; the 55.0 s set ends before the spawn; **boundaries:** the same carrier at the 58.0 s wave (inside the 55.0 s set's
  lit window, x 700 column within reach) is flagged, and option A at `.at(-45, -260)` (world x 550, on a 78.0 s column) is flagged;
- **lit replay at 16×** (`level1_slice_replay.gd` with `light_lasers` on) over the carrier's window: no carrier module dies, the hull never dies; the player stub at the replay's
  usual place;
- constraint 2 and the spill-over row; constraint 3 inside `test_level1_drone_spawns.gd`;
- a guard row in `test_engagement_deadline.gd`: no `carrier.tscn` entry in any `ENEMIES_CLEARED` section (boundary: a synthetic section with one fails);
- **attack-in-budget replay at 16×:** both hangars launch and at least one of its mounts fires (battery, bow cannon or missile bank) before it leaves;
- `test_level1_ph9_attacks.gd`, `test_level1_ph8_attacks.gd`, the specialist gate and the fire-density schedule row stay green; the carrier's mount fire is added to the measured,
  ungated heavy fire-density report (§2.12).

### 2.14 Hub placement (R10.24; t10)

`open_space/scenes/levels/sector_hub.gd` / `.tscn`, **appended draws** (every earlier seed unchanged):
- **Draw 19:** a Heavy Gunship on the 2600 ring at bearing **157.5°** (anchor ≈ (−2402, 995)); `_patrol_groups()` entry `"Heavy Gunship": [anchor, idle_radius 180,
  perceive_radius 900]`.
- **Draw 20:** a Carrier on a new 3400 ring at bearing **−112.5°** (anchor ≈ (−1301, −3141)); entry `"Carrier": [anchor, idle_radius 220 + leash 900, perceive_radius 1100]`
  (its SCREEN / PANIC leash is part of its footprint); its Open Space launches (drones / fighters) live in `EnemyContainer`.
- Exports for both rings / bearings like the Hacker's; `patrol_anchor` and `rng_seed` set before `add_child()`; `_expected_seeds()` grows to 20 draws.
- Every existing sweep covers them (interactables, the Ph6 TacticalSpace sweep, the Ph7 minefield row, the Ph8 sweeps A / B, the Ph9 sweep C) and the anchors stay > 1000 px
  from every other anchor. **Pre-approved levers if a sweep fails:** the gunship to bearing **−67.5°** on the 2600 ring (22.5° is unusable: ≈ 120 px from `HubDefenseSite` and
  `SectorJammer`); the carrier's ring radius anywhere in 3200–3800.
- Rows (`test_sector_hub_patrol.gd`): draws 19–20 composition (scene, ring, bearing, seed, `start_engaged` false), both groups clear the spawn, every trigger and pickup, every
  sweep passes; **a 30 s hand-ticked hub carrier with the player 3000 px away launches nothing (not engaged), and the control: with the player moved inside its 1100 px
  perceive radius it notices and its first hangar launches within `notice_time` + `door_open_seconds` + one `launch_period`, children landing in `EnemyContainer`**.

### 2.15 Gate time and the gate room (t1)

GUT ≈ 225 s at the Ph9 close (2888 tests). **t1 frees ≥ 12 s before any other task lands** (hard floor; target 15 s), by the `tests/README.md` rules only: real-physics rows on the 8×
clock, replays computed once and shared (`before_all` / memo keyed by inputs), per-tick bookkeeping no assertion reads dropped, and a production speed-up only when
bit-identical (Ph8 t1 sped up `FighterBrain.tick`). Never by lowering a tick count, duration, sample count or start grid, widening a bound or removing an assertion. t1
profiles with `scripts/gate-time.sh` (15 slowest files), reports two runs before and two after, and writes the Phase 10 allotments into `tests/README.md`. If 12 s cannot be found,
`Result: ESCALATE` with the profile (the owner decides between a smaller phase and a split gate).

**Allotments** (new GUT s; revision 2 resized them after review finding 16): t2 2.0 (≈ 10 real-physics rows), t3 0.8, t4 3.5 (incl. the corridor exit probe over both start sets;
earlier probes cost 1.95–6.7 s, so the probe is memoised once and shared with t11), t5 2.5, t6 2.0, t7 1.8, t8 2.2, t9 0.4, t10 0.8, t11 3.0 (one lit 16× replay: only the deep_space
heavy meets lasers), t12 2.5, t13 0 = 21.5 s; the phase ends ≤ 225 − 12 + 21.5 = 234.5 s. **Noise rule:** run-to-run noise is ±1–3 s, so a task compares the mean of two runs and
its own files' summed time; it escalates when the two-run mean passes 237 s or its own new / changed files exceed 1.5× its allotment.

### 2.16 Numbers and where they come from

| Value | Start | Source |
|---|---|---|
| Gunship hull HP / contact / score | 700 / 30 / 300 | judgement: ≈ 14 Standard shots (50 dmg) on the hull alone, ≈ 2.5 s of sustained fire; contact kept (gate); score above the old 200 |
| Gunship parts HP | batteries 160, cannon 200, missiles 140, vents indestructible | judgement; a part ≈ 3–4 shots, readable in a fight; X-Morph finding (few parts) |
| Gunship body | rectangle 112 × 144, parts flush with its edges | flush-edge rule (review finding 1); IDEAS §21 size 112–160 |
| Gunship phase bands | 0.6 / 0.3 | IDEAS §7 (100–60 / 60–30 / < 30) |
| Gunship ranges | OS 560 ± 90, Assault 420, `min_range` 260, emergency 800 | judgement, between the corvette (620 / 460) and the fighter |
| Gunship movement | `max_speed` 140, accel 120, `max_turn_rate` 0.9 rad/s, arc 0.16 rad/s, reversal 5–8 s | judgement: heavier than the corvette (0.22 rad/s arc) |
| Gunship hazards | avoidance 1.0, margin 90, resistance 0.6 | hull half-width 56 + laser pad 24 + 10; heavier than the Ram (0.5) |
| Break-away / emergency boost | 360 px/s 0.7 s rearm 3 s / 420 px/s 0.9 s every 5 s | below the player's 700 px/s boost exit, above its 420 cruise only briefly; judgement |
| Heat / vent | 4 bursts, 2.2 s, speed × 0.6 | judgement; Madhead "critical point" finding (bonus window) |
| Vent hull share | 1.0 (2× total) | Madhead / Amygdala findings; judgement on the factor |
| Cannon shield | arc 120°, capacity 60, regen 2.0 / 4.0 s, reboot 5.0 s | Ph5 shield defaults scaled (projected shield 40 / 4 s); judgement |
| Heavy cannon mount | 2 Heavy Shells, 220 px/s, charge 0.7 s, cooldown 3.2 s, range 900, traverse 70° | Heavy Shell scene (160 px/s, 20 dmg) sped up for a cannon; judgement |
| Gunship Assault budget / exit | 9.0 s / 300 px/s, 240 px/s² | **derived:** Cloud Descent deadline 23.2 s at rel −13.2 s − attack window ≈ 1.05 − margin 0.5 − exit ≤ 12.6 s; levers §2.4.3 |
| Carrier parts HP | engines 180, guns 160, hangars 220, core 600 | judgement: exposing the core ≈ 10 shots, the core ≈ 12 |
| Carrier module x extent | ≤ 100 px from the centre | level-1 lane math (§2.13) |
| Core exposure | any 3 of the 6 outer parts | Garegga / DonPachi lock-and-release finding; owner choice 1 |
| Carrier movement | OS `max_speed` 70, accel 40, turn 0.35 rad/s, band 600–950, leash 900; engines × 0.5 / 0.15, list 0.06 rad/s | FTL subsystem finding; judgement |
| Carrier hazards | avoidance 0.5 (0 in CROSS), margin 120, resistance 1.0 | capital ship; a constant crossing (review finding 8) |
| Carrier Assault crossing / sway / leash / cap | 90 px/s / 30 px/s / ± 30 px / 110 px/s | judgement: 1.5× the 60 px/s structure drift reads as moving; a 20.6 s worst life fits between two column sets |
| Pulse ring | r 420, telegraph 1.0 s, 360 px/s, gaps 2 × 50°, 14 dmg, trigger 340 px, cooldown 5 s | Ph8 `EnergyRing` shape scaled to the hull; fairness rule kept |
| Missile bank | PURSUIT, cooldown 7 s, min range 450 px | Ph5 / Ph8 rocket battery; judgement |
| Hangars | doors 0.8 s, hold 2.0 s, period 9 s, 2 per launch, caps 3 / 6, Assault 1 launch per hangar at 3.0 / 7.0 s | Laser Tender rearm 7 s; judgement |
| Carrier contact / score | 15 + ARMOR shove 220 px/s / 600 | Ram Corvette shove 260; judgement |

All are *starting values* except the derived ones: keep them unless a row forces a change, and log any change in `DECISIONS.md`.

### 2.17 Docs and phase close (t13)

Invoke the `updating-project-docs` skill: `docs/architecture/PROJECT.md` → Conventions (new item "Modular enemies": `EnemyModule` / `ModularHull`, the hit rule, wreckage, the
`enemy_parts` group, the two hull rules and the Gunship flush-edge rule, enemy energy weapons not reaching parts, mount traverse, the heavy rocket term in deadlines),
`docs/architecture/modules/global.md` (`EnemyModule`, `ModularHull`), `assault.md` (heavy gunship, carrier, mount builder / traverse / HEAVY_CANNON, the lit slice replay),
`open_space.md` (hub draws 19–20), `docs/enemy-roster.md` (Heavy Gunship replaces Gunship incl. every "never `.move()` the gunship" line; Carrier; `heavy_gunship()` / `carrier()`;
Heavy Shell's consumer), per-entity `ENEMY.md`, and CLAUDE.md's gate list (`test_enemy_module.gd`, `test_turret_mount_traverse.gd`, `test_heavy_gunship.gd`, `test_carrier.gd`,
`test_carrier_hangars.gd`, `test_level1_heavy_spawns.gd`, `test_ph10_sprites.gd`, the widened transparency walk). Write the epic dossier `docs/epics-done/cmug23oo90029m52wae4clve0/`
(`PRD.md`, `SOURCES.md` — the §1.2 sources, `REPORT.md`) and append `## Phase 10 - as built (<date>)` to `DECISIONS.md`, including the deferrals of §6.

## 3. Build sequence

1. **t1** Gate room: ≥ 12 s of GUT back (§2.15).
2. **t2** `EnemyModule` + `ModularHull` (minus `build_mounts`) + the beam / nova `enemy_parts` reach, on a fixture host (§2.1, §2.2). After t1.
3. **t3** `TurretMountBuilder`, mount traverse (along the arc), `HEAVY_CANNON`; `ModularHull.build_mounts()` and module-attached mounts (§2.2 t3 rows, §2.3). After t2.
4. **t4** Heavy Gunship shell (rectangle body, flush-edge parts), movement, Assault life, legacy rows and callers moved (§2.4, §2.11). After t3.
5. **t5** Heavy Gunship phases, vents, emergency, rear missiles (Assault closure), cannon shield, battery loss (§2.5, §2.9). After t4.
6. **t6** Carrier shell, armoured hull, core exposure, movement in both modes incl. the EMP-proof crossing (§2.6, §2.11). After t4 (roster files) and t3.
7. **t7** Carrier weapons and PANIC (§2.7). After t6.
8. **t8** Carrier hangars (§2.8). After t7.
9. **t9** Art for both ships and their parts, widened transparency walk, geometry frozen (§2.9, §2.10). After t5 and t8.
10. **t10** Hub placement (§2.14). After t5 and t8.
11. **t11** Level 1 Heavy Gunships, lit slice replay, deadline with the rocket term (§2.12). After t5.
12. **t12** Level 1 Carrier (§2.13). After t8 and t11.
13. **t13** Docs, roster, dossier, phase record (§2.17). After everything.

## 4. Test plan

The rows live with their design sections so each task sees them: §2.1 / §2.2 (`test_enemy_module.gd`), §2.3 (`test_turret_mount_traverse.gd`), §2.4.5 and §2.5
(`test_heavy_gunship.gd`), §2.6.4 and §2.7 (`test_carrier.gd`), §2.8 (`test_carrier_hangars.gd`), §2.10 (`test_ph10_sprites.gd`, widened `test_entity_sprite_transparency.gd`), §2.11
(roster gates), §2.12 / §2.13 (`test_level1_heavy_spawns.gd`, `test_engagement_deadline.gd`, `test_level1_drone_spawns.gd`, the lit `level1_slice_replay.gd`), §2.14
(`test_sector_hub_patrol.gd`). The epic's §40 requirements, in both harnesses:

| Requirement | Open Space and Assault rows |
|---|---|
| Module death disables an attack | Gunship battery → its mount UNPOWERED, no round for 30 s (§2.5); Carrier gun → no battery round into that half-plane with the player kept on that side (§2.7); Gunship missiles lost → no rocket (§2.5); fixture mounts (§2.2) |
| Module death changes movement | Gunship battery → it swaps its broadside side; both → nose to player (§2.4.5); Carrier engines → turn time ×1.8 / ×5 and a list, Assault sway 30 / 15 / 3 px/s (§2.6.4) |
| Core vulnerable only when intended | Carrier core with 0–2 outer parts dead refuses real bullets, the beam and the nova; 3rd → vulnerable next frame (§2.6.4); Gunship vents refuse bullets, beam and nova outside VENT (§2.5); closed hangars refuse all three (§2.6.4, §2.8); fixture locked part (§2.1) |
| Destroyed components remain as wreckage | Fixture module (§2.1), Carrier four-part row (§2.6.4), sprite swap row (§2.10) |
| A destroyed hangar stops launches | §2.8 rows in both modes, incl. destroyed mid-OPENING, Assault before 3.0 s, and emergency deployment with a destroyed hangar |
| Parts are reachable | Gunship flush-edge static row and per-part real-physics rows (§2.4.5) |

Boundary rows: the killing shot consumed under both callback orders (§2.1); `traverse_deg` 360 bit-identical and the 300° along-the-arc row (§2.3); `core_exposure_count` read from
the `.tres` (§2.6.4); the deadline exit- and rocket-term boundaries derived from config (§2.12); the lit-replay kill-detection boundary (§2.12); the carrier lane and lit-window
boundaries (§2.13); one extra heavy at the peak (§2.12); the Assault one-launch-per-hangar cap (§2.8).

## 5. Risks

- **Gate time** (§2.15): the phase needs ≈ 21.5 s on a suite with 15 s of headroom. t1's 12 s floor and the escalation rule exist for this.
- **Level-1 lasers** kill parts (and a vulnerable Gunship hull) on contact. The deep_space heavy is mobile and meets the wall and three column sets; the lit replay is the test and has
  ordered levers. The Carrier's lane is ± 70 px of slack (§2.13); its module x extent is pinned by a row.
- **Cloud Descent deadline:** a 9 s fight for the cloud_descent heavies (derived); if the measured exit is slower than estimated, the levers cut the budget to 7 s at worst, which the
  attack-in-budget rows must still pass, else the owner decides (owner choice 2).
- **Cloud Descent difficulty:** three firing heavies where none fired before (owner choice 2). The deadline gate bounds their lives, not their difficulty; nothing is play-tested.
- **Flush-edge rule:** a part hit counts on the hull only when the shot enters through the part's edge; an oblique shot that clips the part's side inside the outline is spent on the
  hull alone. Accepted (a heavy's parts are on its edges by design); the real-physics rows prove the intended bearing.
- **Callback order** on the killing shot (§2.1) — the row forces both orders.
- **Shared component edits:** `beam_behavior.gd` / `plasma_nova_module.gd` (player weapons), `TurretMount` (every Ph8 turret), `level1_slice_replay.gd` (every level-1 replay; the
  new option defaults off), `test_entity_sprite_transparency.gd` (wider walk). All additive with bit-identical defaults and rows that prove it.
- **Rear rockets in Cloud Descent** are a bounded exception to "no persistent ordnance in `ENEMIES_CLEARED` sections" (§2.5); the rocket term keeps it honest.
- **The hull rule split** (gunship hull vulnerable, carrier hull armour) is two behaviours on one framework; Ph11 / Ph12 must pick one per boss explicitly.
- **Big sprites:** PixelLab may cap the canvas below 288 px (§2.10 rule: integer scaling only).
- **ScoreTracker orphan tally:** launched children count toward the shared orphan wave-clear tally (`counts_toward_wave_clear` true) as Ph8 drones do; harmless in DURATION sections.

## 6. Out of scope

| Item | Owner phase | Reason |
|---|---|---|
| Hangar launches / battery-loss phases on the shared boss machinery (§10, §24, §25 for the heavies) | Ph18 | Ph1 roadmap; Ph10 builds them in the brains behind `ModularHull` signals |
| Enemy energy weapons (`EnemyBeam`, `EnergyRing`) damaging parts | Ph18 / Ph19 | `EnergyHitScan` would need an owner-of-part exemption; nothing in Ph10 needs it, and it would let a carrier's ring hurt its own parts |
| Destroyed parts as LOS-blocking wrecks, capital wrecks on death, heavy mass rules beyond `hazard_resistance` | Ph19 | Ph1 roadmap; `wreck_chance` 0 |
| Station rework onto `EnemyModule`; **EMP on the bonus drone, the station and the Ph8 turrets / fences** (the Ph9 deferral, DECISIONS.md:3533) | Ph11 | the station stays byte-identical; Ph11 reworks the station and its turret machinery, the natural place for structure EMP answers. The gunship part of that deferral is closed here (both heavies answer EMP) |
| Encounter compositions (heavy patrol, convoy, carrier + support) | Ph13 / Ph14 | |
| Ship-mounted EMP (carrier pulse as EMP) | Ph18 | owner choice 5 |
| Audio (vent hiss, hangar klaxon) | Ph17 | |
| Per-part score, a part HUD | Ph17 | no score system for parts exists |
| Level 2's gunship row beyond the builder rename | Ph15 | the level is not in the game flow; t4 only keeps it compiling (rail kept) |
| Leash / cleanup of a carrier's Open Space children | Ph13 | caps bound them |
| Difficulty scaling of the heavies | Ph16 | |
| A gated heavy fire-density ceiling | a later phase | Ph10 measures and records it (§2.12) |

## 7. Requirements coverage

| # | Requirement (IDEAS section) | Task(s) |
|---|---|---|
| R10.1 | Large enemies stop using one Health node; modules with their own health (§14) | t2, t4, t6 |
| R10.2 | Module exposes armour and accepted damage types (§14, §13.1) | t2 (DefenseProfile per module, deflect rule) |
| R10.3 | Disabled state (§14) | t2 (destroy), t3 (mounts powered down), t5, t7, t8 |
| R10.4 | Visual state: dark / off when destroyed, remaining as wreckage (§14, §23) | t2, t9 |
| R10.5 | Gameplay-consequence hook (§14, §26) | t2 (`ModularHull` signals), t5, t6, t7, t8 |
| R10.6 | Weak points found by looking (§13.3) | t5 (vents on the hull edge), t6 (core plating), t9 |
| R10.7 | Builds on DefenseProfile, enemy shields, turrets (epic) | t2, t3, t5 (local-module shield shipped) |
| R10.8 | Turrets mounted on larger ships (§6.5) | t3, t4, t6, t7 |
| R10.9 | Gunship 112–160 px mobile gun platform (§7) | t4, t9 |
| R10.10 | Keeps distance, turns broadside, strafes wide arcs, boosts away (§7) | t4 |
| R10.11 | Left / right batteries, central cannon, rear missiles as separate modules; battery loss removes the attack for good (§7) | t4, t5 |
| R10.12 | Phases controlled → overheat-and-vent → emergency boost with rear missiles (§7) | t5 |
| R10.13 | Retreat keeps it in the encounter; the three Assault-only assumptions removed; screen-top parking scrapped (§7, §38) | t4, t5 |
| R10.14 | Carrier 192–320 px with engines, guns, hangars, core each with HP (§6.11) | t6, t9 |
| R10.15 | Engines → turning authority; gun → one side safe; hangar → launches cut; core exposed → panic (§6.11, §26) | t6, t7, t8 |
| R10.16 | Heavy cannon, missile bank, fighter / drone launch, anti-approach pulse, emergency deployment (§6.11) | t7, t8 |
| R10.17 | Large ships built from coherent modules (§22) | t4, t6, t9 |
| R10.18 | Assault: the carrier crosses vertically at a controlled speed as a moving arena (§6.11, §20) | t6, t12 |
| R10.19 | Carrier stops launching from a destroyed hangar (§40) | t8 |
| R10.20 | Visual states: hangar doors open before launches, damaged banks spark and stop, destroyed modules remain (§23) | t5, t7, t8, t9 |
| R10.21 | Sprites for both, silhouette changes as parts are lost (§21–23) | t9 |
| R10.22 | Both replace the level-1 gunship spawns (epic) | t11 (Heavy Gunship); the Carrier joins as a new line, t12 |
| R10.23 | The Carrier joins Assault waves (epic) | t12 (+ `WaveBuilder.carrier()` t6) |
| R10.24 | The Carrier joins the hub's ambient spawn (epic) | t10 (the Heavy Gunship too) |
| R10.25 | Tests in both harnesses: module death disables an attack / changes movement, core vulnerable only when intended, wreckage stays, hangar stops launches (§40) | t2, t3, t4–t8 (§4 table) |
| R10.26 | §41 Phase 4 (heavy enemies) | this epic |
| — | §10 / §24 / §25 for the heavies | Ph18 |
| — | §28 LOS / §3.2.5 mass for heavies, wreck blockers | Ph19 |
| — | §19 encounter patterns with heavies | Ph13 / Ph14 |

## 8. Response to feedback (round-1 review)

| # | Finding | What changed |
|---|---|---|
| 1 | Inner Gunship parts unreachable through the vulnerable hull; homing parked; shield stopped nothing | **Flush-edge rule** (§2.4.1): Gunship body / hurtbox is a rectangle and every part's hurtbox has its outer side flush (± 2 px) with it, so a shot through that edge hits part and hull in one step (bullets free deferred, §1.3); `HomingPoint` markers at the exposed-edge midpoints; static geometry row + a real-physics row per part in both harnesses (§2.4.5); §2.5 says the cannon shield protects only the cannon's HP. The Carrier keeps its armoured hull, which passes projectiles to parts anywhere. |
| 2 | Enemy beams never see parts; adding them would let the ring hit its own parts | Claim dropped: enemy energy weapons do not reach parts in Ph10 (`EnergyHitScan` unchanged, §2.1, For every task); the level `LaserRay` row stays; new rows "ring / enemy beam leave fixture modules untouched" (§2.1) and "the ring never damages its own carrier" (§2.7); deferred in §6. |
| 3 | Rear rockets outlive the gunship in Cloud Descent | In Assault the Missiles mount is open only while the budget runs (closed at DISENGAGE, §2.5); the deadline adds the rocket term `engage + rocket max_time` (read from the pool scenes) with a boundary that the closure is what keeps it in (§2.12); an Assault row that no rocket leaves after expiry (§2.5); recorded as a bounded exception in DECISIONS. |
| 4 | 14 s budget cannot meet the Cloud Descent deadline | `engage_seconds` 9.0 **derived** from the 23.2 s window; DISENGAGE exit speed / acceleration 300 / 240 written by the brain; ordered levers (exit up to 360 / 320, then budget to a 7.0 s floor), each legal only while attack-in-budget stays green; else ESCALATE (§2.4.3, §2.12, §2.16). |
| 5 | Level-start laser wall ignored; −160 fallback inside it | The `LaserWallWave` is named in §1.1 S9, §1.3 and §2.12, lit in the replay, and the offset lever is `.at(160, -500)` only, with "never −160" stated. Also found: the cloud_descent heavies meet no laser at all (last column set 34 s), so the laser work is the deep_space heavy only. |
| 6 | Column replay lit nothing | `level1_slice_replay.gd` gains opt-in `light_lasers` that calls the director's real `_spawn_laser_columns` on the slice timeline and places the wall; it reports hull and module deaths under lit rays; a boundary row (avoidance 0, held on a column) proves a kill is detected (§2.12). |
| 7 | Carrier window from wrong timings; default infeasible; `_column_conflicts()` reused | Lit windows computed from `COLUMN_WARN_SECONDS` / `COLUMN_ACTIVE_SECONDS` (hoisted director defaults) plus the laser's animation lengths, with a real-laser sanity row; per-column overlap in a new `_carrier_column_conflicts()`; option A rebuilt (65.0 s wave, x 750, only the 78 s set overlaps, ≥ 70 px slack), B (x 350) and C (88 s wave, x 650) recomputed; two boundaries (§2.13). |
| 8 | Carrier sway, avoidance, speed cap and EMP made its x and life drift | Sway leashed to ± 30 px of the anchored spawn x; hazard profile explicit (0.5 / 120 / 1.0, avoidance 0 in CROSS) with a `HAZARD_PROFILES` row; Assault cap 110 px/s ≥ the crossing's hypotenuse; an EMP keeps the crossing (`on_emp_started` boost); rows with the player at each view edge and through a 5 s EMP (§2.6.3, §2.6.4). Crossing speed raised to 90 px/s so the worst life (20.6 s) fits one column gap. |
| 9 | Level 2 compile and a station test name the old gunship | t4 moves `level_2_waves.gd:34` to `heavy_gunship()` with its rail kept and renames `test_station_reinforcements.gd:363`'s assertion; S8 corrected (§1.1, §2.4.6). |
| 10 | Transparency walk never sees export textures | t9 widens `_collect_textures()` to every `Texture2D`-valued node property, with a stated fallback (own check in `test_ph10_sprites.gd`); in t9's acceptance (§2.10). |
| 11 | No beam / nova rows against immune parts | Rows: fixture locked part (§2.1), closed vent (§2.5), plated core and closed hangar (§2.6.4), all with the real beam held 2 s and a nova. |
| 12 | planSections gaps; wrong cross-reference | t5 gets §1.3; t6 §2.9; t7 §1.3 and §2.8; t12 §2.7 and §2.16; the Light cross-reference now points at §2.9; every task's list re-checked (tasks.json). |
| 13 | Framework details | Nova wording (map-wide) and the dash fixed (§2.1, S3); `EnemyModule._ready()` applies its own `DefenseProfile`; `max_health` 0 skips `Health`; wreck tint on the `Sprite` child; mounts turn along the arc with a 300° row (§2.3); t2's acceptance now covers only t2's rows, `build_mounts` and the pool-name / mount rows moved to t3 (§2.2). |
| 14 | Burst during VENT, own rockets, PANIC vs leash, "one side safe" stub, ring friendly fire | VENT ticks guns with `can_fire = is_committed()` (§2.5); own-rocket hits acknowledged with a row and a fallback exemption (§2.5); the leash wins in PANIC (§2.6.3); the stub follows the port side every tick (§2.7); ring friendly fire is owner choice 8 and constraint 4 (§2.13). |
| 15 | Acceptance and gate gaps | t4: every level-1 replay green incl. `test_level1_ph8_attacks.gd`; t12: `test_level1_ph9_attacks.gd`; heavy count "one extra at the peak" boundary; config-derived deadline boundary; spill-over row; Assault hangar rows written out and emergency deployment with a destroyed hangar (§2.8); t10 engaged-launch control (§2.14); measured, ungated heavy fire density (§2.12). |
| 16 | Allotments, geometry under measurements, hub bearing | t1 floor 12 s; allotments t2 2.0 / t4 3.5 / t11 3.0; two-run mean and per-file 1.5× escalation rule (§2.15); t9 may not change geometry and re-asserts the geometry rows (§2.10); 22.5° dropped, −67.5° the only gunship fallback (§2.14). |
| 17 | Ph9 EMP deferral unassigned | Bonus drone, station and Ph8 turrets / fences EMP → Ph11 (§1.1 S12, §6); the gunship part is closed by the rework. |
