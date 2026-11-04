# t18 — Hub placement: the defended derelict site, the Laser Tender and a twin-drone patrol

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t18, building epic plan §2.17. Context: `1-context.md` beside this file.
Baseline: `scripts/gate-time.sh` at `2711e16` (measured at the start of this task; figure in the task report and `tests/README.md` → Gate time).

## Problem

The hub has none of Phase 8's new enemies. A player flying out to the derelicts by the gravity well should find them **defended**: a heavy emplacement,
three turrets (sweep beam, rocket battery, lance), a shield generator bubbling them, a power source that shuts everything down when shot, and a
switching laser barrier behind a gap in the wreck line. Elsewhere a Laser Tender and a Twin-Laser Drone pair should be on patrol like every other hub
ship. None of it may be able to reach the player's spawn, a planet, a station or a pickup, and no patrol may idle through the site's structures.

## Design

### A. `hub_defense_site.tscn` (`assault/scenes/structures/turret_group/presets/`)

A `TurretGroup` preset (`coverage_radius` 450, everything else default) with seven `TurretGroupSlot`s. Origin in the hub: **(2520, 1040)** (§2.17).

| Slot | Member scene | `variant` | Offset (plan §2.17) | **Offset built** |
|---|---|---|---|---|
| `HeavyEmplacement` | `heavy_emplacement.tscn` | −1 | (0, 0) | **(180, 20)** |
| `SweepTurret` | `defense_turret.tscn` | 1 `SWEEP_BEAM` | (−240, 160) | (−240, 160) |
| `RocketTurret` | `defense_turret.tscn` | 2 `ROCKET_BATTERY` | (240, 160) | (240, 160) |
| `LanceTurret` | `defense_turret.tscn` | 4 `LANCE` | (0, −260) | (0, −260) |
| `ShieldGenerator` | `shield_generator.tscn` | −1 | (−120, −120) | (−120, −120) |
| `PowerSource` | `power_source.tscn` | −1 | (120, −120) | **(200, −120)** |
| `Barrier` | `laser_fence/hub_barrier.tscn` | −1 | "between two derelicts, posts ≈ 300 px apart" | **(44, 98)**, posts at ±(33, −146) |

**Why two offsets move (a deviation, logged in DECISIONS).** §2.17's offsets were written without the derelicts' bodies. Relative to the origin the
derelicts sit at module (−63, 163) r 45, cargo platform (−25, −7) r 55 and satellite (68, −153) r 28. At (0, 0) the r 64 heavy emplacement would sit
**inside** the cargo platform (centre gap 26 px against 119 px of radii): its burst rounds would spawn inside a wreck that stops enemy rounds (Ph6)
and die at once. At (120, −120) the r 34 power source touches the satellite (gap 0). Moved: the heavy emplacement to (180, 20), behind the wreck line on
the well side; the power source to (200, −120), behind it too, so the player has to flank or get through a gap to reach the source. The lance offset
(0, −260) is kept, so the plan's 1360 px reach stands.

