# Review — t2 plan (HurtBox absorb hook + EnemyShield), round 1

Reviewer: independent subagent. Read: task `1-context.md`, `3-plan.md`; epic §2.3, §2.13, §2.14, §4.1, §4.3, "For every
task"; `hurtbox_component.gd`, `armor_query.gd`, `armor_plate.gd`, `bullet.gd`, `base_enemy.gd`, `fixture_enemy.tscn`,
`fixture_brain.gd`, the player weapon-mode `.tres` damage values.

## What is right

- The hook is §2.3's code verbatim: filter first, live absorber asked once, `hit_absorbed(hb)` else `received_damage`.
  With no absorber the path is unchanged. Every unit row §2.3 lists for `test_hitbox_hurtbox.gd` is present, plus a
  "freed slot can be retaken" row.
- Every §2.3 shield row is in the plan: the 54°/56° edge, 110 → 360 while attached, 40 vs 25+25+25, reboot, regen,
  turn rate, sustain lapse, slot cleared on free, the armoured host, and the counting fake. The integration rows are
  there too: bullet front/behind, rockets, beam bypass, local module and bubble. The ≤ 6 awaited cases on the 8×
  clock and the 3.0 s budget are kept.
- Host = the hurtbox's parent matches §2.3 ("the `HurtBox`'s parent") and gives the local-module case for free.
  Points as a float with `int` `points()`, and `restored()` on every refill to full, are consistent with §2.3 and its
  "restored once" row. Nothing later depends on `restored` being emitted only after a break. A sustain clock that
  starts at creation suits t12, which creates the shield and then sustains it every tick.
- Conventions: signals are typed, the clock is accumulated delta, nothing writes `rotation`, there are no allowlists,
  the fixture scene is unchanged and P-15 is recorded.

## Problems

1. **As specified, the integration rows cannot pass with the real numbers.** A default player `Bullet` does
   **50** damage (`bullet.tscn`, `default.tres`). The shield's default `capacity` is **40**, and `fixture_enemy.tscn`
   has **Health 10**.
   - **Bubble row ("absorbs four bullets from four directions"):** the first bullet breaks the shield (it is absorbed
     whole). The shield then reboots and bullets 2–4 hit the hull.
   - **"From behind damages the hull" and "hull is not shielded" rows:** one 50-damage bullet kills the 10-HP fixture.
     That runs the death path (`died`, the explosion and `queue_free`) in the middle of the case.

   The plan has to state the fixture values. Two options: shield `capacity` ≥ 4 × bullet damage, or a lower
   `Bullet.damage` set on spawn; and a hull `max_health`/`current_health` well above 50, set before `add_child`.
   Without these the rows are red or assert on a dying node.
   (Not a t2 change, but flag it for t12/owner: the epic's `shield_capacity` 40 means one Standard shot (50) breaks the
   projected shield, then 4 s of reboot. It is worth a line in DECISIONS so t12 tunes it knowingly.)

2. **The local-module fixture must not be an `ArmorPlate`.** The context calls it "an `ArmorPlate`-like child hurtbox".
   An `ArmorPlate` takes damage in its **own** `hurt_box.area_entered` handler (`_on_hurt_box_area_entered` →
   `_resolve`), not through `received_damage`. So the absorb hook does not protect a plate at all. A bullet would be
   absorbed by the shield (points spent), yet the plate's `deflects_hit` would still answer and keep the bullet flying.
   State that the part is a plain `Node2D` with a `HurtBox` → `received_damage` → `Health`. Place it **outside** the
   hull hurtbox's circle so each shot overlaps exactly one hurtbox. Record "an enemy shield does not cover
   `ArmorPlate`s" as a known limitation, in DECISIONS for Ph10 module shields.

3. **The turn-rate row cannot fail on a frozen arc.** "Facing turns ≤ `turn_rate × delta` per tick" is green on a
   shield that never turns. Assert that, while far from the bearing, each tick turns by `turn_rate × delta` within
   epsilon, and that the facing then settles on the bearing without overshooting. Also state that with no threat point
   set, the facing holds (the integration rows rely on `face()` staying put).

