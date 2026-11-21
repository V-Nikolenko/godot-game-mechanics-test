# t2 — Destructible enemy parts: `EnemyModule` and `ModularHull`

Task plan for Phase 10 t2. The design is the epic's approved plan (`docs/plans/cmug23oo90029m52wae4clve0/3-plan.md` §2.1, §2.2 without
`build_mounts`, §2.15); this file fixes the build-level choices that plan leaves open and the test list. It does not redesign anything.

**Revision 2** (after review round 1, `4-review.md`): DAMAGED reuses `LowHealthSmoke` (B1); the fixture pins every id, role, authored
hurtbox value and `Health` a row reads (B2); direct-children collection (M1); `is_armored()` on a part (M6); rows 4, 5, 6, 7, 11, 12, 13,
14, 15 and 16 tightened (M2–M5, M7).

## Problem

Today a large enemy is one health bar. The player cannot shoot a gun off a ship, cannot see a ship come apart, and nothing the game has
can say "this part is armoured until something opens it". The only precedents are bespoke: the station's `StationTurret` (stays as
wreckage, but only for the station) and the Ram's `ArmorPlate` (resolves a hit once, but breaks and vanishes, and a shield can never
cover it). Phase 10's two heavies (t4–t8) and the Ph11 / Ph12 bosses need one reusable part: it takes its own damage, can be locked,
type-filtered or shielded, and stays on the hull as dark wreckage when it dies. After this task the part exists and is proven on a
fixture; no shipped enemy uses it yet, so the player sees no change.

## Design

### `global/components/enemy_module.gd` — `class_name EnemyModule extends Node2D`

Scene shape, exports, signals and API exactly as §2.1. Build-level choices:

- **`_ready()`**: join `&"enemy_parts"`; resolve `Sprite` (`Sprite2D`), `HurtBox`, `Health`, `DefenseProfile`, `HomingPoint`, `Light`
  children by name. Write `intact_texture` onto `Sprite` when set. The `HurtBox` gets layer `ENEMY_HURTBOX` (512); a child
  `DefenseProfile` is applied with `apply_to(hurt_box)`, otherwise the module writes the §2.1 default mask
  `PLAYER_HITBOX | PLAYER_ROCKETS | HAZARD_CONTACT` (1120) and leaves `accepted_damage_types` empty. With `max_health > 0` the export is
  written into `Health` (max and current; a `Health` is created when the scene authors none, the `ArmorPlate` precedent); with
  `max_health == 0` `Health` is never read or written. Connects `received_damage`, `area_entered`, `area_exited`. Builds two
  `HitEffect`s (the default orange burst, and a white ping for deflections).
- **One decision point, `_resolve(hit_box) -> bool` (true = consume)**, cached per HitBox instance id, stale ids swept, erased on the
  hurtbox's `area_exited` (the `ArmorPlate` shape). Deflect when: wreck from an earlier physics frame
  (`_destroyed and _destroyed_frame < Engine.get_physics_frames()`), or `not _vulnerable`, or the hit's type is not in the hurtbox's
  `accepted_damage_types` (empty = all). Destruction never clears `_vulnerable`, so a part killed this physics frame still answers
  consume: the killing shot is spent whichever `area_entered` Godot runs first. `deflects_hit(hit_box)` = `not _resolve(hit_box)`
  (null → true). The resolver never applies damage.
