# Review — Player bullet lifetime: give the player's shots an owner

VERDICT: CHANGES_REQUESTED

The diagnosis is correct and I re-derived it independently: the leak is real, the pass-through-on-
overlap behaviour is real and load-bearing, the chosen fix shape is defensible, the tests are
runnable headless (I ran the key techniques on Godot 4.6.3 to be sure), and the scope fits one
session. Nothing here is reinvented; nothing contradicts `CLAUDE.md`.

What blocks approval is a cluster of **checkable factual errors** in the plan's evidence and test
numbers. Three of them (F1, F3, F4) would send an unattended implementation down a wrong path or
produce a test that fails for reasons unrelated to the code. Fix the items in "Required changes"
and the plan is good to build; none of them changes the plan's shape.

---

## Verified as claimed

| Claim | Checked |
|---|---|
| Player bullets have no owner — all four behaviours do a plain `add_child` | `straight_behavior.gd:22`, `spread_behavior.gd:21`, `long_range_behavior.gd:17`, `sniper_behavior.gd:87` — confirmed verbatim |
| `Bullet.expired` has exactly two connections repo-wide, neither on the player path | `grep -rn expired` over the tree: `bullet_pool.gd:56`, `sniper_enemy.gd:102`. `sniper_enemy` fires `enemy_bullets/enemy_sniper_bullet.tscn`, whose script is `enemy_bullet.gd` — so it is not even the same class |
| `queue_free()` is gated on `range_px > 0.0`; `screen_exited` only emits `expired` | `bullet.gd:45-49`, `bullet.gd:51-52` |
| Three of five modes ship `range_px = 0.0` | `default.tres:12`, `long_range.tres:12`, `sniper_shot.tres:12`; `gatling.tres:12` = 450, `spread.tres:12` = 360 |
| ~1000 nodes in three minutes of held fire | `default.tres:13` `fire_interval = 0.18`, hold-to-fire at `weapon_state.gd:133-136`. 180/0.18 = 1000. Each is `Area2D` + 2 `Line2D` + `WorldEnvironment` + notifier + `HitBox` (`bullet.tscn:16-52`) |
| The spawn-site list is exhaustive | Repo-wide grep for `bullets/bullet.tscn` / `sniper_bullet.tscn`: the four behaviours, `ally_fighter.gd:11`, and the dead `shooting_state.gd:42`. No other spawner |
| `bullet.tscn` has exactly one pooled user | Every `BulletPool.new()` site checked: `ally_fighter.gd:22` (bullet.tscn), `gunship.gd:60`, `interceptor.gd:30`, `light_assault_ship.gd:27`, `racer_weapon.gd:11` (defaults to `enemy_bullet.tscn`, and no racer `.tscn` overrides the export), `space_station.tscn:122` (`enemy_bullet.tscn`) |
| Nothing else frees a player bullet | There is no offscreen-cull component in `global/components/` and no group sweep; bullets parent to `WeaponState`, a plain `Node` (`player_fighter.tscn:351`), so they attach to the canvas directly and live until the level does |
| The station coupling is real | `test_space_station.gd:150-171` + `space_station.gd:168-174` + `ENEMY.md:528-536`. Consuming on first overlap does make the boss unkillable |
| `shooting_state.gd` is referenced by no scene | Only `warhead_missile_shooting_state.gd` appears in `player_fighter.tscn:8` / `player_ship.tscn:11` |
| Test techniques work headless | I ran them on 4.6.3: `notifier.screen_exited.emit()` relays through `_on_visible_on_screen_notifier_2d_screen_exited`, `screen_exited.connect(queue_free)` + `is_connected(queue_free)` behave, and `is_queued_for_deletion()` flips. The pool harness precedent is `test_radial_attack_pattern.gd:20-35` (pool → ship → container, for `bullet_pool.gd:47`) |

On the reviewer's question (c) — **deferring the piercing/`PierceModule` question is defensible, not
dodging.** The backlog body (`BACKLOG.json:131`) itself calls it "a real balance question for
multi-part targets", and the item's stated deliverable is *knowledge* ("worth knowing before anyone
reasons about projectile lifetime again"). The plan delivers that half (gate test 1, a doc comment,
a cross-reference) and correctly refuses to make a whole-game balance change that requires
`SpaceStation` to change in the same breath. **But see F6: the deliverable is documentation, and the
plan does not name the docs that currently state the false thing.** Deferral is only honest if the
task leaves the record correct.

