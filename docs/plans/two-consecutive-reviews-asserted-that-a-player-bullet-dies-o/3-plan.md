# Player bullet lifetime: give the player's shots an owner

> **Revision 2** — after `4-review.md` round 1, `VERDICT: CHANGES_REQUESTED`. The shape of the
> change is unaltered and the reviewer independently re-derived the diagnosis. What changed is the
> *evidence*: a precedent that pointed the wrong way (**F1**), an unstated behaviour change
> (**F2**), two wrong test expectations that would have gone red on the first run for reasons
> unrelated to the code (**F3**, **F4**), an invariant test that could not hold its own invariant
> (**F5**), three documentation lines that state the misconception this task exists to kill
> (**F6**), and a missing fifth free path (**F7**). Corrections are marked **[R1]**.

## Problem

**What the player experiences today.** Framerate decays over the course of an assault mission for
no visible reason. With the Standard, Long Range or Sniper weapon selected, *every shot ever
fired stays in the level* — travelling, running `_physics_process`, and holding a live `Area2D`
HitBox, an `Area2D` body, two `Line2D`s and a `WorldEnvironment` — until the mission ends. At
`default.tres:13`'s `fire_interval = 0.18`, three minutes of held fire is ~1000 of them.

**Why.** Player shots are the only projectiles in the game with no owner. Enemy and ally bullets
are recycled by `BulletPool` on `expired`; the warhead missile frees itself on `screen_exited`
(`warhead_missile.gd:19-20`); the homing missile frees itself on an arena-bounds
check (`homing_missile.gd:29-32`). **[R2, N3]** Enemy bullets are *recycled*, not freed:
`enemy_bullet.gd:31-37` reaches the same arena bound but only `expired.emit()`s, and the pool
reclaims it (`bullet_pool.gd:56,80-89`); the one enemy bullet that actually frees is the unpooled
sniper one, via `sniper_enemy.gd:102`'s `expired.connect(queue_free)`. Player *bullets* do none
of these: all four behaviours do a plain `state.add_child(bullet)` (`straight_behavior.gd:22`,
`spread_behavior.gd:21`, `long_range_behavior.gd:17`, `sniper_behavior.gd:87`), and the whole repo
has exactly two connections to `Bullet.expired` — `bullet_pool.gd:56` and `sniper_enemy.gd:102`
(which is not even the same class; it fires `enemy_sniper_bullet.tscn`) — neither on the player
path.

**[R1, F7]** `bullet.gd` has **five** "done" paths, and only two of them free:

| # | `bullet.gd` | Emits `expired` | Frees | Reachable on the player path? |
|---|---|---|---|---|
| 1 | `:45-49` range cap | yes | **yes** | Only if `range_px > 0` — Gatling (450) and Spread (360) only |
| 2 | `:51-52` screen exit | yes | no | Always — and nothing listens |
| 3 | `:71-76` unlimited-pierce hits an asteroid/ram-ship | yes | **yes** | Sniper only, and only against those two groups |
| 4 | `:79-83` pierce hit with `pierces_remaining > 0` | no | no | Only with `PierceModule` equipped |
| 5 | `:84` ordinary hurtbox hit | yes | no | **[R2, N4]** Non-sniper only — `:78`'s bare `return` means an `unlimited_pierce` bullet never reaches it |

So Standard and Long Range have **no** free path at all, and Sniper has one that requires hitting
an asteroid or a ram-ship. That is the leak.

**What should change.** A player shot ends when it leaves the screen. Nothing about *damage*
changes.

## Design

### The rule this states

> **An unpooled projectile owns its own lifetime and frees itself when it leaves the screen.
> A player bullet is NOT consumed by a hurtbox it overlaps.**

