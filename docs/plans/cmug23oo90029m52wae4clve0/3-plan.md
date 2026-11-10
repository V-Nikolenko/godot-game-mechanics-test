# Enemy rework, phase 10: modular damage, Heavy Gunship and Carrier

Revision 1 (2026-11-10). Epic `cmug23oo90029m52wae4clve0`, phase 10 of the enemy rework (idea `docs/ideas/cmufkkgmx0001o02y6bnf52bq/`).
**This directory has no `1-context.md` / `2-research.md`:** the research task is marked done but left no files, so the plan stage gathered the
context itself and records it here (§1.1 scope check, §1.2 research findings, §1.3 code facts). Code facts were read on `agent/auto-dev` @ `b4b3de2`.

## Summary for the owner

- **For the player:** big ships stop being health bars. You take them apart: each gun, engine, hangar and missile pod has its own health, goes dark and stays on the hull as visible wreckage when destroyed, and losing it changes the fight.
- **Heavy Gunship (reworked):** no longer parks at the top of the screen. It keeps its distance, turns side-on so a gun battery faces you, sweeps wide arcs and boosts away if you rush it. Kill a side battery and that gun is gone for good, so it turns its other side to you; its nose cannon is shielded from the front. Below 60% it overheats and has to vent: glowing vents open on its flanks and shots into them hurt double. Below 30% it boosts away and fires rear missiles at whoever chases it, but it stays in the fight instead of flying off and vanishing.
- **Carrier (new, the largest ship so far):** an armoured hull carrying two engines, two side gun batteries, two hangars and a core. Engines lost: it turns slower and lists. A battery lost: that side is safe from battery fire. A hangar lost: no more launches from it (and a hangar can only be hit while its doors are open). After any three of those six are destroyed the core's plating opens; the carrier panics (launches everything left, pulses faster, tries to escape) and dies when the core does. It also has a bow heavy cannon, a missile bank and a pulse ring that punishes hugging the hull.
- **Where:** level 1's four old gunships become Heavy Gunships; one Carrier crosses Planet Approach slowly as a moving arena; both ships also patrol the Open Space hub.
- **Built for the bosses to come:** the part system, guns mountable on ships (with limited firing arcs) and the heavy cannon are shared pieces the fortress and dreadnought phases reuse.
- **Left out:** hangar launches and phases driven by the shared boss machinery (phase 18), wrecks you can hide behind and heavy ships resisting gravity wells (phase 19), encounter design around them (phases 13–14), sound (phase 17), score for individual parts.
- **Main risks:** the test suite is close to its time ceiling, so the first task must win back about 10 s before anything else lands; level 1's laser columns kill anything they touch, so the Carrier and the gunships must be placed and steered around them by measurement; Cloud Descent gets harder (its three old gunships never actually fired).
- **Choices for you (default in brackets):**
  1. When does the Carrier's core open: after any three of its six outer parts are destroyed, or only after both hangars? [any three]
  2. Cloud Descent's three old gunships never fired (a rail switched their brain off). Replace all three with firing Heavy Gunships, or only the first? [all three]
  3. Does a hit on a Heavy Gunship's part also wear down its hull (one damage pool for its phases, parts on top)? [yes]
  4. Can a hangar only be damaged while its doors are open? [yes]
  5. The Carrier's anti-approach pulse: a damaging ring now, or also an ability-locking EMP (phase 18)? [ring now, EMP later]
  6. In Assault the Carrier launches only swarm drones (fighters only in the hub), to keep level 1's fighter fire density unchanged? [yes]
  7. May the Support Ship shield a Heavy Gunship (it never shields the Carrier, whose armoured hull makes a shield useless)? [yes]

## For every task

