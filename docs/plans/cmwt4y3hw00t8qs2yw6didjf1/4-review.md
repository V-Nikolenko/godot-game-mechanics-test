VERDICT: CHANGES_REQUESTED

# Review: Phase 11 t9, Space Fortress art (round 1)

Reviewed `3-plan.md` and `1-context.md` against the code: `space_fortress.tscn`, `space_fortress.gd`, `global/components/enemy_module.gd`,
`global/boss/boss_reinforcements.gd`, `global/components/bullet_pool.gd`, `assault/scenes/enemies/defense_turret/mounts/turret_mount_builder.gd`,
`global/components/state_light.gd`, `tests/integration/test_ph10_sprites.gd`, `test_entity_sprite_transparency.gd`, `test_space_fortress.gd`, and epic
§2.5.1 / §2.5.2 / §2.9 (`docs/plans/cmug256so0031m52wbxomst72/3-plan.md:315-348, 667-683`).

The design is sound and right-sized. The texture list covers every §2.9 item. Sizes match the frozen hurtboxes (`space_fortress.tscn:33-46`: battery r 22 -> 44,
hangar 36 x 56, generator r 26 -> 52, core r 44 -> 88, hull canvas 384). The hangar hook is the simplest correct option. Four items have to change before
implementation: two would make the new gate fail or force bad art, one is a silent rename, and one is missing docs.

## Required changes

1. **Test 9's instance walk fails on a correct build** (plan line 74-75). It asks that "every texture-valued property of every node of an instance
   resolves under `space_fortress/` or `turret_head_`". A readied fortress breaks that rule in two places:
   - `TurretMountBuilder.build()` adds each mount's `BulletPool` as a **root child** (`turret_mount_builder.gd:33-38`), and `BulletPool._ready()` fills
     itself with idle projectiles as its own children (`bullet_pool.gd:63-78`). The ROCKET_BATTERY mount (`space_fortress.tscn:456`, variant 2) therefore
     parents rockets under the fortress, and they carry `res://assault/assets/sprites/projectiles/enemy_rocket.png` and the cluster, warhead and
     submunition PNGs (`assault/scenes/projectiles/enemy_rockets/*.tscn:9`).
   - Every part's `Light` (`StateLight`) builds a `GradientTexture2D` in code with an empty `resource_path` (`state_light.gd:42, 93-102`).

   Restrict the check to the authored scene: walk `space_fortress.tscn`'s `PackedScene.get_state()` (the transparency sweep's method), or skip
   `BulletPool` subtrees and textures with an empty `resource_path`. The `.tscn` text check for `station_` stays as written.

2. **Test 1's opacity bounds contradict each other for the overlay** (plan line 61-62). The row asks every file for "15 % < fully-opaque fraction",
   then sets the overlay's ceiling at "at most 35 % non-transparent". At 384 x 384 the floor means more than 22 000 fully opaque crack pixels, about a
   quarter of the hull disc (r 176 ≈ 97 000 px). A crack-and-glow overlay is mostly semi-transparent glow. The art would be forced heavy, or the row
   would fail. Give the overlay its own row, for example "> 1 % non-transparent, ≤ 35 % non-transparent, corners alpha 0, no centre requirement". State
   plainly which bounds apply to which files, because the parenthesis in line 61-62 is ambiguous.

3. **The hull file name departs from §2.9 without a recorded reason** (plan line 15). Epic §2.9 (`3-plan.md:674`) names `fortress_hull.png`; the plan
   uses `hull.png`. Every other file name is the plan's own choice, which is fine, because §2.9 names only the hull. Use `fortress_hull.png`. If
   `hull.png` is kept for the Ph10 folder convention (`heavy_gunship/hull.png`, `carrier/hull.png`), record the deviation in DECISIONS. A silent rename is
   not acceptable.

