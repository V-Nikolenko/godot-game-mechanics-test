# Weapon Modes & Reflect Shield — Design Spec

**Date:** 2026-05-05
**Scope:** Assault mode primary fire is reworked into 5 selectable weapon modes (default, long range, piercing, spread, auto-aim). A separate Reflect shield upgrade is added on its own button. All six abilities are persistent ship upgrades.

---

## 1. Goals

1. Replace the single primary-fire bullet with **5 selectable weapon modes**, each with distinct ranges and trade-offs.
2. Add **Reflect**, a defensive shield with a tight i-frames-style timing window, as a separate upgrade slot — not a weapon mode.
3. Persist unlocks across sessions in a new `UpgradeState` autoload, populated by drops earned in missions or in the Open Space hub.
4. Keep existing rocket (special weapon) behavior intact; only its key bindings change.

---

## 2. Input map changes

| Action | Old | New | Notes |
|---|---|---|---|
| `interact` | E | **F** | Frees E for cycle. |
| `special_weapon` (rocket fire) | X | **K** | Frees X (still used by `dialog_auto`, no in-gameplay conflict). |
| `switch_weapon` (rocket type toggle) | Z | **Q** | |
| `cycle_weapon` (NEW) | — | **E** | Cycles primary fire through unlocked modes. |
| `reflect` (NEW) | — | **H** | Triggers reflect window. |

`shoot` (J + LMB) and all other actions are unchanged.

---

## 3. Weapon modes

Each mode is described by a `WeaponModeResource` (Resource subclass). Five `.tres` files ship with the project. All distances in pixels; the assault viewport is roughly 640×360.

| ID (`StringName`) | Range | Fire interval | Damage | Heat/shot | Notes |
|---|---|---|---|---|---|
| `&"default"` | 180 px (auto-expire by distance) | current rate | current (10) | 1.0 | Same as today, just range-clipped. |
| `&"long_range"` | none (until off-screen) | 0.4× current | 1.5× current | 2.0 | Slow, heavy single shot. |
| `&"piercing"` | full screen | held beam, sustained | 30 DPS to each enemy in beam | 3.0 / sec | Blocked by asteroids and undamaged ram-ships; damages every other enemy on the segment between muzzle and blocker. |
| `&"spread"` | 120 px (per pellet) | current rate | 0.5× current per pellet, 5 pellets in 60° fan | 1.5 | Devastating up close, useless mid-range. |
| `&"auto_aim"` | full screen | 0.7× current | 1× current | 1.5 | Each shot homes gently to the nearest enemy in the forward 90° cone; expires by lifetime. |

### `WeaponModeResource` schema

```gdscript
class_name WeaponModeResource
extends Resource

enum Behavior { STRAIGHT, LONG, BEAM, SPREAD, HOMING }

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D
@export var behavior: WeaponModeResource.Behavior = WeaponModeResource.Behavior.STRAIGHT
@export var projectile_scene: PackedScene  # null for BEAM
@export var range_px: float = 0.0          # 0 = no cap
@export var fire_interval: float = 0.18    # seconds between shots; ignored for BEAM (continuous)
@export var damage: int = 10
@export var heat_per_shot: float = 1.0     # for BEAM, this is heat per second
@export var pellet_count: int = 1          # SPREAD only
@export var pellet_spread_deg: float = 60.0  # SPREAD only
@export var homing_turn_rate_deg_per_sec: float = 90.0  # HOMING only
@export var homing_lifetime_sec: float = 1.6           # HOMING only
@export var beam_dps: float = 30.0         # BEAM only
```

---

## 4. UpgradeState autoload

New autoload at `global/autoload/upgrade_state.gd`. Persists to `user://upgrades.json`.

