# Shield Rework: Discrete Charges + Icon UI — Design Spec

**Date:** 2026-05-25
**Status:** Approved (pending implementation plan)
**Scope:** Shield system rework only. Pickup system is a separate downstream spec.

## Goal

Replace the current "second HP bar" shield model with a discrete-charge model where each shield absorbs exactly one incoming hit. Permanent shields regenerate after a no-damage cooldown; temporary shields are consumed and gone. Display the active charges as an animated icon strip above the health bar.

## Architecture summary

`Shield` (a `Node` component on the player) holds two counters — `permanent_active` and `temporary_count` — plus a `permanent_max` driven by a new persistence autoload `ShipProgressionState`. `PlayerBase._apply_damage` calls `shield.consume_one()`; if a charge was consumed the hit is absorbed in full, otherwise the damage falls through to `Health`.

A new `ShieldIconStrip` (HBoxContainer) lives in the HUD above the trimmed `HealthShieldBar`. It instantiates `ShieldIcon` nodes (one per shield slot) and animates each in response to `shield_state_changed` snapshots. All animations come from one shared `SpriteFrames` resource cut from `shields.png`.

## Tech stack

Godot 4.3+ GDScript, fully typed. Persistence via `ConfigFile` under `user://`. UI via `Control` nodes inside an existing `CanvasLayer`-based HUD. No new dependencies.

---

## 1. Data model — `Shield` rewrite

`Shield` keeps its `class_name Shield` (so existing references compile) but every internal field, method, and signal is replaced.

### Caps (parallel structure)

| Tier | Cap | Source | Tunable how |
| --- | --- | --- | --- |
| Permanent | 5 | `ShipProgressionState.MAX_SHIELDS = 5` (autoload constant) | Edit constant; persists per-save value |
| Temporary | 5 | `Shield.max_temporary = 5` (`@export` on the node) | Edit constant or override per-scene in inspector |

Both caps are single-source-of-truth integers we expect to retune. The current shield count never exceeds either.

### Fields

```gdscript
class_name Shield
extends Node

@export var max_temporary: int = 5            ## hard cap on temp stack — expected to be retuned later
const REGEN_INTERVAL_SEC: float = 5.0

var permanent_max: int = 1       ## set in _ready from ShipProgressionState (≤ MAX_SHIELDS)
var permanent_active: int = 0    ## ≤ permanent_max
var temporary_count: int = 0     ## ≤ max_temporary
var is_hacked: bool = false

signal shield_state_changed(snapshot: Dictionary)
## snapshot keys: perm_active (int), perm_max (int), temp_count (int), hacked (bool)
```

### API

```gdscript
func consume_one() -> bool
    ## Called by PlayerBase._apply_damage. Pops one charge.
    ## Order: temporary first, then permanent.
    ## If is_hacked: drains ALL charges (perm + temp) and returns true once.
    ## Returns false if no charge was available → damage hits health.
    ## On any successful consumption, restarts the regen timer.

func add_temporary() -> bool
    ## Push +1 onto the temp stack (clamped to max_temporary).
    ## Returns false if already at cap. Emits snapshot.

func restore_all_permanent() -> void
    ## permanent_active = permanent_max. Temp untouched. Emits snapshot.
    ## (Used by armor_tank pickup in the pickup spec.)

func set_all_zero() -> void
    ## permanent_active = 0, temporary_count = 0, restart regen timer.
    ## Emits ONE consolidated snapshot. Used by ShieldOverloadModule.

func set_hacked(value: bool) -> void
    ## API only. Out of scope: no game system currently calls this.
    ## Stores the flag and emits snapshot so icons can switch visuals.
```

### Regen

Internal `Timer` (one-shot, `REGEN_INTERVAL_SEC`):
- Restarted whenever `consume_one()` returns true.
- On timeout: if `permanent_active < permanent_max`, increment `permanent_active`, emit snapshot, and restart the timer. Otherwise stop (idle until next hit).
- Temporary shields **do not regenerate**.

### `_ready` wiring

```gdscript
func _ready() -> void:
    permanent_max = ShipProgressionState.permanent_shield_count
    permanent_active = permanent_max
    ShipProgressionState.permanent_shield_count_changed.connect(_on_progression_changed)
    # Build the regen timer as a child node.

func _on_progression_changed(new_max: int) -> void:
    permanent_max = new_max
    permanent_active = mini(permanent_active + 1, permanent_max)  ## auto-fills the new slot
    _emit_snapshot()
```

### Damage flow in `PlayerBase._apply_damage`