On question (b) — **`free_when_offscreen()` + `_launch()` is not over-engineered.** Two lines and
three lines respectively, with one call site each. It is also the shape that agrees with
`docs/BULLET_POOL.md:15`, "the pool is smart, bullets are dumb" — which is a far stronger reason to
keep the free out of `bullet.gd` than the mechanism paragraph the plan actually gives (which is
wrong; see F4). Cite it. I considered the obvious cheaper alternative the plan does not mention —
`Bullet._ready()` self-detecting `get_parent() is BulletPool` and connecting its own free, which
would fix every unpooled spawn site including future ones in one file — and it should be *named and
rejected* rather than left unexamined, because it directly violates that principle. Residual gap,
worth one sentence in the plan: `_launch()` protects `WeaponBehavior` subclasses only, so anything
that instantiates `bullet.tscn` outside a behaviour still leaks. That is acceptable if and only if
test 3 is written as an invariant over the class list (F3).

---

## Required changes

### F1 — `homing_missile.gd:47` does not free on `screen_exited`. The precedent is one missile, not two.

`3-plan.md:13` ("the two player *missiles* free themselves on `screen_exited`
(`warhead_missile.gd:19-20`, `homing_missile.gd:47`)"), `1-context.md` ("Homing missile does the
same (`homing_missile.gd:32,47`)") and the Risks row at `3-plan.md:138` ("the two player missiles
already ship exactly this") are all wrong.

- `warhead_missile.gd:19-20` — yes, `_on_visible_on_screen_notifier_2d_screen_exited` → `queue_free`.
- `homing_missile.gd:46-47` is `_on_hit_box_area_entered`. Its off-screen despawn is
  `homing_missile.gd:29-32`, an **arena-bounds check** against constants copied from
  `arena_camera.gd` (`homing_missile.gd:4-10`). `homing_missile.tscn` contains **no**
  `VisibleOnScreenNotifier2D` at all — grep for the node type across `assault/` returns only
  `bullet.tscn:37`, `sniper_bullet.tscn:38`, `warhead_missile.tscn:55`.

This matters because the alternative the plan rejects at `3-plan.md:82` ("Arena-bounds check like
`enemy_bullet.gd:6-16`") is exactly what the other player missile and every enemy bullet chose. The
rejection may still stand, but it has to stand on its own reasons, not on a precedent that says the
opposite. Rewrite both the claim and the Risks row.

### F2 — "Nothing else about how it behaves changes" (`3-plan.md:21-22`) is not true, and the plan should say so.

The notifier fires at the **viewport** edge; the assault play area is larger than the viewport.
`arena_camera.gd:1-2,24-26,35-39`: a 1480×1480 arena, a 1280×720 viewport, camera offset limits
±100 x / ±380 y. So up to 380 px of *live arena above the visible top* is where a shot fired
straight up will now be destroyed but today keeps flying. `enemy_bullet.gd:33` documents the
deliberate opposite choice for the enemy side: "Expire when the bullet leaves the full 740×740
arena, **not just the viewport edge**."

I am not asking you to switch to arena bounds — the warhead precedent, camera-agnosticism in open
space, and the fact that gatling (450 px) and spread (360 px) already cap well short of the screen
edge all argue for the notifier. I am asking the plan to (a) state that shots at off-screen-but-
in-arena enemies stop connecting, (b) say why that is acceptable, and (c) note that player and
enemy projectiles now despawn on different boundaries, so the next person does not read it as an
oversight.

### F3 — Test 5's expected damage sequence is wrong: it is 50 → **28** → 15 → 8.

`3-plan.md:120` and `3-plan.md:88-90` both say 50 → 27 → 15 → 8. `bullet.gd:64` is
`maxi(1, roundi(hb.damage * PIERCE_DAMAGE_FACTOR))` with `PIERCE_DAMAGE_FACTOR = 0.55`
(`bullet.gd:18`). Measured on this repo's engine (Godot 4.6.3, headless):

```
50 -> 28 -> 15 -> 8 -> 4
```

`50 * 0.55` is `27.5000000000000036` in double precision and `roundi` rounds half away from zero.
Written to the plan's numbers, test 5 goes red on the first run for a reason that has nothing to do
with the change. Fix the number in both places.

### F4 — Test 4's stated failure mechanism is wrong, and the naive assertion is a trap.

`3-plan.md:69-74` says a self-free "would destroy a bullet the pool still lists in `_active`;
`_recycle()`'s deferred call would land on a freed object and be silently dropped, so the bullet
never returns to `_idle`". I simulated the bad fix on a real pool (`pool_size = 2`, pool → ship →
container, connect `screen_exited` → `queue_free` on both acquired bullets, emit, wait two frames):

```
idle size after: 2   active: 0
SCRIPT ERROR: Trying to assign invalid previously freed instance.
   at: BulletPool.acquire (res://global/components/bullet_pool.gd:67)
acquire after: <null>
```

The deferred `_recycle` runs **before** the delete queue is flushed, so the bullets *do* go back
into `_idle` (`bullet_pool.gd:88-89`) and are freed there. `_idle.size()` therefore still reads 2 —
**a test that asserted the pool's size would be green on the broken build.** The real symptom is
that `acquire()` errors at `bullet_pool.gd:67` and returns `null` on the next shot.

Two edits:
- Correct the mechanism paragraph (the constraint itself is unchanged and still correct; and per
  `docs/BULLET_POOL.md:15` the stronger argument is architectural anyway).
- Pin the assertion to what actually breaks: `acquire()` returns non-null **and**
  `is_instance_valid()` on the returned bullet. Do not assert `_idle.size()`. Note also that the
  broken path emits an engine error, which `tests/README.md:379` says GUT already fails on — that
  is a bonus, not the assertion.

### F5 — Test 3 cannot catch "a sixth behaviour" as written.

`3-plan.md:118` claims the test goes "red again if a sixth behaviour is added that calls `add_child`
directly". A loop over three named classes cannot see a class that does not exist yet. Make it an
invariant over the class list — verified working headless on this repo:

```gdscript
for c in ProjectSettings.get_global_class_list():
    if c.get("base", "") == "WeaponBehavior":
        ...  # BeamBehavior, LongRangeBehavior, SniperBehavior, SpreadBehavior, StraightBehavior
```

Handle the two behaviours whose `fire()` is a deliberate no-op (`beam_behavior.gd:28-29`,
`sniper_behavior.gd:29-30`): drive `SniperBehavior` through `start_charge`/`fire_from_charge` as the
plan already says, and skip/branch `BeamBehavior` explicitly (it spawns `PiercingBeam`, not a
`Bullet`, and owns its own frees at `beam_behavior.gd:46,141`) so a *new* behaviour is never
silently skipped by the same branch. State in the plan which of the two failure modes each branch
covers.

### F6 — The docs that state the misconception are not named, and this task exists to kill the misconception.

`3-plan.md:108` defers to `updating-project-docs` without naming targets. The false claim is
currently written down, in the module doc the next reviewer will read first:

- `docs/architecture/modules/assault.md:37` — "`bullets/bullet.gd`  Pooled player bullet"
- `docs/architecture/modules/assault.md:158-161` — "the **pooled** player bullet … `expired` signals
  the pool to reclaim it" (there is no pool and no listener on the player path)
- `docs/architecture/modules/assault.md:169` — "`BulletPool` … is instantiated by shooters
  (**player**, allies, many enemies)" — the player never instantiates one

Name these three lines as required edits. Two more that go stale the moment this lands, and should
be updated in the same pass rather than left pointing at a closed task:

- `assault/scenes/enemies/space_station/ENEMY.md:528-536` and `test_space_station.gd:150-171` both
  say "the backlog has an open task (`two-consecutive-reviews-…`) proposing that the infinite
  piercing is a bug." After step 5 the open task is the *new* `PierceModule` one; repoint both, and
  make sure the new task's body carries the station coupling verbatim, or the coupling is orphaned.

While there: `assault.md:167` lists a `primary_homing/` projectile directory that does not exist
(`ls assault/scenes/projectiles/` → `bullets, enemy_bullet, enemy_bullets, missiles,
piercing_beam`). Not this task's job, but it is one line in a section you are already editing.

### F7 — The "four done paths" tables miss a fifth.

`1-context.md`'s trace table and `3-plan.md`'s Problem section list range cap / hurtbox hit /
screen exit. `bullet.gd:67-76` is a fourth: with `unlimited_pierce`, an asteroid or ram-ship contact
zeroes the HitBox damage, emits `expired` **and** `queue_free()`s. That is the only free path a
sniper-mode bullet has today (`sniper_shot.tres:12` sets `range_px = 0.0`), so it belongs in the
table and is worth one line in test 5's neighbourhood so nobody "discovers" it later.

---

## Non-blocking notes for the implementer

- **Test 1 needs explicit collision layers.** `HurtBox._on_area_entered` (`hurtbox_component.gd:12`)
  fires off the **HurtBox's own** `area_entered`, so a default `HurtBox.new()` (layer 1 / mask 1)
  never sees the bullet's `HitBox` (layer 64, `bullet.tscn:44-45`). Give it `collision_mask = 64`,
  a layer the HitBox's mask 513 can see (1 or 512), and a real `CollisionShape2D` child, or the test
  fails on setup rather than on behaviour.
- `test_radial_attack_pattern.gd:20-35` is the pool-harness precedent to copy for test 4 —
  `bullet_pool.gd:47` does `get_parent().get_parent()`, so the two-level parenting is mandatory.
- Nothing in the plan awaits a `SceneTreeTimer`, so `scripts/check-test-leaks.sh` should stay clean;
  run it anyway, since test 4 frees nodes across frames.
- Conventions check, for the record: no new component duplicates `global/components/` (there is no
  offscreen-cull helper); no inheritance is added, only a method on the existing `WeaponBehavior`
  strategy base; no balance value moves out of a `.tres`; no design-unit coordinates are involved.
- Scope is right: one new test file, ~5 small edits, docs, one backlog entry. Do not let F5's
  class-list test grow into a general behaviour harness.