```gdscript
extends Node

const _SAVE_PATH := "user://upgrades.json"

signal unlocked(id: StringName)

var _unlocked: Dictionary[StringName, bool] = {}

func _ready() -> void:
    _load()
    if _unlocked.is_empty():
        _unlocked[&"default"] = true
        _save()

func is_unlocked(id: StringName) -> bool:
    return _unlocked.get(id, false)

func unlock(id: StringName) -> void:
    if _unlocked.get(id, false):
        return
    _unlocked[id] = true
    _save()
    unlocked.emit(id)

func unlocked_ids() -> Array[StringName]:
    var out: Array[StringName] = []
    for k in _unlocked.keys():
        if _unlocked[k]:
            out.append(k as StringName)
    return out

func unlock_all() -> void:
    for id in [&"default", &"long_range", &"piercing", &"spread", &"auto_aim", &"reflect"]:
        unlock(id)
```

Save format:
```json
{ "unlocked": ["default", "piercing"] }
```

A debug binding `Ctrl+U` (added to `_unhandled_input` in a debug-only script gated by `OS.is_debug_build()`) calls `UpgradeState.unlock_all()`.

---

## 5. WeaponState (replaces ShootingState)

`assault/scenes/player/states/shooting_state.gd` is renamed to `weapon_state.gd` and refactored:

- Holds `var _active_mode_id: StringName` (default: `&"default"`).
- On `cycle_weapon` action press: `_active_mode_id = next id in UpgradeState.unlocked_ids()` (wrapping). Emits `weapon_changed(mode)` signal for the HUD chip.
- On `shoot`: looks up the matching `WeaponModeResource` and dispatches to a `WeaponBehavior` strategy by `behavior` enum.
- Heat is applied per the mode's `heat_per_shot` (or per-second for BEAM, multiplied by `delta`).
- Fire interval is enforced via a per-mode cooldown timer the state manages.
- Muzzle alternation logic preserved for STRAIGHT and LONG.

### Behaviors (`assault/scenes/player/weapons/behaviors/`)

Each behavior is a small script with a single `fire(state, mode, muzzle)` entry point. They are plain `RefCounted` helpers, not nodes.

- **`straight_behavior.gd`** — instantiates `bullet.tscn`, sets `range_px` so the bullet auto-expires when traveled distance exceeds the limit. (Bullet gets a `range_px` field; `0` = unlimited.)
- **`long_range_behavior.gd`** — same projectile, no range cap, larger `damage`.
- **`beam_behavior.gd`** — every physics frame while `shoot` is held: raycasts from the active muzzle straight up to the screen top. Walks the ray's collisions with `intersect_shape` (or `intersect_ray` repeatedly with `exclude`) collecting bodies. Stops at first blocker (asteroid layer 1024 OR a `RamShip` whose `is_laser_blocking()` returns true). Applies `beam_dps * delta` damage to each enemy hurt-box up to (and not including) the blocker. Renders a `Line2D` from muzzle to terminal point. Heat accrues at `heat_per_shot * delta`.
- **`spread_behavior.gd`** — instantiates `pellet_count` bullets in a fan of `pellet_spread_deg` total spread, each with the mode's `range_px`.
- **`homing_behavior.gd`** — instantiates a new `PrimaryHoming` projectile (separate from the existing rocket-tier `homing_missile`). Picks nearest enemy in the front-90° cone at spawn time; turn-rate-limited.

### New projectiles

- **`assault/scenes/projectiles/primary_homing/primary_homing.gd` + `.tscn`** — Area2D, lighter visual than rockets, no rocket trail; obeys `homing_turn_rate_deg_per_sec` and `homing_lifetime_sec`.
- **`assault/scenes/projectiles/piercing_beam/piercing_beam.gd` + `.tscn`** — Node2D containing a `Line2D` and exposing `set_endpoints(from, to)`. Stateless visual-only.

### Bullet changes

`assault/scenes/projectiles/bullets/bullet.gd` adds:
```gdscript
@export var range_px: float = 0.0  # 0 = no cap
@export var damage: int = 10
var _traveled: float = 0.0

func _physics_process(delta: float) -> void:
    var step := speed * delta
    var forward := Vector2.UP.rotated(rotation)
    global_position += forward * step
    if range_px > 0.0:
        _traveled += step
        if _traveled >= range_px:
            expired.emit()
            queue_free()
```