The second half is not new behaviour — it is what ships today. It is currently an *accident* of
three unrelated settings, and the whole space-station boss depends on it
(`test_space_station.gd:150-171`, `ENEMY.md:528-536`: consume-on-overlap and *"the turrets become
unkillable and so does the boss"*). This change makes it a stated rule with a gate, so the next
person to touch projectile lifetime finds a red test instead of an unwinnable boss. Genre backs
it: *"If an enemy is invulnerable … some games let your bullets pass through during these times,
which is also fine"* (`2-research.md`, shmuptheory).

### The change

**1. `Bullet.free_when_offscreen()`** — new public method on
`assault/scenes/projectiles/bullets/bullet.gd`:

```gdscript
func free_when_offscreen() -> void:
    var notifier := get_node_or_null("VisibleOnScreenNotifier2D") as VisibleOnScreenNotifier2D
    if notifier == null:
        push_warning("[Bullet] %s has no VisibleOnScreenNotifier2D — it will never despawn" % name)
        return
    if not notifier.screen_exited.is_connected(queue_free):
        notifier.screen_exited.connect(queue_free)
```

Opt-in, and it must stay opt-in — see "the one thing that must not be done".

**2. `WeaponBehavior._launch(state, bullet)`** — new shared helper on the strategy base class
(`weapon_behavior.gd`), so a sixth behaviour cannot forget:

```gdscript
func _launch(state: Node, bullet: Bullet) -> void:
    state.add_child(bullet)
    bullet.free_when_offscreen()
```

**3.** The four spawn sites call `_launch(state, bullet)` in place of `state.add_child(bullet)`.

**[R1]** Residual gap, accepted and stated: `_launch()` covers `WeaponBehavior` subclasses only.
Anything that instantiates `bullet.tscn` outside a behaviour still leaks. Today that is exactly
one site, `assault/scenes/player/states/shooting_state.gd:42` — a legacy shooter referenced by no
scene (see Out of scope). Test 3 is written as an invariant over the behaviour class list so a
*sixth behaviour* cannot reopen the gap; it deliberately does not try to police the whole repo.

### The one thing that must not be done

**`bullet.gd` must not free itself on `screen_exited`.** `ally_fighter.gd:11,22-25` pools
`bullet.tscn` (`pool_size = 8`), and `docs/BULLET_POOL.md:15` states the architectural rule
directly: *"The **pool is smart, bullets are dumb**. Bullets know nothing about pooling — they
only emit a signal when they're done."* A bullet that frees itself has to know whether a pool owns
it, which is exactly the knowledge that principle forbids.

**[R1, F4] The mechanism, corrected.** The round-1 claim — that `_recycle()` would land on a freed
object and be dropped, leaving `_idle` short — is wrong, and the reviewer disproved it on a real
pool (`pool_size = 2`, connect `screen_exited` → `queue_free`, emit, wait two frames):

```
idle size after: 2   active: 0
SCRIPT ERROR: Trying to assign invalid previously freed instance.
   at: BulletPool.acquire (res://global/components/bullet_pool.gd:67)
acquire after: <null>
```

The deferred `_recycle` runs **before** the delete queue is flushed, so the bullets *do* return to
`_idle` (`bullet_pool.gd:88-89`) and are freed there. `_idle.size()` still reads 2 — **a test that
asserted the pool's size would be green on the broken build.** The real symptom is that
`acquire()` errors at `bullet_pool.gd:67` and returns `null` on the ninth shot, so `AllyFighter`
silently stops shooting. Test 4 must therefore assert on `acquire()`'s result and
`is_instance_valid()`, never on `_idle.size()`.

### Alternatives rejected

| Alternative | Why not |
|---|---|
| Connect `expired` → `queue_free` on the player path (the `sniper_enemy.gd:102` idiom) | `expired` also fires on an ordinary hurtbox hit (`bullet.gd:84`), so this silently *also* consumes the shot on first contact — the exact change that makes the station boss unwinnable. `expired` conflates "done travelling" with "hit something"; this task does not untangle it. |
| `queue_free()` inside `bullet.gd::_on_visible_on_screen_notifier_2d_screen_exited()` | Breaks `AllyFighter`'s pool, as above. |
| **[R1]** `Bullet._ready()` self-detects `get_parent() is BulletPool` and wires its own free — one file, covers every unpooled spawn site including future ones | Directly violates `docs/BULLET_POOL.md:15` ("bullets are dumb"): it makes the bullet know about pooling. It is also fragile in exactly the way the pool is: `BulletPool._prewarm()` adds bullets as its own children and `acquire()` **reparents** them to the container (`bullet_pool.gd:55,68`), so the parent at `_ready()` and the parent in flight are different nodes, and a pooled bullet in flight would test as unpooled. |
| **[R1, F1]** Arena-bounds check like `enemy_bullet.gd:6-16` / `homing_missile.gd:4-10` | This is the *majority* precedent, not a fringe one — the round-1 plan wrongly claimed both missiles used the notifier; only the warhead does (`homing_missile.tscn` has no `VisibleOnScreenNotifier2D`; only `bullet.tscn`, `sniper_bullet.tscn` and `warhead_missile.tscn` do). It is rejected on one decisive reason: **those constants are the assault arena's, and the player path is shared with Open Space.** `open_space/scenes/entities/player/player_ship.tscn:267` mounts the same `weapon_state.gd` and therefore the same four behaviours, in a mode with a different camera and a different world extent. Hardcoding `x ∈ [-100, 1380], y ∈ [-380, 1100]` into the player's bullets would be silently wrong in one of the two modes. The notifier is viewport-relative and correct in both. |
| Pool the player's bullets too | Bigger change, and the defect is the missing free, not the allocation rate. Godot 4 node creation is cheap enough that pooling should follow a profiler measurement (`2-research.md`). |
| Also stop the default gun piercing damageable targets | **Out of scope — see below.** |

### **[R1, F2]** What this changes besides the leak

`VisibleOnScreenNotifier2D` fires at the **viewport** edge, and the assault play area is bigger
than the viewport: a 1480×1480 arena against 1280×720, with the camera offset clamped to ±100 x /
±380 y (`arena_camera.gd:24-26,35-39`). So up to **380 px of live arena above the visible top**
becomes territory where a shot fired straight up is now destroyed but today keeps flying.
`enemy_bullet.gd:33` documents the deliberate opposite choice on the enemy side: *"Expire when the
bullet leaves the full 740×740 arena, not just the viewport edge."*

This is accepted, for three reasons, and is called out here so the next reader does not file it as
an oversight:

1. **It costs the player nothing they can aim.** The lost band is off-screen. Enemies scroll in
   from above; blind-firing at not-yet-visible spawns is not a skill the mode teaches or rewards.
2. **Two of the five modes already stop far shorter.** Gatling caps at 450 px and Spread at 360 px
   (`gatling.tres:12`, `spread.tres:12`) — well inside the viewport from any normal firing
   position. Standard/Long Range/Sniper becoming *viewport*-bounded is a smaller change than the
   difference already shipping between weapons.
3. **The alternative is wrong in Open Space** (see the rejected-alternatives row above).

**Consequence to record in the docs:** player bullets and enemy bullets now despawn on *different*
boundaries — viewport for the player, arena for the enemy — and that asymmetry is deliberate.

### Explicitly out of scope, and why

`PierceModule` ("Penetrating Rounds": 3 pierces, ×0.55 damage each) is **strictly a downgrade**
today, because the base gun already pierces without limit — equipping it only shrinks hits 2-4
from 50 to **[R1, F3]** 28/15/8 (`maxi(1, roundi(d * 0.55))`, `bullet.gd:64`; verified on Godot
4.6.3: `50 -> 28 -> 15 -> 8 -> 4`), and once `pierces_remaining` hits 0 the bullet flies on at 8
anyway. Genre convention says piercing is what an upgrade buys, not a baseline (`2-research.md`,
SLYNYRD). But fixing it means deciding that the default gun stops on the first damaging hit, which
requires `SpaceStation`'s armoured core to stop absorbing shots aimed at its turrets — a coupled
design change across the whole game's balance. **Filed as its own backlog task, carrying the
station coupling verbatim; pinned as characterization here so the next change to it is
deliberate.**

## Build sequence

1. **Tests first** — write `tests/integration/test_player_bullet_lifetime.gd` with all five cases
   below and watch tests 2 and 3 fail (1, 4, 5 pin existing behaviour and should already pass).
2. Add `Bullet.free_when_offscreen()` with the doc comment explaining the pool constraint.
3. Add `WeaponBehavior._launch()`; switch `straight_behavior.gd`, `spread_behavior.gd`,
   `long_range_behavior.gd` and `sniper_behavior.gd` to it.
4. Document the rule in `bullet.gd`'s header. **[R1, F6]** Required doc edits, by line:
   - `docs/architecture/modules/assault.md:37` — "`bullets/bullet.gd` Pooled player bullet" → it
     is not pooled on the player path.
   - `docs/architecture/modules/assault.md:158-162` **[R2, N5]** — "the **pooled** player bullet … `expired`
     signals the pool to reclaim it". Replace with the real ownership rule and the viewport-vs-
     arena asymmetry from F2 above.
   - `docs/architecture/modules/assault.md:169` — "`BulletPool` … is instantiated by shooters
     (**player**, allies, many enemies)". The player never instantiates one.
   - `assault/scenes/enemies/space_station/ENEMY.md:528-536` and
     `tests/integration/test_space_station.gd:150-171` — both say "the backlog has an **open** task
     (`two-consecutive-reviews-…`)". Repoint at the new `PierceModule` task (step 5) and at
     `test_player_bullet_lifetime.gd` test 1.
   - While in `assault.md`: `:167` lists a `primary_homing/` projectile directory that does not
     exist (`ls assault/scenes/projectiles/` → `bullets, enemy_bullet, enemy_bullets, missiles,
     piercing_beam`). One-line fix in a section already being edited.
5. File the `PierceModule` balance task via `backlog-cli.js add-task code-health-backlog`, with the
   station coupling copied into the body so it is never orphaned.
6. `bash /agent/verify.sh`, then `bash scripts/check-test-leaks.sh`, then `updating-project-docs`.

Step 3 is the only one that changes player-visible behaviour.

## Test plan — `tests/integration/test_player_bullet_lifetime.gd`

| # | Test | Asserts | Can it fail? |
|---|---|---|---|
| 1 | `test_a_bullet_is_not_consumed_by_a_hurtbox_it_overlaps` | Real `bullet.tscn` overlapped with a real `HurtBox` for two physics frames: `received_damage(50)` fires, and the bullet is **still in the tree** with `HitBox.damage` still 50. **[R1]** The `HurtBox` needs `collision_mask = 64` (the HitBox's layer, `bullet.tscn:44`), a layer inside the HitBox's mask 513 (use 1), and a real `CollisionShape2D` child — `hurtbox_component.gd:12` fires off the HurtBox's *own* `area_entered`, so a default `HurtBox.new()` never sees the bullet. | Yes — red the moment anyone consumes a bullet on hit. The station boss's premise, restated at the bullet level. |
| 2 | `test_a_launched_bullet_frees_itself_when_it_leaves_the_screen` | Fire through `StraightBehavior.fire()` against a stub state, emit the bullet's `VisibleOnScreenNotifier2D.screen_exited`, `await` a frame: the bullet is freed. | Yes — red today. |
| 3 | `test_every_weapon_behavior_hands_off_its_projectile_s_lifetime` | **[R1, F5]** Enumerate behaviours from `ProjectSettings.get_global_class_list()` filtered on `base == "WeaponBehavior"` (today: Beam, LongRange, Sniper, Spread, Straight) rather than a hand-written list, so a *sixth* behaviour is covered on the day it is added. Two explicit branches, each covering a distinct failure mode: **(a)** `SniperBehavior` — `fire()` is a deliberate no-op (`sniper_behavior.gd:29-30`), so drive `start_charge()` + `fire_from_charge()`; **(b)** `BeamBehavior` — spawns a `PiercingBeam`, not a `Bullet`, and owns its own frees (`beam_behavior.gd:46,141`), so assert *that* rather than skipping silently. Everything else goes through `fire()`. Every spawned `Bullet` must have `screen_exited` connected to its own `queue_free`; the test **fails on an unrecognised behaviour class** rather than passing over it. **[R2, N1]** Each non-Beam branch must first `assert_gt(bullets.size(), 0)`, or the connection loop is vacuous and green — which is the *default* outcome of the obvious harness, not a hypothetical. | Yes — red today for three of the five, and red again the day a sixth behaviour is added, which is the point of the class-list form. |
| 4 | **Boundary:** `test_a_pooled_bullet_survives_leaving_the_screen` | `BulletPool` of `bullet.tscn`, `pool_size = 2`, parented pool → ship → container (mandatory: `bullet_pool.gd:47` does `get_parent().get_parent()`; copy the harness at `test_radial_attack_pattern.gd:20-35`). Acquire both, emit `screen_exited` on both, `await` two frames, emit `expired` on both, `await`: **`acquire()` returns non-null and `is_instance_valid()` on it**. **[R1, F4] Do not assert `_idle.size()` — it reads 2 even on the broken build.** | Yes — red if someone "simplifies" the fix into `bullet.gd` and silently drains `AllyFighter`'s pool. Green today, and that is the point: it guards the constraint, not the change. |
| 5 | **Characterization:** `test_pierce_module_today_only_reduces_damage` | Drive `_on_hit_box_area_entered` four times with `pierces_remaining = Bullet.MAX_PIERCE`, flushing deferred calls between: damage decays **[R1, F3]** 50 → 28 → 15 → 8, `pierces_remaining` reaches 0, and the bullet is **still alive** on the fourth hit. Comment names the new backlog task. **[R1, F7]** A sibling assertion pins free path 3: a bullet with `unlimited_pierce = true` **is** freed by an area whose parent is in group `asteroids` (`bullet.gd:71-76`). | Yes — red if anyone changes pierce behaviour without updating the pin. |

Determinism notes:
- Tests 2-4 **emit `screen_exited` directly** rather than relying on render culling.
  `VisibleOnScreenNotifier2D` is driven by the renderer and needs a draw pass (`2-research.md`,
  Godot docs), which is not something a headless gate should be asked to reproduce. The unit under
  test is *our wiring*, not Godot's culling. The reviewer confirmed on 4.6.3 that
  `notifier.screen_exited.emit()`, `screen_exited.connect(queue_free)` / `is_connected(queue_free)`
  and `is_queued_for_deletion()` all behave headless.
- **[R2, N1/N2]** The stub `state` needs a **script** declaring `var actor`; a scriptless `Node.new()` makes `state.get("actor")` return `null`, every `fire()` early-returns and test 3 passes with zero bullets. The stub actor is a scripted `Node2D` declaring `var velocity: Vector2` and `var pierce_module_active: bool` — four behaviours read `actor.velocity` **directly** (`straight_behavior.gd:19`, `long_range_behavior.gd:14`, `spread_behavior.gd:18`, `sniper_behavior.gd:84`), so a bare `Node2D` reds tests 2-3 on setup rather than on behaviour.
- Test 1 uses the real physics server, following the harness at `test_space_station.gd:171-186`
  (two `await get_tree().physics_frame`s for `area_entered`).
- Everything parents under `add_child_autofree` containers; nothing awaits a `SceneTreeTimer`
  (`tests/README.md`'s `LevelDirector` trap), so `scripts/check-test-leaks.sh` stays clean. Run it
  anyway — test 4 frees nodes across frames.

## Risks

| Risk | Check |
|---|---|
| Freeing a pooled bullet by accident | Test 4 (asserting on `acquire()`, not pool size), plus `free_when_offscreen()` being opt-in and documented as such. Verified by grep: `bullet.tscn` has exactly one pooled user (`ally_fighter.gd:11`). |
| Shots at off-screen-but-in-arena enemies stop connecting | **[R1, F2]** Accepted and documented above; recorded in `assault.md` as a deliberate player/enemy asymmetry. |
| `screen_exited` never fires for a bullet that was never drawn | Accepted: the warhead missile already ships exactly this and it is the Godot recipe. Gatling/Spread additionally free at range. If it ever matters, the arena-bounds check is the escalation — but only for assault, which is why it is not the default (Open Space shares the path). |
| Double free (range cap **and** screen exit both fire) | `queue_free()` is idempotent; the `is_connected` guard prevents a duplicate connection. |
| The station's two real-physics tests break | They instantiate bullets directly, never through a behaviour, so `free_when_offscreen()` is never called on them. Test 1 restates their premise at a lower level. |
| Open Space uses the same `WeaponState` (`player_ship.tscn:267`) with a different camera | The notifier is camera-agnostic — it reports against whatever viewport is drawing. This is the reason arena bounds were rejected. |

## Out of scope

- Whether the default gun should stop on the first damaging hit (the `PierceModule` inversion) —
  filed as a separate backlog task.
- Pooling player bullets.
- `assault/scenes/player/states/shooting_state.gd`, a legacy shooter referenced by no scene
  (`player_fighter.tscn` / `player_ship.tscn` mount only `warhead_missile_shooting_state.gd`) —
  reported as a finding, not touched here.
- `Bullet.expired` conflating "done travelling" with "hit something".