4. **The rule that the regen delay restarts on every absorbed hit (§2.3, F10) has no row.** Add one: hit, wait less
   than `regen_delay`, hit again. Points must not start rising until `regen_delay` after the *second* hit. Also state
   what happens after a break. Per §2.3 the shield regenerates from 0 straight after `reboot_seconds`, with no
   additional `regen_delay`. Add the row: not up at `reboot_seconds − tick`; up and refilling after it; full (with
   `restored`) at `reboot_seconds + regen_seconds`. Today "nothing absorbed during reboot" is the only post-break
   assertion.

5. **Release the hurtbox slot at the lapse, not at the end of the fade.** As planned, a lapsed shield keeps the slot
   for `fade_seconds` plus a frame. In that window a support that re-acquires the same ward (§2.12 retarget, back in
   range) gets `attach() == false`, and §2.13 then skips the projection. Since a lapsed shield already absorbs
   nothing, call `clear_absorber(self)` when it lapses and keep the fade purely visual. `_exit_tree` still clears the
   slot, guarded with `is_instance_valid`. The lapse row then asserts `has_absorber()` false and `absorbs_hit` false
   right after `lapsed`. This still meets t12's "slot free within `heartbeat + fade_seconds` + 1 tick".

6. **Log what later tasks depend on in DECISIONS.** The phase-log rule requires it, and t12/t13 build on these choices:
   - the new `face(world_dir)` snap and the initial facing `Vector2.DOWN`. In Open Space a fresh projected shield
     otherwise needs about 2 s to swing toward the player, so t12 should call `face()` before its first `sustain()`;
   - the semantics of `restored()`;
   - the slot release at lapse (item 5);
   - the `ArmorPlate` limitation (item 2).

7. **Measure gate time before as well as after.** Step 4 says "gate-time after" only. §4.1 and §4.3 require before and
   after, with the delta reported.

## Advisory (not required)

- Make `set_absorber(obj)` return false for an `obj` without `absorbs_hit`, so a misuse fails loudly rather than
  erroring per hit.
- Note in `global.md` that the player's contact ram hitbox also hits enemy hurtboxes, so a shield in its arc absorbs a
  ram contact too. This is consistent with §2.6's "a shielded ward's arc can absorb" rocket impacts.

VERDICT: CHANGES_REQUESTED

# Review — t2 plan, round 2
VERDICT: APPROVED

Reviewer: independent subagent, round 2. Read: `1-context.md`, `3-plan.md` (including "Revisions after review round 1",
lines 64-82), round 1 of this file; epic `3-plan.md` "For every task" (l. 28-86), §2.3 (l. 196-302), §4.1, §4.3. Checked
against the code at HEAD: `global/components/hurtbox_component.gd`, `armor_query.gd`, `armor_plate.gd`,
`defense_profile.gd`, `health_component.gd`, `assault/scenes/projectiles/bullets/bullet.gd` + `.tscn`, both player missile
scripts and scenes, `tests/helpers/fixture_enemy.tscn`, `fixture_brain.gd`, `assault/scenes/enemies/base_enemy.gd`,
`global/physics/collision_layers.gd`, `tests/integration/test_armor_query.gd`.

## Round-1 findings: each one is resolved

1. **Fixture values (resolved, plan l. 65-67).** I checked the numbers in the code. A bullet does 50 damage
   (`bullet.gd:33`; `bullet.tscn` HitBox layer 64, mask 513). The warhead does 50 and the homing missile 100
   (`warhead_missile.tscn:63`, `homing_missile.tscn:57`). The fixture has 10 HP (`fixture_enemy.tscn:33`). With hull
   Health at 1000/1000 and capacity 1000, the worst case is the bubble's 4 x 50 = 200, which leaves the shield up and the
   hull alive. `Health._ready()` only clamps current to max (`health_component.gd:23`), so setting both values before
   `add_child` sticks. The hull's own HurtBox gets its mask from `DefenseProfile.apply_to` (`defense_profile.gd:51-54` ->
   1|32|64|1024), so it sees both bullets (64) and rockets (32). `fixture_brain.gd` requests `Vector2.ZERO` by default,
   so the fixture holds still and the on-axis geometry stays valid.
