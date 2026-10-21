VERDICT: CHANGES_REQUESTED

Review of `docs/plans/cmvg30aax007rqs2x14trnuf9/3-plan.md` (t10, wreck family) against epic §2.8 / "For every task" / §4.1 /
§4.4, CLAUDE.md, and the code at `a1e94b2`. I checked the plan's claims in the code. The two physics claims that carry
the most weight I also ran as standalone headless probes (Godot 4.6.3, scratch project in `/tmp/wprobe`, nothing in the
repo touched). The overall design is sound and reuses what exists: the `HazardField` attach pattern, `ProjectileLifetime`,
`HitEffect` / `ExplosionEffect`, `LineOfSight`'s opt-in, and the duck-typed round filter. The `EnemyBullet` mask change
is safe (see "Checked and fine"). There is one blocker and four majors. Each has a small fix, so this is not a rejection.

## Blocker

**B1. In Open Space the `ProjectileLifetime` is never actually switched off, so wrecks die at 30 s with no fade and
placed structures die at 30 s (breaks t18).** The plan's `wreck.gd` → `_enter_tree()` (lines 58-60) calls
`ProjectileLifetime.set_physics_process(false)`. A parent's `_enter_tree()` runs *before* its children's
`NOTIFICATION_READY`. In Godot 4 a node whose script overrides `_physics_process` is switched back on by
`set_physics_process(true)` during its own READY, so the switch-off is overwritten. Probe: a parent disables its child in
`_enter_tree()`, and one frame later `child.is_physics_processing()` reads `true`. `projectile_lifetime.gd:71`
overrides `_physics_process`, so the scene's `max_time 30` (plan line 39) applies in Open Space. Three consequences:
- every Open Space wreck emits `expired` at 30 s and hits `expired → queue_free`, with no fade (§2.8: "frees after
  `lifetime` 40 s, fading over the last 2 s");
- every placed structure (`lifetime = 0`, "permanent") disappears 30 s after the hub loads, which breaks t18;
- the test planned to catch this, row 7 `test_open_space_wreck_frees_after_lifetime` (line 157), is hand-ticked. It
  never runs the child's real physics ticks, so it stays green on the broken build.

Fix: in Open Space, write a property instead of the processing flag. Either `_lifetime.max_time = 0.0` (Open Space has
no world rect and `max_distance` is 0, so the component does nothing), or
`_lifetime.process_mode = PROCESS_MODE_DISABLED`. Neither is reset by READY. If the processing flag is kept, the call has
to be in `_ready()`, which runs after the children are ready. Tests: an Open Space row that runs at least one real
physics frame and then asserts `lifetime.max_time == 0` (or `!is_physics_processing()`, depending on the fix). Add a
structure row: a `structure_satellite.tscn` in an Open Space harness is still registered and in the tree after its
`ProjectileLifetime._physics_process(31.0)` is hand-ticked. Apply the same rule to `DebrisFragment`'s "`lifetime` 0 → the
`ProjectileLifetime` is switched off" (line 125).

## Major

**M1. A drifting wreck does not reliably hurt the ship it runs into: the yield can fire before the contact box reaches
the hurtbox.** (Plan lines 79-98 and risk line 184.) The hold starts on *any* body overlap. Damage needs the wreck's
contact box (same size as its body) to overlap the ship's **hurtbox**, which is smaller than the ship's body:
- Assault fighter: 13.77 body vs 13.5 hurtbox (`player_fighter.tscn` `Collision` r 5.099 × 2.7, `HurtBoxCollision` r 5 × 2.7);
- Open Space ship: 11.045 vs 11.0.

So when the drift step's first penetration is shallower than the difference between those radii, the wreck undoes the
step and holds, and no hurt ever arrives. The hold then lasts as long as the ship stays put. The first penetration
depth depends on sub-pixel phase, so this happens by chance in play. A probe replicated the plan's yield: R 25 wreck,
60 px/s = 1 px/tick, 10 start offsets 0.0-0.9 px, both tree orders. Ships hurt per offset:
- idle fighter: `[0,1,1,1,1,1,1,1,0,0]`, a 30 % miss;
- idle Open Space ship: `[0,1,…,1]`, the exact-touch offset misses;
- fighter calling `move_and_slide()` each tick: still misses at offset 0;
- `hurtbox == body` (enemies): hits at every offset. Tree order made no difference.

Slower Open Space drifts (an inherited `drift_velocity` of 15 px/s is 0.25 px/tick) make the miss band wider. Row 6
uses a single approach distance, so it passes or fails depending on that distance and proves nothing either way.

Fix: hold only once the hit has registered. Hold when `Hazards.hurt_box_of(ship).overlaps_area($ContactHitBox)` is true
(the overlap state after the previous step), **or** when body penetration exceeds a cap, e.g. 1.5 px. The cap covers an
unarmed box and a ship with no hurtbox. At 1 px/tick the deepest overlap is about 1.27 px for one tick, so the
"≤ 2 frames over 0.5 px" row still holds. Row 6 must then sweep at least 10 sub-pixel start offsets, including exact
touch (0.0), for both player scenes and a real enemy, plus one slow (≤ 20 px/s) Open Space drift. Assert that each one is
hurt exactly once.

**M2. "A stationary wreck is harmless" is false for the Sniper, which t13 parks against cover; the measured margin is
also not what the plan states.** `1-context.md` says the gap at rest is "slide margin 0.08 + 0.05 / 0.27 px". A probe
pushed a body into a stationary R 25 wreck with `move_and_slide()` for 1 s, at 100 and 360 px/s and three angles. The
minimum centre gap was **0.000-0.007 px**, not 0.08: the body rests touching. At that gap:
- fighter and Open Space ship: 0 hits (their hurtbox is smaller than their body);
- `hurtbox == body`: 0 hits, but on a knife edge;
- **Sniper** (`sniper.tscn:76` body scale 1.44, `:89` hurtbox scale 1.4505, +0.15 px): **hit on every approach**.

t13 has the sniper settle behind a wreck, so each touch would cost it 10 HP. The Risks line 181 margin is overstated for
the players and wrong for enemies. Fix:
- Add an invariant row to `test_wreck.gd`. For every mover-driven enemy scene and both player scenes, assert that the
  hurtbox circle (radius × scale) is no larger than the body circle (radius × scale). It fails today on the sniper.
- Bring the sniper's hurtbox scale to 1.44. That is a one-line scene change and still satisfies
  `test_enemy_hurtbox_geometry.gd`, which only requires the hurtbox to cover the body within 1 px.
- Add a real-physics row: a real `sniper.tscn`, pushed into a stationary wreck by a hand-set mover request, takes no
  damage.
- Correct the margin in the Risks and context files.

**M3. HP 200 / 800 never happens: `Health` clamps to `max_health` (default 100).** Plan line 54 calls
`Health.set_health(health_amount)`. `health_component.gd:13` defaults `max_health = 100`, and `decrease()` (`:35-53`)
clamps `current_health - amount` to `[0, max_health]`. So the first hit takes a 200 HP wreck straight to ≤ 100, and an
800 HP structure is effectively a 100 HP one. The asteroid precedent never shows this because no asteroid goes over 100.
Every enemy and `ArmorPlate` sets `max_health` first (for example `armor_plate.gd:61`, `swarm_drone.gd:45`,
`gunship.gd:36-37`). Row 2's "HP < 200" and row 5's "reaches zero" both pass on the bug. Fix: set
`health.max_health = health_amount` before `set_health()`. Test: one 10-damage hit leaves exactly `health_amount - 10`,
for one wreck scene and one structure scene.

**M4. A retiring wreck still takes damage and can still emit `destroyed`, which would set off t12's blast on a fading,
evicted wreck.** `retire()` (lines 74-77) sets the HurtBox **layer** to 0. That stops bullets *seeing* the hurtbox, but
the HurtBox is still `monitoring` with mask 96. `hurtbox_component.gd:44-54` acts on any `HitBox` it detects, and Godot's
area-area detection depends only on the detector's mask and the other area's layer, not on the detector's own layer. So a
player bullet (layer 64) crossing a retiring wreck passes through without being consumed and still damages it. Enough of
those reach `destroyed.emit` plus an explosion during the fade. t11's eviction and t12's explosive wreck both rely on
`retire()` being final. Fix: in `retire()`, also `HurtBox.set_deferred("monitoring", false)` and ignore
`received_damage` / `amount_changed` while `_retiring`. Test: a retiring wreck crossed by a real `bullet.tscn` keeps its
HP, never emits `destroyed`, and the bullet is not consumed.

## Minor

**m1. The Sniper Shot passes through wrecks; the plan says player bullets stop.** `bullet.gd:113-125`: an
`unlimited_pierce` bullet stops only on group `asteroids`; any other hurtbox it passes through. A wreck is not in
`asteroids`, so the player's Sniper Shot passes through every wreck and kills a t13 sniper behind its cover. Plan line
102 says "player bullets … stop on the HurtBox". Either rule is defensible, but it must be pinned. Fix: either add a
duck-typed opt-in (`stops_piercing()`) next to the asteroid check, or state "the Sniper Shot pierces cover" in
`HAZARD.md` and DECISIONS.md. Add a row either way.

**m2. A held Assault wreck can vanish on screen.** In Assault, `expired → queue_free` (line 56) is justified by
"leaving the world rect is off screen". But a wreck held by the yield above an idle player at y ≈ 1060 reaches the
**30 s** `max_time` cap inside the view, and §2.8 promises a wreck "never vanishes on screen without a fade". Fix:
connect `expired → retire()` (the 0.5 s fade then frees it) instead of `queue_free`.

**m3. A wreck that starts out overlapping a ship never leaves it.** A wreck spawned on the player (t11: an enemy dies
against the player) has `_last_step = 0`. While the player is ahead of it the wreck holds where it is, the idle player
sits inside the wreck indefinitely, and at 0.6 s the arming hits them. Without the yield it would have drifted off.
Fix: yield only to ships that the wreck's own step ran into. Ignore ships already overlapping at `_enter_tree` (or since
before the last step) until they separate. Add an Assault variant of the "spawned on the player" row in which the
overlap ends within about 1.5 s.