Phase 10 of the enemy rework. Read `CLAUDE.md`. Earlier phases' rules in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` stand unless a line here changes them.
- **`EnemyModule`** (`global/components/enemy_module.gd`, `Node2D`, group `&"enemy_parts"`): one destructible part of a large enemy. Children `HurtBox` (layer 512),
  `Health`, `Sprite`, optional `DefenseProfile` (mask + `accepted_damage_types`), optional `MountSlots` (`TurretMountSlot`s). `enum Role { WEAPON, ENGINE, HANGAR, CORE,
  WEAK_POINT }` (append-only). Exports `module_id: StringName`, `role`, `max_health` (0 = indestructible), `starts_vulnerable := true`, `hull_share := 0.0`,
  `intact_texture`, `wreck_texture`. API: `is_destroyed()`, `is_vulnerable()`, `set_vulnerable(on)`, `deflects_hit(hit_box) -> bool`, `destroy()`, `mounts()`,
  `attach_mount(mount)`, `visual_state()` (`VisualState { INTACT, DAMAGED, WRECK }`). Signals `damaged(module: EnemyModule, amount: int)`, `destroyed(module:
  EnemyModule)`, `deflected(module: EnemyModule)`, `vulnerability_changed(module: EnemyModule, vulnerable: bool)`. **Damage is taken from the module's
  `HurtBox.received_damage`** (after the hurtbox's type filter and absorber slot), so a local `EnemyShield` attaches to the module's hurtbox as in Ph5. The
  deflect decision is cached per HitBox instance id (the `ArmorPlate._resolve` shape) and a module destroyed this physics frame still consumes the shot that
  killed it. **A destroyed module stays in the tree as wreckage**: hurtbox closed (deferred), wreck texture, out of `enemy_parts`, mounts powered down, never freed
  before its host. Modules sit under a `Modules` group node, never as direct children of the enemy root (the hurtbox-geometry gate's rule).
- **`ModularHull`** (`global/components/modular_hull.gd`, `Node`, child of the host root): collects the `Modules/*` `EnemyModule`s, builds every module's mounts
  through `TurretMountBuilder` (pools as **host root children**), forwards `hull_share × amount` of a module's damage to the host's `Health`, and re-emits
  `module_destroyed(module: EnemyModule)`. Queries `module(id)`, `modules()`, `live(role)`, `destroyed_count(roles: Array) -> int`.
- **Host rule (both heavies, later bosses):** a `BaseEnemy` with one full-size root `HurtBox` (covers the body; the gate), `is_laser_blocking() == false`, duck-typed
  `launch_velocity()` / `rocket_clear_radius()` for rocket mounts, and `homing_point(from)` = the nearest live vulnerable module to `from` (else the hull centre), so player
  homing rockets steer into a part instead of parking on the hull (the Ph4 rule). The Heavy Gunship's hull is **vulnerable** (its root `Health` is the hull bar the phases read; a
  hit on a part also lands on the hull, owner choice 3). The Carrier's hull is **armour**: `deflects_hit()` true, `_on_received_damage` refuses, and the carrier
  dies when its `Core` module dies (`health.set_health(0)` drives the normal `BaseEnemy` death).
- **Player direct emitters reach parts:** `beam_behavior.gd` and `plasma_nova_module.gd` add group `&"enemy_parts"` to their target list (the module's `HurtBox`
  child is found by name, as for enemies).
- **`TurretMount` extensions** (`assault/scenes/enemies/defense_turret/mounts/`): `traverse_deg := 360.0` (360 = today, bit-identical) and
  `TurretMountSlot.traverse_deg_override := -1.0`; a mount never aims or fires outside `rest_bearing_deg ± traverse_deg/2`. Appended
  `Variant.HEAVY_CANNON` (`heavy_cannon_mount.tscn`, `BurstCannonMount` firing `EnemyRounds.HEAVY_SHELL`: the Heavy Shell's first consumer).
  `TurretMountBuilder.build(...)` (static) is the one place a mount and its pools are built; `DefenseTurret._build_mounts()` calls it unchanged in behaviour.
- **New names and places:** `assault/scenes/enemies/heavy_gunship/` (a `git mv` of `gunship/`: `HeavyGunship`, `HeavyGunshipBrain`, flat `HeavyGunshipConfig`);
  `assault/scenes/enemies/carrier/` (`Carrier`, `CarrierBrain`, `CarrierHangar` logic in `carrier_hangars.gd`, flat `CarrierConfig`, `carrier_pulse_ring.tscn`).
  `WaveBuilder.heavy_gunship()` (`GUNSHIP` const removed) and `carrier()`. One `*config*.tres` per enemy directory.
- **Conventions kept:** brains tick on physics through `BaseEnemy._physics_process`; only `EnemyMover` writes an AI body's velocity / rotation (the single-writer gate);
  committed moves are `mover.boost()`; randomness only from `brain.rng`; `TargetInfo` for the player; mounts write only their own rotation; hull art nose-down
  (`sprite_forward_angle` `PI/2`); configs are flat `@export_group` fields; weapon tuning lives in weapon / mount scene exports; IDEAS §21: state shows on a light or a
  part (orange = venting / overheating, yellow = charging, white = locked, red = armed, cyan = shield, dark = destroyed), never a recoloured hull; signals declared
  with their arity; per-frame prints behind `OS.is_stdout_verbose()`; never hand-type a `uid://`, never run `update_project_uids`; art only through the
  `pixel-art-generation` skill and `./scripts/pixellab.sh`. **`enemy_mine.gd` never names its own `class_name`.**
- **Assault life:** both heavies have an `EngagementBudget` (`engage_seconds`), a measured exit and an attack gate like every Ph4–Ph9 AI enemy. **No Carrier in an
  `ENEMIES_CLEARED` section** (guard row). A Heavy Gunship may sit in `cloud_descent` (`ENEMIES_CLEARED`, timeout 10 s, last trigger 76.0 s) only with a per-entry
  deadline row. Assault exit probes are built only through `tests/helpers/ph10_exit_keys.gd` (static `prepare_probe`, never a lambda; the Ph8 / Ph9 memo rule).
- **Not in this phase:** module-tied launches and phase rules on the shared boss machinery (Ph18), destroyed parts as line-of-sight-blocking wrecks, death wrecks
  (`wreck_chance` stays 0) and heavy hazard resistance (Ph19), encounter compositions (Ph13 / Ph14), audio (Ph17), per-part score.
- **Tests first, GUT.** Behaviour specs run in both harnesses (`tests/helpers/enemy_ai_harness.gd`, `open_space()` / `assault()`, label-parameterised, never
  `use_parameters([HARNESS…])`), hand-ticked at 1/60; physics-dependent rows (projectile hits, LOS) run on real physics at the 8× clock (`_scale_clock()` /
  `_restore_clock()` from `test_level1_drone_exit.gd`). Per-tick drivers are a child `_Ticker` node. Run `scripts/check-test-leaks.sh` after anything that awaits.
- **Gate time is a budget:** GUT was ≈ 225 s at the Ph9 close (ceiling 240 s). **t1 frees ≥ 10 s first** (hard floor; below it, `Result: ESCALATE`). Allotments (new GUT
  s): t2 1.5 · t3 0.8 · t4 2.0 · t5 2.5 · t6 2.0 · t7 2.0 · t8 2.5 · t9 0.3 · t10 0.8 · t11 3.5 · t12 2.5 · t13 0 = 20.4 s, so the phase ends ≤ 236 s. Measure every task
  with `scripts/gate-time.sh` before and after and add a row to `tests/README.md` → Gate time. An overrun is fixed by sharing a scenario, the 8× / 16× clock or a memoised
  probe, never by cutting an assertion; a task that would take GUT past 238 s stops with `Result: ESCALATE`.
- **Task order:** `enemy_module.gd` / `modular_hull.gd` are written by t2 → t3 (a later task changes them only with a DECISIONS note); t5 and t6 may run in parallel; the roster gates (`test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`,
  `test_enemy_hurtbox_geometry.gd`, `test_base_enemy.gd`, `test_enemy_dual_mode.gd`) and `wave_builder.gd` t4 → t6; carrier files t6 → t7 → t8; `sector_hub.*` and
  `test_sector_hub_patrol.gd` only t10; `level_1_director.gd` t11 → t12. `DECISIONS.md` and the `tests/README.md` gate table are append-only and shared.
- Numbers marked *starting value* (§2.16) are judgement, not play-tested; keep them unless a row forces a change, and log a change in `DECISIONS.md`.
- Every task appends its "Phase 10, built in tN" notes and any deviation to `DECISIONS.md`. Finish with `bash /agent/verify.sh` green. Stay on `agent/auto-dev`.

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

### 1.1 Scope check (re-validated against the code @ `b4b3de2`)

| # | Finding | Effect on this phase |
|---|---|---|
| S1 | No module / part / weak-point concept exists in game code. Precedents: `StationTurret` (own `HurtBox`/`Health`, texture swap to `station_turret_destroyed.png`, stays in the tree, `destroyed(turret)`), `ArmorPlate` (hit-aware `_resolve` cached per HitBox id; freed on break), `EnemyShield` "local module" mode (fixture-proven, no shipped consumer), `TurretMount` (host-agnostic aim-and-fire, writes only its own rotation). | Build **one** reusable `EnemyModule` composing these ideas (§2.1). `ArmorPlate` stays the Ram's breakable plate; `StationTurret` stays byte-identical (Ph11 reworks the station). |
| S2 | Ph4 recorded "Ph10 modular damage should extend or compose `ArmorPlate`". `ArmorPlate` damages itself in its own `area_entered`, so a shield can never cover it (Ph5 deviation 6), it is freed on break (no wreckage) and it only breaks on rockets / high impact. | **Changed, with reason:** `EnemyModule` takes the plate's *resolve-once* rule but damages from `received_damage` (so Ph5 "module shields must sit on a plain part's `HurtBox`" holds) and keeps its wreckage. Recorded in DECISIONS. |
| S3 | Player direct emitters (`beam_behavior.gd:72-98`, `plasma_nova_module.gd:34-41`) only look at nodes in groups `enemies` / `asteroids` and their child `HurtBox`; part hurtboxes (station turrets, plates) never take beam or nova damage. | Modules join `&"enemy_parts"` and both emitters add that group (§2.1). Station turrets and plates are not in it (unchanged). |
| S4 | `TurretMount` tracks without limit; a host cannot make "one side safe". | Append `traverse_deg` (default 360, bit-identical) and a slot override (§2.3). |
| S5 | `DefenseTurret._build_mounts()` holds the only mount-building code (pools as root children so their container is the enemy container). | Extract `TurretMountBuilder` (behaviour-identical, Ph8 rows guard it) and reuse it for modules (§2.3). `BulletPool` container injection stays unneeded and **deferred again** (pools are still root children). |
| S6 | `EnemyRounds.HEAVY_SHELL` (speed 160, 20 dmg, 12 s / 1800 px) has no consumer; Ph3/Ph4/Ph8 assigned it to the Heavy Gunship. | `HEAVY_CANNON` mount variant fires it (§2.3); the Carrier's bow cannon reuses it. |
| S7 | Gunship: `extends BaseEnemy`, enum `ENTER/HOLD/RETREAT`, own `_physics_process`, no brain / mover, 200 HP, contact 30, `heave_gunship.png` 92×84. Tests use it as the canonical legacy / config-isolation subject (`test_config_instance_isolation.gd`, `test_base_enemy.gd` legacy rows, `test_enemy_emp.gd`, `test_emp_blast_module.gd`, `test_support_ship.gd`, `test_explosion_effect_placement.gd`, `test_enemy_bullet_lifetime.gd` bullet speed 260). | t4 rewrites it in place (`git mv gunship/ heavy_gunship/`) and moves every legacy-subject row to the Bonus Drone or the station (§2.4.6). |
| S8 | Level 1 gunship rows: deep_space 3.5 s `b.gunship().at(0, -500)` (DURATION 30 s); cloud_descent (ENEMIES_CLEARED, timeout 10.0 s, last trigger 76.0 s) 50.0 s `.at(0, -400).move(b.straight(42))` and 62.0 s `.at(∓100, -400).move(b.straight(36))` (second `.delay(0.8)`). **The cloud_descent three never fire** (the rail disables `_physics_process`). No level-1 gate counts gunships. Level 2 (`level_2_waves.gd`) is unreferenced. | t11 replaces all four (owner choice 2) and adds a heavy count gate frozen at the legacy peaks (§2.12). Level 2 is left (Ph15). |
| S9 | Level-1 laser columns (`Level1Director.laser_column_schedule()`) emit `_KILL_DAMAGE` on every layer-512 hurtbox they touch, modules included; lit columns register `&"laser_wall"` hazards the mover avoids. deep_space columns 6.0 / 14.0 / 22.0 s; planet_approach 10 / 25 / 38 / 55 / 78 / 98 s; cloud_descent 8 / 18 / 34 s. | Heavies are placed and checked against the schedule (§2.12, §2.13). |
| S10 | Specialist gate: deep_space 12 of 12.5, planet_approach 7 of 7.5 (peaks 28.4–32.0 s and 98.0 s), cloud_descent 6 of 10. Fighter density gates count fighters + Gatlings spawned by waves only. | Heavies and the Carrier are **not** specialists; they get their own count rule. Carrier launches in Assault are swarm drones only (owner choice 6) and are counted in the drone gate (§2.13). |
| S11 | `LaserTender.launch_pair()` and `TurretGroup.spawn_members()` set the pattern for runtime children: siblings in the spawner's parent, `EventBus.enemy_spawned_orphan.emit(node)`, synchronous from the physics step (deferred from a physics callback). A freed-not-killed child with `counts_as_escape` true costs combo. | Hangars launch the same way and never dock (§2.10). |
| S12 | Ph9: a brain-driven enemy answers EMP automatically (`answers_emp()` = `is_ai_driven()`); the brain is not ticked for the window. | Both heavies get EMP for free (mounts and hangars are ticked by the brain, so they pause). "EMP on legacy enemies (gunship)" is closed by the rework. Ship-mounted EMP stays Ph18 (owner choice 5). |
| S13 | Ph1 roadmap: Ph18 moves the Carrier's hangar-tied launches and the Gunship's battery-loss phases onto Ph11's boss machinery; Ph19 owns LOS-blocking wreckage, capital wrecks and heavy hazard resistance. | Ph10 builds the consequences directly in the two brains behind `ModularHull` signals, so Ph18 can swap the driver without touching the parts. Destroyed modules here are **visual** wreckage only. |
| S14 | GUT ≈ 225 s at the Ph9 close (`verify.sh` 225.05 s), 240 s ceiling. | t1 gate room first (§2.15). |

### 1.2 Research findings (the research stage left no file; done in this stage)

| Finding | Tradeoff | Typical values / decision | Source |
|---|---|---|---|
| Fewer, clearer hitboxes make a multi-part boss better: X-Morph: Defense's KM-2 Redwing "severely reduced" its hitboxes and distractors after playtests; component damage changed the attack pattern (engine damage → more aggressive, wings → heavier barrages), and losing all weapons triggered a last stand. | Each extra part is a target the player must read; too many and the fight is noise. | Gunship 6 parts (4 weapons, 2 vents), Carrier 7. Every part loss changes one visible thing. | gamedeveloper.com, "11 Boss Battles of X-Morph: Defense part 5 – KM-2 Redwing" |
| Locked parts plus a backstop: Battle Garegga's propeller turrets stay invulnerable until the wing turrets on that wing die; DonPachi's core changes pattern when its four turrets die and fires a deadly pattern if the player stalls. | A locked part needs a visible tell, or the player wastes shots. | Carrier core plated (deflects with a ping) until 3 outer parts die; hangars hittable only with doors open. The Assault crossing is the stall backstop (it leaves). | shmups.wiki Battle Garegga / DonPachi pages |
| Separate "hard points", "weak points" (type-specific) and "critical points" (bonus damage) (Madhead, *The Alpha*); weak points placed where the boss attacks from push aggressive play (Bloodborne's Amygdala). | Bonus-damage spots must be readable at a glance, not a menu. | Gunship vents: hull damage ×2, open only while venting, orange glow. | madheadgames.com "The Alpha: an apex of aggression"; lizard-error.pages.dev on Amygdala |
| Subsystem damage that impairs the enemy physically (FTL engines → evasion, weapons → charge) gives the player a strategic reason to aim somewhere specific. | Impairment must stay readable and bounded. | Carrier engines → turn rate ×0.5 / ×0.15 and a list; a battery → one side safe. | ftl.fandom.com "Ship"; vigaroeentertainment.blogspot.com "FTL Analysis: Subsystems" |
| A carrier the player cannot finally damage is the classic complaint (an itch.io shmup thread); Raiden Fighters' carrier stage makes the hull an arena of many turrets while support craft keep coming. | The core must always become reachable. | Core exposure after any 3 of 6; launches are capped so the arena never floods. | itch.io post 6895475; breezewiki Raiden "Carrier Ship" |

`moddb.com/features/destroying-procedural-carriers` (403 to WebFetch, read through `scripts/fetch-page.sh`) only covered death explosions; not used. Every number in §2.14
not tied to a source above is **judgement**, labelled so.

### 1.3 Code facts every design section relies on

- `BaseEnemy` (`assault/scenes/enemies/base_enemy.gd`): root `$HurtBox` / `$Health` / optional `ContactHitBox`; `DefenseProfile` / `ContactProfile` resolved from children
  and applied to the **root** hurtbox only; `_physics_process` ticks `brain.tick` then `mover.step`; virtual `_on_received_damage(damage)` / `_on_health_changed(current)`;
  death = `was_killed`, `died`, explosion, `_maybe_leave_wreck()`, `queue_free()` in one call. `answers_emp()`, `apply_emp()`, `suspend_ai()`, `is_ai_driven()`,
  `accept_tow()`, `repair()`.
- `HurtBox._on_area_entered`: HitBox → `accepted_damage_types` filter → absorber (`absorbs_hit`, emits `hit_absorbed`) → else `received_damage.emit(hb.damage)`.
  `received_damage` carries no type. Player projectiles ask `ArmorQuery.deflects(area, hit_box)` (`deflects_hit` on the hurtbox's parent, else `is_armored()`) and pass
  through without `expired` on true.
- `TurretMount` (`setup(host, pools, owner_group)`, `tick(delta, target, can_fire)`, `scan(delta)`, `power_down()` (UNPOWERED for good, `UNPOWERED_TINT`), `pool_specs()`,
  `telegraph_gate`); variants `BurstCannonMount` (`round_scene`, `round_speed`, `burst_count`, `charge_seconds`), `RocketBatteryMount` (DUMB / PURSUIT rockets; asks the
  host `launch_velocity()` / `rocket_clear_radius()`), `PulseRingMount`, beams. `TurretMountScenes.scene_for/export_of/reach_of`.
- `EnergyRing` (`assault/scenes/projectiles/enemy_beams/energy_ring.gd`): `setup(host, owner_group)`, `start(gap_start_deg)`, `tick(delta)`, `cancel()`; exports
  `telegraph_seconds` 0.8, `ring_speed` 360, `max_radius` 280, `band` 24, `gap_count` 2, `gap_deg` 45, `gap_spin_deg` 30, `damage` 12; owner set exempt.
- `EnemyShield` (`global/components/enemy_shield.gd`): `attach(hurt_box)` takes the hurtbox's absorber slot; host = `hurt_box.get_parent()`; never absorbs while the host
  answers `is_armored() == true`.
- Hub (`open_space/scenes/levels/sector_hub.gd`): 18 seeded draws appended in order; the 2600 ring's free bearings are 22.5°, 157.5°, −67.5°, −112.5°;
  `test_sector_hub_patrol.gd::_patrol_groups()` entries are `label: [anchor, idle_radius, perceive_radius]` and every sweep covers them; `_expected_seeds()` lists every draw.

## 2. Design

### 2.1 `EnemyModule`: a destructible part (R10.1–R10.6; t2)

`global/components/enemy_module.gd`, `class_name EnemyModule extends Node2D`, joins group `&"enemy_parts"` in `_ready()`. One file, used by both heavies and by the Ph11 /
Ph12 bosses. It never reads its host's type.

**Scene shape** (authored in the host scene under a `Modules` `Node2D`, never a direct child of the enemy root):
```
Modules/<Name> (EnemyModule)
  Sprite (Sprite2D)            intact_texture; wreck_texture after destruction
  HurtBox (HurtBox, layer 512)  one CollisionShape2D (circle or rectangle) covering the part's sprite
  Health
  DefenseProfile (optional)    mask and accepted_damage_types; default mask = PLAYER_HITBOX | PLAYER_ROCKETS | HAZARD_CONTACT
  MountSlots (optional)        TurretMountSlot children; mounts are built by ModularHull
  Light (optional)             the part's state light (§2.11)
```

**Exports:** `module_id: StringName` (unique within the host, e.g. `&"battery_port"`), `role: Role` (`enum Role { WEAPON, ENGINE, HANGAR, CORE, WEAK_POINT }`, append-only),
`max_health: int` (written into `Health` in `_ready()`; **0 = indestructible**, damage is still counted and forwarded), `starts_vulnerable: bool = true`,
`hull_share: float = 0.0`, `intact_texture: Texture2D`, `wreck_texture: Texture2D` (null → the intact texture tinted `WRECK_TINT` `Color(0.35, 0.35, 0.4)`),
`damaged_ratio: float = 0.5` (VisualState DAMAGED at or below this health fraction).

**Hit rule (the one decision point):**
- `deflects_hit(hit_box) -> bool` = `_resolve(hit_box)`, cached per HitBox instance id and erased on the hurtbox's `area_exited` (the `ArmorPlate` shape), computed as:
  **deflect** when the module is a wreck from an earlier physics frame (`_destroyed_frame < Engine.get_physics_frames()`), or not vulnerable, or the hit's type is not
  in the profile's `accepted_damage_types` (empty = all); **consume** otherwise. A module destroyed this physics frame still answers consume, so the killing shot is
  consumed whatever order Godot calls the bullet's and the hurtbox's `area_entered` in.
- **Damage comes only through `HurtBox.received_damage(damage)`**, i.e. after the hurtbox's own type filter and absorber slot. So an `EnemyShield` attached to a module's
  `HurtBox` absorbs first (Ph5's local-module shield, now shipped on the Gunship's cannon, §2.5), and a direct emitter (player beam, nova, dash, an enemy beam, a level
  laser column) reaches the module the same way. The handler: destroyed → ignore; not vulnerable → `deflected.emit(self)` and a white ping (no damage); else
  `Health.decrease(damage)` (skipped when `max_health == 0`), `damaged.emit(self, damage)`, `HitEffect.burst()`.
- A module is never armour for its host: the host's root hurtbox and the module's hurtbox are separate areas, and each answers its own `deflects_hit`.

**Destruction (`Health` reaches 0, or `destroy()`):** once only. `_destroyed_frame = Engine.get_physics_frames()`; `remove_from_group(&"enemy_parts")`; the hurtbox's
`monitoring` / `monitorable` and shape go off **deferred**; every attached mount `power_down()` (droops, dark, never fires again); the sprite swaps to `wreck_texture`
(VisualState WRECK) and the light goes OFF; an `ExplosionEffect` bursts into the host's parent (the `StationTurret` re-homing, so it neither rotates with the hull nor dies
with it); `destroyed.emit(self)`. **The node stays in the tree** for the host's whole life and is freed with it: that is the wreckage (IDEAS §23 "destroyed modules visibly
remain"). It is not a `Wreck` body and blocks nothing (Ph19).

**Vulnerability:** `set_vulnerable(on)` (no-op on a wreck), emits `vulnerability_changed(self, on)` on a change. A host changes it from its brain or deferred
(`call_deferred`) when the change is caused inside a physics callback (the Ram `_expose` rule).

**Visual state:** `visual_state()` → `INTACT`, `DAMAGED` (health ≤ `damaged_ratio` · max; a code-drawn spark flicker on the sprite, IDEAS §23 "damaged weapon banks spark"),
`WRECK`. No recolouring of the hull; the part's own sprite and light carry it.

**Player direct emitters:** `beam_behavior.gd` appends `get_nodes_in_group("enemy_parts")` to its target list and `plasma_nova_module.gd` does the same; both already find the
`HurtBox` child by name and damage it with a direct `received_damage.emit`. The host root answers `is_laser_blocking() == false`, so the beam passes over the hull and burns
the parts on its line (12 px perpendicular test against the part's centre, as for enemies).

**Test rows** (`tests/integration/test_enemy_module.gd`, a fixture host `tests/helpers/fixture_modular_host.tscn` — a `BaseEnemy` with a `ModularHull` and three modules, its root hull armoured (`deflects_hit` true, damage refused) unless a row says otherwise — in
both harnesses where movement matters, real physics at 8× for projectile rows):
- a player bullet into a vulnerable module: consumed, module health −damage, host hull health unchanged when `hull_share` 0 and the bullet does not touch the root hurtbox;
- into a non-vulnerable module: passes through (not consumed, no `expired`), module health unchanged, `deflected` once; after `set_vulnerable(true)` the next bullet is consumed;
- a type not in `accepted_damage_types` (a rocket against a LASER-only part): deflected, no damage;
- **the killing shot is consumed** with both callback orders (the row forces each order by calling `deflects_hit` before / after `received_damage`);
- **wreckage stays:** after destruction the node is still a child of `Modules` 2 s later, `visual_state() == WRECK`, its sprite texture is `wreck_texture`, it is out of
  `enemy_parts`, its hurtbox no longer monitors, a later bullet passes through it, `destroyed` fired exactly once, and the host is still alive;
- `max_health` 0: never destroyed, damage still emitted and forwarded;
- `hull_share` 1.0: the host's `Health` drops by the same amount (forwarded by `ModularHull`);
- a local `EnemyShield` attached to the module's hurtbox absorbs a frontal bullet (consumed, module health unchanged) and not a rear one;
- the player's beam (`BeamBehavior` on a real Assault player) burns a module on its line and the armoured fixture root takes nothing; the nova damages every module in range;
- an enemy `EnemyBeam` and a level `LaserRay` kill a module through `received_damage` (the column-kill fact §2.12 relies on);
- mounts attached to a module are UNPOWERED after it is destroyed and never fire again (60 s hand-ticked with the player in range).

### 2.2 `ModularHull`: the host's coordinator (R10.1, R10.7; t2)

`global/components/modular_hull.gd`, `class_name ModularHull extends Node`, a child of the host root named `ModularHull`. In `_ready()` (after the host's other children) it
collects every `EnemyModule` under the sibling `Modules` node, in tree order, and connects their signals. It is the seam Ph18 replaces the consequence driver behind; it
holds no gameplay rules of either heavy.

- `signal module_destroyed(module: EnemyModule)`, `signal module_damaged(module: EnemyModule, amount: int)`.
- `build_mounts(host: Node2D, rng: RandomNumberGenerator, owner_group: StringName, telegraph_gate := Callable())`: for every module, every `TurretMountSlot` under its
  `MountSlots`, `TurretMountBuilder.build(host, slot, index, rng, owner_group, telegraph_gate)` with one running `index` across the host (unique pool names), then
  `module.attach_mount(mount)`. The host calls it from its own `_ready()`; pools are **host root children**, so their container is the host's parent.
- Forwarding: on `damaged(module, amount)`, if `module.hull_share > 0` and the host has a `Health`, `host.health.decrease(roundi(amount * module.hull_share))`.
- Queries: `modules()`, `module(id) -> EnemyModule` (null if none), `live(role) -> Array[EnemyModule]`, `destroyed_count(roles: Array) -> int`, `mounts_of(id) -> Array[TurretMount]`.
- Tests in `test_enemy_module.gd`: collection order, unique pool names over 3 modules × 2 slots, forwarding, `destroyed_count` over role sets, `module_destroyed` re-emitted once.

### 2.3 Ship-mounted turrets: traverse limits, the builder and the heavy cannon (R10.8, S4–S6; t3)

**`TurretMountBuilder`** (`assault/scenes/enemies/defense_turret/mounts/turret_mount_builder.gd`, static, `RefCounted`):
`build(host: Node2D, slot: TurretMountSlot, index: int, rng: RandomNumberGenerator, owner_group: StringName, telegraph_gate := Callable(), variant_override := -1,
bearing_override := NAN) -> TurretMount` — exactly today's `DefenseTurret._build_mounts()` loop body (variant, `rest_bearing_deg`, `turn_rate_override`, the new
`traverse_deg_override`, rng, gate, `slot.add_child(mount)`, one `BulletPool` per `pool_specs()` entry added to `host` named `"%s_%d" % [spec.name, index]`, `setup()`).
`DefenseTurret._build_mounts()` calls it; every Ph8 turret, heavy emplacement and turret-group row must stay green unchanged.

**Traverse:** `TurretMount` export `traverse_deg: float = 360.0`; `TurretMountSlot` export `traverse_deg_override: float = -1.0` (≥ 0 replaces it). With `traverse_deg < 360`
the mount's aim bearing (in its parent's frame) is clamped into `rest_bearing_deg ± traverse_deg / 2` before the turn step, the scan arc is clamped into the same range,
and TRACK → TELEGRAPH and every `_fire_tick` additionally require the target's bearing to lie inside the arc (outside it the mount behaves as if `can_fire` were false).
At 360 every code path is skipped, so all Ph8 rows are bit-identical (a row asserts a recorded 10 s mount trace is unchanged with `traverse_deg` 360).

**HEAVY_CANNON:** append `Variant.HEAVY_CANNON` to `TurretMount.Variant` and `TurretMountScenes` (`heavy_cannon_mount.tscn`, script `BurstCannonMount`, `round_scene =
EnemyRounds.HEAVY_SHELL`, `burst_count` 2, `burst_gap` 0.35 s, `charge_seconds` 0.7 s (yellow), `round_speed` 220 px/s, `cooldown_seconds` 3.2 s, `fire_range` 900 px,
`turn_rate` 0.9 rad/s, `fire_cone_deg` 6, `traverse_deg` 70). Starting values. The round lifetime sweep (`test_enemy_bullet_lifetime.gd`) adds the mount's `round_speed`
as a Heavy Shell speed source: 1800 / 220 = 8.2 s ≤ 12 s.

**A mount on a moving, rotating host** already compensates its parent's `global_rotation` (`turret_mount.gd` `_parent_rotation()`); rocket mounts ask the host's
`launch_velocity()` (the heavies answer their `velocity`) and `rocket_clear_radius()` (the hull's half-diagonal + 4 px, so a rocket never arms inside its own hull).

**Rows** (`tests/integration/test_turret_mount_traverse.gd`, hand-ticked): a 120° mount never rotates outside its arc while the target circles it (sampled 600 ticks), never
fires a round with the target outside the arc, fires normally with the target inside; a 360° mount's 10 s trace equals the recorded pre-change trace; the builder gives a
`DefenseTurret` the same pool names, sizes and mount exports as before (heavy emplacement too); a `HEAVY_CANNON` mount fires two Heavy Shells at 220 px/s after a 0.7 s
charge; `TurretMountScenes.scene_for(HEAVY_CANNON)` is not null and every variant sweep includes it.

### 2.4 Heavy Gunship: shell, movement and Assault life (R10.9–R10.12, R10.17; t4)

#### 2.4.1 Files and scene
`git mv assault/scenes/enemies/gunship assault/scenes/enemies/heavy_gunship`; rename to `heavy_gunship.tscn` / `.gd`, `heavy_gunship_brain.gd`, `heavy_gunship_config.gd` /
`.tres`, `ENEMY.md` rewritten. `class_name HeavyGunship extends BaseEnemy`; `HeavyGunshipBrain extends EnemyBrain`; `HeavyGunshipConfig extends ShipConfig` (flat,
`@export_group` Movement / Attack / Phases / Defense / Tactics / Scoring; the old fields `entry_speed`, `hold_y_offset`, `track_speed`, `track_player`, `retreat_hp_ratio`,
`burst_interval`, `burst_gap`, `bullet_damage`, `bullet_speed` are deleted). `WaveBuilder.heavy_gunship()` replaces `gunship()`; the `GUNSHIP` const becomes `HEAVY_GUNSHIP`.
The old textures `heave_gunship.png` / `heavy_gunship_non_shielded.png` (and the `.pdn`) are deleted once t9's art lands (t4 may keep them as placeholders).

```
HeavyGunship (HeavyGunship, CharacterBody2D)    body: one CapsuleShape2D ≈ 112 × 144 px, layer ENEMY_HITBOX, mask ENVIRONMENT
  Sprite2D (hull)        CollisionShape2D      HurtBox (root, covers the body)      Health (hull, max = config.max_health)
  HitFlashAnimationPlayer  ContactHitBox (same shape id and scale as the body)  ContactProfile (COLLISION)
  Brain (HeavyGunshipBrain)   Mover (EnemyMover)   ModularHull   StateLight
  Modules (Node2D)
    BatteryPort   (EnemyModule, WEAPON, 160 HP)  MountSlots/Slot0 BURST_CANNON, rest bearing = port side, traverse 160°
    BatteryStarboard (EnemyModule, WEAPON, 160 HP)  MountSlots/Slot0 BURST_CANNON, starboard, traverse 160°
    Cannon        (EnemyModule, WEAPON, 200 HP)  MountSlots/Slot0 HEAVY_CANNON, forward (the nose), traverse 70°; a local EnemyShield (§2.5)
    Missiles      (EnemyModule, WEAPON, 140 HP)  MountSlots/Slot0 ROCKET_BATTERY, rear, traverse 360°
    VentPort / VentStarboard (EnemyModule, WEAK_POINT, max_health 0, starts_vulnerable false, hull_share 1.0)
```
Contact: `ContactProfile` COLLISION, `collision_damage` 30 (kept, so `test_gunship_rams_for_its_configured_collision_damage` survives renamed). `counts_as_escape` true.
`is_laser_blocking()` false. `accepts_tow()` false in every phase (a heavy is not towed); `can_be_repaired()` true.

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
tracking, no fly-off-the-top retreat. `EngagementBudget` `engage_seconds` 14.0 s (starting value; the cloud_descent deadline needs ≤ 14, §2.12) → DISENGAGE: the
Missile Corvette's exit (curve to the nearest corridor edge at `exit_speed` 260, release the constraint, freed outside the projectile rect). Attack gate: a battery /
cannon telegraph starts only with `budget.remaining() ≥ attack_window() + 0.05`; a started burst finishes (deferral ≤ `attack_window()`).
The Assault corridor exit is measured once per GUT run through `tests/helpers/ph10_exit_keys.gd::heavy_gunship_exit()` (the `SpecialistExitProbe` memo, both start sets).

#### 2.4.4 Weapons in t4
All four mounts are built by `ModularHull.build_mounts()`. The brain ticks them every tick with `TargetInfo.player(tree)` and `can_fire = can_see_player() or
mount.fires_past_cover()`, and passes `can_fire` false to the missiles mount outside EMERGENCY (t5 opens it). Battery rounds are Pulse rounds (the mount default).

#### 2.4.5 Rows (t4; `tests/integration/test_heavy_gunship.gd`, both harnesses)
- spawn: 6 modules, 4 mounts with the authored variants and traverses, hull `Health` = config, contact damage 30, `is_ai_driven()` true, `answers_emp()` true;
- holds `preferred_range` ± (`range_drift` + `range_tolerance`) over 20 s against a still player and against a 200 px/s circling player;
- **broadside:** with both batteries alive, the angle between the hull heading and the bearing to the player stays within 90° ± 20° for ≥ 80% of 20 s of BROADSIDE;
- **module death changes movement:** destroy `BatteryPort` while the port side faces the player → within 5 s the starboard side faces the player and stays (the swap);
  both batteries destroyed → the nose faces the player (± 20°);
- BREAK_AWAY: a 300 px/s rusher inside `min_range` triggers one boost away; the rearm holds a second one;
- **Assault:** never parks — over 14 s its y spread is ≥ 120 px and it never holds a y within 8 px for more than 2 s while the player moves; never leaves the corridor's
  outer band before DISENGAGE; frees after DISENGAGE within the measured exit; a 1 s budget boundary row ends in DISENGAGE;
- hub idle: orbits its anchor, notices at `perceive_radius`, returns after `lose_radius`.

#### 2.4.6 Gates and legacy rows moved
Roster entries renamed in `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd` (the old 1 px gap goes away with the new
shape), `test_base_enemy.gd` (roster; tow table: refuses in every phase), `test_enemy_dual_mode.gd` (one spawn row), `test_explosion_effect_placement.gd` (scene path).
**Legacy-subject rows move off the gunship:** `test_base_enemy.gd::test_legacy_enemies_are_not_ai_driven` keeps the Bonus Drone only; `test_enemy_emp.gd`'s legacy rows
and `test_emp_blast_module.gd`'s legacy process-disable row use the Bonus Drone (both are legacy, non-brain enemies; the row asserts the same thing); `test_config_instance_isolation.gd`
keeps the gunship as its canonical subject under the new path (any flat config works); `test_enemy_bullet_lifetime.gd` drops `gunship_cfg.bullet_speed` (no enemy fires
plain bullets at 260 any more; the derived defaults do not change because 150 stays the minimum). **`test_support_ship.gd`'s gunship row flips (owner choice 7):** the
Heavy Gunship is AI-driven and outscores a fighter, so it is now a legal ward (the support shields its hull and interposes; the tow is refused by the brain). `docs/enemy-roster.md`
loses every "never `.move()` the gunship" line in t13.

### 2.5 Heavy Gunship: phases, overheat-and-vent, weak points, emergency and rear missiles (R10.10–R10.13; t5)

**Hull phases** read the root `Health` fraction (owner choice 3: every hit on a part also hits the hull, because the part sits on the hull's hurtbox):
`CONTROLLED` ≥ `overheat_ratio` 0.6 > `OVERHEAT` ≥ `emergency_ratio` 0.3 > `EMERGENCY`. Entering a band is one-way (a `repair()` from a Support Ship never steps back).
`signal hull_phase_changed(hull_phase: int)` on the brain.

- **CONTROLLED** (defensive): BROADSIDE / BREAK_AWAY as in §2.4; battery cooldown `battery_cooldown` 2.2 s (the mount's).
- **OVERHEAT:** each battery or cannon burst adds 1 heat; at `heat_limit` 4 the brain enters **VENT** for `vent_seconds` 2.2 s: every mount gets `can_fire` false (a started
  burst finishes first), `max_speed` × 0.6, the vents' lights glow orange and `VentPort` / `VentStarboard` become vulnerable (`set_vulnerable(true)`), heat resets; at the end
  the vents close (`set_vulnerable(false)`). So attack windows become shorter (four bursts, then a vent) and the player gets a timed weak-point window. A vent hit deals its
  damage to the vent (indestructible) and `hull_share` 1.0 forwards it to the hull, on top of the hull's own hit: double damage.
- **EMERGENCY:** "emergency boost pattern, aggressive retreat, rear missile launches". Every `emergency_period` 5.0 s: one `mover.boost` away from the player
  (`emergency_boost_speed` 420 px/s, 0.9 s, along `break_contact`), then the `Missiles` mount is allowed to fire (`can_fire` true) for `missile_window` 2.0 s at a player who
  is behind the gunship (inside the rear 200° — the pursuer); the batteries keep firing. Between boosts it holds BROADSIDE at `emergency_range` 800 px (Open Space) /
  `assault_preferred_range` + 120 (Assault). **It never despawns because of health**: in Open Space it stays in the encounter until killed (Ph13 owns leash / cleanup).
  Venting stops in EMERGENCY (the vents stay closed).
- **Cannon shield (the shipped local-module shield, Ph5's open item):** an `EnemyShield` child of `Modules/Cannon`, attached to the Cannon's `HurtBox`: `arc_deg` 120 facing
  the hull's nose (the brain calls `face()` / `set_threat_point()` every tick so it tracks the nose), `capacity` 60, `regen_delay` 2.0, `regen_seconds` 4.0, `reboot_seconds`
  5.0. Head-on fire is absorbed (bullets consumed); from the flank the cannon takes damage. The shield does not cover the hull or the batteries.
- **Battery loss removes the attack for good:** the module's mount is UNPOWERED from the destroy call on; the brain picks the other side (§2.4.2). Cannon lost → the nose
  no longer fires; Missiles lost → EMERGENCY boosts without missiles.

Rows (`test_heavy_gunship.gd` §phases, both harnesses):
- hull 61% → CONTROLLED, 59% → OVERHEAT, 29% → EMERGENCY; a `repair()` back to 70% stays in EMERGENCY;
- OVERHEAT: after the 4th burst the next 2.2 s fire no round from any mount; the vents are vulnerable only inside that window (**weak point vulnerable only when intended**);
  a bullet into a closed vent is consumed by the hull (1× hull damage) and deals no vent damage; into an open vent it deals 2× to the hull (the hull hit + the vent forward);
- EMERGENCY: boosts away every 5 s; the Missiles mount fires only in its window and only at a player behind it; Open Space: still alive and in the encounter 60 s after
  entering EMERGENCY with the player chasing at 300 px/s (never freed, never flagged an escape); Assault: still freed only by DISENGAGE;
- **module death disables an attack:** destroy `BatteryStarboard` → over the next 30 s (player kept on the starboard side by a stub), no round leaves that mount and the
  mount is UNPOWERED; destroy `Missiles` in EMERGENCY → no rocket ever leaves;
- cannon shield: a frontal real-physics bullet is consumed and the Cannon's health is unchanged; a flank bullet damages it; the shield's arc follows the nose;
- the cannon fires Heavy Shells (`EnemyRounds.HEAVY_SHELL`) at 220 px/s.

### 2.6 Carrier: shell, modules, core exposure, movement in both modes (R10.14–R10.16, R10.18; t6)

#### 2.6.1 Files and scene
`assault/scenes/enemies/carrier/`: `carrier.tscn`, `carrier.gd` (`class_name Carrier extends BaseEnemy`), `carrier_brain.gd` (`CarrierBrain extends EnemyBrain`),
`carrier_config.gd` / `.tres` (`CarrierConfig extends ShipConfig`, flat), `ENEMY.md`. `WaveBuilder.carrier()`.

```
Carrier (Carrier, CharacterBody2D)   body: RectangleShape2D ≈ 176 × 280 px (hull 192 × 288 art, nose-down), layer ENEMY_HITBOX, mask 0 (ploughs through, the station's rule)
  Sprite2D (hull)   CollisionShape2D   HurtBox (root, covers the body)   Health (hull; refuses damage, see below)
  HitFlashAnimationPlayer   ContactHitBox (same shape)   ContactProfile (ARMOR, shove_speed 220)
  Brain (CarrierBrain)   Mover (EnemyMover)   ModularHull   StateLight   HullMounts (MountSlots for hull systems, §2.7)
  Modules (Node2D)
    EnginePort / EngineStarboard   (ENGINE, 180 HP, aft)
    GunPort / GunStarboard          (WEAPON, 160 HP, amidships, one BURST_CANNON slot each, traverse 150° to its own side)
    HangarPort / HangarStarboard    (HANGAR, 220 HP, starts_vulnerable false — vulnerable only while its doors are open, §2.8)
    Core                            (CORE, 600 HP, starts_vulnerable false, centre)
```
`collision_damage` 15 (the ARMOR shove's touch damage). `score_value` 600, `counts_as_escape` true, `wreck_chance` 0 (Ph19). `is_laser_blocking()` false.
`accepts_tow()` false. `can_be_repaired()` false. Duck-typed `accepts_ward() -> false` (owner choice 7): `SupportShipBrain`'s ward filter adds "skip a candidate that
answers `accepts_ward() == false`" (a shield on an `is_armored()` hull would never absorb).

#### 2.6.2 The armoured hull and the core
- `homing_point(from)`: the live vulnerable module nearest `from`, else the hull centre (player homing rockets otherwise park on the armoured hull; the Ph4 rule). The
  Heavy Gunship answers the same.
- The hull is armour: `Carrier.deflects_hit(_hb)` → true and `is_armored()` → true always, so every player projectile crossing the hull overlaps it without being consumed
  and reaches the parts; `_on_received_damage` is overridden to refuse (white flash, `armor_deflected(damage)` signal), so neither bullets nor the beam nor the nova ever lower
  the hull `Health`.
- **Core exposure (owner choice 1):** when `ModularHull.destroyed_count([ENGINE, WEAPON, HANGAR]) ≥ config.core_exposure_count` (3), `Core.set_vulnerable(true)`
  deferred, the core's plating art opens (VisualState change on the core sprite) and the brain enters **PANIC** (§2.7). Before that a hit on the core pings (`deflected`)
  and does nothing — the core is vulnerable **only when intended**.
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
- **Assault CROSS** (IDEAS §6.11 "moves vertically through the corridor at a controlled speed; its body becomes a moving arena"): `constraint_mode` NONE (it enters from
  above and leaves below; the corridor would force it back), nose-down and never rotated (`face_toward` straight down every tick). Vertical speed is constant,
  `assault_cross_speed` 70 px/s (starting value), **independent of engines and panic** (only an EMP window halts it, ≤ 5 s, the Ph9 rule), so its Assault life is fixed: it frees itself once its top edge is below the
  projectile world rect (`EnemyWorld.projectile_world_rect(tree).end.y + hull half-height`). Lateral sway: `request_velocity` x toward keeping the player inside a live
  battery's arc, capped at `assault_sway_speed` 40 px/s × the engine factor (1 / 0.5 / 0.1), clamped to keep the hull inside `EnemyWorld.view_rect()`'s x span. A wave spawn
  sets `world_anchored_x` true (the Ph8 rule, `EnemyWorld.view_rect()` / `projectile_world_rect()` centres, once in `_ready()`), so its world x is `640 + 2 · design_x`.
- **No budget, no DISENGAGE** in Assault: the crossing is its life (≈ (1608 + 288) / 70 ≈ 27 s from a spawn at the rect's top edge; the placement task measures the real
  figure from its spawn y).

#### 2.6.4 Rows (t6; `tests/integration/test_carrier.gd`, both harnesses)
- spawn: 7 modules with roles, HP and vulnerability as authored; hull refuses a bullet (not consumed, `armor_deflected`), the beam and the nova (hull `Health` unchanged);
- **core vulnerable only when intended:** with 0, 1 and 2 outer modules destroyed (each of three combinations: two engines, a gun and a hangar, an engine and a gun) a
  real-physics bullet on the core passes and the core's health is unchanged; after the 3rd, from the next physics frame, the core takes damage; destroying the core kills
  the carrier (`died`, `was_killed`); boundary: `core_exposure_count` 3 read from the `.tres`, never typed;
- **module death changes movement:** with both engines alive the hull turns 90° in t; with one engine dead it takes ≥ 1.8 t and lists toward the dead side (a still player:
  the heading drifts by ≥ 0.05 rad/s with no turn request); both dead: ≥ 5 t. Assault: the lateral sway speed caps at 40 / 20 / 4 px/s;
- Open Space SCREEN: never closes inside 600 px of a still player; never leaves `leash_radius` + 50 px of its anchor while chasing a fleeing player for 30 s;
- **wreckage stays:** destroy four modules over 10 s; each stays in the tree with its wreck texture until the carrier dies, and the carrier's silhouette (the set of
  visible module sprites with intact textures) changes with each loss;
- Assault CROSS: y advances at 70 px/s ± 1 with any combination of engines alive and in PANIC; x stays inside the view; freed below the projectile rect; never rotates;
- contact: touching the hull shoves the real player (ARMOR) and deals 15.

### 2.7 Carrier weapons: side batteries, bow cannon, missile bank, anti-approach pulse, panic (R10.15, R10.16; t7)

- **Side batteries** (`GunPort` / `GunStarboard`, BURST_CANNON, traverse 150° centred on their own side): "a gun destroyed → one side becomes safe". With the port battery
  dead, no battery round ever leaves toward the port half-plane (the traverse keeps the starboard battery on its side).
- **Bow heavy cannon** (hull-mounted, `HullMounts/Bow`, HEAVY_CANNON, traverse 70°, forward): a hull system, not a module (it falls silent only when the carrier dies;
  Ph18 may tie it to a module). Heavy Shells.
- **Missile bank** (hull-mounted, `HullMounts/Dorsal`, ROCKET_BATTERY, traverse 360°, PURSUIT rockets, `cooldown_seconds` 7.0): fires at a player beyond
  `missile_min_range` 450 px (rockets punish standing off, the pulse punishes hugging).
- **Anti-approach pulse:** `carrier_pulse_ring.tscn` (an inherited `energy_ring.tscn`: `max_radius` 420, `telegraph_seconds` 1.0, `ring_speed` 360, `band` 24, `gap_count` 2,
  `gap_deg` 50, `damage` 14) owned and ticked by `CarrierBrain` (`setup(carrier, owner_group)`; `start()` when the player's distance to the hull centre < `pulse_trigger_range`
  340 px and `pulse_cooldown` 5.0 s has run out). The ring's fairness rule (Ph8: gap arc at `max_radius / 2` ≥ 3 · r_player) is asserted for this scene too. The ring
  exempts the carrier's owner group (its launched children are in it, §2.8). Damaging only (owner choice 5; an EMP variant is Ph18).
- **Hull mounts** are built from `HullMounts/*` slots by the same `TurretMountBuilder` (the carrier calls it for the hull slots, `ModularHull.build_mounts()` for the
  module slots; one running pool index).
- **PANIC** (core exposed): emergency deployment (every live hangar launches its full payload at once, §2.8), `pulse_cooldown` × 0.5, battery `cooldown` × 0.7 (set on the
  mounts), Open Space: `retreat_from` the player at full (engine-limited) speed while still facing a live battery to it (it tries to escape the fight it is losing); Assault:
  unchanged crossing speed (§2.6.3). Core light flashes red; hull running lights strobe.
- The brain ticks every mount with `can_fire = can_see_player() or fires_past_cover()`; the Assault attack gate is the crossing itself (mounts fire only inside
  `EnemyWorld.view_rect()`, the Ph8 turret rule).

Rows (`tests/integration/test_carrier.gd` §weapons, both harnesses):
- **module death disables an attack / one side safe:** destroy `GunPort`; with the player stub on the port side for 20 s no battery round is fired and none lands in the port
  half-plane; a control with both guns alive is hit;
- the bow cannon fires Heavy Shells only inside its 70° arc; the missile bank fires only beyond 450 px;
- the pulse starts within one tick of the player entering 340 px after the cooldown, never before the cooldown, and the ring's gap rule holds for `carrier_pulse_ring.tscn`;
- PANIC: entered on the tick after exposure; pulse cooldown halves; Open Space: distance to the player grows while it lasts.

### 2.8 Carrier hangars: doors, launches, caps, emergency deployment (R10.16, R10.19; t8)

`assault/scenes/enemies/carrier/carrier_hangars.gd` (`class_name CarrierHangars extends RefCounted`, held by `CarrierBrain`; one per carrier), driving the two HANGAR modules.
- **Payload** per hangar, read from the config: `hangar_port_scene` / `hangar_starboard_scene` (string paths in the flat config: Open Space swarm drones port, fighters
  starboard; `assault_hangar_scene` swarm drone for both, owner choice 6), `launch_count` 2 per launch.
- **Cycle:** `CLOSED` → `OPENING` (`door_open_seconds` 0.8 s: doors animate open, the hangar's light yellow, **the HANGAR module becomes vulnerable** — owner choice 4) →
  `LAUNCH` (children spawned) → `OPEN` (`door_hold_seconds` 2.0 s, still vulnerable) → `CLOSED` (invulnerable again). Open Space: a launch every `launch_period` 9.0 s while
  engaged, only while that hangar's live children < `hangar_live_cap` 3 and the carrier's total < `carrier_live_cap` 6. Assault: **one launch per hangar per life**, the
  first `assault_first_launch` 3.0 s after entering the view, the second 4.0 s later.
- **Spawning** (the `LaserTender.launch_pair()` rule): synchronous from the brain's physics tick; each child is instantiated at the hangar's mouth marker, given
  `start_engaged = true` where its brain has it, a seeded `rng_seed` from `brain.rng`, a squad (`SquadController`, one per carrier per payload kind, held by
  `CarrierHangars`), added to the group `owner_group` of the carrier (ring exemption), added as a **sibling** in the carrier's parent, a collision exception with the
  carrier, given an outward `mover.boost` (300 px/s, 0.4 s) on its first tick, and announced with `EventBus.enemy_spawned_orphan.emit(child)`. Children keep their own
  config (score, escape flag, Assault budget from spawn). They never dock, so a launch never costs combo by itself.
- **A destroyed hangar never launches again** (its cycle stops in whatever state, its wreck doors hang open). If it dies mid-OPENING, nothing launches.
- **Emergency deployment** (PANIC entry): every live hangar that may still launch (Open Space: under its caps; Assault: not launched yet) goes straight to LAUNCH without the
  door telegraph, once.
- Rows (`tests/integration/test_carrier_hangars.gd`, both harnesses): doors open 0.8 s before children appear; the hangar is hittable only from OPENING to the end of OPEN;
  launch period and caps (Open Space, 60 s with the player still: never more than 3 live per hangar or 6 total); **a destroyed hangar stops launching** (destroy `HangarPort`
  mid-CLOSED: over the next 40 s every new child came out of `HangarStarboard`; destroy both: no new child ever, the carrier keeps fighting); destroyed mid-OPENING → no
  launch; Assault: exactly one launch per hangar, ≤ 4 children per life; emergency deployment on PANIC; children are siblings, announced once through
  `enemy_spawned_orphan` (a spy on the EventBus), in the carrier's owner group (the carrier's ring passes through them), and outlive the carrier.

### 2.9 Visual states and light vocabulary (R10.20, R10.21; t5, t6, t7, t8, t9)

Every state is a light or a part, never a hull recolour (IDEAS §21): `StateLight` on each hull (the Ph5 component: OFF / CHARGING yellow / ARMED red / LOCKED white); module
lights: vents **orange** while venting, battery / cannon yellow while charging, hangar yellow while the doors open, core **red flashing** in PANIC, everything **dark** on a
wreck; the cannon's shield is cyan (the `EnemyShield` drawing). Damage: DAMAGED parts spark (code-drawn); wrecks swap to their wreck texture and keep their place; the
Carrier's silhouette changes as parts break (wreck sprites are visibly smaller / torn), its hangar doors read closed / open / broken, its core plating closed / open.
Engine plumes are code-drawn and go out with the engine.

### 2.10 Art (R10.21; IDEAS §21–23; t9)

Every sprite through the `pixel-art-generation` skill (strict top-down, `view: "high top-down"`, `isometric: false`), saved with `./scripts/pixellab.sh`, opened and checked,
and passing `test_entity_sprite_transparency.gd` (fix a background with `./scripts/strip-sprite-bg.sh`). Faction palette: dark navy hull, red / maroon accents, a cool blue edge
light. Hulls are drawn with **empty sockets** where the parts sit, so a wreck reads as damage to a part, not a hole in the art. If the generator caps the canvas below a hull's
size, generate at the largest supported size and scale by an integer factor only.

| Asset | Size | Notes |
|---|---|---|
| Heavy Gunship hull | 112 × 144 | wide, slab-sided, nose-down; sockets for 2 side batteries, a nose cannon, a rear missile pod, 2 flank vents |
| Gunship battery (intact / wreck) | 32 × 32 each | one sprite, mirrored for the other side; the mount head stays code-drawn |
| Gunship nose cannon (intact / wreck) | 32 × 40 each | long barrel housing |
| Gunship missile pod (intact / wreck) | 32 × 32 each | 4 tube mouths |
| Gunship vent | 16 × 16 | grille; the orange glow is code-drawn |
| Carrier hull | 192 × 288 | long flight-deck carrier, nose-down, sockets for every part, hangar bays port / starboard, bow cannon housing |
| Carrier engine (intact / wreck) | 48 × 48 each | |
| Carrier gun battery (intact / wreck) | 48 × 48 each | |
| Carrier hangar (closed / open / wreck) | 64 × 56 each | the door states |
| Carrier core (plated / exposed / wreck) | 64 × 64 each | plating panels open on exposure |

Rows (`tests/integration/test_ph10_sprites.gd`, no physics): every scene's hull texture is assigned and has the planned size (± the generator's proportion, as Ph5 allowed);
every module has `intact_texture` and `wreck_texture` set and different; the hangar has three door textures and the core two plating textures; destroying a module in a
hand-ticked instance swaps its sprite texture to `wreck_texture`; the transparency sweep covers every new texture.

### 2.11 Roster gates every new scene joins (t4, t6)

`heavy_gunship/` (renamed) and `carrier/` are in: `test_enemy_contact_damage.gd` `ROSTER` (30 and 15), `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`
(the root hurtbox covers the body; parts are under `Modules`), `test_config_instance_isolation.gd` (directory sweep, automatic; both configs flat), `test_entity_sprite_transparency.gd`
and `test_project_load_integrity.gd` (automatic), `test_base_enemy.gd` (roster, tow table: both refuse), `test_enemy_dual_mode.gd` (one spawn row each),
`test_enemy_mover_single_writer.gd` (automatic for both brains and roots; `enemy_module.gd` / `modular_hull.gd` are under `global/components/` and write no motion),
`test_signal_emit_arity.gd` (automatic). `carrier_pulse_ring.tscn` joins the Ph8 ring fairness rows; `heavy_cannon_mount.tscn` joins the mount variant sweeps and the round
lifetime sweep.

### 2.12 Level 1: the Heavy Gunship replaces the four gunship rows (R10.22; t11)

`assault/scenes/levels/edelia/1/level_1_director.gd`. **Triggers, delays and list order stay** (the deep_space 3.5 s wave's position is pinned by
`test_level1_fighter_fire_density.gd::test_waves_trigger_on_the_shipped_schedule`, the "wave-order quirk").
- deep_space 3.5 s: `b.gunship().at(0, -500)` → `b.heavy_gunship().at(0, -500)`.
- cloud_descent 50.0 s: `b.gunship().at(0, -400).move(b.straight(42))` → `b.heavy_gunship().at(0, -400)` (no rail).
- cloud_descent 62.0 s: both rows → `b.heavy_gunship().at(-100, -400)` and `.at(100, -400).delay(0.8)` (no rail). Owner choice 2 (default: all three).

**Gates** (`tests/integration/test_level1_heavy_spawns.gd`, new):
- **pin** the four rows (section, trigger, offset, delay, scene) as `EXPECTED_PH10_GUNSHIPS`, with mutation boundary rows (a changed delay, a `.move()` put back);
- **count:** `_LEGACY_PEAK_HEAVIES` is **computed once from the pre-change rows and frozen** (deep_space 1; cloud_descent: the 50 s rail gunship is culled ≈ 14.8 s after
  spawning, so with the 62.0 / 62.8 s pair the legacy peak is 3 — the task recomputes it from the old rail speeds and records the figure); the gate asserts peak alive Heavy Gunships
  per section ≤ 1.0 × the frozen value (a section without a frozen value may hold none; the Carrier has its own rule, §2.13), lives = spawn + `engage_seconds` + attack deferral + measured exit;
- **deadline** (`test_engagement_deadline.gd`, per-entry rows like the fighters' and rams'): each cloud_descent Heavy Gunship's worst case (spawn + `engage_seconds` 14 +
  `attack_window()` + the measured curved exit from `ph10_exit_keys.gd`) ≤ 76.0 + 10.0 s, with a boundary row (a heavy at 72.0 s fails); the deep_space heavy's life ends
  before 30.0 s (it no longer carries into the station section; a boundary row shows a 20 s budget would);
- **columns:** a replay at 16× (`tests/helpers/level1_slice_replay.gd`) of each heavy's window shows no module and no hull of a Heavy Gunship is killed by a lit column
  (deep_space columns 6 / 14 / 22 s at x 128 / 640 / 1152, 384 / 896, 256 / 640 / 1024): the mover's `&"laser_wall"` avoidance must keep the whole hull clear, so the
  gunship's `hazard_margin` is set from its hull half-width (≥ 80 px) in its config. **Pre-approved levers, in order, if a column kills a part:** (1) `hazard_margin` up to
  110; (2) the deep_space offset to `.at(±160, -500)`; (3) `assault_preferred_range` 420 → 480. None fits → `Result: ESCALATE` with the replay log;
- **attack-in-budget:** each placed heavy reaches a battery FIRE before its budget expires (replay at 16×);
- the existing specialist, fighter and drone gates stay green (heavies are counted only by the new gate).

### 2.13 Level 1: the Carrier crosses Planet Approach (R10.23; t12)

`planet_approach` (DURATION 110 s). **Hard constraints:**
1. The carrier's whole life (spawn → freed below the projectile rect at 70 px/s) lies **between two column events**, with every module's world x span clear of every column lit
   during its life by 28 px (`Level1Director.laser_column_schedule()`: 10.0 200 / 600 / 1000, 25.0 400 / 800, 38.0 128 / 384 / 640 / 896 / 1152, 55.0 300 / 700 / 1100,
   78.0 150 / 550 / 950, 98.0 450 / 850; a column is lit from its telegraph to its fade, read from the `LaserRay` exports, never typed). The 55 → 78 s gap is the default window.
2. The carrier's ≤ 4 launched swarm drones (Assault payload) are counted in `test_level1_drone_spawns.gd`'s concurrency gate (as intervals: launch time + their own budget +
   measured exit) and the all-drones peak stays ≤ 2.5× the frozen legacy peak; the attack-capable peak ≤ 2.0×.
3. The specialist count (planet_approach 7 of 7.5) is unchanged (the carrier and its drones are not specialists).
4. No overlap with a Heavy Gunship (there is none in planet_approach) and at most one carrier alive in the level.

**Ordered placement options (pre-approved; take the first that meets 1–4 and record the measured life, x span and peaks):**
- **A (default):** a new wave at 59.0 s (after the 55.0 s columns fade), `b.carrier().at(x, -300)` (world-anchored) with x chosen so its 192 px span clears the 78.0 s columns
  if it is still alive then; `assault_cross_speed` 70.
- **B:** option A at 62.0 s inside the existing 62.0 s wave (the Ph9 jammer's wave) if a new wave breaks the fire-density schedule pin.
- **C:** option A with `assault_cross_speed` 85 (shorter life).
- **None fits:** `Result: ESCALATE` with the measured timeline; never change a frozen `_LEGACY_PEAK_*`, never put the carrier in an `ENEMIES_CLEARED` section.

Rows: pin `EXPECTED_PH10_CARRIER` (section, trigger, offset, scene) in `test_level1_heavy_spawns.gd`; constraint 1 from the measured life (a boundary row moves it to 50.0 s and
fails); constraint 2 inside the drone gate; a guard row in `test_engagement_deadline.gd`: no `carrier.tscn` entry in any `ENEMIES_CLEARED` section (boundary: a synthetic
section with one fails); an attack-in-budget replay at 16×: the carrier's hangars both launch and a battery fires before it leaves.

### 2.14 Hub placement (R10.24; t10)

`open_space/scenes/levels/sector_hub.gd` / `.tscn`, **appended draws** (every earlier seed unchanged):
- **Draw 19:** a Heavy Gunship on the 2600 ring at bearing **157.5°** (anchor ≈ (−2402, 995)); `_patrol_groups()` entry `"Heavy Gunship": [anchor, idle_radius 180,
  perceive_radius 900]`.
- **Draw 20:** a Carrier on a new 3400 ring at bearing **−112.5°** (anchor ≈ (−1301, −3141)); entry `"Carrier": [anchor, idle_radius 220 + leash 900, perceive_radius 1100]`
  (its SCREEN leash is part of its footprint); its Open Space launches (drones / fighters) live in `EnemyContainer`.
- Exports for both rings / bearings like the Hacker's; `patrol_anchor` and `rng_seed` set before `add_child()`; `_expected_seeds()` grows to 20 draws.
- Every existing sweep covers them (interactables, the Ph6 TacticalSpace sweep, the Ph7 minefield row, the Ph8 sweeps A / B, the Ph9 sweep C) and the anchors stay > 1000 px
  from every other anchor. **Pre-approved levers if a sweep fails:** the free bearings 22.5° / −67.5° on the 2600 ring for the gunship, 3200–3800 ring radius for the carrier.
- Rows (`test_sector_hub_patrol.gd`): draws 19–20 composition (scene, ring, bearing, seed, `start_engaged` false), both groups clear the spawn, every trigger and pickup, every
  sweep passes; a 30 s hand-ticked hub carrier with the player 3000 px away launches nothing (not engaged).

### 2.15 Gate time and the gate room (t1)

GUT ≈ 225 s at the Ph9 close (2888 tests). **t1 frees ≥ 10 s before any other task lands** (hard floor), by the `tests/README.md` rules only: real-physics rows on the 8×
clock, replays computed once and shared (`before_all` / memo keyed by inputs), per-tick bookkeeping no assertion reads dropped, and a production speed-up only when
bit-identical (Ph8 t1 sped up `FighterBrain.tick`). Never by lowering a tick count, duration, sample count or start grid, widening a bound or removing an assertion. t1
profiles with `scripts/gate-time.sh` (15 slowest files), reports before / after and writes the Phase 10 allotments into `tests/README.md`. If 10 s cannot be found,
`Result: ESCALATE` with the profile (the owner decides between a smaller phase and a split gate). Allotments: t2 1.5, t3 0.8, t4 2.0 (incl. the gunship exit probe), t5 2.5,
t6 2.0, t7 2.0, t8 2.5, t9 0.3, t10 0.8, t11 3.5, t12 2.5, t13 0 = 20.4 s; the phase ends ≤ 236 s; a task that would pass 238 s escalates.

### 2.16 Numbers and where they come from

| Value | Start | Source |
|---|---|---|
| Gunship hull HP / contact / score | 700 / 30 / 300 | judgement: ≈ 14 Standard shots (50 dmg) on the hull alone, ≈ 2.5 s of sustained fire; contact kept (gate); score above the old 200 |
| Gunship parts HP | batteries 160, cannon 200, missiles 140, vents indestructible | judgement; a part ≈ 3–4 shots, readable in a fight; X-Morph finding (few parts) |
| Gunship phase bands | 0.6 / 0.3 | IDEAS §7 (100–60 / 60–30 / < 30) |
| Gunship ranges | OS 560 ± 90, Assault 420, `min_range` 260, emergency 800 | judgement, between the corvette (620 / 460) and the fighter |
| Gunship movement | `max_speed` 140, accel 120, `max_turn_rate` 0.9 rad/s, arc 0.16 rad/s, reversal 5–8 s | judgement: heavier than the corvette (0.22 rad/s arc) |
| Break-away / emergency boost | 360 px/s 0.7 s rearm 3 s / 420 px/s 0.9 s every 5 s | below the player's 700 px/s boost exit, above its 420 cruise only briefly; judgement |
| Heat / vent | 4 bursts, 2.2 s, speed × 0.6 | judgement; Madhead "critical point" finding (bonus window) |
| Vent hull share | 1.0 (2× total) | Madhead / Amygdala findings; judgement on the factor |
| Cannon shield | arc 120°, capacity 60, regen 2.0 / 4.0 s, reboot 5.0 s | Ph5 shield defaults scaled (projected shield 40 / 4 s); judgement |
| Heavy cannon mount | 2 Heavy Shells, 220 px/s, charge 0.7 s, cooldown 3.2 s, range 900, traverse 70° | Heavy Shell scene (160 px/s, 20 dmg) sped up for a cannon; judgement |
| Gunship Assault budget / exit speed | 14.0 s / 260 px/s | cloud_descent deadline (§2.12); corvette exit |
| Carrier parts HP | engines 180, guns 160, hangars 220, core 600 | judgement: exposing the core ≈ 10 shots, the core ≈ 12 |
| Core exposure | any 3 of the 6 outer parts | Garegga / DonPachi lock-and-release finding; owner choice 1 |
| Carrier movement | OS `max_speed` 70, accel 40, turn 0.35 rad/s, band 600–950, leash 900; engines × 0.5 / 0.15, list 0.06 rad/s | FTL subsystem finding; judgement |
| Carrier Assault crossing / sway | 70 px/s / 40 px/s | judgement; the 60 px/s structure drift is the floor, so the carrier reads as moving |
| Pulse ring | r 420, telegraph 1.0 s, 360 px/s, gaps 2 × 50°, 14 dmg, trigger 340 px, cooldown 5 s | Ph8 `EnergyRing` shape scaled to the hull; fairness rule kept |
| Missile bank | PURSUIT, cooldown 7 s, min range 450 px | Ph5 / Ph8 rocket battery; judgement |
| Hangars | doors 0.8 s, hold 2.0 s, period 9 s, 2 per launch, caps 3 / 6, Assault 1 launch per hangar at 3.0 / 7.0 s | Laser Tender rearm 7 s; judgement |
| Carrier contact / score | 15 + ARMOR shove 220 px/s / 600 | Ram Corvette shove 260; judgement |

All are *starting values*: keep them unless a row forces a change, and log any change in `DECISIONS.md`.

### 2.17 Docs and phase close (t13)

Invoke the `updating-project-docs` skill: `docs/architecture/PROJECT.md` → Conventions (new item "Modular enemies": `EnemyModule` / `ModularHull`, the hit rule, wreckage, the
`enemy_parts` group, mount traverse, the heavy hull rules), `docs/architecture/modules/global.md` (`EnemyModule`, `ModularHull`), `assault.md` (heavy gunship, carrier, mount
builder / traverse / HEAVY_CANNON), `open_space.md` (hub draws 19–20), `docs/enemy-roster.md` (Heavy Gunship replaces Gunship incl. every "never `.move()` the gunship" line;
Carrier; `heavy_gunship()` / `carrier()`; Heavy Shell's consumer), per-entity `ENEMY.md`, and CLAUDE.md's gate list (`test_enemy_module.gd`, `test_turret_mount_traverse.gd`,
`test_heavy_gunship.gd`, `test_carrier.gd`, `test_carrier_hangars.gd`, `test_level1_heavy_spawns.gd`, `test_ph10_sprites.gd`). Write the epic dossier
`docs/epics-done/cmug23oo90029m52wae4clve0/` (`PRD.md`, `SOURCES.md` — the §1.2 sources, `REPORT.md`) and append `## Phase 10 - as built (<date>)` to `DECISIONS.md`.

## 3. Build sequence

1. **t1** Gate room: ≥ 10 s of GUT back (§2.15).
2. **t2** `EnemyModule` + `ModularHull` + the beam / nova `enemy_parts` reach, on a fixture host (§2.1, §2.2). After t1.
3. **t3** `TurretMountBuilder`, mount traverse, `HEAVY_CANNON`; module-attached mounts (§2.3). After t2.
4. **t4** Heavy Gunship shell, movement, Assault life, legacy rows moved (§2.4, §2.11). After t3.
5. **t5** Heavy Gunship phases, vents, emergency, cannon shield, battery loss (§2.5, §2.9). After t4.
6. **t6** Carrier shell, armoured hull, core exposure, movement in both modes (§2.6, §2.11). After t4 (roster files) and t3.
7. **t7** Carrier weapons and PANIC (§2.7). After t6.
8. **t8** Carrier hangars (§2.8). After t7.
9. **t9** Art for both ships and their parts (§2.9, §2.10). After t5 and t8.
10. **t10** Hub placement (§2.14). After t5 and t8.
11. **t11** Level 1 Heavy Gunships (§2.12). After t5.
12. **t12** Level 1 Carrier (§2.13). After t8 and t11.
13. **t13** Docs, roster, dossier, phase record (§2.17). After everything.

## 4. Test plan

The rows live with their design sections so each task sees them: §2.1 / §2.2 (`test_enemy_module.gd`), §2.3 (`test_turret_mount_traverse.gd`), §2.4.5 and §2.5
(`test_heavy_gunship.gd`), §2.6.4 and §2.7 (`test_carrier.gd`), §2.8 (`test_carrier_hangars.gd`), §2.10 (`test_ph10_sprites.gd`), §2.11 (roster gates), §2.12 / §2.13
(`test_level1_heavy_spawns.gd`, `test_engagement_deadline.gd`, `test_level1_drone_spawns.gd`), §2.14 (`test_sector_hub_patrol.gd`). The epic's four §40 requirements, in both
harnesses:

| Requirement | Open Space and Assault rows |
|---|---|
| Module death disables an attack | Gunship battery → its mount UNPOWERED, no round for 30 s (§2.5); Carrier gun → no battery round into that half-plane (§2.7); Gunship missiles lost → no rocket (§2.5) |
| Module death changes movement | Gunship battery → it swaps its broadside side; both → nose to player (§2.4.5); Carrier engines → turn time ×1.8 / ×5 and a list, Assault sway 40 / 20 / 4 px/s (§2.6.4) |
| Core vulnerable only when intended | Carrier core with 0–2 outer parts dead deflects real bullets, the beam and the nova; 3rd → vulnerable next frame (§2.6.4); Gunship vents only while venting (§2.5) |
| Destroyed components remain as wreckage | Fixture module (§2.1), Carrier four-part row (§2.6.4), sprite swap row (§2.10) |
| A destroyed hangar stops launches | §2.8 rows, incl. destroyed mid-OPENING |

Boundary rows: the killing shot consumed under both callback orders (§2.1); `traverse_deg` 360 bit-identical (§2.3); `core_exposure_count` read from the `.tres` (§2.6.4);
the deadline and column boundaries (§2.12, §2.13); the Assault one-launch-per-hangar cap (§2.8).

## 5. Risks

- **Gate time** (§2.15): the phase needs ≈ 20 s on a suite with 15 s of headroom. t1's floor and the escalation rule exist for this.
- **Level-1 columns** kill parts on contact. A heavy that cannot dodge a column loses modules mid-section; the placement tasks measure and have ordered levers (§2.12, §2.13).
- **Cloud Descent difficulty:** three firing heavies where none fired before (owner choice 2). The deadline gate bounds their lives, not their difficulty; nothing is
  play-tested.
- **Callback order** on the killing shot (§2.1) — the row forces both orders.
- **Shared component edits:** `beam_behavior.gd` / `plasma_nova_module.gd` (player weapons) and `TurretMount` (every Ph8 turret). Both are additive with bit-identical
  defaults and rows that prove it.
- **The hull rule split** (gunship hull vulnerable, carrier hull armour) is two behaviours on one framework; Ph11 / Ph12 must pick one per boss explicitly.
- **Big sprites:** PixelLab may cap the canvas below 288 px (§2.10 rule: integer scaling only).
- **ScoreTracker orphan tally:** launched children count toward the shared orphan wave-clear tally (`counts_toward_wave_clear` true) as Ph8 drones do; harmless in DURATION sections.

## 6. Out of scope

| Item | Owner phase | Reason |
|---|---|---|
| Hangar launches / battery-loss phases on the shared boss machinery (§10, §24, §25 for the heavies) | Ph18 | Ph1 roadmap; Ph10 builds them in the brains behind `ModularHull` signals |
| Destroyed parts as LOS-blocking wrecks, capital wrecks on death, heavy hazard resistance | Ph19 | Ph1 roadmap; `wreck_chance` 0, hazard fields at defaults |
| Station rework onto `EnemyModule` | Ph11 | the station stays byte-identical |
| Encounter compositions (heavy patrol, convoy, carrier + support) | Ph13 / Ph14 | |
| Ship-mounted EMP (carrier pulse as EMP) | Ph18 | owner choice 5 |
| Audio (vent hiss, hangar klaxon) | Ph17 | |
| Per-part score, a part HUD | Ph17 | no score system for parts exists |
| Level 2 gunship rows | Ph15 | the level is unreferenced |
| Leash / cleanup of a carrier's Open Space children | Ph13 | caps bound them |
| Difficulty scaling of the heavies | Ph16 | |

## 7. Requirements coverage

| # | Requirement (IDEAS section) | Task(s) |
|---|---|---|
| R10.1 | Large enemies stop using one Health node; modules with their own health (§14) | t2, t4, t6 |
| R10.2 | Module exposes armour and accepted damage types (§14, §13.1) | t2 (DefenseProfile per module, deflect rule) |
| R10.3 | Disabled state (§14) | t2 (destroy, mounts powered down), t5, t7, t8 |
| R10.4 | Visual state: dark / off when destroyed, remaining as wreckage (§14, §23) | t2, t9 |
| R10.5 | Gameplay-consequence hook (§14, §26) | t2 (`ModularHull` signals), t5, t6, t7, t8 |
| R10.6 | Weak points found by looking (§13.3) | t5 (vents), t6 (core plating), t9 |
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
| R10.22 | Both replace the level-1 gunship spawns (epic) | t11 (Heavy Gunship); the Carrier joins as a new wave, t12 |
| R10.23 | The Carrier joins Assault waves (epic) | t12 (+ `WaveBuilder.carrier()` t6) |
| R10.24 | The Carrier joins the hub's ambient spawn (epic) | t10 (the Heavy Gunship too) |
| R10.25 | Tests in both harnesses: module death disables an attack / changes movement, core vulnerable only when intended, wreckage stays, hangar stops launches (§40) | t2, t4–t8 (§4 table) |
| R10.26 | §41 Phase 4 (heavy enemies) | this epic |
| — | §10 / §24 / §25 for the heavies | Ph18 |
| — | §28 LOS / §3.2.5 mass for heavies, wreck blockers | Ph19 |
| — | §19 encounter patterns with heavies | Ph13 / Ph14 |
