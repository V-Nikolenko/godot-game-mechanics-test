VERDICT: CHANGES_REQUESTED

# Review of `3-plan.md` (t2: `EnemyModule` and `ModularHull`), round 1

Reviewed against the epic plan (`docs/plans/cmug23oo90029m52wae4clve0/3-plan.md`: "For every task", §1.3, §2.1, §2.2, §2.15), the
Phase 10 section of `DECISIONS.md`, `CLAUDE.md`, `tests/README.md` (house rules, Gate time) and the code itself. The design follows
§2.1 / §2.2 closely. The killing-shot rule, the two `deflected` sources, the direct-emitter rule, the wreck tint on the `Sprite` child
and the beam / nova / `EnergyHitScan` split are all correct against the code (verified list at the end). Two changes are needed
before implementation. Both are small plan edits, not redesigns: one part reinvents a component that already exists, and the
fixture is described too loosely for two rows to fail on a broken build.

## Blocking

**B1. The DAMAGED spark emitter duplicates `LowHealthSmoke` (`3-plan.md:52-53`; `global/components/low_health_smoke.gd:1-57`).**
The plan has a code-built `CPUParticles2D` that starts on first entry to DAMAGED and stops on WRECK. `LowHealthSmoke` already does
this. It is a `Node2D` holding a continuous `CPUParticles2D`. `setup(health)` connects it to `Health.amount_changed`. It emits
exactly while `current / max <= threshold and current > 0`, which is the plan's DAMAGED rule (`<= damaged_ratio × max`) with the
WRECK stop built in. It turns off again on a repair, and `deactivate()` covers a scripted `destroy()` above 0 HP. Colour, amount,
velocity and emission radius are exports, so a spark colour needs no new code. The plan neither names it nor says why not. Fix:
- On a `max_health > 0` part, compose a `LowHealthSmoke` with `threshold = damaged_ratio` and a spark colour.
- Call `deactivate()` from `destroy()`.
- Keep `visual_state()` as the query.
- Or, if its upward smoke stream is wrong for a part, say why and extend it with an export rather than writing a second emitter.

**B2. The fixture leaves out the values rows 11 and 14 depend on, so both can pass on a broken build (`3-plan.md:75-84`, `:145-146`,
`:153-155`).**
- **Roles.** The fixture never sets `role` on the three parts. The export defaults to the first enum value, `WEAPON`, so as written
  all three are WEAPON. Then `live(WEAPON)` equals "every live part" and `destroyed_count([WEAPON])` equals `destroyed_count([])`.
  A `ModularHull` that ignores its `role` / `roles` argument passes row 14. Pin distinct roles and ids in the fixture section.
  Suggested: Open WEAPON `&"open"`, Locked CORE `&"locked"`, Laser ENGINE `&"laser"`. Then add a row-14 assertion that a role set
  containing only the destroyed part's role counts 1, and one that excludes it counts 0.
- **Authored hurtbox values.** Row 11 asserts that Open's hurtbox ends with layer 512, mask 1120 and empty types, and that Laser's
  carries the profile's mask and `[LASER]`. That only proves the module wrote them if the scene authored something else. The natural
  way to author the fixture (copying `fixture_enemy.tscn`'s `collision_layer = 512` / a hand-written mask, or setting the types on the
  `HurtBox` itself) makes the row vacuous. Say in the plan that the fixture's part `HurtBox`es author `collision_layer = 0`,
  `collision_mask = 0` and no `accepted_damage_types`. Laser's types then come only from its `DefenseProfile`, whose default flags give
  1121, which differs from the no-profile 1120. With that, row 11 and every projectile row break if `_ready()` stops writing them.

## Minor

**M1. Nested collection goes beyond the upstream design, has no row, and conflicts with how the host is found (`3-plan.md:47-48`,
`:60-61`).** `ModularHull` walks `Modules` depth-first, so it accepts `Modules/Group/Part`. `EnemyModule.destroy()` finds the host as
"the `Modules` node's parent", which for a nested part is two hops in one case and three in the other. The upstream "For every task"
says `Modules/*`. Either collect direct children only (simpler, and what upstream asks), or define the walk in both scripts (up to the
ancestor named `Modules`, then its parent) and add a nested part to the fixture.

