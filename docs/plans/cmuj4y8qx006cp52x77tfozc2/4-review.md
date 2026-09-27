# Review, round 1

VERDICT: CHANGES_REQUESTED

The plan follows the approved epic design (§2.3 rev 2, §4 rows) closely. The API, the mode table, COLLISION leaving
the hitbox alone, the deferred toggles, the blast's re-homing and its own frame counter are all correct, and I checked
each against the code. There is **one blocking defect**: `ContactBlast.spawn()` as specified leaks the blast whenever
its container is freed before the deferred `add_child` runs. The plan's Risks section says the opposite, and several
of the planned unit cases trigger it directly. The fix is small. The other findings are minor.

I checked the plan's engine claims empirically with a standalone Godot 4.6.3 headless project in `/tmp/exp`, not the
repo. Results are quoted below.

## Blocking

### B1. A deferred `add_child` into a freed container leaks the blast, and the plan says it does not
- Plan, *Risks*, last bullet: "a blast queued into a freed container is dropped by the engine without error (the
  Callable's object is gone)". Plan, *Design*: `ContactBlast`: `container.add_child.call_deferred(blast)`.
- The *call* is dropped silently, but the blast is not. It was built out of the tree and is never parented, so it is an
  orphan `Area2D`, `CollisionShape2D` and `CircleShape2D` for the rest of the process. Experiment: `cont.add_child.call_deferred(area); cont.free()`
  gives `orphan valid=true inside=false`, and at exit
  `WARNING: ObjectDB instances leaked at exit` plus `1 RID allocations of type 'P11GodotArea2D' were leaked`.
  That is exactly the `LEAK` pattern `scripts/check-test-leaks.sh:30` greps for, and the acceptance criteria require
  "no leaks".
- The tests hit this path. `addons/gut/autofree.gd:65-70` frees `add_child_autofree` nodes with an immediate
  `free()`, not `queue_free()`. So any test that detonates and returns without awaiting a flush frees the container
  first and leaks the blast. Several planned unit cases detonate synchronously:
  - "EXPLOSIVE armed: emitting `hit_box.area_entered(area)` → … `detonated` once"
  - "EXPLOSIVE death while armed → detonates"
  - "`detonate()` twice → one `detonated`, one `ContactBlast`" (this one needs an await anyway to count the blast)

  The mitigation "tests await the frames they need" relies on every test author remembering to await, and the gate
  prints GATE PASS anyway.
- It also happens in game whenever the enemy container is freed in the same frame as a death: a scene change, or a
  level section torn down.
- **Required change:** have the blast parent itself. Defer a call on the blast (which is always valid), not on the
  container. For example, `blast._attach.call_deferred(container)`, where `_attach` does
  `if is_instance_valid(container) and container.is_inside_tree(): container.add_child(self) else: free()`.
  The alternative is a weakref check with the same outcome. Add a unit case: detonate, free the container before the
  flush, await a frame, then assert `not is_instance_valid(blast)`. Hold the reference returned by `spawn()` for this.
  Fix the Risks bullet to match.

## Minor (fix in the same revision)

### M1. Pin the blast-lifetime case to the blast's own tree entry, and assert queue state, not instance validity
- Plan, test plan: "gone after `blast_frames` physics frames … alive after `blast_frames − 1`", counted with
  `Engine.get_physics_frames()`.
- The blast enters the tree in the message flush after `detonate()`. Which physics frame counts as tick 1 depends on
  where the GUT coroutine resumed: inside `physics_frame` or on idle.
- The experiment showed entry at frame 21, tick 1 at 22, tick 2 at 23, then `queue_free`. The node is still
  `is_instance_valid` until the idle flush after frame 23. So a count taken from `detonate()` can be off by one, and
  `is_instance_valid` lags `queue_free` by one frame.
- **Change:** await `blast.tree_entered` (or read the frame number in a probe) and count from there. Assert
  `blast.is_inside_tree() and not blast.is_queued_for_deletion()` after `frames − 1` ticks, and
  `is_queued_for_deletion() or not is_instance_valid(blast)` after `frames`. That is deterministic and still fails if
  the counter is wrong.

