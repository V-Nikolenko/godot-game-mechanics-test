# Log records placeable in assault and infiltration missions

## Problem

Every log record today only exists in the open-space hub. Two independent things stop that from
generalizing, and this plan fixes both without waiting on unrelated in-flight work:

1. **The ground (infiltration) player cannot collect anything.** It's a plain `CharacterBody2D`,
   not a `PlayerBase`, and is not in the `"player"` group. `PickupBase._on_body_entered` requires
   both, so no `PickupBase` pickup can ever fire there — and while `InfoLogInteractable` doesn't
   need the `PlayerBase` cast, it still needs the group tag, so it silently no-ops there too.
2. **A one-time, counted pickup placed in a *replayable* mission can double-grant.** Assault
   missions can be restarted from the pause menu (`pause_menu.gd:149`,
   `get_tree().reload_current_scene()`), which respawns every static child fresh with no memory.
   `LogState.collect_next()` is anonymous/sequential — it has no idea a specific placement already
   fired once, so a respawned lore-log pickup would hand out a *new* catalogue entry on every
   replay. This is exactly the "miss-able collectible" trap the task calls out.

The actual `LoreLogPickup` class (the `PickupBase` subclass that would call
`LogState.collect_next()`) is being built by a sibling task in this epic
(`flying-into-a-log-record-in-open-space-picks-it-up-and-tells`), currently **stuck** two review
rounds in over an unrelated test-design issue — the class itself doesn't exist in the repo yet.
This plan does not build it (see Out of scope) — it fixes both problems above at the
infrastructure level and demonstrates real placement using `InfoLogInteractable`, which already
exists, is a real "log record" type per the epic's own spec (an Information Log), and needs only
fix (1) to work in every mode.

## Design

### 1. Infiltration pickup detection (fixes the named "real obstacle")

- `infiltration/scenes/entities/player/player.gd::_ready()` gains `add_to_group("player")` as its
  first line (mirroring `global/entities/player_base.gd:56` exactly).