**M2. Row 6's "part nodes' `modulate` is the beam's" clause cannot fail (`3-plan.md:130-134`; `beam_behavior.gd:122-134`).**
- After 2 s of beam the heat is 1.0 (`_HEAT_RATE` 0.7/s, capped). `cool_targets(1.0)` takes it to 0 and writes `Color.WHITE`, which is
  also the untouched default.
- The row still bites where it matters: wreck tint on the module node instead of the `Sprite` child gives `Sprite.modulate` WHITE, so
  the row fails.
- Use `cool_targets(0.5)` so the module node reads `(1, 0.5, 0.5)`. That proves the beam wrote the node and the `Sprite` child kept
  `WRECK_TINT` under it.

**M3. Row 7 needs to say how the ray's HitZone is opened (`3-plan.md:135-136`; `laser_ray.gd:127-129, 211-225`;
`test_level1_laser_columns.gd:92-110`).** The cited `_ray` helper only sets `_phase = IDLE`. That never turns on `HitZone.monitoring`
/ `monitorable`, which happens only in `_on_animation_finished()` for `laser_increase`, so no `area_entered` and no damage. State one of
two ways:
- Let `start()` run `laser_init` → `laser_increase` → IDLE on its own. With `warn_duration` and `active_duration` both 0, that path
  creates no `SceneTreeTimer`; `_continuous_timer` is a child `Timer`, freed with the ray.
- Or set `_phase` and both HitZone flags by hand, then await physics frames.

**M4. Row 12 does not prove "map-wide" (`3-plan.md:147-149`).** Put the second host far outside any plausible radius (for example
4000 px away). As written, two hosts near each other also pass for a range-limited nova.

**M5. Small gaps in the test list.** All are cheap and each can regress silently:
- No row asserts the promised order `damaged` before `destroyed` / `module_damaged` before `module_destroyed` (`3-plan.md:37`). Record
  the order in row 4 or row 15.
- No row checks the DAMAGED emitter, whether B1's reuse or the plan's own: emitting at DAMAGED, stopped at WRECK and after a scripted
  `destroy()`. Add it to row 16.
- No row checks that the destruction burst is parented to the host's parent rather than to `Modules`: a `CPUParticles2D` child of the
  test container after `destroy()`.
- Either "`Health` created when the scene authors none" or "authored `Health` overwritten from `max_health`" goes untested, depending
  on what the fixture authors. Have one part author `Health` and one not.
- No fixture part has a `Light`, so "`Light` OFF on destruction" is untested. A `StateLight` on one part and a one-line assertion
  would cover it.

**M6. A local shield on a locked part (`3-plan.md:38-43`; `enemy_shield.gd:152-164`) is not addressed.** `EnemyShield` holds fire only
while its host answers `is_armored()`. The module answers only `deflects_hit`. Result: a shield on a locked part spends points and
flares on a bullet that the part refuses, and the bullet flies on through it. That is the inconsistency the armoured-host rule exists
to prevent. No t2 content hits it: the Gunship's shielded nose is never locked. Either have the module answer
`is_armored() -> not _vulnerable` (`ArmorQuery` asks `deflects_hit` first, so projectiles are unaffected), or write the combination
down as unsupported in DECISIONS.

**M7. Row 13's ring control (`3-plan.md:150-152`; `energy_ring.gd:158-170, 208-231`).** A ring centred exactly on the host sees the
host at `offset == Vector2.ZERO`, and `ZERO.angle()` is 0. With the default `gap_start_deg` 0, gap 0 sits at 24° when EXPANDING
begins (0.8 s × 30°/s). Its half-width is 22.5°, so the control passes by 1.5°. Pass an explicit gap start (for example 90) so the
control does not rest on that margin.

**M8. A note with no change needed (`3-plan.md:171`).** `test_project_load_integrity.gd:174-188` only calls `can_instantiate()`; it
never instantiates. The conclusion stands.

## Verified as described (no change needed)

- `HurtBox._on_area_entered` order: HitBox cast, then type filter, then absorber (`hit_absorbed`), then `received_damage`, carrying
  the damage only (`hurtbox_component.gd:38-47`).