**The barrier.** `TurretGroupSlot` can only choose a member scene (no `mode`, no rotation), so the fence is an inherited scene
`assault/scenes/structures/laser_fence/hub_barrier.tscn` (from `laser_fence.tscn`): `mode = CYCLE` (OFF 2.5 / TELEGRAPH 0.8 (`twin_beam.tscn`) / ACTIVE 3.0, the
fence's own defaults), `PostA` at (33, −146), `PostB` at (−33, 146) — 299.4 px apart along the wreck line (direction module → satellite). At slot
(44, 98) it runs parallel to the line ~90 px behind the module–cargo gap: a player slipping through that gap meets the barrier when it is lit. The
fence reads its endpoints from the posts' global positions every tick, so a rotated pair needs no fence code. It lives in `laser_fence/`, not in
`presets/`, because the coverage row loads every preset `as TurretGroup`. No `TurretGroup` change (copying slot rotation was rejected: a rotated turret
slot would rotate a root that must never rotate).

Measured gaps (body circle to body circle, members and derelicts): smallest 35 px (post A – cargo platform); every pair ≥ 30 px. The barrier segment
clears every derelict body by ≥ 35 px and every member body by ≥ 51 px (it would otherwise be shadowed by its own cover, or burn nothing but
the site). A row pins this (Test plan, row S6).

The generator shields the five `BaseEnemy` members other than itself (heavy, three turrets, power source); the barrier's posts are never shielded
(§2.10.5). Coverage at 450 px holds (the heavy emplacement's two 700 px mounts reach every point alone; epic review M5 accepted that).

`rng_seed` (§2.17 "the group's `rng_seed` is a scene export"): `TurretGroup` has no rng, and the site is a scene node, so it draws nothing from
the patrol rng whatever; its members' brains randomize their own rng as every turret does. No export is added (logged).

### B. `sector_hub.tscn`

`EnemyContainer` gains one child, `HubDefenseSite` (instance of the preset, no uid) at (2520, 1040). Its members spawn deferred into
`EnemyContainer` on the hub's first frame (`TurretGroup._ready()`); Open Space has no view rect, so its x is untouched.

### C. `sector_hub.gd`: draws 16 and 17

- Exports `laser_tender_ring_radius` 2600 / `laser_tender_anchor_bearing_deg` 112.5 → anchor (−995, 2402); `twin_pair_ring_radius` 2600 /
  `twin_pair_anchor_bearing_deg` −157.5 → anchor (−2402, −995).
- `_spawn_patrol()` appends `_spawn_laser_tender(anchor, rng)` (draw 16: brain `rng_seed`, `patrol_anchor`, position, before `add_child()`) and
  `_spawn_twin_laser_pair(anchor, rng)` (draw 17: a `TwinLaserPairSpawn` with `rng_seed = _next_seed(rng)` at the anchor, added, then
  `spawn_pair()` called at once, so both drones exist on frame 0 like every other patrol; A gets draw 17, B draw 17 + 1). The spawner
  `queue_free()`s itself; it is a container child until the frame ends.
- Spacing: the nearest other anchors are the Sniper's (−1202, 1202) 1218 px from the tender and the Ram's (−1202, −1202) 1218 px from the pair; every
  pair of the eleven distinct anchors is > 1000 px apart.
- Clearance (existing rule: distance − worst idle offset > perceive): tender idle 160 + perceive 700; pair worst idle offset
  max(`idle_radius` + `slot_tolerance`, `rig_length` / 2) = 210 (the drones spawn 210 px either side of the anchor) + perceive 650. The nearest
  interactables are ≈ 1960–2050 px away, so both clear by > 1100 px.

### D. Tests (`tests/integration/test_sector_hub_patrol.gd`)

Helpers: `_patrol_groups()` gains `"Laser Tender"` and `"Twin Pair"`; `_brain_seeds()` skips children without a `Brain` (the queued spawner);
new `_hub_sites(hub)` walks `EnemyContainer` for `TurretGroup` and `LaserFence` children; `_slot_reach(slot)` / `_slot_footprint(slot)` /
`_fence_reach(fence_or_scene)` instantiate the member scene off-tree and read config `perceive_radius`, `TurretMountScenes.reach_of()` per mount slot
(the group's first-slot `variant` override honoured), the root `CollisionShape2D` circle, the posts' positions and the beam's `draw_half_width` /
`hazard_pad`.

## Build sequence

1. Tests first: extend the hub test (rows below); run it, watch the new rows fail (no preset, no draws 16/17).
2. `hub_barrier.tscn`, `hub_defense_site.tscn`; the site instanced in `sector_hub.tscn`.
3. `sector_hub.gd` draws 16 and 17.
4. Run the hub test, `test_turret_group.gd`, `test_laser_fence.gd`, `test_project_load_integrity.gd`, `test_resource_uid_integrity.gd`.
5. Frame-time measurement (one-off headless script, not a GUT row: full `sector_hub.tscn`, 600 frames, `TIME_PHYSICS_PROCESS + TIME_PROCESS` mean,
   with the site and with it removed) → DECISIONS.
6. Docs: `STRUCTURE.md` (turret group: the hub preset; laser fence: `hub_barrier.tscn`), `docs/architecture/modules/open_space.md` (hub patrol and
   site), DECISIONS "Phase 8, built in t18", `tests/README.md` gate row; `bash /agent/verify.sh`; `scripts/gate-time.sh` after.

## Test plan

All in `test_sector_hub_patrol.gd`. Off-tree rows read `sector_hub.tscn`; spawn rows use the existing minimal `_spawn_hub()` harness; site rows put the
preset in an Open Space harness container and hand-tick.

Patrols
- P1 `test_laser_tender_anchor_clears_every_planet_pickup_and_the_player_spawn` and P2 `test_twin_pair_anchor_clears_…` (bearing / ring asserted,
  margin printed).
- P3 the spacing row becomes eleven anchors (renamed), and asserts the tender's and both drones' `patrol_anchor`.
- P4 seed row: 17 draws; `seeds[0..15)` = draws 1–15 unchanged; the tender = draw 16; drone A = draw 17, B = draw 17 + 1.
- P5 composition / container-count: one `LaserTender`, two `TwinLaserDrone`s bound as one `TwinLaserPair`; the live (not queued) children count is
  15 + 3; the with-space row's count and seed list updated likewise.
- P6 frame-0 row: the tender's brain and both drones' brains are `IDLE` after one tick (both variants of the existing parameterised row).
- The existing TacticalSpace sweep now covers both new patrols (via `_patrol_groups()`).

Site
- S1 the real hub places exactly one `TurretGroup` under `EnemyContainer`, scene `hub_defense_site.tscn`, at (2520, 1040), `coverage_radius` 450.
- S2 composition: the preset's slots are one heavy emplacement, a sweep / rocket / lance turret (variants by slot), a generator, a power source and a
  CYCLE `LaserFence` whose posts are 300 ± 2 px apart.
- S3 spawned (Open Space harness): seven members, each a sibling of the group in the container (never under the group), each in `owner_group`, each
  `is_powered()`; the group is powered.
- S4 shielded: after one generator tick the five `BaseEnemy` members other than the generator carry an up `EnemyShield` in their hurtbox's absorber
  slot; the generator has none; neither fence post has one (nor an absorber).
- S5 coverage: covered by `test_turret_group.gd`'s every-preset row (asserted to have found this preset: it loads the directory).
- S6 geometry: every pair of site bodies and TacticalSpace derelicts is ≥ 30 px apart (gap printed); the barrier segment clears every derelict body by
  > `draw_half_width`. **Boundary:** the same check on the plan's original heavy offset (0, 0) fails (inside the cargo platform).

Sweeps
- A `test_hub_defense_site_reach_clears_spawn_triggers_and_pickups`: for every `TurretGroup` / `LaserFence` child of `EnemyContainer`, reach =
  max over slots of |offset| + max(member `perceive_radius`, largest mount reach) (a fence slot: |offset| + fence reach; a standalone fence: half post
  separation + `draw_half_width` + `hazard_pad`); assert the site's reach = |lance offset| + `reach_of(LANCE)` (1360); every player-spawn / mission
  trigger / pickup point clears the reach by > 300 px (the interactable margin the TacticalSpace sweep uses); found ≥ 1 site. **Boundary:**
  `test_a_mission_trigger_inside_the_sites_reach_fails_sweep_a`: a real `MissionTrigger` added to the off-tree hub 1000 px from the site origin is
  reported, and the unmodified scene is not.
- B `test_hub_patrols_clear_the_defense_site`: for every group in `_patrol_groups()` (12 entries, the two new ones included), anchor distance to the
  site origin − worst idle offset > footprint, footprint = max over slots of |offset| + body radius (+ fence half length for a fence slot) + 100;
  the footprint is printed and asserted < 500. **Boundary:** `test_a_patrol_anchored_on_the_site_fails_sweep_b`: a synthetic group anchored at the
  site origin is reported.

## Risks

- Godot does not run the deferred `spawn_members()` in the off-tree rows — they read slots only, by design.
- `_tick_all` order: drone A must tick first for the rig's stand-down to be mirrored by B on frame 0; container order guarantees it (A added first).
  If B still reads FORM after one tick, the row ticks the pair twice and says why.
- Gate time: off-tree reads plus two hand-ticked harness rows; expected well under 1.2 s.

## Out of scope

Level 1 placement (t19); the docs / roster closure (t20); hub frame-time as a GUT row (epic review M3); re-powering; slot rotation.

## As built (after the round-1 review, `4-review.md`: APPROVED)

- Review item 1: the spawn row asserts `owner_group` membership on every `BaseEnemy` member and both fence posts, `is_powered()` only where a member
  has it, `provides_power()` on the source and `is_powered()` on the group. No class changed.
- Item 2: sweep A takes mount reaches from `TurretGroup.mount_reaches()`; per slot it adds only `perceive_radius` (or a fence's beam reach).
- Item 3: the twin beam's TELEGRAPH is 0.8 s and its `draw_half_width` 14 (`twin_beam.tscn`); the rows read both from the scene.
- Item 4: the geometry row also asserts every site body clears the gravity well's `damage_radius` (read from the scene). The heavy emplacement
  (≈ 305 px) and the power source (≈ 386 px) sit inside the well's 420 px pull, outside its 150 px stress pulse; static members have no mover.
- Rows are merged where the plan listed them separately: P1-P6 are new rows plus edits of the existing seed, composition, spacing, with-space and
  frame-0 rows; S1 + S5 is `test_the_hub_places_the_defense_site_under_the_enemy_container` (it also asserts `coverage_holes()` is empty), S2
  `test_the_site_preset_has_the_planned_members`, S3 + S4 `test_the_site_spawns_powered_members_into_the_container_shielded_except_the_fence_posts`,
  S6 `test_the_site_bodies_clear_each_other_and_the_derelicts` with its boundary `test_a_heavy_emplacement_on_the_site_origin_fails_the_geometry_check`.
