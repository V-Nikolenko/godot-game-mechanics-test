VERDICT: CHANGES_REQUESTED

## What was verified as correct

- **The three-site list is complete.** A project-wide grep for `get_camera_2d()` and
  `cam.global_position` (no path filter) turns up exactly the sites the plan lists as spawns
  (`wave_manager.gd:172`, `station_reinforcements.gd:238` via `_spawn_origin()` at `:282-286`,
  `level_1_director.gd:125`) plus a long, correctly-excluded list of continuous despawn/exit
  checks (`bomb.gd:96`, `strafe_exit_state.gd:21-22`, `drone_interceptor.gd:132-135`,
  `enemy_path_mover.gd:106-109`, `kamikaze_drone.gd:72`, `bomber.gd:52`, `ram_ship.gd:67`,
  `small_asteroid.gd:29-32`, `ally_fighter.gd:71`) and hold-position waypoints
  (`gunship.gd:58/121`, `approach_state.gd:20`). `big_asteroid.gd`'s shard spawn (referenced by
  `station_reinforcements.gd:227-229`'s comment) copies the parent's `global_position` directly —
  no camera-relative offset, so it is not a fourth site. `score_popup.gd:34` genuinely already
  uses `cam.global_position + cam.offset`, confirmed by reading the file — it is a correct
  precedent, not a misattributed one.
- **`Camera2D.offset` needs no cast, confirmed empirically, not just read from source.** I ran a
  throwaway GUT test (`tests/unit/test_tmp_camera_probe.gd`, created and deleted during this
  review) that adds a bare `Camera2D` via `add_child_autofree`, sets `.offset`, and immediately
  calls `WaveManager._trigger_wave()` in the same test body — `get_viewport().get_camera_2d()`
  returned the camera synchronously (no extra `await` needed once the tree is already running, as
  a live GUT suite is), `.offset` read back correctly, and the reproduced bug matched the plan's
  numbers exactly: with `cam.global_position = (640,360)`, `offset = (0,380)`, and a design offset
  of `(0,150)`, the ship spawned at **(640, 660)** today (offset ignored) where the fix's formula
  targets **(640, 1040)**. This is solid evidence the fix is correctly specified and the "no
  camera in this test" claims in `test_station_assault_section.gd:8` and
  `test_station_reinforcements.gd` (never adds a `Camera2D`) are accurate — the fix is currently
  unreachable by the suite, exactly as `1-context.md` states.
- **The margin-budget consequence claim checks out numerically.** With the fix, both the visible
  screen's bottom edge and the spawn point shift by the same `offset.y`, so a reinforcement's
  vertical margin no longer needs `V_LIMIT` headroom — I recomputed both the pre-fix case (a
  design-y-290 spawn, 580 world px from origin, lands inside the panned-down view at max
  `V_LIMIT`, reproducing the described bug) and the post-fix case (same spawn now resolves past
  the panned bottom edge regardless of pan) and both match the plan's reasoning.
- No test file anywhere under `tests/` currently references `Camera2D` (`grep -rl Camera2D
  tests/` is empty), confirming the fix cannot regress any existing test — every current spawn
  test exercises only the at-rest/no-camera path.

## Problems found