- `ArmorQuery` asks the hurtbox parent's `deflects_hit` before `is_armored` (`armor_query.gd:18-24`). The fixture root's
  `deflects_hit` → true makes every crossing fly on. `BaseEnemy._on_received_damage` is the virtual that `_ready()` connects
  (`base_enemy.gd:88-90, 287-289`), so a no-op override does refuse root damage.
- `Engine.get_physics_frames()` is incremented in `Main::iteration` before `flush_queries()`. Both `area_entered` callbacks of one
  overlap therefore share a frame number, and an `await physics_frame` advances it, so the row 8 boundary works.
- A consumed bullet is freed at the end of that physics iteration. `set_deferred` hurtbox changes are flushed before the next step,
  following `station_turret.gd:65-96`. Adding `CPUParticles2D` inside a flush is legal (the StationTurret precedent).
- Geometry. The bullet's `HitBox` capsule is about 5 × 10 px after the root scale `(0.236, 0.168)` and moves 15 px per step at 900
  px/s, so it cannot tunnel a 12 px part. Parts 80 px apart and the 56 px `LaserRay` strip never touch a neighbour. A 110 px `SHOT`
  start lies outside the 240 × 60 root.
- Beam:
  - The block ray (`_RAY_BLOCK_MASK` 1 | 1024) meets the layer-1 root body and honours `is_laser_blocking()`
    (`beam_behavior.gd:56-71`).
  - Targets are chosen by centre within 12 px, and the heat tint goes on the target node (`:88-111`), so the wreck tint has to live
    on `Sprite`.
  - The beam under Locked also burns the root, which sits at the same point and refuses it.
  - Mining-laser damage over 2 s is about 55, so Open loses health without dying.
- The nova is a direct emit over `enemies` (`plasma_nova_module.gd:34-41`). Freeing the flash `CanvasLayer` kills its tween.
- `LaserRay` emits 9999 directly on `area_entered` and on a 0.1 s `Timer` in IDLE, with HitZone mask 128 | 256 | 512 and layer 0
  (`laser_ray.gd:263-283`).
- `EnergyHitScan.VICTIM_GROUPS` is player / allies / enemies / asteroids (`energy_hit_scan.gd:17`), so the "never reach a part" row
  fails if anyone adds `enemy_parts` there or puts parts in `enemies`.
- `EnemyShield`'s host is the hurtbox's parent, and the arc bearing is taken from `hit_box.global_position` (`enemy_shield.gd:152-181`),
  so row 5's front and rear cases work under an armoured root.
- `DefenseProfile.apply_to` writes the mask and types. Default flags give 1121; the §2.1 no-profile default is 1120
  (`defense_profile.gd:38-54`).
- Signals naming their own class (`ArmorPlate.broken`, `StationTurret.destroyed`) are the leak-free precedent, and the fallback is
  already listed.
- `roundi(12.5)` is 13 in Godot (half away from zero).
- Acceptance coverage: every listed criterion maps to a row (1–17). Mount rows are deferred to t3, as the task says. The BeamDriver
  deviation from "a real Assault player" is reasoned and logged. Gate time (≤ 2.0 s, 8× clock, two-run mean, README row) and the
  DECISIONS / docs steps are in the build sequence.

---

# Round 2 (revision 2 of `3-plan.md`)

VERDICT: APPROVED

Every round-1 finding is resolved, and I checked each one against the code. Revision 2 adds one new problem: the signal order row 4
expects only appears if the test connects its listeners before the host enters the tree. It is a test-wording fix (R2-1 below) and
must be applied when the row is written. The two notes after it are optional.

## Round-1 findings, checked

- **B1 (resolved).** `3-plan.md:57-60` now uses `LowHealthSmoke`. Its rule `float(current) / max <= threshold and current > 0`
  (`low_health_smoke.gd:53-57`) is the DAMAGED rule, it stops on a kill by damage (`current > 0` fails), and `deactivate()`
  (`:50-51`) covers a scripted `destroy()`. Row 16 (`3-plan.md:184-186`) covers all three cases, using a second part for the
  scripted kill; Laser works, because a direct `received_damage` emit skips its type filter.
