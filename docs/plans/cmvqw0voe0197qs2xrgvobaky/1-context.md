# Context — t18 Hub placement: the defended derelict site, the Laser Tender and a twin-drone patrol

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t18, building epic plan §2.17 (with §2.7–§2.14 for the pieces it places). Code read on
`agent/auto-dev` @ `2711e16` (t16 landed; every structure, turret, drone and tender this task places already exists).

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `open_space/scenes/levels/sector_hub.gd` | `_spawn_patrol()`: 15 rng draws (swarm ×4, razor, fighter ×2, Gatling ×2, sniper, bomber, ram, corvette, support, mine layer), each `_next_seed(rng)` set on the brain before `add_child()`, plus `patrol_anchor` | Draw 16 (Laser Tender) and draw 17 (a `TwinLaserPairSpawn`) are appended; new ring / bearing exports |
| `open_space/scenes/levels/sector_hub.tscn` | `EnemyContainer` (empty in the scene), `TacticalSpace` (well (2956,1225), anomaly, three derelicts: station module (2457,1203) r45, cargo platform (2495,1033) r55, satellite (2588,887) r28; debris; Minefield (3300,560)); player spawn (0,0); pickups / planets / logs | The site is instanced under `EnemyContainer`. No test adds the whole scene to the tree (only off-tree instantiation: `test_sector_hub_patrol.gd`, `test_hub_log_placement.gd`, `test_module_unlock_sources.gd`, `test_weapon_unlock_sources.gd`, `test_boost_upgrade_source.gd`), so the site can turn no existing row red by shooting |
| `assault/scenes/structures/turret_group/turret_group.gd` | `TurretGroup`: deferred `spawn_members()` into its own parent; copies slot `variant` / `rest_bearing_deg`, turns `world_anchored_x` off, calls `set_turret_group`; copies **no rotation** and **no other property**; `mount_reaches()` / `coverage_holes()` off-tree | The preset is a `TurretGroup`; a fence slot can only choose a member **scene**, so a CYCLE fence with posts along a chosen line needs its own (inherited) scene |
| `assault/scenes/structures/turret_group/presets/assault_pair.tscn`, `tests/helpers/shielded_site.tscn` | Preset shape: `TurretGroupSlot` markers with `member_scene` / `variant` | Template for `hub_defense_site.tscn` |
| `assault/scenes/structures/laser_fence/laser_fence.gd/.tscn` | Posts `PostA` (−150,0) / `PostB` (150,0); endpoints read from the posts' global positions every tick (any orientation works); `mode` export; `set_turret_group()` | An inherited `hub_barrier.tscn` sets `mode = CYCLE` and rotates the post pair |
| `assault/scenes/enemies/twin_laser_drone/twin_laser_pair_spawn.gd` | `spawn_pair()` (public, idempotent): A and B at ∓`rig_length/2` (210) along local X, seeds `rng_seed` / `rng_seed + 1`, both brains' `patrol_anchor` = spawner position, binds, then `queue_free()`s itself | Draw 17's seed goes on the spawner. Called synchronously by the hub so the pair exists on frame 0 like every other patrol; the queued spawner stays a container child until the frame ends |
| `assault/scenes/enemies/laser_tender/laser_tender.tscn` + brain | Single node (drones are made at launch); brain `rng_seed`, `patrol_anchor`, `Phase.IDLE`; config idle 160 / perceive 700 | Draw 16 |
| `tests/integration/test_sector_hub_patrol.gd` | Off-tree clearance rows, minimal-harness spawn rows (`_spawn_hub()`), `_patrol_groups()` (feeds the TacticalSpace sweep), `_brain_seeds()` (every container child's `Brain`), seed / composition / container-count / frame-0 rows, the 9-anchor spacing row | Extended: two patrols, sweeps A / B, site rows. `_brain_seeds()` must skip the queued spawner (no `Brain`) |
| `tests/integration/test_turret_group.gd::test_every_preset_meets_the_coverage_rule` | Iterates every `.tscn` in `turret_group/presets/`, `as TurretGroup` | The hub preset joins it automatically; nothing but `TurretGroup` scenes may live in that directory |
| `assault/scenes/enemies/defense_turret/mounts/turret_mount_scenes.gd` | `reach_of(variant)` (mount `reach()`: fire range, ring `trigger_range`), `export_of()` | Sweep A's mount ranges |
| `assault/scenes/projectiles/enemy_beams/enemy_beam.gd` | `draw_half_width` (16 by default, 14 on `twin_beam.tscn`), `hazard_pad` 24 exports | Sweep A's fence reach |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `TurretGroup.spawn_members()` / `members()` | The site spawns into `EnemyContainer` with no new code |
| `TwinLaserPairSpawn.spawn_pair()` | The hub pair, seeds and shared anchor |
| `test_turret_group.gd` `_spawn()` / `_gen_step()` / `_shield_of()` shapes | The hand-ticked site rows (written locally in the hub test, same shape) |
| `_interactable_points()`, `_patrol_groups()`, `_space_elements()` in the hub test | Sweeps A and B reuse them |
| `TurretMountScenes.reach_of()`, `EnemyBeamScenes.export_of_scene()` | Numbers read from scenes, never typed |

## Conventions that constrain this

- Every earlier rng draw unchanged; seeds set before `add_child()`; `_next_seed()` never returns 0.
- Never hand-type a `uid://`: new `.tscn` files and new `ext_resource` lines carry no uid.
- Nothing but `TurretGroup` scenes in `turret_group/presets/` (the coverage row loads each `as TurretGroup`).
- Numbers in rows are read from scenes / configs.
- Gate allotment 1.2 s of new GUT time; baseline from `scripts/gate-time.sh` at `2711e16`.
- Plan review M3 (epic `4-review.md`): the hub frame-time note is a one-off headless measurement recorded in DECISIONS (the Ph7 precedent), not a GUT row.
- Plan review M5: the coverage rule counts mounts, so the heavy emplacement alone satisfies it at 450 px — accepted by the epic review, kept.