### M2. Add one test where contact and then death both detonate: the path t8b's consumer actually takes
- Plan, `_on_contact`: EXPLOSIVE calls `detonate()`. The epic §2.3 table says "then the owner self-destructs", which
  in practice means `health.set_health(0)` from a `contact_made` handler, as `kamikaze_drone.gd:54-57` does today. That
  fires `_on_health_changed` → `detonate()` a second time on the same frame.
- Idempotence is only tested by calling `detonate()` twice directly. Add a case: an armed EXPLOSIVE fixture whose
  `contact_made` is connected to `health.set_health(0)`, then a contact. Assert one `detonated` and one `ContactBlast`
  in the container. It is cheap, and it is the real ordering: the `amount_changed` re-entry happens *inside*
  `_on_contact`, before `detonate()` returns if the flag is set late. **Set `_detonated = true` before spawning or
  emitting.** The plan does not say where the flag is set.

### M3. The "detonating inside `area_entered`" case can fail, but say why in the test
- Plan, integration bullet 4, "`get_errors()` empty".
- Experiment: a direct `add_child` of an `Area2D` inside `area_entered` logs `ERROR: Can't change this state while
  flushing queries … at: area_set_shape_disabled (godot_physics_server_2d.cpp:355)`. GUT 9.7.1 treats that as a
  failure by default (`addons/gut/gut_config.gd:57`, `failure_error_types = ["engine", "gut", "push_error"]`). So the
  test does go red on a non-deferred spawn. Good.
- Record the exact engine message in the test's comment. Assert that the blast is in the container *after awaiting*
  the flush (it is not in the tree synchronously; see B1). Otherwise "the blast exists" is true of the
  never-parented orphan too.