**m4. Debris lifetime has two sources of truth.** `debris_drift.tscn` authors `max_time 30` "(= `lifetime`)" next to a
`lifetime` export (lines 122, 125). t15's Ram fragment will set one and forget the other. Fix: copy `lifetime` into
`_lifetime.max_time` in `_ready()`, as `EnemyRocket._apply_exports()` does (`enemy_rocket.gd:367-374`), with 0 meaning
`max_time = 0`.

**m5. The plan's own pinned decisions are not recorded for later tasks.** "For every task" requires that "a deviation
later phases depend on goes into the Phase 6 section of DECISIONS.md". Build step 6 (line 177) lists only `HAZARD.md` and
the module doc. These pinned choices are relied on by t11-t18:
- circle bodies and their radii;
- the `spawned` flag;
- the yield;
- debris hurts at any speed;
- the Open Space lifetime handling;
- the M2 hurtbox ≤ body rule.

Fix: add a DECISIONS.md entry to step 6.

**m6. A stale comment on the round mask.** `station_gunnery.gd:33-35` says the round HitBox is "layer 256 / mask 128
(the player hurtbox only)". After this change that is false, although its conclusion (no self-damage) still holds. Fix:
update the comment in step 4.

## Nit

- Row 7 "frees on leaving the world rect": spawn the wreck near the rect's bottom edge rather than letting it cross
  1608 px (26.8 s simulated, about 3.4 s of wall time at 8×) to stay inside the +3 s allowance.