4. **Docs are under-scoped** (plan step 8). The plan adds an export (`hangar_open_texture`), a door-art hook and six new nodes. CLAUDE.md
   ("MANDATORY — keep the docs current") requires the `updating-project-docs` skill for that. Ph10 t9 added a CLAUDE.md line naming its art gate
   ("Art of both heavies (t9) … gates `test_ph10_sprites.gd`"), and this task should do the same for `test_fortress_sprites.gd` and the hangar hook. Also
   update the export comments "placeholder until t9" at `space_fortress.gd:39-42`, and the header line about t9 at `space_fortress.gd:6`, if it changes.
   State in the plan that the `pixel-art-generation` skill is invoked before any PixelLab call (§2.9 and CLAUDE.md both require it; the plan only implies
   it).

## Verified correct (no change needed)

- **Hangar hook timing and wreck safety.**
  - `_reinforcements` is created in `_ready()` at `space_fortress.gd:126`, so connecting right after it is valid. It is never reassigned
    (`fortress_brain.gd:144` only keeps a reference).
  - `door_changed(bay_id, true)` fires on OPENING (`boss_reinforcements.gd:254-270`), which is when the doors start, `door_seconds` 0.8 before the launch,
    the Ph10 timing. `false` fires on `_close` (`:293-300`, including `_hold` on inactive) and on `_kill` (`:394-399`).
  - `_kill` runs from `module_destroyed`. `EnemyModule.destroy()` sets `_destroyed`, writes `wreck_texture` and only then emits `destroyed`
    (`enemy_module.gd:207-240`). So when the closing `door_changed(false)` arrives, `is_destroyed()` is already true and the guard keeps the wreck.
  - Filtering on `bay_id == &"hangar"` is necessary, because both generators' bays (`north_defenders`, `south_defenders`; `space_fortress.tscn:514-538`)
    emit `door_changed` too.
  - `opens_part` / `set_vulnerable` are independent of the sprite, and no existing test asserts the hangar's sprite.
- The rejected `CarrierHangarDoors` alternative is correctly rejected: `BossReinforcements` writes no `open_amount`, and adding a door node to the
  generic `global/boss` class would be churn.
- **Existing gates.**
  - `test_space_fortress.gd:512-529` (shutter and plating swaps, `core_open_texture != intact_texture`) holds with real, distinct art.
  - M9 (`test_space_fortress.gd:1281-1311`) drives `Thrusters.modulate`; child `Sprite2D`s inherit it, so "visibility logic unchanged" is right. This is
    also how §2.9's "visible while repositioning" is met. Say so in ENEMY.md.
  - `test_entity_sprite_transparency.gd::test_the_station_core_has_sky_around_it` still finds `station_core.png` through `space_station.tscn` once the
    fortress stops referencing it.
- **Opacity budget.** Disc art (hull about 66 %, round parts at most 78.5 %) stays under the 90 % ceiling. The 36 x 56 hangar must not fill its rectangle,
  the same constraint the Ph10 carrier hangar met.

## Suggestions (non-blocking)

- Test 6: add one row driven by the real door cycle, not only a direct `emit`: `f.reinforcements().surge(&"hangar", 1)` then `tick(0.0, true)` opens the
  doors with no launch (`door_seconds` 0.8). Assert the open art, then `destroy()` the hangar and assert the wreck stays. This also pins the scene's
  `Bay.bay_id` (`space_fortress.tscn:499`), which a literal `&"hangar"` emit cannot catch.
- Test 3: pin `ShieldSouth/Sprite.flip_v == true` and north `false`, as Ph10 pinned `flip_h` (`test_ph10_sprites.gd:146`). Without that row the flip
  could be lost silently.
- Draw order: `Thrusters` and `CriticalOverlay` come before `Modules` (`space_fortress.tscn:183-189`), so the overlay draws under the parts. That fits
  "cracks over the ring". Check it in the critical composite rather than assume it.

---

VERDICT: APPROVED

# Review: Phase 11 t9, Space Fortress art (round 2)

