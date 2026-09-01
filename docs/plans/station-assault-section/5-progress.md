# Progress

Implementing revision 2 of `3-plan.md` (approved in review round 2). §0 and tests 1-3 are
**withdrawn** per review M1 and were never built.

- [x] Step 1 — `LevelSection.enemies_cleared_timeout` export, defaulting to `10.0`
      (`global/resources/levels/level_section.gd`). → test 4 green.
- [x] Step 2 — `LevelDirector._wait_enemies_cleared()` reads the section's timeout and frees
      every remaining container child on expiry
      (`assault/scenes/systems/level_director/level_director.gd:105-137`). → tests 5, 6, 7 green.
- [x] Step 3 — `WaveBuilder.SPACE_STATION` const + `space_station()` constructor
      (`assault/scenes/systems/wave_builder.gd:93, :245`).
- [x] Step 4 — `assault/scenes/levels/edelia/1/phases/phase_station_assault.tres` (three
      properties, no `transition_in_duration` — review M3).
- [x] Step 5 — `Level1Director._build_sections()` refactor + `_build_station_assault()`
      (`assault/scenes/levels/edelia/1/level_1_director.gd`). → tests 8, 9, 10 green.
- [x] Step 6 — docs per §6.
- [x] Step 7 — gate check.

**Resume at:** complete.

## Red before green

The new file was run before any implementation existed. GUT collected it (**19** scripts, so it
was not silently dropped) and reported **7 failing tests**, exit code 1, with stderr showing the
expected causes and nothing else:

```
Invalid access to property or key 'enemies_cleared_timeout' on a base object of type 'Resource (LevelSection)'
Invalid call. Nonexistent function '_build_sections' in base 'Node (level_1_director.gd)'
```

## Deviations from plan

1. **The new `.tres` carries no UID.** The plan did not specify one. `BACKLOG.md`'s *Discovered*
   list flags hand-written UIDs as a silent-collision risk, and no `[ext_resource]` anywhere
   references this file — `level_1_director.gd` `preload`s it by path, exactly as it does the
   other four phases. So the header omits `uid=` rather than inventing a ninth hand-typed one.
   `test_resource_uid_integrity.gd` still passes.

2. **Test 5 drains the director's coroutine before teardown.** Not in the plan, and it was not
   predictable from reading: ending a test while `_wait_enemies_cleared()` is suspended inside
   `_wait_for_child_exit_or_timeout()` strands that helper's 1 s `SceneTreeTimer` and its
   `GDScriptFunctionState`, which Godot reports at process exit as

   ```
   WARNING: ObjectDB instances leaked at exit
   ERROR: 1 resources still in use at exit
   Resource still in use: res://assault/scenes/systems/level_director/level_director.gd
   ```

   Confirmed as introduced by this file by running the suite with it removed (clean) and with it
   present (leaking), then identified with `--verbose`. The gate's FATAL regex does not match
   either line, so **this would have passed the gate while leaking.** Fixed by freeing the enemy
   and waiting 0.5 s at the end of test 5; tests 6 and 7 already run the wait to completion.
   Re-verified: no `leaked` or `still in use` lines in the full suite run.

3. **`_ready()`'s section wiring is a `for` loop** over `_build_sections()` rather than four named
   locals plus four `add_section` calls. Same behaviour, and it means adding a sixth section later
   touches only the builder list.

## Verification

`bash /agent/verify.sh` → **GATE PASS**. GUT: **19** scripts, **172** tests, **172** passing
(baseline before this change: 18 / 165 / 165), no `Parse Error` or `SCRIPT ERROR` on stderr, no
leak lines. Sub-item 1's nine `test_space_station.gd` tests pass unchanged — `space_station.tscn`
was not modified.