- The spawned-on-player row should also assert that the player **is** hurt shortly after arming while still
  overlapping. Without that it passes on a build whose contact box never arms. Row 6 covers arming in general, but not
  this path.

## Checked and fine

- **`EnemyBullet` mask 128 → 1152 plus the filter** (`enemy_bullet.gd:45-46`, `enemy_bullet.tscn:28-29`).
  - The only areas on layer 1024 are asteroid / race-asteroid contact boxes (`big_asteroid.tscn:45`,
    `small_asteroid.tscn:46`, `race_asteroid.tscn:36`). None answers `stops_enemy_rounds()`, so they still pass rounds.
  - No code-built area uses layer 1024.
  - The rounds inherit the mask (`rounds/*.tscn` do not override it).
  - Pooling: the round's `expired` is unchanged, so `BulletPool` recycling is unaffected.
  - `become_friendly()` still writes mask 513. That never sees 1024, and a friendly round now stops on and damages a
    wreck's 512 hurtbox, which is consistent. Separately, `reset()` never restores the layer or mask after
    `become_friendly()`; that bug already exists and nothing calls `become_friendly()`.
  - `racer_weapon.gd`: race shots only ever hit 128, and race asteroids now pass rounds exactly as before.
  - Station gunnery: the core hurtbox mask 1121 still excludes 256.
  - The only test pinning the old mask is `test_enemy_rounds.gd:59`, as the plan says.