- **B2 (resolved).**
  - The fixture table (`3-plan.md:92-99`) pins ids and roles: WEAPON / CORE / ENGINE. Row 14 (`:177-180`) now assertions that bite:
    `live(HANGAR)` is empty, `destroyed_count([CORE, ENGINE])` is 0, and `destroyed_count([])` is 1. A hull that ignores the role
    argument fails.
  - Part hurtboxes are authored 0 / 0 with no types, so every layer, mask and type a row reads comes from `EnemyModule._ready()`.
  - Laser's `DefenseProfile` at default flags gives 1121 (`defense_profile.gd:38-48`), which is not the no-profile 1120.
  - Open's authored `Health` 10 / 10 is clamped to 10 by `Health._ready()` (`health_component.gd:23`), which runs before the
    module's `_ready()` because it is a child. Reading 100 / 100 therefore proves the module overwrote it.
  - Laser authors no `Health`, so it exercises the created path.
- **M1 (resolved).** Collection takes direct children only, and the host is found as `Modules`'s parent (`3-plan.md:70-71`).
- **M2 (resolved).** Row 6's `cool_targets(0.5)` is checked in "(e)" below.
- **M3 (resolved).** Row 7's opening sequence is checked in "(d)" below.
- **M4 (resolved).** The two nova hosts are 4000 px apart (`3-plan.md:170`).
- **M5 (resolved, with R2-1).** Row 15 covers the `Light` going OFF and the burst going into the host's parent, row 16 covers the
  sparks, and row 11 covers authored versus created `Health`. The signal-order assertion in row 4 needs R2-1.
- **M6 (resolved).** Checked in "(b)" below.
- **M7 (resolved).** With a gap start of 90°, the ring's gaps sit at 90° and 270° plus 30°/s. Over the whole ~1.73 s cycle
  (0.8 + 0.78 + 0.15) the nearest gap centre reaches at most 322°, 38° from the root's bearing of 0 against a 22.5° half-width.
  The control cannot depend on the gap any more.
- **M8 (resolved).** `3-plan.md:199` now says the integrity test only calls `can_instantiate()`.

## The five checks the coordinator asked for

**(a) Reusing `LowHealthSmoke` (`low_health_smoke.gd:25-57`): correct.** `setup(health)` connects `amount_changed`, and `threshold`
is read live on every change. Two implementation notes, neither a plan defect:
- `_ready()` copies `amount`, `color`, `min_velocity` / `max_velocity` and `emission_radius` into its `CPUParticles2D`
  (`:25-41`). The spark colour and the faster particles must therefore be set **before** `add_child()`; set afterwards, they are
  silently ignored. `threshold` can be set at any time.
- `setup()` must follow `add_child()`, as its own comment says (`:43-47`).

**(b) `is_armored()` on `EnemyModule` (`3-plan.md:61-63`): safe.** A grep over every `.gd` outside `addons/` finds only two
production readers of `is_armored()` on another node:
- `armor_query.gd:24`: the fallback, which runs only when the target has no `deflects_hit`. A module has one (`:22-23`), so
  projectiles are unaffected.
- `enemy_shield.gd:158`: the host is the hurtbox's parent, so the shield sees the module.

Every other hit is a self-call (`space_station.gd:177`, `ram_corvette.gd:91, 96, 129`), a comment, or a test assertion on the
station or the Ram. Nothing else changes. `tests/unit/test_enemy_shield.gd:294` pins that the shield asks only `is_armored()`,
never `deflects_hit`.

The row 5 addition then plays out as expected:
1. Locked's shield refuses the hit (`absorbs_hit` returns false), so its points stay full.
2. The hurtbox emits `received_damage`.
3. The module refuses it and emits `deflected`.
4. `deflects_hit` answers deflect, so the bullet flies on.

Open's shield still absorbs because Open is vulnerable. A shield on the fixture root is never involved.