```gdscript
func _apply_damage(damage: int) -> void:
    var effective: int = roundi(damage * (1.0 - damage_reduction))
    if shield_component.consume_one():
        return                            ## one mistake absorbed
    health_component.decrease(effective)
```

### Removed (no callers remaining after this spec)

- `current_shield`, `max_shield` properties
- `absorb(damage)`, `increase(amount)`, `set_shield(value)`, `is_empty()` methods
- `shield_changed`, `shield_depleted`, `shield_restored` signals
- `PlayerBase._on_shield_changed`, `PlayerBase._on_shield_depleted`
- `EventBus.player_shield_changed`, `player_shield_depleted`, `player_shield_restored`

---

## 2. Icon UI — `ShieldIcon` + `ShieldIconStrip`

### `ShieldIcon` (`global/components/shield_icon.gd` + `.tscn`)

Root: `AnimatedSprite2D` with `sprite_frames` pointing at `global/components/shield_animations.tres`. `texture_filter = NEAREST` (pixel art).

```gdscript
class_name ShieldIcon
extends AnimatedSprite2D

enum Tier { PERMANENT, TEMPORARY }

var tier: int = Tier.PERMANENT
var _is_empty: bool = false
var _interference_timer: Timer  ## fires every 3.0–4.0 s while in hacked_idle

func setup(t: int) -> void
    ## Stores tier; plays the tier-appropriate idle animation.

func play_destroy() -> void
    ## Plays "<prefix>_destroy". On animation_finished:
    ##   - PERMANENT: marks _is_empty = true; sprite shows the destroy anim's last frame
    ##     (which the artist authors as an empty slot frame).
    ##   - TEMPORARY: queue_free() — temp icons remove themselves.

func play_recharge() -> void
    ## Plays "<prefix>_recharge"; on animation_finished returns to idle.
    ## _is_empty cleared.

func play_hacked() -> void
    ## Plays "<prefix>_hacked_idle". Starts _interference_timer.
    ## Timer fires every random_range(3.0, 4.0)s → play "<prefix>_hacked_interference"
    ## (one-shot), then resumes hacked_idle.

func play_restore() -> void
    ## Plays "<prefix>_restore_after_hacking"; stops _interference_timer;
    ## on animation_finished returns to idle.

func _prefix() -> String:
    return "shield" if tier == Tier.PERMANENT else "additional_shield"
```

Animation names in the shared `SpriteFrames`:

| Permanent | Temporary |
| --- | --- |
| `shield_idle` | `additional_shield_idle` |
| `shield_destroy` | `additional_shield_destroy` |
| `shield_recharge` | `additional_shield_recharge` |
| `shield_hacked_idle` | `additional_shield_hacked_idle` |
| `shield_hacked_interference` | `additional_shield_hacked` |
| `shield_restore_after_hacking` | `additional_shield_restore_after_hacking` |

The user creates the SpriteFrames cuts from `res://global/assets/sprites/shields.png`. The spec's responsibility is just to lock down the names so the script can look them up unambiguously.

### `ShieldIconStrip` (`global/components/shield_icon_strip.gd` + `.tscn`)

Root: `HBoxContainer`, separation ~2 px.

```gdscript
class_name ShieldIconStrip
extends HBoxContainer

const _ICON_SCENE: PackedScene = preload("res://global/components/shield_icon.tscn")

var _shield: Shield = null
var _perm_icons: Array[ShieldIcon] = []   ## length == shield.permanent_max
var _temp_icons: Array[ShieldIcon] = []   ## length == shield.temporary_count
var _last_snapshot: Dictionary = {}

func setup(shield: Shield) -> void
    ## Builds permanent_max permanent icons (left).
    ## Connects to shield.shield_state_changed.

func _on_shield_state_changed(snap: Dictionary) -> void
    ## Diff against _last_snapshot:
    ##   - perm went down by N: call play_destroy on the rightmost N active perm icons
    ##   - perm went up by N:   call play_recharge on the leftmost N empty perm icons
    ##   - perm_max grew:       instance new PERMANENT icons at the right of the perm block
    ##   - perm_max shrank:     queue_free trailing perm icons (won't happen with current progression API)
    ##   - temp went up:        instance & play_recharge new TEMPORARY icons (appended right)
    ##   - temp went down by N: play_destroy on the rightmost N temp icons (they self-free)
    ##   - hacked flipped on:   play_hacked on all icons
    ##   - hacked flipped off:  play_restore on all icons
    ## Update _last_snapshot.
```