- **Enemy rockets.** Their impact HitBox is layer 32 with mask 640 (`dumb_rocket.tscn:41-42`), so they detonate on the
  wreck's 512 hurtbox, and the wreck's mask 96 takes their damage. `enemy_rocket.gd:378` only skips `ArmorQuery`
  deflections.
- **Line of sight** (`line_of_sight.gd:16, 49-54`): a layer-1 body answering `blocks_line_of_sight()` blocks; an
  `Area2D` fragment cannot.
- **Targeting**: every homing / AI / module path reads group `enemies`.
- **Physics ordering.** `_physics_process` runs, then the physics step, then the next tick's flush emits
  `area_entered`, so the one-step overlap does register (probe: `hurtbox == body` hit at every offset). Tree order
  between the wreck and the ship did not change any result.
- **The clamp-edge row's boundary** (yield off ⇒ many overlapping frames on an idle player) can genuinely fail. Probe:
  with the yield on, overlap stays ≤ 1 px for one tick.
- **Gate rosters.** Adding the six scenes to `test_enemy_hurtbox_geometry.gd` and `test_contact_hitbox_geometry.gd`
  works: both instantiate any `Node2D`, find the body by the name `CollisionShape2D`, and take the first direct-child
  `HitBox` / `HurtBox`.

---

# Round 2 (plan "Revision 2", `3-plan.md:193-217`; correction at `1-context.md:31-32`)

VERDICT: CHANGES_REQUESTED

Every round-1 finding is answered, and most answers are correct as written. One new problem comes from the m1 answer, and
it is a single line of specification. One test detail in the new M1 sweep also needs pinning. Once both are in, I would
approve without another full round. I re-checked the code for each answer, and for M2 I instantiated all nine
mover-driven enemy scenes headless, using a script in `/tmp`.

## Round-1 findings, re-checked

- **B1: resolved.** The fix writes `_lifetime.max_time = 0.0` in the wreck's own `_ready()`. That runs after the
  children's READY, and a property write is not undone by READY anyway. `projectile_lifetime.gd:73-77` then never
  trips: `max_distance` is 0 and Open Space has no rect provider. `_assault` is computed in `_enter_tree()`, which runs
  before `_ready()`, so it is available. The new row, real frames followed by a hand tick of the child at 31 s, does
  fail on the round-1 design (the hand tick emits there), so it can catch a regression. Debris
  `max_time = lifetime` also settles m4.
  - Nit: a wreck authored into an *Assault level scene* ahead of its `ArenaCamera` node would see no arena in
    `_enter_tree()` and pick Open Space. Nothing in t10 does this, but t18 should place structures only in Open Space,
    or resolve the mode lazily on the first physics tick. Note it in `HAZARD.md`.
