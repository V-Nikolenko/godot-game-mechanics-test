# Review: Log records can be placed in assault and infiltration missions

VERDICT: CHANGES_REQUESTED

## Summary

The scope cut (fix the cross-cutting infiltration-detection gap + build a `PickupState`
restart-safety primitive + demonstrate placement in both modes with the already-existing,
stateless `InfoLogInteractable`, deferring the actual `LoreLogPickup` to the stuck sibling
task) is a sound, well-justified reading of the task. Every factual claim about `WaveManager`/
`ScoreTracker`, `pause_menu.gd`'s restart path, `LogState`'s anonymous `collect_next()`, the
infiltration player's class, and the static-child placement pattern in `level_1.tscn` checks
out against the actual code. However, the plan's central technical claim in Design §1 — that
widening `PickupBase._collect`'s parameter type from `PlayerBase` to `Node2D` "is safe" and
"no file among the 9 [subclasses] needs to change" because GDScript permits an override to
narrow a parent method's declared parameter type back down to a subtype — is **factually
wrong**, verified by direct reproduction against this exact Godot 4.6.3 build. As designed,
step 2 of the build sequence would break the script compilation of all 9 existing `PickupBase`
subclasses project-wide, which `tests/integration/test_project_load_integrity.gd` would catch
at gate time (good, the gate wouldn't go green), but the plan as written cannot be implemented
as specified and needs to change before work starts.

## Findings

### 1. (Blocking) The override-narrowing safety claim is false — verified empirically on this build

`docs/plans/.../3-plan.md` lines 60-67 claim: "verified empirically against this Godot build
(godot --headless --path . --import against two throwaway classes) that GDScript does not
error or warn when an override narrows a base method's parameter type back down to a subtype
— each of the 9 keeps compiling unchanged."

I reproduced this exact scenario (base class with `_collect(_player: Node2D)`, subclass with
`_collect(player: PlayerBase)`, mirroring `global/pickups/pickup_base.gd:13-19` and e.g.
`global/pickups/armor_tank_pickup.gd:5`) against the same binary (`godot --headless`, engine
banner: `Godot Engine v4.6.3.stable.official.7d41c59c4`). Result:

```
SCRIPT ERROR: Parse Error: The function signature doesn't match the parent. Parent signature is "_collect(Node2D) -> void".
          at: GDScript::reload (res://sub.gd:4)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
```

The catch: `godot --headless --path . --import` alone (the exact command the plan cites as its
verification method) does **not** surface this — the "Registering global classes" step is a
lightweight name-registration pass, not a full compile. The error only appears once the script
is actually loaded/reloaded for real use (`load()`, `preload()`, or scene instantiation via
`--script`, or — critically — the project's own gate). I confirmed this two-step distinction
directly: `--import` printed no error for the throwaway pair; running a script that referenced
the subclass by its global name (forcing `GDScript::reload`) immediately produced the Parse
Error above. The plan's verification method is therefore the reason its claim looks true and
isn't — `--import` is not sufficient evidence for "compiles."

Consequence: if `pickup_base.gd::_collect` is widened to `Node2D` while all 9 subclasses
(`armor_tank_pickup.gd`, `health_tank_pickup.gd`, `armor_and_health_pickup.gd`,
`ship_shield_up_pickup.gd`, `temporary_damage_up_pickup.gd`, `temporary_health_shield_up_pickup.gd`,
`temporary_health_up_pickup.gd`, `temporary_shield_up_pickup.gd`, `ship_module_unlocker_pickup.gd`,
`weapon_mode_unlocker_pickup.gd` — I additionally read `armor_tank_pickup.gd`,
`ship_module_unlocker_pickup.gd`, and `weapon_mode_unlocker_pickup.gd` directly and confirmed
each still declares `func _collect(player: PlayerBase) -> void` / `func _collect(_player:
PlayerBase) -> void`) are left untouched, **every one of those 9 scripts fails to compile**.
This isn't a narrow risk — it breaks health/shield/armor/module/weapon pickups everywhere they
are placed (`global/pickups/scenes/*.tscn` and `open_space/scenes/levels/sector_hub.tscn`,
confirmed by grep). `tests/integration/test_project_load_integrity.gd::test_every_script_compiles`
(walks every `.gd` outside `addons/`, asserts `can_instantiate()`) would fail the gate — so this
would not silently ship, but the plan as written is not implementable and would burn a full
build-sequence step before failing step 5 (`bash /agent/verify.sh`).

I additionally verified a real fix exists and is cheap: an **untyped** override parameter
(`func _collect(player) -> void:`) compiles cleanly against a `Node2D`-typed parent signature
in the same reproduction. So the plan's underlying idea (widen the base, keep behavior for the
9 unchanged) is achievable — it just cannot claim "no file among the 9 needs to change." Either
every one of the 9 needs its override's type annotation loosened (to `Node2D`, with an internal
`as PlayerBase` cast/guard, or left untyped), or the widening needs a different shape entirely
(e.g. `PickupBase` keeps `_collect(player: PlayerBase)` and gains a separate, non-overridden
`_collect_node2d`-style entry point that only `InfoLogInteractable`-style future subclasses use).
The plan needs to pick one and update Design §1 and Build-sequence step 2 accordingly — this
also changes the "no file among the 9 needs to change" framing used to justify not touching
`ScoreTracker` et al. is unaffected, but the "9 files, zero changes" scope statement in both
`1-context.md` (row for the 9 pickup files) and `3-plan.md` is not accurate and needs to be
corrected before implementation starts.