- **Discovered during implementation, not caught by either review round**: the group fix alone
  is not sufficient. `InfoLogInteractable`/`PickupBase` Area2Ds only ever emit `body_entered` for
  a body whose `collision_layer` overlaps their `collision_mask` (`4`, the `"environemnt_player"`
  layer every pickup/interactable scene uses — `player_fighter.tscn` sets `collision_layer = 4`
  to be detectable by it). `infiltration/scenes/entities/player/player.tscn`'s `CharacterBody2D`
  set no `collision_layer` at all (Godot default: layer 1 only), so the signal itself would never
  have fired for the infiltration player regardless of group membership — every test that calls
  `_on_body_entered()` directly (including the ones in this plan's own test list) passes on this
  broken state, since it bypasses physics entirely. Fixed by adding `collision_layer = 4` to the
  `Player` node in `player.tscn`, alongside the group fix. A new integration test,
  `test_test_isometric_scene_log_record_detects_the_real_player_via_physics` in
  `tests/integration/test_log_record_mission_placement.gd`, positions both bodies overlapping and
  awaits real `physics_frame`s rather than calling the handler directly — verified this test
  fails without the `collision_layer` line and passes with it.
- `global/pickups/pickup_base.gd` widens its **detection** (the group/cast gate in
  `_on_body_entered`) without widening the `_collect` override contract itself, per the task's
  explicit option (a):

  ```gdscript
  func _on_body_entered(body: Node2D) -> void:
      if not body.is_in_group("player"):
          return
      if persistent_id != &"" and PickupState.has_collected(persistent_id):
          queue_free()
          return
      var player := body as PlayerBase
      var handled := true
      if player != null:
          _collect(player)
      else:
          handled = _collect_any(body)
      if not handled:
          return
      if persistent_id != &"":
          PickupState.mark_collected(persistent_id)
      var text: String = _get_dialog_text()
      if not text.is_empty():
          _show_notification(text)
      queue_free()

  func _collect(_player: PlayerBase) -> void:
      pass

  ## Fallback hook for a body that is in group "player" but is not a PlayerBase (e.g. the
  ## infiltration CharacterBody2D). Returning false (the default) means "not for me" — the
  ## pickup does not consume itself, mark persistent_id, or notify, exactly as if detection had
  ## never widened. A future non-PlayerBase-aware pickup overrides this and returns true.
  func _collect_any(_body: Node2D) -> bool:
      return false
  ```

  Rejected alternative — option (b), giving the infiltration player `PlayerBase`: explicitly ruled
  out by the task body as a much larger change to a module this epic isn't touching.

  **Correction from review round 1**: the original design proposed retyping `_collect`'s
  parameter from `PlayerBase` to `Node2D` directly, on the claim that GDScript permits an
  override to narrow a parent's declared parameter type back down to a subtype, "verified" via
  `godot --headless --path . --import` against two throwaway classes. The independent reviewer
  reproduced the same scenario against this exact build (4.6.3) and got a real
  `SCRIPT ERROR: Parse Error: The function signature doesn't match the parent` — `--import` only
  does lightweight class-name registration and never forces the full compile that surfaces this,
  so the original verification method was not sufficient evidence. Retyping `_collect` as
  written would have broken compilation of all 9 existing subclasses project-wide.

  The corrected design instead adds a **second, separate virtual hook**, `_collect_any(body:
  Node2D)`, with a no-op default — `_collect(player: PlayerBase)`'s signature is completely
  untouched. This is safe for the 9 existing `PickupBase` subclasses
  (`armor_tank_pickup.gd`, `health_tank_pickup.gd`, `armor_and_health_pickup.gd`,
  `ship_shield_up_pickup.gd`, `temporary_damage_up_pickup.gd`,
  `temporary_health_shield_up_pickup.gd`, `temporary_health_up_pickup.gd`,
  `temporary_shield_up_pickup.gd`, `ship_module_unlocker_pickup.gd`,
  `weapon_mode_unlocker_pickup.gd`) because none of them override `_collect_any`, they keep
  overriding `_collect(player: PlayerBase)` exactly as today with no signature change at all, and
  they are still only ever handed a real `PlayerBase` instance (confirmed: none of the 9 are
  placed anywhere but `open_space`/`assault`, where the body is always a `PlayerBase`). **No file
  among the 9 needs to change.** A future non-`PlayerBase`-aware pickup (e.g. a `LoreLogPickup`
  variant meant to work in infiltration) overrides `_collect_any` instead of `_collect`. Behavior
  for a body that is in group `"player"` but fails the `PlayerBase` cast (the infiltration
  player, and only the infiltration player) is unchanged from today for all 9 existing pickups —
  `_collect_any`'s default no-op means nothing happens, the pickup does not free itself or fire
  its notification, exactly as if detection had never widened for them at all — while a pickup
  that opts in by overriding `_collect_any` now works there.

### 2. Restart-safe one-time pickups (`PickupState` autoload)

New autoload `global/autoloads/pickup_state.gd`, registered in `project.godot`, modeled directly
on `LogState`'s save shape:

```gdscript
extends Node
## Tracks which persistent-id pickups have ever been collected, independent of any specific
## physical node — so a pickup placed in a mission that can be restarted (assault) doesn't
## re-grant itself just because the scene reloaded and respawned the node fresh. Opt-in via
## PickupBase.persistent_id; a pickup that leaves persistent_id empty (every pickup today)
## is untouched by this and keeps respawning every scene load, which is what health/shield/
## module pickups already want.

const SAVE_PATH := "user://pickup_state.cfg"
const SECTION := "collected"

var _collected: Dictionary = {}

func _ready() -> void:
    _load()

func has_collected(id: StringName) -> bool:
    return _collected.get(id, false)

func mark_collected(id: StringName) -> void:
    if _collected.get(id, false):
        return
    _collected[id] = true
    _save()

func _save() -> void: ...  # ConfigFile, same shape as LogState._save()
func _load() -> void: ...  # ConfigFile, same shape as LogState._load()
```

`global/pickups/pickup_base.gd` gains:

```gdscript
## Empty by default — this pickup respawns fresh every time its scene loads, which is what
## health/shield/module pickups already want on a mission restart. Set to a level-unique id to
## make a one-time pickup (e.g. a future lore-log placement) remember "already granted" across
## a scene reload, so replaying the mission does not collect it again.
@export var persistent_id: StringName = &""
```

`_collect()`/`_get_dialog_text()` never run a second time for the same `persistent_id` — the node
is silently `queue_free()`'d instead, matching "a player who quits mid-mission after grabbing one
should not be punished for it": once granted, it's granted, regardless of whether the mission is
later completed, restarted, or abandoned.

`tests/helpers/save_sandbox.gd`'s `PATHS` gains `"user://pickup_state.cfg"`.

This is the primitive the (currently stuck) `LoreLogPickup` task will consume with a single
`persistent_id` value per placement once it lands — no further `PickupBase` change needed then.

### 3. Concrete placement: `InfoLogInteractable` in one assault level and the infiltration test scene

Both placements use the **existing, unmodified** `InfoLogInteractable` scene
(`global/interactables/scenes/info_log_interactable.tscn`) — no `persistent_id` needed, since
information logs are explicitly stateless/re-readable by design (never touches `LogState`, no
completion tracking), so the restart trap in problem (2) does not apply to them at all. This also
means "Done when"'s replay/restart criterion is proven at the `PickupState`/`PickupBase` unit level
(problem 2's actual fix), not by the info-log placements — nothing about an info log's behavior on
restart needs a new test; `test_info_log_interactable.gd` already covers "reading twice is
idempotent."

- **Assault**: `assault/scenes/levels/edelia/1/level_1.tscn` gains an `InfoLogInteractable`
  instance as a static child of the level root, alongside `PlayerFighter`/`LaserWallWave`. Static
  children in this scene are never routed through `WaveManager` (confirmed: `WaveManager`/
  `ScoreTracker` treat *any* spawned-and-freed node as a wave/escape entry via
  `enemy.get(...) != null else true`, so a collected pickup would misfire the escape-combo
  penalty — routing a pickup through that system is a bug, not a convention to follow here).
  Position is computed from the same design-space formula waves use, at `t = 0` (`cam.offset ==
  Vector2.ZERO` at level start): `world_pos = Vector2(640, 360) + design_offset * ArenaCamera.
  WORLD_SCALE`. Choosing a design offset of `(-60, -60)` gives `world_pos = (520, 240)` — near the
  `deep_space` section's opening area, clear of `LaserWallWave` (`y = -380`). The derivation is
  written as a scene comment (`.tscn` files support `;`-prefixed comments, precedent:
  `TestIsometricScene.tscn`) so the next person placing something here isn't left guessing where a
  bare `position` number came from.
- **Infiltration**: `infiltration/scenes/levels/TestIsometricScene.tscn` gains an
  `InfoLogInteractable` instance near the player start (`Player position = Vector2(166, -120)`);
  placed at `Vector2(260, -120)`, a plain raw-pixel position matching every other node in this
  scene — infiltration has no design-space/`WORLD_SCALE` concept at all (confirmed:
  `ArenaCamera`/`WORLD_SCALE` are assault-only), so there is nothing to derive here beyond "a few
  steps from spawn."

## Build sequence

1. `infiltration/scenes/entities/player/player.gd`: add `add_to_group("player")` in `_ready()`.
   Failing test first: `tests/unit/test_infiltration_player_group.gd` (new) instantiates the
   player scene, asserts `is_in_group("player")`.
2. `global/autoloads/pickup_state.gd` + `project.godot` autoload registration +
   `tests/helpers/save_sandbox.gd` path. `tests/unit/test_pickup_state.gd` (new, modeled on
   `test_log_state.gd`): collect-once, idempotent-on-repeat, survives a save/load round trip.
   **(Reordered ahead of the `PickupBase` step below after round-2 review: `PickupBase` step 3
   references `PickupState.has_collected`/`mark_collected`, which must exist and be tested first
   or step 3 cannot compile/be tested standalone.)**
3. `global/pickups/pickup_base.gd`: add the `_collect_any(body: Node2D) -> bool` fallback hook
   (default `return false`, `_collect(player: PlayerBase)` untouched), add `persistent_id` +
   `PickupState` checks. Failing tests first, extending `tests/unit/test_pickup_base.gd` (new,
   using tiny test-double `PickupBase` subclasses — no existing pickup test file exists to
   extend):
   - a persistent-id pickup collects once and calls `_collect`.
   - a **second** instance sharing the same `persistent_id` (simulating a scene reload
     respawning the node) does not call `_collect` again and frees itself immediately — the
     restart/replay boundary case.
   - a pickup with `persistent_id == &""` (every existing pickup) is unaffected — collects every
     time, matching current behavior exactly (characterization).
   - a body that is in group `"player"` but is a plain `Node2D` (simulating the infiltration
     player), against a test-double whose `_collect_any` override returns `true`: the pickup
     calls `_collect_any` and consumes itself (marks `persistent_id`, notifies, frees) — proves
     the opt-in generic path works end-to-end.
   - the same plain-`Node2D` body against the **base class default** (`_collect_any` not
     overridden, returns `false`): the pickup does **not** free itself, mark `persistent_id`, or
     notify — proves the 9 existing subclasses are inert against a non-`PlayerBase` body exactly
     as before, the boundary case Finding 1 of the round-1 review exists to guard.
4. Place `InfoLogInteractable` in `level_1.tscn` and `TestIsometricScene.tscn`.
   `tests/integration/test_log_record_mission_placement.gd` (new):
   - loads `level_1.tscn`, finds the placed `InfoLogInteractable` by type, asserts it exists and
     `_on_body_entered`/interact collects it (reusing the same pattern as
     `test_info_log_interactable.gd`, not starting a real `DialogPlayer.play()` coroutine per that
     file's documented leak trap).
   - loads `TestIsometricScene.tscn`, adds the (now group-fixed) infiltration `Player` scene as
     the body, asserts the placed `InfoLogInteractable` reacts to it (`_on_body_entered` shows the
     prompt) — this is the test that actually exercises fix (1) end-to-end.
5. `bash /agent/verify.sh`.

Each step is independently checkable.

## Test plan

- `tests/unit/test_infiltration_player_group.gd` — infiltration `Player` is in group `"player"`.
- `tests/unit/test_pickup_base.gd` — the opt-in `_collect_any` fallback (a plain `Node2D` body
  reaches a test-double's `_collect_any` and is consumed when it returns `true`, and is left
  untouched when the base-class default returns `false`), `persistent_id` collect-once/replay-
  safety (the boundary case), and the `persistent_id == &""` characterization case proving zero
  behavior change for existing pickups.
- `tests/unit/test_pickup_state.gd` — `has_collected`/`mark_collected`, idempotent double-mark,
  save/load round trip (via `SaveSandbox`, same pattern as `test_log_state.gd`).
- `tests/integration/test_log_record_mission_placement.gd` — the "Done when" proof: a log placed
  in `level_1.tscn` and one in `TestIsometricScene.tscn` are both reachable/collectable by their
  respective real player scenes.

## Risks

- `enemy.get(...)` returning `null` for a non-enemy and the `else true` fallback in `ScoreTracker`
  is a real landmine for *any* future work that spawns a non-ship through `WaveManager` — noted
  here because it's exactly why this plan avoids that path, but it is a pre-existing property of
  `ScoreTracker`, not something this task fixes (out of scope: it isn't touched by any placement
  this task makes).
- Round 1 review (`4-review.md`) reproduced a real Parse Error against this exact Godot build
  (4.6.3) when `_collect`'s declared parameter type is narrowed in a subclass override —
  `godot --headless --path . --import` alone does not surface this (it never forces a full script
  reload), so any future verification of a GDScript override-compatibility claim must force a real
  reload (e.g. run the GUT suite, or `test_project_load_integrity.gd`) rather than `--import`
  alone. The corrected design in this plan (a separate `_collect_any` hook, `_collect`'s signature
  untouched) sidesteps the override-compatibility question entirely rather than relying on it.

## Out of scope

- Building `LoreLogPickup` itself, or placing any Lore Log (persisted, completion-counting)
  instance anywhere — owned by `flying-into-a-log-record-in-open-space-picks-it-up-and-tells`,
  currently stuck in review. This plan's `PickupState`/`persistent_id` primitive is what that task
  will use, but does not itself ship a Lore Log placement.
- Giving the infiltration player `PlayerBase` (option (b), explicitly ruled out by the task body).
- Placing anything via `WaveManager`/`WaveBuilder` (actively wrong for a pickup — see Risks).
- Any change to `ScoreTracker`.
- Test-logs content authoring on the open-space map — owned by
  `test-logs-on-the-open-space-map-prove-both-log-types-work-en`.