**(c) The fixture table (`3-plan.md:92-99`): consistent with the code.**
- `StateLight._ready()` builds its own child `Sprite2D` named `Light` (`state_light.gd:31-36`), so the node path is `Open/Light/Light`.
  That is harmless: the module resolves its direct child `Light`, which is the `StateLight`. `set_state(ARMED)` followed by OFF is
  readable through `get_state()`, and its code-built texture is outside the transparency sweep.
- `HomingPoint` at (0, 12) is local to Open.
- The root's `_resolve_defense_profile()` looks at direct children of the root only (`base_enemy.gd:280-286`), so Laser's profile is
  never taken for the root.
- Authored `collision_layer` / `collision_mask` 0 has no set bits for `test_collision_layer_names.gd` to check.

**(d) Row 7's `LaserRay` opening sequence (`laser_ray.gd:182-189, 203-225, 242-246`): correct.**
1. With `auto_start` false and `warn_duration` 0, `start()` plays `laser_init` and creates no timer. `_sync_hazard` registers
   nothing, because `registers_hazard` defaults to false.
2. `_begin_increase()` moves INIT to INCREASE and calls `play("laser_increase")`. That sets the master segment's `animation` at once,
   so the direct `_on_animation_finished()` call takes the `&"laser_increase"` branch.
3. That branch enters IDLE, plays the looping `laser_idle` (which fires no further `animation_finished`), sets `HitZone.monitoring`
   and `monitorable` to true (`race_hazard` is false), and starts the child 0.1 s `Timer`.
4. `active_duration` 0 creates no `SceneTreeTimer`.

The next physics step reports `area_entered` for the part hurtboxes, which are on layer 512 and inside the 128 | 256 | 512 mask.
Open takes the direct 9999; Locked deflects on that hit and again on each continuous tick.

**(e) Row 6, `cool_targets(0.5)` (`beam_behavior.gd:106-111, 122-129`): the expectation is exact.**
- Heat rises by `0.7 × 1/60` per tick, and `minf(1.0, ...)` caps it at exactly 1.0 after about 86 ticks, well inside 2 s.
- Once the parts leave `enemy_parts`, `tick()` no longer targets them and never cools, so their tracked heat stays 1.0 through the
  0.25 s and until the drivers stop.
- `cool_targets(0.5)` gives `1.0 - 0.5 × 1.0 = 0.5` and writes `Color(1, 0.5, 0.5, 1)` on each tracked node. Both values are exact
  in float.
- `WeaponBehavior` is `RefCounted` (`weapon_behavior.gd:2-3`), so calling `cool_targets()` on a held reference after the driver
  stops is fine.
- The root, tracked by the beam under Locked, also reads (1, 0.5, 0.5). The row does not assert on it.

## New in revision 2

**R2-1 (minor; fix it when writing the row). The signal order row 4 records depends on when the test connects
(`3-plan.md:144-145`).**
- Godot calls a signal's callbacks in connection order: `Object::emit_signalp` iterates an insertion-ordered `HashMap`.
- `ModularHull._ready()` connects to `Open.damaged` / `destroyed` when the host enters the tree.
- A recorder the test connects afterwards (the natural way: build the host, then connect) therefore records
  `module_damaged, damaged, module_destroyed, destroyed`. The hull's handler runs and re-emits first.
- On a correct build that log contradicts the row's `damaged, module_damaged, destroyed, module_destroyed`.

Fix the test, not the code. Either:
- connect the four recorders after `instantiate()` and before the host enters the tree (then the stated order is what a correct
  build produces), or
- assert the invariant: both damage signals come before both destruction signals.

**Do not** make the hull's re-emit or forwarding deferred to get the stated order. `hull_share` forwarding has to land in the same
call as the hit.

**R2-2 (note).** `visual_state()` computes DAMAGED as `current <= damaged_ratio × max_health`, while `LowHealthSmoke` uses
`float(current) / max <= threshold`. They agree at the fixture's 0.5 × 100. For other ratios the multiply and the divide can differ
by one ulp at the boundary. Write `visual_state()` with the smoke's exact expression so the sparks and the state can never disagree.

**R2-3 (note).** Row 16's "second part" should be Laser, damaged through a direct `received_damage` emit, which skips its type
filter. It cannot be Locked, which refuses damage. Name it in the row when writing it.