### 2. (Non-blocking, worth a decision) Replay/restart boundary case is proven only at unit level

`3-plan.md` lines 130-133 explicitly acknowledge that "Done when"'s replay/restart criterion is
proven only at the `PickupState`/`PickupBase` unit level, not via an actual assault-mission
scene-reload. I read `pause_menu.gd:149` (`get_tree().reload_current_scene()`) and confirm this
is the real trigger the task calls out ("Decide and test what happens to an already-collected
log on a replay"). Since no persisted/counted log is placed anywhere by this task (that's the
stuck sibling's job), there is genuinely nothing end-to-end to integration-test yet — the unit
test on `PickupBase`+`PickupState` (second instance sharing `persistent_id`, simulating a
scene-reload respawn, must not double-collect) is a real, falsifiable boundary case and is the
right level of test for the code this task actually ships. This is a defensible scope cut, not
a gap to block on, but flagging it because the task text names the replay trap explicitly and a
reviewer of the *next* task (the one that actually places a `LoreLogPickup` in a replayable
mission) should not assume this task already proved the reload path works end-to-end — it
proved the primitive, not the integration.

### 3. Everything else checked out

- `global/pickups/pickup_base.gd:13-19` — confirmed `_on_body_entered` requires both
  `is_in_group("player")` and a successful `as PlayerBase` cast, exactly as claimed.
- `global/entities/player_base.gd:55-56` — confirmed `add_to_group("player")` is the only
  place group membership is granted, and it's the first line of `_ready()`.
- `infiltration/scenes/entities/player/player.gd:35-37` — confirmed plain `CharacterBody2D`,
  no `add_to_group` anywhere, `_ready()` currently just calls `refresh_modules()`.
- `global/interactables/info_log_interactable.gd:24-26` — confirmed `_on_body_entered` checks
  only `is_in_group("player")`, no `PlayerBase` cast, never touches `LogState`.
- `global/autoloads/log_state.gd:80-87` — confirmed `collect_next()` is anonymous/sequential
  with no per-placement identity, matching the plan's framing of the "missable collectible"
  root cause.
- `assault/scenes/systems/wave_manager/wave_manager.gd:159-190` and
  `assault/scenes/systems/score_tracker/score_tracker.gd:137-143` — confirmed
  `_spawn_ship` emits `enemy_spawned` for any `PackedScene`, and
  `ScoreTracker._on_enemy_spawned` defaults both `counts_in_wave` and `counts_as_escape` to
  `true` via `enemy.get(...) != null else true` when the spawned node has neither property —
  routing a pickup through `WaveManager` would indeed misfire the wave-clear tally and the
  escape-combo penalty on collection. Avoiding that path is correct.
- `assault/scenes/levels/edelia/1/level_1.tscn:43-47` — confirmed `LaserWallWave` and
  `PlayerFighter` are static top-level children with resolved-pixel `position`, the pattern the
  plan proposes to copy.
- `assault/scenes/hazards/laser_ray/laser_wall.tscn` — checked the actual hazard geometry:
  `LaserWallWave` sits at world `(0, -380)` and its 12 `Laser` children span local x = 28..644
  (all y = 0 relative to the wall), so the wall occupies a horizontal band at world y = -380.
  The plan's proposed placement at `(520, 240)` is 620px away vertically — genuinely clear, the
  arithmetic and the clearance claim both hold.
- `global/ui/pause_menu/pause_menu.gd:149` — confirmed `_confirm()` case 1 (Restart) calls
  `get_tree().reload_current_scene()` directly.
- `tests/helpers/save_sandbox.gd:16-23` — confirmed `PATHS` is a flat hand-maintained array
  that would need `"user://pickup_state.cfg"` appended, per the plan.
- `infiltration/scenes/levels/TestIsometricScene.tscn` — confirmed it's backdrop + `Player`
  (`position = Vector2(166, -120)`) + `PauseMenu`, matching the plan's placement target and
  proposed `InfoLogInteractable` position `(260, -120)`.
- Grep confirms the 9 `PickupBase` subclasses are only ever instanced from
  `global/pickups/scenes/*.tscn` and `open_space/scenes/levels/sector_hub.tscn` — the "never
  placed in infiltration" premise behind the (otherwise broken) safety claim is itself correct,
  it just doesn't rescue the compile error, which happens at script-load time regardless of
  where the scene is placed.
- `tests/unit/test_info_log_interactable.gd` and `tests/unit/test_log_state.gd` both exist,
  confirming the reuse/precedent claims.
- Build-sequence sizing is reasonable — each of the 5 steps is small and independently
  verifiable — once step 2 is corrected per Finding 1.

## What needs to change before approval

Fix Design §1 / Build-sequence step 2's account of the `_collect` widening: either loosen the
override signature (untyped or `Node2D`-typed with an internal cast) in all 9 existing
`PickupBase` subclasses as part of this task, or choose a different mechanism that genuinely
requires zero changes to those files. Update the "no file among the 9 needs to change" claims
in both `1-context.md` and `3-plan.md` to match whichever path is chosen, and re-verify
compilation with a method that actually forces a full script reload (e.g. run the GUT suite or
`test_project_load_integrity.gd` itself against the throwaway repro), not `--import` alone.

## Round 2

VERDICT: APPROVED

### Summary

The revision replaces the false "narrow the override, zero changes needed" claim with a
genuinely different mechanism — a new, non-overriding `_collect_any(body: Node2D) -> bool` hook
on `PickupBase`, with `_collect(player: PlayerBase)`'s signature left byte-for-byte untouched.
This sidesteps the override-narrowing question entirely rather than re-litigating it, which is
the right move. I re-read the current `global/pickups/pickup_base.gd` from disk, re-derived all
four dispatch cases by hand against the proposed `_on_body_entered`, and grepped the 9 subclasses
for collisions. The blocking finding from round 1 is fixed, cleanly, with no new correctness
problem in the design itself. I found one real but non-blocking issue in the **build-sequence
ordering** (not the design), detailed below.

### Findings

#### 1. (Fixed) Round-1 blocking finding — verified against the actual file

Read `global/pickups/pickup_base.gd:1-50` as it exists today. Current `_on_body_entered`
(lines 13-23):

```gdscript
func _on_body_entered(body: Node2D) -> void:
    if not body.is_in_group("player"):
        return
    var player := body as PlayerBase
    if player == null:
        return
    _collect(player)
    var text: String = _get_dialog_text()
    if not text.is_empty():
        _show_notification(text)
    queue_free()
```

The proposed rewrite (`3-plan.md` lines 40-69) is a faithful, complete superset of this: same
group gate first, same `_collect`/dialog/`queue_free()` sequence for the `PlayerBase` path when
`persistent_id == &""` (the characterization case — every existing pickup), nothing dropped. The
only behavioral additions are (a) an early `queue_free()` for an already-collected persistent
pickup, before the `PlayerBase` cast, and (b) the `_collect_any` fallback for a non-`PlayerBase`
body. `_show_notification`/dialog behavior and the relative position of `queue_free()` on the
existing path are unchanged.

Walked all four dispatch cases against the proposed code:

- **`PlayerBase` body, not previously collected**: `player != null` → `_collect(player)` runs,
  `handled` stays at its default `true` → `persistent_id` marked (if set) → dialog → `queue_free`.
  Matches today's behavior exactly when `persistent_id == &""`.
- **`persistent_id` set and already collected** (replay/restart case): short-circuits before the
  `PlayerBase` cast even runs — `queue_free()` and return, no `_collect`, no dialog. This is the
  fix for problem (2) (`PickupState`) and is independent of the `_collect_any` fix.
- **Generic (non-`PlayerBase`) body, `_collect_any` overridden to return `true`**: `player == null`
  → `handled = _collect_any(body)` = `true` → mark/dialog/`queue_free` same as the `PlayerBase`
  path. This is the opt-in path a future infiltration-aware pickup uses.
- **Generic body, base-class `_collect_any` default (`false`)**: `handled = false` → early
  return, no free/mark/notify — byte-for-byte the same as today's `player == null: return`. This
  is the exact boundary case round 1's Finding 1 exists to guard, and it is both designed and
  listed as a test in Build-sequence step 2.

#### 2. (Fixed) Legality of the new hook and the "9 files, 0 changes" claim — verified by grep

```
grep -rn "_collect_any" --include="*.gd" .   → 0 matches outside the plan text (does not exist yet)
grep -n "func _collect" global/pickups/*.gd  → each of the 9 still declares
                                                 func _collect(player: PlayerBase) / (_player: PlayerBase)
```

None of the 9 subclasses (`armor_tank_pickup.gd`, `health_tank_pickup.gd`,
`armor_and_health_pickup.gd`, `ship_shield_up_pickup.gd`, `temporary_damage_up_pickup.gd`,
`temporary_health_shield_up_pickup.gd`, `temporary_health_up_pickup.gd`,
`temporary_shield_up_pickup.gd`, `ship_module_unlocker_pickup.gd`,
`weapon_mode_unlocker_pickup.gd`) defines a method named `_collect_any`, so adding it to the base
class cannot collide with or narrow anything they declare — it's a brand-new virtual with a
default body, not an override of an existing parent signature, which is exactly the category of
change round 1 confirmed is safe (only *narrowing an existing override* triggered the Parse
Error). `_collect(player: PlayerBase)`'s signature is untouched in the base class and in all 9
subclasses, so the round-1 repro scenario does not apply here at all. Also grepped `_on_body_entered`
(only `pickup_base.gd` defines it — no subclass override to reconcile) and `_get_dialog_text`
(11 hits, all pre-existing, unaffected by this change). The "no file among the 9 needs to change"
claim in both `1-context.md` and `3-plan.md` now holds.

#### 3. (Non-blocking, should fix before implementation) Build-sequence step 2 forward-references an autoload step 3 creates

`3-plan.md` Build sequence step 2 (lines 195-213) has `pickup_base.gd` reference
`PickupState.has_collected(...)` / `PickupState.mark_collected(...)` and lists failing tests for
this — including "a persistent-id pickup collects once and calls `_collect`" and the replay
boundary case — as part of *step 2*. But the `PickupState` autoload class doesn't exist until
*step 3* (lines 214-216: `global/autoloads/pickup_state.gd` + `project.godot` registration).
Confirmed `PickupState` is not yet in the codebase (`find . -iname "pickup_state*"` → no results)
and not yet in `project.godot`'s `[autoload]` block (only `MissionState`, `DialogPlayer`,
`UpgradeState`, `EventBus`, `ShipModuleState`, `ShipProgressionState`, `SessionState`, `LogState`,
`CameraShake` are registered today).