- **Damage only through `HurtBox.received_damage(damage)`** (after the hurtbox's type filter and absorber slot). Handler: destroyed →
  ignore; not vulnerable → `deflected.emit(self)` + white ping, nothing else; else `Health.decrease(damage)` unless `max_health == 0`,
  `damaged.emit(self, damage)` (the incoming amount, so an indestructible part still reports and forwards it), orange burst, sparks
  on reaching DAMAGED, then destruction when `Health` reached 0. Order is always `damaged` before `destroyed`.
- **`deflected` fires once per refused hit, from whichever filter refused it:** the vulnerability refusal fires it from the
  `received_damage` handler (above); a HitBox the hurtbox's own type filter drops never reaches `received_damage`, so the module's own
  `area_entered` handler fires it for that case (live, type not accepted). An absorbed hit fires neither (the shield flares itself).
  Direct emitters (beam, nova, `LaserRay`) skip both `HurtBox` filters: only the vulnerability check stands between them and a part
  (§2.1, review finding 11), so a LASER-only part *is* hurt by the nova. That is the project rule for direct emitters (they also bypass
  `EnemyShield`), written down in DECISIONS.
- **`destroy()`** (and `Health` reaching 0): once only. `_destroyed_frame = Engine.get_physics_frames()`; leave `enemy_parts`;
  `monitoring`, `monitorable` and every hurtbox shape's `disabled` set **deferred** (`station_turret.gd` reasons); every attached mount
  `power_down()`; `Sprite.texture = wreck_texture`, or, with none, `Sprite.modulate = WRECK_TINT` `Color(0.35, 0.35, 0.4)` (on the
  child, because `BeamBehavior` writes heat on the module node); sparks off; `Light` off (`StateLight.set_state(OFF)`, else hidden); an
  `ExplosionEffect` into the host's parent (host = the `Modules` node's parent); `destroyed.emit(self)`. The node stays in the tree.
  `destroy()` also works on a locked part and on a `max_health` 0 part (a scripted kill); damage never destroys a `max_health` 0 part.
- **`set_vulnerable(on)`**: no-op on a wreck or when unchanged; else `vulnerability_changed.emit(self, on)`. Cached decisions are kept
  (a HitBox already inside keeps its answer until it exits, the plate rule).
- **`visual_state()`**: WRECK if destroyed; DAMAGED when `max_health > 0` and current ≤ `damaged_ratio × max_health`; else INTACT.
  DAMAGED reuses `LowHealthSmoke` (`global/components/low_health_smoke.gd`, review B1): a part with `max_health > 0` gets one child
  `LowHealthSmoke` named `Sparks`, `threshold = damaged_ratio`, a spark colour and faster particles, `setup(health)`; it emits exactly
  while `0 < current <= damaged_ratio × max` (its own rule), stops on a kill by damage, and `destroy()` calls `deactivate()` for a
  scripted kill above 0 HP. No new emitter code.
- **`is_armored()`** (review M6) = `_destroyed or not _vulnerable`. Projectiles never see it (`ArmorQuery` asks `deflects_hit` first);
  it is what `EnemyShield` reads, so a shield on a locked part absorbs nothing (the armoured-host rule) instead of spending points on a
  bullet the part then lets through.
- **`homing_point()`**: `HomingPoint` marker's global position, else the module's. **`mounts()`** returns a copy;
  **`attach_mount(mount)`** appends (and powers it down at once on a wreck). Mount rows are t3's.
- Accessors (the `ArmorPlate` idiom): `hurt_box`, `health`, `sprite` vars; `is_destroyed()`, `is_vulnerable()`.

### `global/components/modular_hull.gd` — `class_name ModularHull extends Node`