- **M1: sound, with one residual gap.** The hold now waits for either a registered hit
  (`hurt_box_of(ship).overlaps_area(ContactHitBox)`, the state flushed from the previous step) or 1.5 px of penetration
  along the drift. The wreck then backs off its whole overlapping travel. The arithmetic, at 1 px/tick head-on:
  - Assault fighter (body 13.77, hurtbox 13.5): the first overlap d₁ is in (0, 1]. If d₁ > 0.267 the hit registers at
    d₁. Otherwise the next step reaches d₁ + 1 ≤ 1.27 and registers there.
  - The hold fires on the next tick and the overlap ends on that tick. That gives at most one frame over 0.5 px, so the
    "≤ 2 frames" row holds.
  - An unarmed box, a ship with its hurtbox off and a ship with no hurtbox all fall through to the 1.5 px cap, which
    keeps the overlap bounded.
  - Back-off: tracking `_overlap_travel` is right. Undoing only the last step, as round 1 planned, would leave the
    2-step case still overlapping.
  - Residual gap (nit): the test is "penetration *along the drift*", so on a glancing contact it fires early. At an
    angle θ to the drift, closing is cos θ px per tick, and backing off 1.5 px along the drift opens the gap only by
    about 1.5·cos θ. So for θ ≳ 79° the cap trips at about 0.26 px of radial depth, before the fighter's 0.267 deficit,
    and that contact never hurts. This is acceptable (a near-tangential brush), but `HAZARD.md` should say so, and the
    sweep should stay head-on so it does not flake.
- **M2: resolved, and the invariant holds on every other scene.** Measured at runtime (radius × global scale):

  | Scene | Body | HurtBox |
  |---|---|---|
  | razor | 12.5 | 12.5 |
  | fighter | 28.6 | 28.6 |
  | gatling | 25.2 | 25.2 |
  | bomber | rect half-extents (48, 22) | (48, 22) |
  | ram corvette | 34 | 34 |
  | missile corvette | 40 | 40 |
  | support ship | 34 | 34 |
  | sniper | 20.16 | **20.3077** |

  Only the sniper fails, so changing `sniper.tscn:89` to scale 1.4400002 is the whole fix. After it the hurtbox shares
  `CircleShape2D_se` and the body's scale, identical to the body, so `test_enemy_hurtbox_geometry.gd` stays green. No
  test pins 1.4505 or 20.31, and `test_sniper.gd` has no edge-of-hurtbox distance.
  - The Ram's `ArmorPlate` hurtboxes mask 96 and not 1024 (`ram_corvette.tscn:124-125, 147-148, 171-172`), so a
    stationary wreck cannot hit a plate.
- **M3, M4, m2, m5, m6 and the nits: resolved as written.**
- **m3: resolved.**
  - Nit: the "drifts off within 1.5 s" row only works for small and medium wrecks. Worst case at 60 px/s is
    2·(R + 13.77) px: 1.29 s for medium (R 25), 1.79 s for large (R 40). Pin the row to `wreck_medium.tscn`, or derive
    the bound from R.

## New findings

**R2-M1 (major): the m1 branch makes a Sniper Shot's damage to a wreck depend on callback order.** Revision 2 routes
`stops_piercing()` through the existing `unlimited_pierce` branch (`bullet.gd:114-125`). That branch **zeroes
`HitBox.damage` first** and then expires. That is fine for asteroids, which are meant to take nothing. But Godot orders
the bullet's `area_entered` and the hurtbox's `area_entered` undefined; the comment at `bullet.gd:118-119` says so, and
`hurtbox_component.gd:44-54` reads `hb.damage` at its own callback. So a Sniper Shot into a wreck sometimes deals its
full damage and sometimes 0. For a 200 / 800 HP wreck that is a coin-flip outcome. It would also make t12's "a shot
detonates an explosive wreck" non-deterministic for the player's strongest weapon. The planned row ("a Sniper Shot ends
on a wreck") checks only that the shot ends, so it cannot catch this.