**Layout & sizing**: `ShieldIcon` renders at native sprite size (scale 1,1). The strip's width grows with icon count via `HBoxContainer` auto-layout — no hard width math in code. The HUD slot below assumes icon frames ≤ 18 px tall and a worst-case width of ~180 px (10 icons × ~18 px). If the SpriteFrames the artist authors use a different cell size, the HUD offsets in Section 3 are the only thing to retune.

---

## 3. HUD integration

### Trim `HealthShieldBar`

`assault/scenes/gui/health_shield_bar.tscn`:
- Delete the `ShieldBar` `ProgressBar` child node.
- Keep `HealthBar`.

`assault/scenes/gui/health_shield_bar.gd`:

```gdscript
class_name HealthShieldBar    ## class_name preserved for existing references
extends Control

@onready var _health_bar: ProgressBar = $HealthBar

func setup(health: Health) -> void:
    _health_bar.max_value = health.max_health
    _health_bar.value     = health.current_health
    health.amount_changed.connect(_on_health_changed)

func _on_health_changed(current: int) -> void:
    _health_bar.value = current
```

The `class_name` and node name are kept to minimize churn elsewhere. (A future cleanup can rename to `HealthBar`, but it's out of scope for this spec.)

### Add `ShieldIconStrip` to both HUDs

`assault/scenes/gui/hud.tscn` and `open_space/scenes/gui/hud.tscn`:

```
HUD (CanvasLayer)
├── HealthShieldBar           (existing — now trimmed)
│   anchor_top=1, anchor_bottom=1
│   offset_left=8, offset_top=-36, offset_right=158, offset_bottom=-8
└── ShieldIconStrip            (NEW)
    anchor_top=1, anchor_bottom=1
    offset_left=8, offset_top=-58, offset_right=180, offset_bottom=-40
```

### Wire-up in `mission_hud.gd`

The existing player→HUD binding extends with one extra call:

```gdscript
$HealthShieldBar.setup(player.health_component)
$ShieldIconStrip.setup(player.shield_component)
```

### Event bus cleanup

Delete from `global/systems/event_bus.gd`:
```gdscript
signal player_shield_changed(current: int, maximum: int)
signal player_shield_depleted
signal player_shield_restored
```

Delete the corresponding `EventBus.player_shield_*.emit(...)` calls (currently in `PlayerBase._on_shield_changed` and `_on_shield_depleted`). Those handler methods themselves are deleted along with the `health_component` / `shield_component` signal hookups in `PlayerBase._setup_components` for shield-side signals.

---

## 4. `ShieldOverloadModule` rewrite

`global/ship_modules/shield_overload_module.gd` — change only `try_activate` and the damage constant + description.

```gdscript
const _DAMAGE_PER_SHIELD: int = 25
const _RADIUS: float = 100.0
const _KNOCKBACK: float = 280.0

func get_description() -> String:
    return "Press H to detonate your shield. Spends every active shield (permanent + temporary) and deals damage in a radius, scaling with the number consumed. Also destroys nearby projectiles."

func try_activate(player: Node) -> bool:
    var shield: Shield = player.get("shield_component") as Shield
    if shield == null:
        return false
    var spent: int = shield.permanent_active + shield.temporary_count
    if spent <= 0:
        return false

    shield.set_all_zero()
    var damage: int = spent * _DAMAGE_PER_SHIELD

    ## … existing radius / knockback / projectile-clear / _spawn_burst code unchanged.
```

The existing `_BULLET_GROUPS`, `_RING_*` visual constants, and `_spawn_burst` helper remain untouched.

---

## 5. Persistence — `ShipProgressionState` autoload

New file: `global/autoloads/ship_progression_state.gd`.

```gdscript
extends Node
## Persists permanent ship upgrades (currently just shield count).
## Mirrors the ConfigFile pattern used by ShipModuleState.

const SAVE_PATH := "user://ship_progression.cfg"
const SECTION := "progression"
const KEY_SHIELDS := "permanent_shield_count"
const MIN_SHIELDS: int = 1
const MAX_SHIELDS: int = 5

signal permanent_shield_count_changed(new_count: int)

var permanent_shield_count: int = MIN_SHIELDS

func _ready() -> void:
    _load()

func set_permanent_shield_count(n: int) -> void:
    var clamped := clampi(n, MIN_SHIELDS, MAX_SHIELDS)
    if clamped == permanent_shield_count:
        return
    permanent_shield_count = clamped
    _save()
    permanent_shield_count_changed.emit(clamped)

func add_permanent_shield() -> bool:
    if permanent_shield_count >= MAX_SHIELDS:
        return false
    set_permanent_shield_count(permanent_shield_count + 1)
    return true

func _save() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value(SECTION, KEY_SHIELDS, permanent_shield_count)
    var err := cfg.save(SAVE_PATH)
    if err != OK:
        push_error("ShipProgressionState: failed to save (%s)" % error_string(err))

func _load() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return
    var raw := int(cfg.get_value(SECTION, KEY_SHIELDS, MIN_SHIELDS))
    permanent_shield_count = clampi(raw, MIN_SHIELDS, MAX_SHIELDS)
```

Register in `project.godot` `[autoload]` section directly after `ShipModuleState`:

```
ShipProgressionState="*res://global/autoloads/ship_progression_state.gd"
```

---

## 6. File inventory

### New

- `global/autoloads/ship_progression_state.gd`
- `global/components/shield_icon.gd`
- `global/components/shield_icon.tscn`
- `global/components/shield_icon_strip.gd`
- `global/components/shield_icon_strip.tscn`
- `global/components/shield_animations.tres` (user-created SpriteFrames cuts from `shields.png`; spec locks the animation names)

### Modified

- `global/components/shield_component.gd` — full rewrite (Section 1)
- `global/entities/player_base.gd` — `_apply_damage` switch; remove shield signal handlers (Section 1)
- `global/systems/event_bus.gd` — remove three deprecated shield signals (Section 3)
- `global/ship_modules/shield_overload_module.gd` — rewrite `try_activate` and update description (Section 4)
- `assault/scenes/gui/health_shield_bar.gd` — trim to health-only (Section 3)
- `assault/scenes/gui/health_shield_bar.tscn` — delete `ShieldBar` child (Section 3)
- `assault/scenes/gui/hud.tscn` — add `ShieldIconStrip` instance (Section 3)
- `open_space/scenes/gui/hud.tscn` — same
- `global/ui/mission_hud.gd` — bind `shield_icon_strip.setup(player.shield_component)` (Section 3)
- `project.godot` — register `ShipProgressionState` autoload (Section 5)

### Untouched

- `assault/scenes/player/player_fighter.tscn` and `.gd` — `ShieldComponent` node stays in place
- `open_space/scenes/entities/player/player_ship.tscn` and `.gd` — same
- All other ship modules and enemy code — no shield API leaks beyond `ShieldOverloadModule`

---

## 7. Out of scope / future hooks

These are intentionally NOT implemented now but the API is shaped to receive them:

| Hook | Provided by this spec | Future caller |
| --- | --- | --- |
| Hacked-state visuals | `Shield.set_hacked()`, `ShieldIcon.play_hacked()` / `play_restore()`, all animation slots in SpriteFrames | EMP enemy / hazard zone (later spec) |
| Pickup: temp shield up | `Shield.add_temporary()` | Pickup spec |
| Pickup: armor_tank | `Shield.restore_all_permanent()` | Pickup spec |
| Pickup: ship_shield_up | `ShipProgressionState.add_permanent_shield()` | Pickup spec |
| Temp HP overlay bar | Not in this spec | Pickup spec |
| Temp damage up | `PlayerBase.damage_multiplier` already exists | Pickup spec |

---

## 8. Testing strategy

The codebase has no automated test harness; verification is manual in the Godot editor.

**Per-task manual repro** (the implementation plan will spell exact steps for each task):

1. **`Shield` unit behavior** — open an empty test scene with one `Shield` node + a `print(snapshot)` listener. Call `consume_one()`, `add_temporary()`, `set_all_zero()` from the remote-inspect console; verify snapshot values and timer behavior (wait 5s, observe regen).
2. **Icon strip** — load assault `hud.tscn` in isolation, pass a mock `Shield` via setup(), call `consume_one()` and `add_temporary()` from the debugger; visually confirm `destroy` / `recharge` animations play on the correct icons.
3. **End-to-end** — launch level 1, take a hit from a known enemy bullet, confirm one icon plays destroy and HP is unchanged. Wait 5s without further damage, confirm icon plays recharge.
4. **Persistence** — call `ShipProgressionState.add_permanent_shield()` via the debug console; restart the project; verify the strip starts with the new permanent count.
5. **Module sanity** — equip Shield Overload, take hits to spawn temps via debug, press H, confirm all icons clear and enemies take `count × 25` damage.

A small debug helper (a temporary input action or extra method on `DebugUnlockAll`) may be added to make manual triggering convenient. That helper is one of the implementation-plan tasks, not a permanent shipping feature.