Child of the host root, named `ModularHull`. `_ready()`: host = parent; collects the **direct** `EnemyModule` children of the sibling
`Modules` node in tree order (`Modules/*`, review M1; the module finds its host the same way: `Modules`'s parent), connects `damaged` / `destroyed`, resolves the host's `Health` child by
name (null → no forwarding). Signals `module_destroyed(module: EnemyModule)`, `module_damaged(module: EnemyModule, amount: int)`.
On `damaged`: forwards `roundi(amount × hull_share)` to the host `Health` when `hull_share > 0` and the result is > 0, then re-emits.
On `destroyed`: re-emits once (the module emits once). Queries `modules()` (copy), `module(id)`, `live(role)` (not destroyed),
`destroyed_count(roles: Array)` (empty array = any role), `mounts_of(id)` (empty when no such module). No gameplay rule of either
heavy. `build_mounts` is t3's.

### Player direct emitters

- `beam_behavior.gd`: `all_targets` also appends `get_nodes_in_group("enemy_parts")`; nothing else changes (a part is burned when its
  centre is within 12 px of the line; the heat tint lands on the part node).
- `plasma_nova_module.gd`: the damage loop runs over `enemies` then `enemy_parts` (map-wide, 50 each, same `HurtBox` lookup).
- `EnergyHitScan.VICTIM_GROUPS` is **not** changed (a row pins that enemy energy weapons never reach a part).

### Fixture `tests/helpers/fixture_modular_host.tscn` + `.gd`

A `BaseEnemy` (no `class_name`, the `fixture_enemy` idiom) in group `enemies`: root body and root `HurtBox` one 240 × 60 rectangle
(body on the default layer 1, so the beam's block ray meets it), `Health` 1000, `HitFlashAnimationPlayer`, `Modules` with three
12 px-circle parts 80 px apart, each `max_health` 100 and `hull_share` 0, and a `ModularHull` (review B2 / M5 pin every value a row
depends on):

| Part | `module_id` / `role` | At | Authored children |
|---|---|---|---|
| `Open` | `&"open"` / WEAPON | (−80, 0) | `Sprite` (intact texture), `wreck_texture` set, `HurtBox`, `Health` authored **10 / 10** (the export overwrites it to 100), `HomingPoint` at (0, 12), `Light` (`StateLight`) |
| `Locked` | `&"locked"` / CORE, `starts_vulnerable` false | (0, 0) | `Sprite`, no `wreck_texture` (tint path), `HurtBox`, `Health` 100 / 100 |
| `Laser` | `&"laser"` / ENGINE | (80, 0) | `Sprite`, `HurtBox`, **no `Health`** (the module creates one), `DefenseProfile` with default flags (mask 1121) and `accepted_damage_types` [LASER] |

Every part `HurtBox` authors `collision_layer = 0`, `collision_mask = 0` and no `accepted_damage_types`, so a layer, mask or type the
rows read can only have come from `EnemyModule._ready()` (and 1121 ≠ the no-profile default 1120). The root answers `deflects_hit` → true, `is_armored()` → true, `is_laser_blocking()` → false and
refuses every root damage (`_on_received_damage` is a no-op), so a projectile always reaches the part it is aimed at and the root never
changes health except through `hull_share`. Textures are existing station-turret PNGs (the transparency gate does not sweep `tests/`).
UID-less.

### Rejected alternatives

- *Damage in the resolver (the `ArmorPlate` way)*: it would bypass the hurtbox's absorber, so a local `EnemyShield` could never cover a
  part (the Ph5 limitation the epic plan removes).
- *A real Assault player for the beam row*: `BeamBehavior.tick()` is the code that changes; the existing `BeamDriver` (three gates use
  it) drives that exact code without a player scene's input, weapon state and HUD. Logged as a deviation from §2.1's wording.
- *Emitting `deflected` from the resolver*: the resolver runs once per HitBox from two callbacks in undefined order and never sees a
  direct emitter, so it cannot give "once per refused hit" for both paths.

## Build sequence

1. Progress notes; fixture scene + script; `tests/integration/test_enemy_module.gd` with every row below → run: red (no classes).
2. `enemy_module.gd` → module rows green.
3. `modular_hull.gd` → hull rows green.
4. `beam_behavior.gd`, `plasma_nova_module.gd` → emitter rows green; energy-weapon row green without touching `EnergyHitScan`.
5. Regression: `test_space_station.gd`, `test_station_incoming_damage_paths.gd`, `test_ram_corvette.gd`, `test_defense_turret.gd`,
   `test_armor_query.gd`, `test_enemy_shield_hits.gd`, `tests/unit/test_enemy_shield.gd`, `test_energy_ring.gd`, `test_enemy_beams.gd`,
   `test_laser_ray_hit_mask.gd`, `test_signal_emit_arity.gd`, `test_project_load_integrity.gd`, `test_collision_layer_names.gd`,
   `test_resource_uid_integrity.gd`, `test_suite_integrity.gd` (untouched files, all green).
6. Own-file time (`-gselect` with a junit file), `scripts/check-test-leaks.sh`, two `scripts/gate-time.sh` runs after (two before were
   taken on a clean `git archive HEAD` copy), `tests/README.md` row, `DECISIONS.md` "Phase 10, built in t2", docs
   (`updating-project-docs`: `global.md` components, `PROJECT.md` conventions, CLAUDE.md line), `bash /agent/verify.sh`.

## Test plan — `tests/integration/test_enemy_module.gd`

Real-physics rows on the 8× clock (`_scale_clock` / `_restore_clock` pattern), launched like `test_enemy_shield_hits.gd::_fire`
(`expired -> queue_free`). Hand-ticked rows need no physics. The direct-emitter rows that need no physics run in both harnesses
(`use_parameters(MODES)` with labels); the host does not move in any t2 row, so projectile rows run in one world (§2.1: "both harnesses
where the host moves").

Real physics:
1. `test_a_bullet_into_the_open_part_is_consumed_and_hurts_only_that_part` — consumed; Open 100 → 50; host `Health` 1000 unchanged
   (`hull_share` 0, the armoured root refused the crossing); Locked / Laser unchanged.
2. `test_a_bullet_through_the_locked_part_flies_on_until_the_part_is_made_vulnerable` — not consumed, no `expired`, Locked unchanged,
   `deflected` exactly once; `set_vulnerable(true)` → `vulnerability_changed(Locked, true)` once; the next bullet is consumed, −50.
3. `test_a_rocket_against_the_laser_only_part_flies_on_and_does_no_damage` — a warhead: not consumed, Laser unchanged, `deflected` once
   (type filter path); control: a bullet (LASER) into Laser is consumed and deals 50.
4. `test_the_wreck_stays_on_the_hull_and_lets_later_shots_through` — two bullets kill Open (the second, killing shot, is consumed);
   after 2 s game time: still a child of `Modules`, `visual_state()` WRECK, `Sprite.texture` is `wreck_texture`, out of
   `enemy_parts`, hurtbox `monitoring` / `monitorable` false and shape disabled, a third bullet flies on, `destroyed` once,
   `ModularHull.module_destroyed` once, host alive; the recorded order is `damaged`, `module_damaged`, `destroyed`, `module_destroyed`
   (review M5).
5. `test_a_local_shield_on_a_part_eats_a_frontal_bullet_and_not_a_rear_one` — `EnemyShield` (arc 110, facing down) attached to Open's
   hurtbox: a bullet from below is consumed with Open unchanged; one from above lands (−50). Host `is_armored()` true does not disable
   it (the shield's host is the part). Same row (review M6): a second shield on Locked's hurtbox absorbs nothing, its points stay
   full and the bullet into Locked flies on (`is_armored()` true while locked).
6. `test_the_beam_burns_the_open_part_and_never_the_locked_part_or_the_armoured_root` — two `BeamDriver`s (real `BeamBehavior`,
   `mining_laser.tres`) under Open and Locked for 2 s: Open loses health, Locked unchanged with `deflected` emitted, root 1000.
   Then `Locked.destroy()` (tint path) and `Open.destroy()` (texture path), 0.25 s more beam, the drivers stop, and
   `behavior.cool_targets(0.5)` (review M2): Locked's node `modulate` reads (1, 0.5, 0.5) (the beam wrote the node, heat 1.0 → 0.5)
   while its `Sprite.modulate` is still `WRECK_TINT`, and Open's `Sprite.texture` is still its wreck texture.
7. `test_a_lit_laser_ray_destroys_the_open_part_and_spares_the_locked_one` — two `LaserRay`s across Open and Locked, `auto_start`,
   `warn_duration` and `active_duration` 0, opened by hand (review M3): `start()`, `_begin_increase()`, then `_on_animation_finished()`
   while the master segment plays `laser_increase`, which enters IDLE and switches the `HitZone` on (no `SceneTreeTimer`; the 0.1 s
   `Timer` is a child freed with the ray); then physics frames: Open destroyed (through `received_damage`), Locked intact with `deflected`, host alive at 1000.

No physics (hand-driven):
8. `test_the_killing_shot_is_consumed_whichever_callback_runs_first` — order A: `deflects_hit` (false) then `received_damage` kills;
   order B on a fresh host: `received_damage` kills, then `deflects_hit` → false; boundary: one physics frame later a new HitBox is
   deflected (wreck from an earlier frame).
9. `test_an_indestructible_part_is_never_destroyed_and_still_forwards_its_damage` — `max_health` 0, `hull_share` 1.0, host `Health`
   20 000: 10 000 damage → not destroyed, INTACT, `damaged` carries 10 000, host −10 000.
10. `test_hull_share_forwards_the_rounded_share_to_the_host` — 1.0: host −50 for 50; 0.5: −13 for 25 (`roundi(12.5)` = 13); 0: nothing.
11. `test_a_parts_own_defense_profile_is_applied_to_its_hurtbox` — Laser: mask = profile mask, types [LASER]; Open (no profile):
    layer 512, mask 1120, types empty (every part hurtbox authored 0 / 0 / none). Open's authored `Health` 10 / 10 reads 100 / 100;
    Laser, which authors none, has a created `Health` at 100 / 100.
12. `test_the_nova_damages_every_live_part_on_the_map_and_never_a_locked_one` (both harnesses) — two hosts **4000 px apart** (review M4), one with Open
    already destroyed: every live vulnerable part −50 (Laser too: a direct emit skips the type filter), Locked unchanged with `deflected`, the
    wreck unchanged, both roots 1000.
13. `test_enemy_energy_weapons_never_reach_a_part` (both harnesses) — an `EnergyRing` centred on the host, started with an explicit
    gap start of 90° (review M7, so the root is never in a gap), and an `EnemyBeam` swept
    across it, hand-ticked through their full cycles, host not in their owner set: every part's health unchanged, no `damaged`; the
    root was a candidate (control: the ring's `target_hit` / the beam's `target_hit` reached the root).
14. `test_the_hull_collects_its_parts_in_tree_order_and_answers_queries` — `modules()` = [Open, Locked, Laser]; `module(&"locked")`;
    `module(&"none")` null; `live(WEAPON)` = [Open], `live(CORE)` = [Locked], `live(HANGAR)` empty; after `Open.destroy()`: `live(WEAPON)` empty,
    `destroyed_count([WEAPON])` 1, `destroyed_count([CORE, ENGINE])` 0, `destroyed_count([])` 1 (any role); `mounts_of(&"open")` and
    `mounts_of(&"none")` empty.
15. `test_destruction_is_once_only_and_reemitted_once` — `destroy()` twice + damage after: `destroyed` 1, `module_destroyed` 1,
    no `damaged` after the wreck, `live()` drops it, `set_vulnerable` on a wreck emits nothing; Open's `Light` (set ARMED first) is OFF; the destruction burst is a
    `CPUParticles2D` child of the host's parent, not of `Modules` (review M5).
16. `test_visual_state_goes_from_intact_to_damaged_to_wreck` — `damaged_ratio` 0.5: 49 damage INTACT with `Sparks` not emitting, 1 more
    DAMAGED with `Sparks` emitting, kill by damage → WRECK with `Sparks` stopped; a second part taken to DAMAGED then `destroy()`ed above
    0 HP → `Sparks` stopped (`deactivate()`) (review B1 / M5).
17. `test_homing_point_is_the_marker_else_the_part_centre`.

Boundary cases: row 8's next-frame deflect; row 10's 0 share; row 3's control; row 13's control; row 14's excluding role set.
Gate time: ≤ 2.0 s for the file (≈ 7 real-physics rows at 8×, longest 2.5 s game ≈ 0.35 s wall).

## Risks

- **Self-reference leak** (`enemy_mine.gd` trap): `EnemyModule` names itself in its signals. `ArmorPlate` / `StationTurret` do the same
  leak-free; `scripts/check-test-leaks.sh` decides. Fallback: `Node2D`-typed signal parameters, logged in DECISIONS.
- **Beam / nova regressions**: the station's turrets and the Ram's plates are not in `enemy_parts`, so existing rows are unaffected;
  the regression list in step 5 proves it.
- **Nova flash canvas** left in the root after a hand row: the row frees the nova's `CanvasLayer` itself.
- `test_project_load_integrity.gd` only loads the fixture and asks `can_instantiate()` (review M8): nothing of the module runs there.

## Out of scope

`build_mounts`, `TurretMountBuilder`, mount rows and unique pool names (t3); any heavy enemy, `homing_point(from)` on a host, the
flush-edge rule (t4+); `EnergyHitScan` changes (Ph18 / Ph19); art (t9); the station and Ram plates (unchanged).