### M4. Place the damage test off-origin
- Plan, integration setup: "contact box r 10 placed 40 px away".
- The unit case already offsets the container so that a local/global mix-up fails. The damage cases should do the
  same. If the player `HurtBox` sits near (0,0), a blast wrongly left at the canvas origin (the epic's B1 rev-1 bug)
  would still land and the "drops by exactly 25" case would pass. Put the pair at e.g. (400, 300) under an offset
  container.

### M5. Assert the out-of-tree `push_warning`
- Plan, unit test: "`detonate()` with an actor outside the tree → warning". GUT does not fail on warnings, so as
  written the warning is not checked. Use `assert_push_warning` so the case pins the message and cannot pass silently
  on a crash-free no-op.

## Checked and correct (no change)
- **Arming while already overlapping (C5):** the experiment added a hitbox overlapping a layer-128 / mask-1281 area
  and disabled both flags with `set_deferred` in the same idle frame. Result: 0 hits over 5 frames, then exactly 1 hit
  after `set_deferred(true)`. The planned engine pin is sound and will pass. Spawning on top of the player while
  RAMMING / EXPLOSIVE also registers 0 hits, so applying the resting state by deferred call in `setup()` is fine.
- **Blast timing:** a deferred-added `Area2D` with its position set in `_enter_tree()` was detected by the hurtbox on
  the first physics frame after entry, at the right position. `ExplosionEffect.explode()` (`explosion_effect.gd:79-88`)
  is the right precedent.
- **Layers:** `collision_layers.gd:17` `ENEMY_HITBOX := 256`. The player mask of 1281 includes 256. The enemy
  hurtbox masks (default 1121, `test_base_enemy.gd:59`; fixture 97, `fixture_enemy.tscn`) do not, so the blast
  cannot hit enemies.
- **Death hook ordering:** `base_enemy.gd:66` connects `amount_changed` before the profile's `setup()`. So
  `_on_health_changed` has already `queue_free()`d when the profile's handler runs, but the actor is still in the
  tree and `get_parent()` is valid. Detonation on death works.
- **`suspend_ai()` before `_ready()`:** not reachable today. `wave_manager.gd:184/208` and
  `station_reinforcements.gd:245/267` add the `EnemyPathMover` after the enemy is in the tree, so `setup()`'s deferred
  disable is queued before `set_armed(true)`'s enable, and FIFO order leaves the enemy armed. The null guard is
  harmless.
- **Legacy enemies:** every `BaseEnemy` subclass calls `super._ready()`. The only subclasses touching the hitbox's
  flags or layer are `space_station.gd:234` (layer, deferred) and the Kamikaze and Interceptor `area_entered`
  connects (`kamikaze_drone.gd:47-48`, `drone_interceptor.gd:38-40`). COLLISION touches neither. The child-iterating
  tests (`test_enemy_hurtbox_geometry.gd:132-150`, `test_station_gunnery.gd:109`, the container counts in
  `test_spawn_camera_pan.gd`) filter by type or count container children, so an extra `Node` child under each enemy
  does not break them.
- **Gates:** the single-writer gate's forbidden set (`test_enemy_mover_single_writer.gd:35-39`) covers
  velocity/rotation/move_and_slide. `global_position` in `ContactBlast._enter_tree` is not in scope, and
  `global/components/` is not swept. The arity gate (`test_signal_emit_arity.gd:55`) will see `contact_made.emit(area)`
  and `detonated.emit(at)`, which match the declarations. A static `spawn(... damage ...)` shadowing `HitBox.damage`
  logs no runtime warning (checked), so `test_project_load_integrity` stays clean.
- **Unit test loading a scene** is precedented (`tests/unit/test_enemy_mover.gd:11` preloads `fixture_enemy.tscn`).

# Review, round 2

VERDICT: CHANGES_REQUESTED

M1–M5 are all addressed as asked. M1: `tree_entered` probe plus a queued-for-deletion assertion. M2: the flag is set
before the spawn, and there is a contact-then-death case. M3: the engine message is documented, and the test awaits
before checking the parent. M4: the setup is off-origin, at (300, 200). M5: the case uses `assert_push_warning`. The
Risks bullet for B1 is corrected. One thing remains, and it is **my own round-1 suggestion, which was wrong**. I
tested it this round in the standalone Godot 4.6.3 headless project in `/tmp/exp`, outside the repo.

### R2-B1. The `_attach()` fallback as written errors and still leaks. It must `queue_free()` and must not type the parameter
The plan (*Design*, `ContactBlast`) says `_attach(container)` "otherwise `free()`s itself". Round 1 suggested exactly
that, and it does not work, in two ways:

1. **`free()` on `self` from inside its own method is refused.** Running `b._attach.call_deferred(cont)`, then
   `cont.free()`, then a flush printed
   `ERROR: Object is locked and can't be freed … SCRIPT ERROR: Attempted to free a locked object (calling or emitting).
   at: _attach`. The blast stayed valid (`freed case valid=true`), and at exit Godot reported
   `ObjectDB instances leaked` plus the Area2D and Shape2D RID leaks. That is a GUT failure (engine error) *and* the
   original leak.
2. **A typed parameter `func _attach(container: Node)` never runs.** When the argument is a freed object, the deferred
   call fails before the body executes:
   `ERROR: Error calling deferred method: '…::_attach': Cannot convert argument 1 from Object to Object.
   (message_queue.cpp:222)`. The blast leaks again.

Both of these variants are clean, with no errors and no leak output (`freed case valid=false`, and the happy path
parents correctly):
```gdscript
func _attach(container) -> void:          # untyped on purpose: a freed Object fails a typed Node parameter
	if is_instance_valid(container) and container.is_inside_tree():
		container.add_child(self)
	else:
		queue_free()                      # not free(): self is locked while its own method runs
```
The other clean variant defers `weakref(container)` and does `ref.get_ref() as Node`, with the same `queue_free()`.

**Required:** change "`free()`s itself" to `queue_free()` in the Design, and say the parameter is untyped (or a
`WeakRef`), with the reason for each. The planned "container freed before the flush" case would catch either mistake,
because GUT fails on the engine error and `check-test-leaks.sh` flags the leak. Make that case await **one idle
frame after** the flush before asserting `not is_instance_valid(blast)`, because `queue_free()` lands at the end of
the frame.

Nothing else needs changing. Once the above is corrected, this plan is approvable without another design pass.

---

## Author note after round 2 (not a review)

The round-2 reviewer's required edit was applied verbatim to `3-plan.md` (untyped `_attach` parameter,
`queue_free()` instead of `free()`, the freed-container test waits past the flush). The reviewer's words: "With this
edit the plan is approvable; nothing else needs another design pass." No third review round was run (the workflow
caps review at two rounds); implementation proceeded on that conditional approval, and the freed-container test plus
`scripts/check-test-leaks.sh` are the check that the edit is right.