I re-read the revised `3-plan.md` and checked it against the code again. All four required changes and both suggestions are in, and each one is correct
for the real code.

## Round-1 findings, resolved

1. **Test 9** (plan line 76) now walks `space_fortress.tscn`'s own `PackedScene.get_state()`. That state holds only what the scene authors: the root
   exports (`shutter_open_texture`, `core_open_texture`, the new `hangar_open_texture`), each part's `intact_texture` / `wreck_texture` and `Sprite.texture`,
   and the new thruster and overlay sprites. It leaves out the mounts' pooled rockets (`turret_mount_builder.gd:33-38`), the code-built `StateLight` glow
   (`state_light.gd:42`) and the mount heads, which `TurretMountBuilder` adds at runtime. The instanced `fortress_spoke_beam.tscn` / `fortress_pulse_ring.tscn`
   author no texture. Requiring the hull and part `Sprite`s to be among the walked textures stops an empty walk from passing.
2. **The overlay** has its own row, 1b (plan line 63): 1 % < visible < 35 % and fully opaque < 20 %. The bounds no longer contradict each other, and the row
   can still fail on a card (corners alpha 0, the ceilings) or on an empty image (the 1 % floor).
3. **The hull file is now `fortress_hull.png`** (plan line 15), the §2.9 name.
4. **Docs** (plan step 8): `updating-project-docs` is invoked, with a CLAUDE.md line, the module docs, the stale comments at `space_fortress.gd:39-42` and the
   file header, and DECISIONS. "How it is made" (plan line 31) names the `pixel-art-generation` skill.

## Suggestions taken

- **6b (plan line 71)** works on the real code. `surge(&"hangar", 1)` queues a launch on a live bay whatever its activation (`boss_reinforcements.gd:143-147`).
  `tick(0.0, true)` then reaches `_open` from CLOSED with a queue (`:126-128`). The Assault limit is not reached (`launches` 0), and `_room()` is the live cap
  with no escorts, so `door_changed(&"hangar", true)` is emitted (`:270`).
- **The `flip_v` pin** is in test 3 (plan line 66).

## Scripted pixel edit (new sentence, plan line 35): acceptable

The `pixel-art-generation` skill itself makes a throwaway headless Godot project in `/tmp` the sanctioned image tool (`SKILL.md:157-168`). It also prefers
post-processing art that is already right in angle and palette over a regeneration, so the set stays consistent (`SKILL.md:184-188`, the `strip-sprite-bg.sh`
rationale). Fixing a misplaced socket by script is the same kind of change. It cannot alter the viewing angle, it writes through `Image.save_png()` (not the
Write tool, which `SKILL.md:115` forbids for PNGs), and the plan names every edit in DECISIONS. One condition, which I read as already implied by "Every
image is opened at 4–6× and in a composite": the 6× view and the in-layout composite must be redone **on the edited file**. A painted-in well that looks
pasted on is "only serviceable" art under `SKILL.md:140-145`, and that means regenerate or hand-draw, not ship.

## Nits (non-blocking)

- Test 1 says "all 23 files". The table lists 22 (hull 1, batteries 10, hangar 3, generator 3, core 3, thruster 1, overlay 1), and 21 once the overlay moved
  to 1b. Fix the count in the comment; the row reads the table, so the test is unaffected.
- 6b and 6: set `set_physics_process(false)` on the fortress, as Ph10's `_fresh()` does (`test_ph10_sprites.gd:94-98`), or keep every assertion in the same
  frame as the `tick()`. Otherwise `BaseEnemy`'s physics tick lets the not-yet-engaged brain tick the reinforcements with `active` false, and `_hold` shuts
  the doors (`boss_reinforcements.gd:120-122, 304-308`). To end the cycle without spawning escorts, `tick(0.0, false)` closes the doors with no launch.
  Ticking past `door_seconds` + `open_hold_seconds` also works, but it spawns swarm drones into the escort container.
