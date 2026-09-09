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
  first line (mirroring `global/entities/player_base.gd:56` exactly). This alone makes
  `InfoLogInteractable` work in infiltration — it never required a `PlayerBase` cast.
- `global/pickups/pickup_base.gd` widens its detection so a **future** `PickupBase`-derived pickup
  (i.e. the eventual `LoreLogPickup`) also works there, per the task's explicit option (a):

  ```gdscript
  func _on_body_entered(body: Node2D) -> void:
      if not body.is_in_group("player"):
          return
      if persistent_id != &"" and PickupState.has_collected(persistent_id):
          queue_free()
          return
      _collect(body)
      if persistent_id != &"":
          PickupState.mark_collected(persistent_id)
      var text: String = _get_dialog_text()
      if not text.is_empty():
          _show_notification(text)
      queue_free()

  func _collect(_player: Node2D) -> void:
      pass
  ```

  Rejected alternative — option (b), giving the infiltration player `PlayerBase`: explicitly ruled
  out by the task body as a much larger change to a module this epic isn't touching.

  **Why this is safe for the 9 existing `PickupBase` subclasses** (which all override
  `_collect(player: PlayerBase)` and several dereference `player.health_component` /
  `player.shield_component`): verified empirically against this Godot build
  (`godot --headless --path . --import` against two throwaway classes) that GDScript does not
  error or warn when an override narrows a base method's parameter type back down to a subtype —
  each of the 9 keeps compiling unchanged and is still only ever handed a real `PlayerBase`
  instance, since none of them are placed anywhere but `open_space`/`assault`. No file among the 9
  needs to change.

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
2. `global/pickups/pickup_base.gd`: widen `_collect`'s parameter type, add `persistent_id` +
   `PickupState` checks. Failing tests first, extending `tests/unit/test_pickup_base.gd` (new,
   using a tiny test-double `PickupBase` subclass — no existing pickup test file exists to extend):
   - a persistent-id pickup collects once and calls `_collect`.
   - a **second** instance sharing the same `persistent_id` (simulating a scene reload
     respawning the node) does not call `_collect` again and frees itself immediately — the
     restart/replay boundary case.
   - a pickup with `persistent_id == &""` (every existing pickup) is unaffected — collects every
     time, matching current behavior exactly (characterization).
   - a body that is in group `"player"` but is a plain `Node2D` (simulating the infiltration
     player) still reaches `_collect()` — proves the widened detection.
3. `global/autoloads/pickup_state.gd` + `project.godot` autoload registration +
   `tests/helpers/save_sandbox.gd` path. `tests/unit/test_pickup_state.gd` (new, modeled on
   `test_log_state.gd`): collect-once, idempotent-on-repeat, survives a save/load round trip.
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
- `tests/unit/test_pickup_base.gd` — widened detection (a plain `Node2D` player reaches
  `_collect`), `persistent_id` collect-once/replay-safety (the boundary case), and the
  `persistent_id == &""` characterization case proving zero behavior change for existing pickups.
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
- The Godot override-signature behavior (widening `_collect`'s param type) was verified against
  this exact Godot build (4.6.3), not against documentation — re-verify if the engine version
  changes.

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