Fix: give `stops_piercing()` its own sub-branch that ends the shot (`expired.emit()` plus `queue_free()`) **without**
touching `hb.damage`. The hurtbox then reads the full value whichever callback runs first, because `queue_free` is
deferred. Pin it as "cover stops the Sniper Shot and takes its full damage", or, if the intent is that cover takes no
damage, say so and filter on the wreck's side instead (ignore `received_damage` from an `unlimited_pierce` hitbox).
Either way, the row must assert the wreck's exact HP afterwards.

This leaves existing behaviour alone: nothing in the project defines `stops_piercing()` today, `ArmorPlate` and the
station core do not gain it, and the asteroid path and `is_high_impact()` (`bullet.gd:98-99`) are untouched. So the
asteroid rows in `test_player_bullet_lifetime.gd:369+` and `test_armor_query.gd:101,164` are unaffected.

**R2-m1 (minor): the concurrent sweep's Swarm Drones must be held still.** Row 6 now runs 10 pairs in one scene,
including real `swarm_drone.tscn`s. A live drone's brain and mover chase the harness player, so a drone can leave its
pair, re-enter its wreck or reach a neighbour's (200 px is about one second of drone travel). "Hurt exactly once"
would then be non-deterministic. Fix: suspend the drones' AI for the row (`suspend_ai()`, or switch off the brain and
the mover), so the wreck is the only thing moving into them. Assert positions are unchanged except for the wreck's
push.

**R2-n1 (nit).** `sniper_bullet.tscn` does not author `unlimited_pierce`; `sniper_behavior.gd:85` sets it at fire time.
The m1 row has to set `bullet.unlimited_pierce = true` itself, as `test_player_bullet_lifetime.gd:369+` does, or it
tests a default bullet.

## What would make this APPROVED

1. A one-line R2-M1 decision (full damage, without zeroing) and a row asserting exact HP.
2. Drones held still in the sweep.

The nits can be handled during implementation.

---

# Round 3 (plan "Revision 3", the end of `3-plan.md`)

VERDICT: APPROVED

This is a confirmation round only. I checked R2-M1, R2-m1 and the new `bullet.gd` sub-branch against the code.

- **R2-M1: resolved.**
  - The `stops_piercing()` sub-branch ends the shot (`expired` plus a deferred `queue_free()`) without writing
    `HitBox.damage`. The wreck's `HurtBox` (`hurtbox_component.gd:44-54`) therefore reads the full value in the same
    flush, whichever `area_entered` runs first.
  - The test's `200 − 50` is correct: `Bullet._ready()` copies `damage` (default 50, `bullet.gd:33, 54`) into the
    HitBox, and `sniper_bullet.tscn:48` also authors 50. In play the mode's 40 applies (`sniper_shot.tres:16`); that
    does not matter here.
  - The test sets `unlimited_pierce = true` itself, which covers R2-n1.
- **Nothing existing breaks.**
  - The sub-branch sits inside `if unlimited_pierce:` (`bullet.gd:114`), so default, spread, gatling and pierce bullets
    never reach it.
  - No existing node defines `stops_piercing()`: no asteroid, `ArmorPlate`, station core or enemy has it. The
    asteroid sub-branch and its zero-damage rule are unchanged, so `test_player_bullet_lifetime.gd:369+` and
    `test_armor_query.gd:101,164` see the same behaviour.
  - A second `queue_free()` alongside `WeaponBehavior._launch()`'s `expired → queue_free` is harmless.
- **R2-m1: resolved.** `suspend_ai()` (`base_enemy.gd:125-136`) halts the mover and suspends the brain. Combined with
  `set_physics_process(false)`, the wreck is the only thing that moves.
  - Nit: `suspend_ai()` also **arms** the Swarm Drone's EXPLOSIVE `ContactProfile` (`swarm_drone.tscn:97-101`; its
    `ContactHitBox` masks 128). An armed drone that touches a player hurtbox detonates (blast radius 48). With pairs
    200 px apart and the wreck dealing 10 against the drone's 30 HP, nothing triggers this. Keep every drone more than
    about 80 px from any player ship in the sweep, and say why in a comment.

Ready for implementation.