The hit-box damage is sourced from `damage` instead of being hard-coded — requires updating wherever bullets currently apply damage. (Verify during implementation; if HitBox already reads from a script field, just point it at `damage`.)

---

## 6. Reflect shield (`reflect_state.gd`)

New state node parallel to `WeaponState`. Behavior:

- Listens for `reflect` action (H) press.
- Gated: if `not UpgradeState.is_unlocked(&"reflect")` → return.
- Cooldown: `1.0 s` between presses (per-state Timer).
- On press:
  1. Spawn a `ReflectArea` Area2D as a child of the player (radius ~24 px).
  2. Connect `area_entered` to a handler that flips any `EnemyBullet` it touches: `bullet.rotation += PI`, move to player projectile layer (and update collision_layer/mask so it now hits enemy hurt boxes).
  3. After **0.15 s**, free the `ReflectArea`.
  4. Visual: brief cyan flash via the existing hit-flash pattern; small expanding ring (`Line2D` arc or `CPUParticles2D`).
- Failed reflect (no bullet entered) still pays the cooldown — skill cost.

`EnemyBullet` needs to expose enough state for the flip to work. If it currently has hard-coded layers, add a `become_friendly()` method that swaps layers and disables the player-hurt collision.

---

## 7. Ram-ship laser blocking

`assault/scenes/enemies/ram_ship/ram_ship.gd` adds:

```gdscript
func is_laser_blocking() -> bool:
    return not _damaged
```

`beam_behavior.gd` checks each ray-collider:
- If collider belongs to layer **1024 (asteroid)** → blocking.
- If collider has method `is_laser_blocking` and it returns `true` → blocking.
- Else → enemy passes through but takes DPS damage.

Once a missile damages the ram-ship (existing `_enter_damaged_state`), `_damaged = true` and the beam now passes through it (and damages it normally).

---

## 8. HUD weapon chip

Small UI element in the existing HUD (top-left, near health/heat):
- Icon (32×32) + display name of the active mode.
- Updates via `WeaponState.weapon_changed(mode)` signal.
- Locked modes are not shown in the cycle. (Locked-icon row is out of scope; revisit when hub vendor lands.)

---

## 9. Save format & migration

- First-run boot: only `&"default"` unlocked.
- Existing players (no upgrades.json yet): treated as first-run.
- Manual unlocks during dev: `Ctrl+U` calls `UpgradeState.unlock_all()` (debug builds only).

---

## 10. Out of scope

- Locked-icon UI / vendor flow (will come with Open Space hub design).
- Drop sources (which enemies / which open-space encounters award which upgrade) — placeholder calls only; level scripts can call `UpgradeState.unlock(...)` ad-hoc for now.
- Visual polish on beam (no glow shader yet — straight `Line2D`).
- Audio for new weapons (uses existing bullet SFX as fallback).
- Controller input / rebinding UI.

---

## 11. Testing checklist

- All 5 modes fire with distinct visible behavior at `Ctrl+U` then cycling with E.
- Default bullet auto-expires at ~180 px.
- Long-range bullet reaches off-screen.
- Piercing beam stops at asteroid; stops at undamaged ram-ship; passes through fighters and damages them per second; passes through ram-ship after a warhead hit.
- Spread shows 5 pellets, each capping at 120 px.
- Auto-aim turns toward nearest enemy and expires by lifetime.
- Reflect: pressing H at the right time flips an incoming enemy bullet back; cooldown prevents spam.
- Cycle wraps around unlocked list; locked modes never appear.
- `UpgradeState` survives game restart (file at `user://upgrades.json`).
- Rocket fire on K, rocket switch on Q, interact on F all work; X no longer fires rockets.
- Heat/overheat behavior is consistent across modes.
