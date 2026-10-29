# t9 — Turret groups with overlapping fire; the power source shuts the whole group down

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t9. Builds epic plan §2.10.1–§2.10.4 and §2.19 (approved). This task plan does not
redesign them; it fixes what they leave open (the stagger clock, the spawn seam tests use, the coverage computation, the rest-bearing hand-over,
file layout, test geometry). Where it says "§2.10", the epic plan wins. Context: `1-context.md`.

**Revision 2** answers round 1 of `4-review.md`: B1 (row 7 gains a reach-sensitive boundary), B2 (new row 11: a real `ScoreTracker` drift-out,
which also pins "the group is never scored" and the `.tres` flag), N1 (row 4 ends with a lethal hit on a dark turret that still scores), N2 (slot
`rest_bearing_deg` defaults to NAN = keep the member's own; new row 12), N3 (row 10 pans the camera and proves the anchor on the real spawn path), N4
(row 4 awaits one frame before "freed"), N5 (row 4's victim is checked on B's beam segment), N6 (row 8 re-seeds the shared rng object), N7 (row 11 also
pins "a provider that drifts out does not darken"), N8 (row 1 disconnects its `EventBus` handler).

## Problem
Today a turret stands alone. The player should meet turrets in small groups whose fire lanes cross, with one obvious weak point: a reactor (the
power source) tied to every turret by an amber line. Destroying it turns every turret in the group dark and harmless at once, and they stay dark.
In Assault a group must land at a predictable world x so level 1 can place it between its laser columns.

## Design

### Files
- `assault/scenes/structures/turret_group/turret_group.gd` — `class_name TurretGroup extends Node2D`.
- `assault/scenes/structures/turret_group/turret_group_slot.gd` — `class_name TurretGroupSlot extends Marker2D`: `@export var member_scene: PackedScene`,
  `@export var variant: int = -1`, `@export var rest_bearing_deg: float = NAN` (NAN = keep the member's own authored bearing; review N2).
- `assault/scenes/structures/turret_group/presets/assault_pair.tscn` — root `TurretGroup` (`coverage_radius` 180), slots `BurstTurret` (−50, 60,
  `defense_turret.tscn`, variant 0), `RingTurret` (50, −60, variant 3), `PowerSource` (0, 0, `power_source.tscn`).
- `assault/scenes/structures/turret_group/STRUCTURE.md` — the per-structure doc (short; the `HAZARD.md` / `ENEMY.md` analogue).
- `assault/scenes/enemies/power_source/` — `power_source.gd` (`PowerSource extends BaseEnemy`), `power_source.tscn`, `power_source_config.gd`
  (`PowerSourceConfig extends ShipConfig`, adds only group "Assault" `assault_drift_speed` 60), `power_source_config.tres`, `ENEMY.md`.
- Edits: `defense_turret.gd` (rest-bearing override, stagger gate binding), `turret_mount.gd` (`reach()`), `pulse_ring_mount.gd` (`reach()`),
  `turret_mount_scenes.gd` (`reach_of()`), `wave_builder.gd`, the roster gates, `test_enemy_dual_mode.gd`, `test_engagement_deadline.gd`, docs.

### `TurretGroup`
- Node fields: `counts_toward_wave_clear := false`, `counts_as_escape := false`, `score_value := 0`. **No `died` signal** (so `ScoreTracker`, which a
  wave spawn of the group reaches through `WaveManager.enemy_spawned`, connects only `tree_exited`, and with `counts_as_escape` false that does
  nothing). Not in `enemies`. `is_laser_blocking() -> false`.
- Exports: `coverage_radius := 180.0`, `coverage_min := 2`, `stagger_seconds := 0.3`, `world_anchored_x := true`.
- `owner_group: StringName` assigned in `_init()` (`&"turret_group_%d" % get_instance_id()`), so it is readable before the group enters the tree.
- Signals: `power_changed(powered: bool)`, `member_left(member: Node)`.
- `_ready()`: the world anchor (below), then `spawn_members.call_deferred()`.
- **World anchor:** if `world_anchored_x` and `EnemyWorld.has_view_rect(tree)` and `EnemyWorld.has_projectile_world_rect(tree)`:
  `global_position.x -= EnemyWorld.view_rect(tree).get_center().x - EnemyWorld.projectile_world_rect(tree).get_center().x`. Once, before any spawn.
  Open Space has neither rect, so nothing changes there. **"Not itself spawned by a group"** is implemented by the spawner: before `add_child` the
  group sets `world_anchored_x = false` on any member that has that property (a nested group, and t10's `LaserFence` in the hub preset), because a
  slot position is already a world position.
- **`spawn_members()`** (public, idempotent; the deferred call from `_ready()` is the production path, and a hand-ticked row calls it directly so no
  physics frame runs between the spawn and the row switching the members' physics off). Returns at once if already spawned or if the group is not
  inside the tree. For every `TurretGroupSlot` child with a `member_scene`, in child order:
  1. `member = member_scene.instantiate()`; `member.position` = the slot's global position in the parent's space (`parent.to_local(slot.global_position)`
     when the parent is a `Node2D`, else the global position);
  2. independently of each other: if `slot.variant >= 0` and `"variant" in member`: `member.variant = slot.variant`; if `slot.rest_bearing_deg` is not NAN
     and `"rest_bearing_override" in member`: `member.rest_bearing_override = slot.rest_bearing_deg`; if `"world_anchored_x" in member`: false; if `member.has_method("set_turret_group")`:
     `member.set_turret_group(self)` — all before `add_child` (inside `BaseEnemy._init()`'s privatisation window, the turret's `_ready()` reads them);
  3. `get_parent().add_child(member)`; remember it; connect `member.tree_exiting` -> `_on_member_exiting.bind(member)` (one-shot);
  4. if `member.has_method("provides_power") and member.provides_power()`: `add_power_provider(member)`;
  5. `EventBus.enemy_spawned_orphan.emit(member)`.
  With no member spawned the group frees itself.
- `members() -> Array[Node2D]`: the remembered members that are valid and not queued for deletion.
- `_on_member_exiting(member)`: forget it, `member_left.emit(member)`; when none is left, `queue_free()` (guarded: inside the tree and not already queued).
  This is the frame the last member leaves (the Minefield precedent, without the dark linger: a group has nothing to show).
- **Power.** `_providers: Array[Node]`, `_powered := true`.
  - `add_power_provider(node: Node)`: ignored when `node` is null, already a provider, has no `died` signal, or the group is already dark (no re-power in
    this phase). Otherwise append and connect `node.died` -> `_on_provider_died.bind(node)` (one-shot) and `node.tree_exiting` -> `_forget_provider.bind(node)`
    (one-shot). Any node with `provides_power()` and `died` works: the Ph20 jammer seam.
  - `_on_provider_died(node)`: forget it; if no provider is left and `_powered`: `_go_dark()`. This runs inside `BaseEnemy._on_health_changed`'s
    `died.emit()`, i.e. **in the same call as the lethal hit**, before the source's `queue_free()`.
  - `_forget_provider(node)` (a provider leaving without dying — it drifted out below the projectile world rect) only removes it; it never darkens
    the group (only a death does, §2.10.1 "on the last provider's `died`"). Its turrets are 60 px from it and leave with it.
  - `_go_dark()`: `_powered = false`; `set_powered(false)` on every `members()` entry that has the method (the source itself has none); then
    `power_changed.emit(false)`. `set_powered(false)` only sets flags and cancels / fades beams, so it is safe inside the bullet flush that killed the source.
  - `is_powered() -> bool`: `_powered` (true for a group that never had a provider).
- **Stagger.** The group owns one clock: `tick(delta)` adds `delta` to `_clock`; `_physics_process(delta)` calls `tick(delta)`. (The group is the
  members' earlier sibling, so on real physics it ticks first in each frame.) `request_telegraph(_member: Node) -> bool`: true, and `_last_grant = _clock`,
  when there has been no grant yet or `_clock - _last_grant + TurretMount.CLOCK_EPS >= stagger_seconds`; false otherwise. A hand-ticked row ticks the group
  and its members in step (physics off on all of them).
  - `DefenseTurret._build_mounts()` sets `mount.telegraph_gate = Callable(_turret_group, "request_telegraph").bind(self)` when its group has that method;
    a lone turret keeps the empty gate (always allowed). The mount already asks the gate last and retries next tick on a refusal (t6).
- **Coverage.** `coverage_points() -> PackedVector2Array`: 36 points `Vector2.from_angle(deg_to_rad(10 * i)) * coverage_radius`, **local to the group
  origin**. `mount_reaches() -> Array[Dictionary]`: for every slot whose `member_scene` instantiates (off-tree, freed straight after) to a node with a
  `MountSlots` child, one `{position, reach}` per `TurretMountSlot` there: `position` = slot position + mount slot position (local), `reach` =
  `TurretMountScenes.reach_of(v)` with `v` = the group slot's `variant` for the first mount slot when ≥ 0, else the mount slot's own. `coverage_holes()
  -> PackedVector2Array`: the coverage points fewer than `coverage_min` reaches cover (`reach ≥ distance`). Everything reads local positions, so it
  works on an off-tree preset instance (the coverage row never adds one to the tree).
  - `TurretMount.reach() -> float` returns `fire_range`; `PulseRingMount.reach()` returns `trigger_range`. `TurretMountScenes.reach_of(variant)` instantiates
    the variant's mount scene off-tree, reads `reach()` and frees it (0.0 for an unbuilt variant). The heavy emplacement (t11) reuses it unchanged.

### `DefenseTurret` edits
- `var rest_bearing_override: float = NAN` (not an export; a group slot or a wave's `prop()` sets it before `add_child`): when not NAN it replaces
  the **first** mount slot's `rest_bearing_deg` (mirrors `variant`).
- The `telegraph_gate` binding above. No other change.

### `PowerSource`
- Scene modelled on `defense_turret.tscn`: `CharacterBody2D` root, one `CircleShape2D` r 34 shared by `CollisionShape2D` and `HurtBox/CollisionShape2D`
  (HurtBox layer 512, mask 65), `Health` 150, `HitFlashAnimationPlayer`, `ContactProfile` mode NONE, `AssaultDrift`, **no `ContactHitBox`, no brain, no mover**.
- `PowerSourceConfig`: `max_health` 150, `collision_damage` 0, `score_value` 80, `counts_as_escape` false, hazard fields 0, `wreck_chance` 0,
  `assault_drift_speed` 60.
- `_ready()`: `super._ready()`, `add_to_group("enemies")`, apply config (health, drift speed), join the owner group (`set_turret_group(group)` before
  `add_child`, read duck-typed as the turret does; alone it is `&"power_source_<id>"`), connect the group's `power_changed` to drop the lines.
- `provides_power() -> true`, `is_laser_blocking() -> false`, `turret_group()`, `owner_group()`.
- **Power lines:** `power_lines() -> Array[Line2D]` refreshes and returns them. One code-built `Line2D` (`top_level`, width 3, amber
  `Color(1.0, 0.7, 0.2, 0.85)`) per live group member that is not a power provider, from the source to the member, while the group is powered; none
  when it is dark or the source has no group. Refreshed from `_process` (visual only; nothing reads a clock there).
- Placeholder art (root `_draw()`): a dark housing disc r 36 and an amber core glow; the art task (t15) replaces it.

### `WaveBuilder`
`const TURRET_GROUP_ASSAULT_PAIR := "res://assault/scenes/structures/turret_group/presets/assault_pair.tscn"` and
`func turret_group(preset_path: String) -> SpawnConfig: return SpawnConfig.new(preset_path)`.

## Build sequence
1. Tests first: `tests/integration/test_turret_group.gd` (rows below), the roster entries and the dual-mode case; watch them fail (missing classes).
2. `TurretMount.reach()` / `PulseRingMount.reach()` / `TurretMountScenes.reach_of()`; `DefenseTurret.rest_bearing_override` and the gate binding.
3. `PowerSource` (config, scene, script, ENEMY.md).
4. `TurretGroupSlot`, `TurretGroup`, `assault_pair.tscn`, `STRUCTURE.md`.
5. `WaveBuilder` const + helper; the engagement-deadline guard row.
6. Run the file, then the gate; `scripts/check-test-leaks.sh`; `scripts/gate-time.sh` after.
7. Docs (`updating-project-docs`), `DECISIONS.md` "Phase 8, built in t9", `tests/README.md` gate-time row.

## Test plan
`tests/integration/test_turret_group.gd` (INTENT). Both harnesses (`MODES` parameter, label string) unless the name says `assault_` or nothing is
mode-dependent. Group origin `G = (640, 300)` (inside the Assault view), player below it. Members are hand-ticked: after `spawn_members()` the row turns off
physics on the group, every member and every member's `AssaultDrift`, then each step is `group.tick(DT)` followed by `member._physics_process(DT)` for the
members the row drives. Deaths are `hurt_box.received_damage.emit(10000)`.
1. **`test_a_preset_spawns_its_members_deferred_as_siblings_at_its_slots`** — `assault_pair` at G: straight after `add_child` the parent holds only the group;
   after `await get_tree().process_frame` (the deferred flush) it holds the group + 3 members, each announced once through `EventBus.enemy_spawned_orphan`
   (position captured in that handler, so drift cannot blur it: G + (−50, 60), G + (50, −60), G); each in `enemies` and in `owner_group`; the turret at
   (−50, 60) carries a `BurstCannonMount`, the one at (50, −60) a `PulseRingMount`, the source `provides_power()`; the group is not in `enemies`, has no
   `died` signal, `counts_toward_wave_clear` / `counts_as_escape` false, `is_laser_blocking()` false; `is_powered()`. Freeing the members one by one emits
   `member_left` three times and the group is gone after the frame of the last (still there after the first two).
2. **`test_assault_the_group_is_world_anchored_in_x`** — `ArenaCamera.offset = (100, 0)`; sanity `view_rect` centre − `projectile_world_rect` centre = 100;
   group placed at `cam.global_position + cam.offset + Vector2(−64, −220) · WORLD_SCALE` (WaveManager's formula): after `add_child` its x is 512; after
   `spawn_members()` the members' x are {462, 512, 562}; the same with `world_anchored_x = false` lands at 612 (boundary). y is untouched (camera-relative).
3. **`test_open_space_the_group_x_is_untouched`** — the same placement point (612, y) in the Open Space harness stays at 612.
4. **`test_killing_the_power_source_shuts_every_member_down_in_the_same_call`** (R8.24, both harnesses, hand-ticked) — a code-built group: BURST at
   (−200, 0), BEAM_CANNON at (−70, 0) and (70, 0), BURST at (200, 0), power source at (0, −100); player at G + (0, 250). The (200, 0) burst turret is killed
   first. Drive: group + beam C until C's beam `is_lethal()`; group + beam B until B's beam is TELEGRAPH (a fixture victim then placed on B's line); group
   + burst A until its mount is FIRE with 1 ≤ rounds < `burst_count`. Sanity (N5): the victim's distance to B's beam segment (B's muzzle along
   `Vector2.RIGHT.rotated(beam.global_rotation)` out to the beam's `length`) is ≤ 14 px, so "never hit" is meaningful. Kill the source; **in the same call** (no tick between): every live turret's mount and
   brain UNPOWERED, `is_powered()` false on members and group, B's beam OFF, C's beam FADE, every light OFF, `power_changed` == [false]; A's rounds still
   valid and in its pool's active list. Then 600 steps (10 s) of group + A, B, C: no `round_fired`, A's pool active count never grows (at 300 steps = 5 s and
   at 600), B's victim never hit, C's beam OFF, every mount still UNPOWERED, `power_changed` still fired once; the turret killed first is queued for
   deletion and never in `members()`; a fresh provider handed to `add_power_provider()` afterwards leaves `is_powered()` false (never reverses). **Dark
   but destructible (N1):** a real `ScoreTracker` is started before the spawn (members reach it as orphans); a lethal hit on dark turret A emits `died` and
   raises the tracker's total score by at least A's `score_value`. Finally one `await get_tree().process_frame`: the first-killed turret is freed and
   `member_left` fired for it.
5. **`test_assault_a_source_killed_while_its_turrets_are_above_the_view_still_disables_them`** — `assault_pair` at y −300 (above the view): after 30 steps
   the turrets' brains are SCAN (they never perceive off-screen); kill the source; both turrets UNPOWERED.
6. **`test_the_group_staggers_telegraph_starts_by_stagger_seconds`** — three PULSE_RING turrets in a code-built group at (−100, 0), (0, 0), (100, 0), player at
   G + (0, 150) (≤ 300 px from each), hand-ticked: they notice and engage on the same tick, and their TELEGRAPH starts are ≥ `stagger_seconds` − 1e-6 apart
   and each within `stagger_seconds` + 2 DT of the previous (a refused mount retries next tick). Control: the same three turrets with no group start on the
   same tick (so the stagger is what separates them).
7. **`test_every_preset_meets_the_coverage_rule`** — every `.tscn` under `turret_group/presets/` (at least one), instantiated off-tree: `coverage_holes()` is
   empty; `assault_pair` has 2 `mount_reaches()` (one per turret mount; the source has none), reaches = `reach_of(BURST_CANNON)` (700) and `reach_of(PULSE_RING)` (300),
   each read from the mount scenes. Boundaries: `assault_pair` with the ring turret slot removed has holes, and with the burst turret slot removed has holes;
   **reach-sensitive (B1):** `assault_pair` with both turrets and `coverage_radius` 240 (> `reach_of(PULSE_RING)` − |(50, −60)| = 221.9) has holes, every hole
   is on the far side of the origin from the ring turret (`hole.dot(ring_turret_position) < 0`), and the coverage point nearest the ring turret's bearing
   is not a hole. This fails an implementation that ignores reach, drops the slot offset or compares the wrong way.
8. **`test_a_groups_pulse_ring_spares_its_power_source_and_hurts_an_outsider`** — `assault_pair` at G, the ring turret's brain rng re-seeded **in place**
   (`brain.rng.seed = S` on the object the mount shares, never a new `RandomNumberGenerator`; N6) so the gap bearing is fixed and the run reproducible
   (`S` a named const), three fixture outsiders 78 px from the ring turret at the source's bearing ±90° and +180°, player within
   `trigger_range`. Tick group + ring turret until the ring is FADE: no `target_hit` on the source or the burst turret, both at full health; at least one
   outsider hit; and the band crossed the source's position outside a gap on some tick (`|radius() − 78| ≤ band/2` and `not in_gap(bearing)`), so the
   "spared" assertion is not vacuous.
9. **`test_the_power_source_draws_a_line_to_each_powered_turret`** — `assault_pair`: `power_lines()` has 2 lines ending at the two turrets; kill the burst turret
   -> 1 line; kill the source -> the group is dark and `power_lines()` is empty in that same call.
10. **`test_assault_wave_builder_spawns_one_group_and_three_members_through_a_real_wave_manager`** — `WaveBuilder.new().turret_group(TURRET_GROUP_ASSAULT_PAIR)`
    `.at(−64, −220)` in a `wave(0.0, …)`: the entry's `ship_scene.resource_path` is the preset; through a real `WaveManager` (Assault harness, container
    `Node2D`) after a few frames the container holds exactly one `TurretGroup` and three members (two `DefenseTurret`, one `PowerSource`), the burst turret's
    pool resolves its container (`BulletPool._container`) to the container. **The anchor on the real path (N3):** the camera's physics is switched off and
    its `offset` set to (−100, 0) before the wave triggers; a `WaveManager.enemy_spawned` handler records `cam.offset.x` (−100, asserted non-zero) and the
    group's x is still 512.
11. **`test_assault_a_group_drifting_out_never_costs_the_combo_and_a_drifted_source_does_not_darken`** (B2, N7) — real `ScoreTracker` (`_combo` 4.0,
    `_process` off: the t6 row's set-up); `assault_pair` spawned near the bottom of the projectile world rect, the group itself announced with
    `EventBus.enemy_spawned_orphan` too (the handler `WaveManager.enemy_spawned` reaches); the shipped `power_source_config.tres` has `counts_as_escape` false
    and so does the live source. Step the source's `AssaultDrift` past the rect's end: it is freed without dying, and after a frame `is_powered()` is still
    true and neither turret is UNPOWERED. Drift the turrets out too: the group frees itself after the last; the combo is still 4.0 and the total score
    unchanged. Control: a fixture enemy (`counts_as_escape` true) freed the same way costs the 0.75× penalty.
12. **`test_open_space_a_slot_sets_its_members_variant_and_rest_bearing`** (N2) — a code-built group: a slot with `variant` LANCE and `rest_bearing_deg` 270
    gives a turret whose first mount is a lance with `rest_bearing_deg` 270; a slot with the defaults (−1, NAN) gives the turret scene's own burst cannon at
    its authored 90.

Elsewhere:
- Roster: `power_source` in the hand `ROSTER`s of `test_enemy_hurtbox_geometry.gd`, `test_contact_hitbox_geometry.gd` (`no_hitbox`) and
  `test_enemy_contact_damage.gd` (`no_hitbox`, its config); `test_wreck.gd::_SHIP_SCENES`; `test_base_enemy.gd` `_MIN_ROSTER_SIZE` 15 and
  `_AUTHORED_CONTACT_MODES["power_source"] = NONE` (no brain, so no tow-table row; the generic lethal flow and mask 1121 sweep cover it).
- `test_enemy_dual_mode.gd::test_power_source_powers_its_group_in_both_modes_and_drifts_only_in_assault` — a code-built group (one burst turret, one source):
  the source is in `enemies`, `provides_power()`, refuses a tow, drifts `assault_drift_speed`·t only in Assault; killing it darkens the turret in both modes.
- `test_engagement_deadline.gd::test_no_enemies_cleared_section_spawns_a_turret_group` — no level-1 `ENEMIES_CLEARED` section spawns a scene under
  `assault/scenes/structures/turret_group/` (vacuous until t19 places one; it is the guard §2.10 asks for).
- Automatic sweeps the new files must pass: config isolation, mover single-writer, signal arity, project load, UID integrity, sprite transparency (no
  textures: code-drawn), collision-layer names (layers 512 / 65 / 1 only).

## Risks
- **Deferred spawn in tests.** Rows that need hand-ticked members call `spawn_members()` synchronously; row 1 pins the deferral itself. The deferred
  call then finds the group already spawned and returns.
- **Shared rng.** Group-spawned turrets' brains randomise their rng (`rng_seed` 0); only rows 6 and 8 depend on it — row 6 uses ring turrets (no aim, so
  the scan offset is irrelevant), row 8 re-seeds the ring turret's rng.
- **Gate time (1.2 s).** Hand-ticked rows; the 10 s shutdown run is 600 steps × 3 turrets × 2 harnesses (comparable to t7's power-down row). Rows 1, 4, 10
  and 11 wait on real frames (≤ 5 frames each). Estimate ~0.7 s.
- **`NAN` export.** If Godot 4.6 does not round-trip a NAN export default, the fallback is a `bool override_rest_bearing` + a 90.0 value (same
  behaviour), logged in DECISIONS.md.
- **Order of `died` handlers.** `ScoreTracker` also listens to the source's `died`; order is irrelevant (the shutdown only sets flags).

## Out of scope
The shield generator and its preset (t9s); the hub preset (t17/t18); level-1 placement and its column row (t19); art (t15); re-powering (Ph20);
mounting turrets on ships (Ph10). The group does not drift in Assault (it is a coordinator; its members drift).

## Round-2 notes taken (review APPROVED)
R2-1: row 11 turns every member's drift off at spawn (the `_spawn` helper does) and places the group 100 px above the rect's end. R2-2: row 1 disconnects its
`EventBus` handler; the ScoreTrackers of rows 4 and 11 are `add_child_autofree`d. R2-3: row 4's tracker has `_process` off.