1. **The `Level1Director` test mitigation in the plan's Risks section does not work as written,
   confirmed by running it.** The plan says: "If instantiating the bare script node throws, call
   `_spawn_bonus_drone()`/`_spawn_bonus_drone_left_to_right()` directly on a freshly-`.new()`'d
   script instance without going through the full scene... no other exported dependency is read
   before the line under test." I tested both halves of this directly:
   - Instantiating `Level1Director`'s script and adding it to the tree via `add_child_autofree`
     (no exports set) throws immediately in `_ready()`: `SCRIPT ERROR: Invalid call. Nonexistent
     function 'add_section' in base 'Nil'` at `level_1_director.gd:39`, because `director` is an
     unset `@export`. This also leaves 71 orphaned nodes (the HUD instance `_ready()`
     unconditionally queues onto `get_tree().root`, plus more from `_build_sections()`).
   - The proposed workaround — calling the spawn function "without going through the full scene"
     — cannot work at all: `_spawn_bonus_drone()` calls `get_viewport().get_camera_2d()`, and
     `get_viewport()` returns `null` on a node that was never added to the tree (confirmed: a bare
     `Node.new()`'s `get_viewport()` is `<Object#null>` off-tree). Calling `.get_camera_2d()` on
     that null immediately throws — there is no code path where calling the function "directly"
     on an un-added instance reaches the line under test.
   - I also confirmed a working alternative exists (assign a real `LevelDirector` to `director`
     and a real `WaveManager` to `wave_manager` *before* `add_child_autofree`, avoiding the
     `_ready()` crash), but it still leaves ~71 orphaned nodes GUT will flag, which the plan does
     not mention needing cleanup (e.g. freeing the HUD node `_ready()` adds to `get_tree().root`).
   The plan's own Risks section anticipated needing a mitigation here, so this isn't an
   unforeseen category of problem — the specific mitigation offered is just wrong, and as written
   it would cost the implementer a debugging cycle discovering both failure modes before landing
   on the "wire `director`/`wave_manager` and clean up orphans" approach. This should be corrected
   before implementation starts, per the task's explicit "described test setup won't actually work
   in GUT" criterion.

2. **The plan's doc-update step misses a comment that becomes false once the fix lands.**
   `arena_camera.gd:7-11` documents, as a load-bearing design guarantee: "This keeps
   cam.global_position stable so: ... WaveManager spawn positions (cam.global_position +
   entry_offset) always resolve from the fixed screen centre — no drift on delayed spawns." After
   this fix, spawn positions resolve from `cam.global_position + cam.offset`, not the fixed
   centre, and a delayed spawn (`WaveManager._spawn_with_delay`, which awaits before calling
   `_spawn_ship`) will now resolve against whatever the camera's pan is *when the delay elapses*,
   not at trigger time — a real, if desirable, behavior change the plan never states explicitly.
   The plan's "Build sequence" step 6 only lists `ENEMY.md` and
   `docs/plans/station-reinforcements/3-plan.md` for updates; it should also touch this comment,
   both because it will be actively misleading once stale and because CLAUDE.md's docs-currency
   mandate applies to exactly this kind of change.

## Scope boundary

Correctly drawn. The exclusion list (despawn/exit checks, `gunship`/`light_assault_ship`
`_hold_y` waypoints, no `ArenaCamera` behavior change) matches what the code actually does at
every cited line, and no spawn site is left out.

## Recommendation

Fix finding 1 (specify a test setup for `Level1Director` that actually reaches the code under
test — wiring `director`/`wave_manager` and handling the resulting orphans, or another approach
that avoids the `_ready()` side effects entirely) and fold finding 2 into the build sequence's doc
pass. The core design (add `cam.offset` at the three sites, matching the `score_popup.gd`
precedent, no new public API) is sound and does not need to change.

---

## Round 2 — plan revised, re-review requested

Changes made in response to the findings above:

1. **Finding 1 (Level1Director test setup)** — replaced the broken mitigation with a verified
   technique: `add_child_autofree()` a plain scriptless `Node`, then `.set_script(...)` the
   `Level1Director` script onto it *after* it has entered the tree. Confirmed empirically with a
   throwaway headless `SceneTree` probe (`n.set_script(...)` after `add_child`, checked
   `ready_called == false` and `n.is_inside_tree() == true` / `get_viewport()` non-null
   afterwards) that this reaches `get_viewport().get_camera_2d()` inside `_spawn_bonus_drone()`
   without invoking `_ready()` at all — zero HUD instance, zero section building, zero orphans.
   See the plan's test case 3 and its Risks section.
2. **Finding 2 (stale header comment)** — added `arena_camera.gd:7-11`'s header comment to the
   plan's build sequence (step 6) and spelled out exactly what changes: `global_position`-fixed
   still keeps `EnemyPathMover`'s cam-scroll delta at 0 (untouched), but the "resolve from the
   fixed screen centre" claim for spawn positions is now false and gets rewritten to state spawns
   resolve against the camera's current view (`global_position + offset`) including whatever pan
   has happened by the time a delayed spawn fires.

Requesting re-review of the updated `3-plan.md`.

---

## Round 2 — re-review

VERDICT: APPROVED

### Finding 2 (stale header comment) — confirmed fixed

`3-plan.md`'s "Build sequence" step 6 now explicitly lists `arena_camera.gd:7-11`'s header comment
alongside `ENEMY.md` and `docs/plans/station-reinforcements/3-plan.md`'s risk note, and the
dedicated "Header comment that becomes false" subsection spells out the exact before/after text:
what stays true (`EnemyPathMover`'s cam-scroll delta pinned at 0, since that depends only on
`global_position` never moving) versus what becomes false (spawns "always resolve from the fixed
screen centre") and its replacement wording. Confirmed against the live file
(`assault/scenes/systems/arena_camera.gd:5-11`) that the comment still reads the old, soon-to-be-false
way today, so this is a real, still-needed edit the plan now correctly schedules.

### Finding 1 (set_script-after-tree-entry claim) — independently verified, holds

I did not take the plan's or round 1's word for it. I wrote a fresh, throwaway headless `SceneTree`
probe under `tests/tmp_review_probe/` (deleted after use, confirmed by `git status --porcelain`
showing only the plan directory as untracked) and iterated through three variants:

1. **First attempt (flawed) — ran the add_child during `_init()`.** This gave a misleading result
   (`is_inside_tree()` was `false` immediately after `root.add_child(n)`, and `_ready()` fired only
   *after* `set_script()` plus two awaited frames — i.e. it looked like the claim was wrong). This
   turned out to be an artifact of doing tree operations before the `SceneTree`'s own startup had
   finished (`root.is_inside_tree()` itself was not yet reliable at that point) — not representative
   of a live GUT test, which always runs inside an already-running tree.
2. **Corrected version — deferred the probe to after the tree was confirmed running**
   (`_initialize()` → `call_deferred`), matching how GUT test bodies actually execute. Result,
   fully synchronous (no `await` at all, matching a plain non-yielding GUT test method):
   - `add_child(n)` on a plain scriptless `Node` → `is_inside_tree() == true` immediately, no script
     yet so no observable `_ready()` effect.
   - `n.set_script(preload(".../probe_target.gd"))` immediately after → `ready_called` stayed
     `false` — the target script's `_ready()` never fired.
   - `n.get_viewport()` was non-null, and `n.get_viewport().get_camera_2d()` was callable without
     throwing.
   - Extended the check further than either prior probe: added a **real** `Camera2D` to the tree
     with `make_current()` afterward and confirmed `get_viewport().get_camera_2d()` on the
     script-attached node correctly found it (`ready_called` remained `false` throughout).
3. Repeated with two full `await process_frame` cycles after `set_script()` for good measure —
   `ready_called` stayed `false` even after two frames, so this isn't a same-frame timing accident
   that would flip once GUT's own frame processing runs.

This directly confirms the plan's load-bearing claim: attaching a script to a node **after** it has
already entered the tree does not retroactively invoke that script's `_ready()`, while
`get_viewport()` (and, concretely, `get_viewport().get_camera_2d()`) work correctly on that node
because it is genuinely in the tree. Test case 3 in `3-plan.md` can be built exactly as written.

### Rest of the plan — sanity-checked, unchanged and correct

- All three formula sites' current line numbers and code were re-read directly and match the plan
  exactly: `wave_manager.gd:172` (`spawn_pos: Vector2 = cam.global_position + spawn.get("offset",
  Vector2.ZERO) * ArenaCamera.WORLD_SCALE`), `station_reinforcements.gd:238`
  (`entity.global_position = _spawn_origin() + entry.base_offset * ArenaCamera.WORLD_SCALE`) with
  `_spawn_origin()` at `:282-286` unchanged from round 1's citation, and `level_1_director.gd:125`
  (`(entity as Node2D).global_position = cam.global_position + camera_offset`, still raw px per the
  plan's note that this site doesn't scale by `WORLD_SCALE`).
  `ENEMY.md:278` and `station-reinforcements/3-plan.md:316-319` still carry the pre-fix "`V_LIMIT`
  deliberately excluded" language today, confirming the doc-update step is still live work, not
  already done or stale.
- Test cases 1 and 2, the scope boundary, and the margin-budget consequence section are unchanged
  from what round 1 already verified line-by-line; nothing in the finding-1/finding-2 revisions
  touched them, and re-reading them found no new inconsistency introduced by the edit.

### Recommendation

No further changes requested. The plan is ready for implementation.