2. **Local module is a plain part (resolved, l. 68-70).** A `Node2D` part with its own HurtBox (layer 512, mask 96 =
   `PLAYER_ROCKETS | PLAYER_HITBOX`, `collision_layers.gd:14-15`) feeding `received_damage` into its own Health is
   exactly what the absorb hook protects. The `ArmorPlate` problem round 1 raised is real: the plate damages itself in
   its own `_on_hurt_box_area_entered` -> `_resolve` (`armor_plate.gd:107`, `:128`). The plan now records it as a
   limitation instead of testing around it. The part is 60 px out against an r 20 hull, so each shot overlaps one
   hurtbox. It is not a direct root child, and the fixture is in no geometry roster, so no sweep is affected.
3. **Turn row can now fail (resolved, l. 71-72).** The row asserts an exact `turn_rate x delta` per tick while far off,
   no overshoot or sign flip, and that the arc holds still with no threat point. A frozen arc fails the first
   assertion, an overshooting arc fails the second, and drifting without a threat point fails the third.
4. **Regen rows (resolved, l. 73-75).** (a) The F10 restart now has its own row. (b) After a break the shield refills
   straight after `reboot_seconds`, with no extra `regen_delay`, and is full with `restored` once at
   `reboot_seconds + regen_seconds`. This is §2.3's "after reboot, refill from 0" (epic l. 271-272).
5. **Slot release at lapse (resolved, l. 76-78).** `_lapse()` clears the slot at once and the fade is drawing only.
   The lapse row asserts `has_absorber()` false and that the next hit arrives as `received_damage`. `_exit_tree()`
   still calls `clear_absorber(self)`, and the plan's own hurtbox row ("clear_absorber by a non-holder is a no-op")
   keeps that call harmless once another shield holds the slot.
6. **DECISIONS (resolved, l. 79-81).** All four items round 1 named are listed. The capacity-40 / one-shot-breaks note
   for t12 is also listed. There is a Phase 5 section to append to (`DECISIONS.md:1853`).
7. **Gate time before and after (resolved, l. 82).** The "before" figure was measured and recorded (GUT 177.6 s, 1593
   tests), and the plan states it will measure "after", as §4.1/§4.3 require. The 177.6 s is under t1's 183 s target, so
   t2's 3.0 s fits under the 240 s ceiling with plenty of room.

## New problems introduced by the revisions

None that block. The revisions only clarify fixture values, rows and records. They do not change the approved §2.3
design, which is still sound against the code:
- The hook goes after the type filter at the one emit point (`hurtbox_component.gd:12-18`). Without an absorber the
  path is unchanged.
- The projectile side needs no edit. A shielded host answers neither `deflects_hit` nor `is_armored`
  (`armor_query.gd:22-24`), so `bullet.gd:113-137` reaches `expired.emit()` and both missiles reach `queue_free()`.
  Their callbacks and the hurtbox's are independent decisions, so the undefined `area_entered` order does not matter.
- `BaseEnemy` stays as it is (`base_enemy.gd:73`, `:176`). An absorbed hit never emits `received_damage`, so it never
  reaches `health.decrease`.

## Advisory (for the implementer; not conditions of approval)

- **Post-reboot "up" moment.** `is_up` is defined on `points() > 0`, with `points()` floored (plan l. 22). At the
  defaults (40 pt / 1.5 s, about 0.44 pt per 1/60 s tick), the shield is still not up for the first two ticks after
  `reboot_seconds`. Row 4(b) should assert "not up at `reboot_seconds - tick`" and "points rising a few ticks after
  `reboot_seconds`", not "up on the very next tick". Assert the `restored` instant on both sides, one tick of float
  tolerance each way, so that a refill which never completes still fails the row.
- **Re-attach in the fade window.** Revision 5's whole point is that t12 can `attach()` a fresh shield while the
  lapsed one fades. One more assertion in the lapse row would pin it cheaply: a second shield attaches during the fade,
  the first frees, and `has_absorber()` is still true afterwards. An `_exit_tree()` that nulls the slot directly would
  fail it.
- Round 1's two advisories (reject an `obj` without `absorbs_hit` in `set_absorber`; note the player's ram contact in
  `global.md`) are still worth doing and still optional.