If step 2 is implemented and tested strictly before step 3 as numbered, `pickup_base.gd` would
reference an undeclared global identifier (`PickupState` is neither a class nor a registered
autoload yet), which is a compile error for `pickup_base.gd` — and by extension, transitively,
for every one of the 9 subclasses that depends on it, the same failure *shape* (a base-class
change breaking all dependents) as round 1's finding, just from a different cause (undefined
identifier vs. signature mismatch). It would also break the "failing test first" methodology the
plan otherwise follows well: the step-2 tests would fail for the wrong reason (parse/compile
error) rather than for an unimplemented behavior, so a red-then-green cycle on step 2 alone isn't
achievable as sequenced. The plan's own claim "Each step is independently checkable" (line 228)
does not hold for step 2 as written.

This doesn't touch the design's correctness — the end state after both steps is fine, and any
implementer would naturally notice the missing autoload and reorder. It's cheap to fix: either
swap the step 2/3 order (create `PickupState` first, then wire the `persistent_id` checks into
`pickup_base.gd` as part of what is currently step 3), or merge steps 2 and 3 into one step since
they're already interdependent. Worth fixing in the plan text before an implementer hits it, but
not worth another review round over.

#### 4. Everything else re-checked

- `global/pickups/pickup_base.gd:9-23` (current) re-read in full — matches round 1's citation and
  the plan's stated baseline exactly.
- `grep -rn "persistent_id"` → 0 hits anywhere in the repo today, confirming this is genuinely new
  surface, not a rename of something existing.
- `tests/helpers/save_sandbox.gd:16-23` — confirmed `PATHS` still does not include
  `"user://pickup_state.cfg"`, so the plan's claim that this needs to be added still holds.
- `global/autoloads/log_state.gd` re-read in full as the stated model for `PickupState`'s
  save/load shape — `SAVE_PATH`/`SECTION`/`_save()`/`_load()` pattern is real and copyable as
  described.
- No existing `tests/**/*pickup*` test file (`find tests -iname "*pickup*"` → no results),
  confirming the plan's claim that `test_pickup_base.gd` and `test_pickup_state.gd` are new files,
  not extensions of something already there.
- Design §2/§3 and the Test plan section are otherwise unchanged in substance from round 1, which
  already checked out (round 1 Finding 3's 15 bullet points all still apply unchanged — none of
  the code they cite was touched by this revision).

### What would need to change for a future round (non-blocking)

Reorder or merge Build-sequence steps 2 and 3 so `pickup_base.gd`'s `PickupState` reference never
precedes `PickupState`'s own creation. This is a documentation fix to the plan, not a design
change, and does not block starting implementation.
