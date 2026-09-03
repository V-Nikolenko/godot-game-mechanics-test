# Ship Modules Selection Menu — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a ship-modules panel (4 slots: cockpit, armor, weapons, engines) to the existing PlayerMenu, each showing a scheme sprite + equipped-module icon frame; pressing Space opens a module-detail list that overlays the weapon-selector area; modules apply their effects on equip (passive) or via H key (active).

**Architecture:** `ShipModuleState` autoload tracks equipped modules and emits signals; `AssaultPlayer` connects to those signals and calls `apply()/remove()` on `ShipModuleBase` subclasses. Active modules (Trajectory Calc) also expose `try_activate()` + `tick()` — player_fighter routes the `use_ability` H-key press to module activation first, before falling through to AbilityController. Warp is active via double-press movement: `DashState` checks `actor.warp_module_active` flag and teleports instead of barrel-rolling. The `ShipModulesPanel` scene handles all visual scheme/icon state. The `ModuleList` scene reuses the `WeaponFrame/WeaponOption` column pattern but with icon + name + description rows. `PlayerMenu._cursor_col` gains a third value (2) for the modules column.

**Tech Stack:** Godot 4.3+, GDScript, existing `WeaponFrame`/`WeaponOption` UI patterns, existing `AbilityState`/`UpgradeState` autoload patterns.

---

## Design Decisions for Spec Ambiguities

| Ambiguity | Decision Made |
|-----------|---------------|
| Passive vs. H-key activated? | Mixed. **Armor** and **Overclock** are fully passive (always-on). **Trajectory Calc** activates on **H key** (same button as abilities; module takes priority over ability system). **Warp** activates on **double-press movement** (same trigger as `DashState` barrel-roll — teleports instead). |
| How Trajectory Calculation activates | Press H → time_scale = 0.3 for 5 s, 20 s cooldown. `ShipModuleBase` gains `try_activate(player)` + `tick(player, delta)` virtual methods; player_fighter checks equipped modules before delegating H-key to AbilityController. |
| Warp — replaces double-press dash | `DashState.start_state_transition()` checks `actor.get("warp_module_active")`. If true it calls `_execute_warp(key_name)` and returns early — the barrel-roll code path is skipped. No new input action added. |
| Can a slot be unequipped? | Yes. First item in every module detail list is always **"None"** — selecting it clears the slot. |
| All 4 modules active simultaneously? | Yes — all equipped slots are active at the same time. |
| Where is the ship modules panel placed? | Added to `ShipLayout` at approximately position **(448, 148)** — right half of menu. Adjust after visual check. |
| Where is the module detail list placed? | `ModuleList` is added as a sibling of `ShipLayout`, covering the weapon-frames area. Its frame background `menu_modules_list_frame.png` is positioned at **(92, 100)** — fine-tune to exactly cover the two weapon frames. |
| Effect timing | Effects apply **immediately** when equipping in-menu (via signal from `ShipModuleState` received by `AssaultPlayer` even while tree is paused, since signals fire synchronously). |

---

## File Structure

### New files to create

| File | Responsibility |
|------|---------------|
| `global/autoloads/ship_module_state.gd` | Persists equipped module IDs per slot; emits signals on change |
| `global/ship_modules/ship_module_base.gd` | Abstract base: `apply()` / `remove()` / `try_activate()` / `tick()` / display helpers |
| `global/ship_modules/armor_plating_module.gd` | Armor slot: passive +max_health, +damage_reduction |
| `global/ship_modules/trajectory_calc_module.gd` | Cockpit slot: H-key time slow (0.3× for 5 s, 20 s cooldown) |
| `global/ship_modules/warp_module.gd` | Engine slot: sets `warp_module_active` flag; DashState does the teleport |
| `global/ship_modules/overclock_module.gd` | Weapon slot: allows firing past overheat with self-damage |
| `global/ui/dialog_system/playermenu/ship_modules_panel.gd` | Scheme sprites + item frame sprites + hover/equip visual state |
| `global/ui/dialog_system/playermenu/ship_modules_panel.tscn` | Scene for the above |
| `global/ui/dialog_system/playermenu/module_list_item.gd` | One row in module detail list: icon + name + description |
| `global/ui/dialog_system/playermenu/module_list_item.tscn` | Scene for the above |
| `global/ui/dialog_system/playermenu/module_list.gd` | Scrollable list of module options for a specific slot |
| `global/ui/dialog_system/playermenu/module_list.tscn` | Scene for the above |

### Existing files to modify

| File | Change |
|------|--------|
| `project.godot` | Register `ShipModuleState` as autoload |
| `global/ui/dialog_system/playermenu/player_menu.gd` | Add col 2 navigation; connect `ShipModulesPanel`; open/close `ModuleList` |
| `global/ui/dialog_system/playermenu/player_menu.tscn` | Add `ShipModulesPanel` + `ModuleList` nodes |
| `assault/scenes/player/player_fighter.gd` | Connect `ShipModuleState` signals; route H key to active modules before AbilityController; call `tick()` on active modules each frame; handle `overclock_module_active` in overheat callback |
| `assault/scenes/player/states/dash_state.gd` | Check `warp_module_active` flag in `start_state_transition()`; if true, execute teleport instead of barrel-roll |
| `assault/scenes/player/states/weapon_state.gd` | In `_fire()`: if `overclock_module_active` and heat at limit, call `actor._apply_damage(3)` |

---

## Task 1: ShipModuleState Autoload

**Files:**
- Create: `global/autoloads/ship_module_state.gd`
- Modify: `project.godot` (add autoload entry)

- [ ] **Step 1: Create `global/autoloads/ship_module_state.gd`**

```gdscript
# global/autoloads/ship_module_state.gd
extends Node

## Persists which module is equipped in each ship slot.
## Slot IDs:  &"cockpit"  |  &"armor"  |  &"weapons"  |  &"engines"
## Module IDs per slot:
##   cockpit  → &"trajectory_calc"
##   armor    → &"armor_plating"
##   weapons  → &"overclock"
##   engines  → &"warp"
## Empty string means nothing equipped.

const SAVE_PATH := "user://ship_modules.cfg"
const SECTION := "modules"

const SLOTS: Array[StringName] = [&"cockpit", &"armor", &"weapons", &"engines"]

## Maps slot → list of available module IDs (in display order).
## First entry is always &"" (None / unequip).
const SLOT_MODULES: Dictionary = {
    &"cockpit":  [&"", &"trajectory_calc"],
    &"armor":    [&"", &"armor_plating"],
    &"weapons":  [&"", &"overclock"],
    &"engines":  [&"", &"warp"],
}

signal module_equipped(slot: StringName, module_id: StringName)
signal module_unequipped(slot: StringName, prev_id: StringName)

## slot → module_id (&"" = nothing equipped)
var _equipped: Dictionary = {
    &"cockpit":  &"",
    &"armor":    &"",
    &"weapons":  &"",
    &"engines":  &"",
}

func _ready() -> void:
    _load()

func get_equipped(slot: StringName) -> StringName:
    return _equipped.get(slot, &"")

func equip(slot: StringName, module_id: StringName) -> void:
    if slot not in SLOTS:
        push_warning("ShipModuleState: unknown slot '%s'" % slot)
        return
    var prev: StringName = _equipped.get(slot, &"")
    if prev == module_id:
        return
    if prev != &"":
        module_unequipped.emit(slot, prev)
    _equipped[slot] = module_id
    _save()
    module_equipped.emit(slot, module_id)

func _save() -> void:
    var cfg := ConfigFile.new()
    for slot: StringName in SLOTS:
        cfg.set_value(SECTION, String(slot), String(_equipped[slot]))
    var err := cfg.save(SAVE_PATH)
    if err != OK:
        push_warning("ShipModuleState: failed to save (%s)" % error_string(err))

func _load() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return
    for slot: StringName in SLOTS:
        var raw: String = cfg.get_value(SECTION, String(slot), "")
        _equipped[slot] = StringName(raw)
```

- [ ] **Step 2: Register as autoload in `project.godot`**

Open `project.godot`, find the `[autoload]` section, and add the line:
```
ShipModuleState="*res://global/autoloads/ship_module_state.gd"
```
(The `*` prefix makes it a singleton node, same as the existing autoloads.)

- [ ] **Step 3: Verify in editor**

Open Godot editor. Check **Project → Project Settings → Autoload** tab — `ShipModuleState` should appear. Run the project; no errors in Output. Confirm `ShipModuleState.get_equipped(&"armor")` returns `&""` in a one-off print.

- [ ] **Step 4: Commit**

```bash
git add global/autoloads/ship_module_state.gd project.godot
git commit -m "feat: add ShipModuleState autoload for ship module persistence"
```

---

## Task 2: ShipModuleBase and Four Module Implementations

**Files:**
- Create: `global/ship_modules/ship_module_base.gd`
- Create: `global/ship_modules/armor_plating_module.gd`
- Create: `global/ship_modules/trajectory_calc_module.gd`
- Create: `global/ship_modules/warp_module.gd`
- Create: `global/ship_modules/overclock_module.gd`

- [ ] **Step 1: Create `global/ship_modules/ship_module_base.gd`**

```gdscript
# global/ship_modules/ship_module_base.gd
class_name ShipModuleBase
extends RefCounted

## Abstract base for ship modules. Modules can be purely passive (Armor, Overclock)
## or have an H-key activation (Trajectory Calc). Warp uses double-press movement
## via DashState — it only needs apply/remove to set a flag.

## Override: human-readable name shown in module detail list.
func get_display_name() -> String:
    return "Module"

## Override: one-sentence description shown in module detail list.
func get_description() -> String:
    return ""

## Override: icon texture shown in item frame and detail list.
func get_icon() -> Texture2D:
    return null

## Override: slot this module belongs to (&"cockpit" / &"armor" / &"weapons" / &"engines").
func get_slot() -> StringName:
    return &""

## Override: apply passive effect to player. Called on equip.
func apply(_player: Node) -> void:
    pass

## Override: remove passive effect from player. Called on unequip or scene change.
func remove(_player: Node) -> void:
    pass

## Override in active modules: called when player presses H (use_ability).
## Return true if the module consumed the input (starts cooldown or effect).
## Passive modules leave this as false — H falls through to AbilityController.
func try_activate(_player: Node) -> bool:
    return false

## Override in active modules: called every physics frame by player_fighter
## for the currently equipped active module. Use for cooldown tracking and
## timed effect expiry. `delta` is real-time delta (Engine.time_scale already applied).
func tick(_player: Node, _delta: float) -> void:
    pass
```

- [ ] **Step 2: Create `global/ship_modules/armor_plating_module.gd`**

Effect: permanently adds 40 to `health_component.max_health` and `damage_reduction += 0.25`.

```gdscript
# global/ship_modules/armor_plating_module.gd
class_name ArmorPlatingModule
extends ShipModuleBase

const _HEALTH_BONUS: int = 40
const _REDUCTION: float = 0.25

func get_display_name() -> String: return "Increased Armor"
func get_description() -> String:
    return "Reinforced hull plating increases maximum hull integrity by 40 and reduces all incoming damage by 25%%."
func get_icon() -> Texture2D:
    return preload("res://assault/assets/sprites/ui/icon_ship_module_armor_increased_plating.png")
func get_slot() -> StringName: return &"armor"

func apply(player: Node) -> void:
    var health := player.get("health_component")
    if health:
        health.max_health += _HEALTH_BONUS
        ## Also restore the bonus HP so the player doesn't gain a phantom bonus bar.
        health.increase(_HEALTH_BONUS)
    player.set("damage_reduction", player.get("damage_reduction") + _REDUCTION)

func remove(player: Node) -> void:
    var health := player.get("health_component")
    if health:
        health.max_health -= _HEALTH_BONUS
        ## Clamp current health so it doesn't exceed new max.
        if health.health > health.max_health:
            health.set_health(health.max_health)
    player.set("damage_reduction", maxf(0.0, player.get("damage_reduction") - _REDUCTION))
```

- [ ] **Step 3: Create `global/ship_modules/trajectory_calc_module.gd`**

Active module: press H → time_scale = 0.3 for 5 s, then 20 s cooldown. Mirrors `TrajectoryCalcAbility` exactly but lives in the module system so the ability slot stays free. Cooldown ticks in real time (delta / _TIME_SCALE).

```gdscript
# global/ship_modules/trajectory_calc_module.gd
class_name TrajectoryCalcModule
extends ShipModuleBase

const _DURATION:   float = 5.0
const _TIME_SCALE: float = 0.3
const _COOLDOWN:   float = 20.0

var _active:        bool  = false
var _time_left:     float = 0.0
var _cooldown_left: float = 0.0

func get_display_name() -> String: return "Trajectory Calculation"
func get_description() -> String:
    return "Press H to engage targeting computers. Slows time to 30%% for 5 seconds. 20-second cooldown."
func get_icon() -> Texture2D:
    return preload("res://assault/assets/sprites/ui/icon_ship_module_cockpit_time_slow_down.png")
func get_slot() -> StringName: return &"cockpit"

func apply(_player: Node) -> void:
    pass  ## No passive effect; H-key triggers everything.

func remove(player: Node) -> void:
    _restore(player)

func try_activate(player: Node) -> bool:
    if _active or _cooldown_left > 0.0:
        return false
    _active    = true
    _time_left = _DURATION
    Engine.time_scale = _TIME_SCALE
    var sprite := player.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
    if sprite:
        sprite.modulate = Color(0.5, 0.7, 1.0, 1.0)
    return true

func tick(player: Node, delta: float) -> void:
    if _cooldown_left > 0.0:
        ## Cooldown ticks in real time, so divide out the current time_scale.
        _cooldown_left -= delta / Engine.time_scale
    if _active:
        ## _TIME_SCALE is what WE set; dividing recovers real elapsed seconds.
        _time_left -= delta / _TIME_SCALE
        if _time_left <= 0.0:
            _restore(player)

func _restore(player: Node) -> void:
    if not _active:
        return
    _active        = false
    _time_left     = 0.0
    _cooldown_left = _COOLDOWN
    Engine.time_scale = 1.0
    var sprite := player.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
    if sprite:
        player.create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.3)

## Safety net: restore time_scale if node is freed mid-effect.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE and _active:
        Engine.time_scale = 1.0
```

- [ ] **Step 4: Create `global/ship_modules/warp_module.gd`**

Sets `warp_module_active` on the player. `DashState` reads this flag — when true, the double-press movement input triggers teleport instead of the barrel-roll. No new input button.

```gdscript
# global/ship_modules/warp_module.gd
class_name WarpModule
extends ShipModuleBase

func get_display_name() -> String: return "Warp Drive"
func get_description() -> String:
    return "Replaces the barrel-roll dash with a micro-warp teleport. Double-tap a movement key to instantly blink 120 px in that direction."
func get_icon() -> Texture2D:
    return preload("res://assault/assets/sprites/ui/icon_ship_module_engine_warp.png")
func get_slot() -> StringName: return &"engines"

func apply(player: Node) -> void:
    player.set("warp_module_active", true)

func remove(player: Node) -> void:
    player.set("warp_module_active", false)
```

- [ ] **Step 5: Create `global/ship_modules/overclock_module.gd`**

Effect: sets a flag on the player; `player_fighter.gd` reads it to never lock `can_attack`; `weapon_state.gd` reads it to apply self-damage per shot when heat is maxed.

```gdscript
# global/ship_modules/overclock_module.gd
class_name OverclockModule
extends ShipModuleBase

func get_display_name() -> String: return "Weapon Overclock"
func get_description() -> String:
    return "Bypasses thermal safeties. Weapons continue firing past heat limit, but each shot while overheated deals 3 damage to the hull."
func get_icon() -> Texture2D:
    return preload("res://assault/assets/sprites/ui/icon_ship_module_weapon_oveclock.png")
func get_slot() -> StringName: return &"weapons"

func apply(player: Node) -> void:
    player.set("overclock_module_active", true)

func remove(player: Node) -> void:
    player.set("overclock_module_active", false)
```

- [ ] **Step 6: Commit**

```bash
git add global/ship_modules/
git commit -m "feat: add ShipModuleBase and four passive module implementations"
```

---

## Task 3: Wire Module Effects into AssaultPlayer, DashState, and WeaponState

**Files:**
- Modify: `assault/scenes/player/player_fighter.gd`
- Modify: `assault/scenes/player/states/dash_state.gd`
- Modify: `assault/scenes/player/states/weapon_state.gd`

- [ ] **Step 1: Add module properties and factory to `player_fighter.gd`**

Add at the top of the class (after `extends PlayerBase`):

```gdscript
## Set true by WarpModule.apply(). DashState reads this to teleport instead of roll.
var warp_module_active: bool = false
## Set true by OverclockModule.apply(). Allows firing past overheat.
var overclock_module_active: bool = false

## Active module instances — created lazily in _apply_module().
var _module_pool: Dictionary = {}  # { StringName: ShipModuleBase }
```

- [ ] **Step 2: Add module connection in `_ready()` inside `player_fighter.gd`**

Append to the end of `_ready()` (after `super()`):

```gdscript
    ## Connect module state signals for live equip/unequip during gameplay.
    ShipModuleState.module_equipped.connect(_on_module_equipped)
    ShipModuleState.module_unequipped.connect(_on_module_unequipped)
    ## Apply modules already equipped from a previous session.
    for slot: StringName in ShipModuleState.SLOTS:
        var id: StringName = ShipModuleState.get_equipped(slot)
        if id != &"":
            _apply_module(id)
```

- [ ] **Step 3: Add module helper methods to `player_fighter.gd`**

```gdscript
func _get_or_create_module(id: StringName) -> ShipModuleBase:
    if not _module_pool.has(id):
        var inst: ShipModuleBase = _create_module(id)
        if inst != null:
            _module_pool[id] = inst
    return _module_pool.get(id, null)

func _create_module(id: StringName) -> ShipModuleBase:
    match id:
        &"armor_plating":   return ArmorPlatingModule.new()
        &"trajectory_calc": return TrajectoryCalcModule.new()
        &"warp":            return WarpModule.new()
        &"overclock":       return OverclockModule.new()
        _:
            push_warning("AssaultPlayer: unknown module id '%s'" % id)
            return null

func _apply_module(id: StringName) -> void:
    var mod := _get_or_create_module(id)
    if mod:
        mod.apply(self)

func _remove_module(id: StringName) -> void:
    var mod := _module_pool.get(id, null)
    if mod:
        mod.remove(self)

func _on_module_equipped(_slot: StringName, module_id: StringName) -> void:
    if module_id != &"":
        _apply_module(module_id)

func _on_module_unequipped(_slot: StringName, prev_id: StringName) -> void:
    if prev_id != &"":
        _remove_module(prev_id)
```

- [ ] **Step 4: Add H-key module routing and per-frame tick to `player_fighter.gd`**

Add `_unhandled_input` and extend `_physics_process`:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    ## Route use_ability (H) to active modules first.
    ## If no module consumes it, the event falls through to AbilityController.
    if event.is_action_pressed("use_ability"):
        for id: StringName in _module_pool.keys():
            var mod: ShipModuleBase = _module_pool[id]
            if mod.try_activate(self):
                get_viewport().set_input_as_handled()
                return  ## Consumed by module; AbilityController won't see it.
```

Extend the existing `_physics_process` in `player_fighter.gd` — add at the end of the method:

```gdscript
    ## Tick all active modules every frame (handles cooldowns, timed effects).
    for id: StringName in _module_pool.keys():
        _module_pool[id].tick(self, _delta)
```

- [ ] **Step 5: Override `_on_overheat_updated` to respect `overclock_module_active`**

Replace the existing `_on_overheat_updated` in `player_fighter.gd` with:

```gdscript
func _on_overheat_updated(pct: float) -> void:
    super(pct)  # emits EventBus.player_overheat_changed
    ## Overclock module: never lock weapons, even at 100% heat.
    if overclock_module_active:
        can_attack = true
        return
    if overdrive_active:
        can_attack = true
        return
    if pct >= 100:
        can_attack = false
        return
    if pct >= 80 and not can_attack:
        return
    if pct < 80 and not can_attack:
        can_attack = true
```

- [ ] **Step 6: Modify `dash_state.gd` to teleport when Warp module is active**

Add a warp helper near the top of the class and modify `start_state_transition()`:

```gdscript
## In DashState — add these constants near the top:
const _WARP_DISTANCE:      float = 120.0
const _WARP_CONTACT_DAMAGE: int  = 25
const _WARP_CONTACT_RADIUS: float = 16.0
```

Replace `start_state_transition()` body:

```gdscript
func start_state_transition(key_name: String) -> void:
    if !dashing_timer.is_stopped():
        return
    if not STATE_KEY_BINDINGS.has(key_name):
        return
    ## Warp module: teleport instead of barrel-roll.
    if actor.get("warp_module_active"):
        _execute_warp(get_dash_direction(key_name))
        return
    ## Normal dash path.
    if dash_cooldown_enabled && !cooldown_timer.is_stopped():
        print("Dash in cooldown. Time to refresh: " + str(cooldown_timer.time_left) + "sec.")
        state_transition.emit(transition_state)
        return
    dashing_direction = get_dash_direction(key_name)
    state_transition.emit(self)
```

Add the new `_execute_warp()` method and ghost helper to `DashState`:

```gdscript
func _execute_warp(dir: Vector2) -> void:
    var dest: Vector2 = actor.global_position + dir * _WARP_DISTANCE
    _spawn_warp_ghost()
    actor.global_position = dest
    ## Contact damage at landing point.
    for e in actor.get_tree().get_nodes_in_group("enemies"):
        var n := e as Node2D
        if n == null or n.global_position.distance_to(dest) > _WARP_CONTACT_RADIUS:
            continue
        var hb := n.get_node_or_null("HurtBox") as HurtBox
        if hb:
            hb.received_damage.emit(_WARP_CONTACT_DAMAGE)

func _spawn_warp_ghost() -> void:
    var ghost := Sprite2D.new()
    var sprite := animated_sprite
    if sprite and sprite.sprite_frames:
        ghost.texture = sprite.sprite_frames.get_frame_texture(
            sprite.animation, sprite.frame)
    ghost.modulate = Color(0.5, 0.8, 1.0, 0.6)
    actor.get_parent().add_child(ghost)
    ghost.global_position = actor.global_position
    ghost.global_scale = actor.global_scale
    var t := ghost.create_tween()
    t.tween_property(ghost, "modulate:a", 0.0, 0.3)
    t.tween_callback(ghost.queue_free)
```

- [ ] **Step 7: Add overclock self-damage in `weapon_state.gd`**

In `weapon_state.gd`, modify `_fire()`. Add these lines **after** `heat_component.increase_heat(mode.heat_per_shot)`:

```gdscript
    ## Overclock module: deal self-damage when firing past overheat limit.
    var is_overclocked = actor.get("overclock_module_active")
    if is_overclocked:
        var heat_pct := heat_component.heat / heat_component.heat_limit
        if heat_pct >= 1.0:
            actor._apply_damage(3)
```

- [ ] **Step 8: Verify behavior**

Run the game in editor.
- Equip armor module via menu → confirm `damage_reduction` becomes 0.25 (check Debugger Remote scene tree → player node properties).
- Equip overclock → shoot until overheated → player continues shooting but takes 3 HP per shot.
- Equip warp → double-tap W → player teleports forward, ghost flash appears at origin.
- Equip trajectory_calc → press H → time slows for 5 s, sprite turns blue, then restores. Second H press blocked during cooldown.

- [ ] **Step 9: Commit**

```bash
git add assault/scenes/player/player_fighter.gd assault/scenes/player/states/dash_state.gd assault/scenes/player/states/weapon_state.gd
git commit -m "feat: wire module effects into AssaultPlayer, DashState (warp), and WeaponState (overclock)"
```

---

## Task 4: ModuleListItem Scene

Single row in the module detail list showing icon + name + description.

**Files:**
- Create: `global/ui/dialog_system/playermenu/module_list_item.gd`
- Create: `global/ui/dialog_system/playermenu/module_list_item.tscn`

- [ ] **Step 1: Create `module_list_item.gd`**

```gdscript
# global/ui/dialog_system/playermenu/module_list_item.gd
## Single selectable row in the module detail list.
## Shows icon, display name, and description. Supports cursor + selection tints.
class_name ModuleListItem
extends Control

const _CURSOR_MODULATE   := Color(1.4, 1.4, 1.0)   ## Yellow highlight when cursor here.
const _SELECTED_MODULATE := Color(2.0, 0.5, 1.2)    ## Pink tint when this is equipped.
const _NORMAL_MODULATE   := Color.WHITE
const _GREY_MODULATE     := Color(0.45, 0.45, 0.45) ## None/empty-slot appearance.

@onready var _bg_sprite: Sprite2D  = $SelectionBG
@onready var _icon:      Sprite2D  = $ModuleIcon
@onready var _name_lbl:  Label     = $SelectionBG/ModuleName
@onready var _desc_lbl:  Label     = $SelectionBG/ModuleDesc

var _is_selected: bool = false
var _is_cursor:   bool = false

func _ready() -> void:
    _update_modulate()

## Populate this row. Pass null icon and empty strings for the "None" row.
func configure(display_name: String, description: String, icon: Texture2D) -> void:
    _name_lbl.text = display_name if display_name != "" else "None"
    _desc_lbl.text = description
    if icon != null:
        _icon.texture = icon
        _icon.visible = true
    else:
        _icon.visible = false

func set_cursor(value: bool) -> void:
    _is_cursor = value
    _update_modulate()

func set_selected(value: bool) -> void:
    _is_selected = value
    _update_modulate()

func _update_modulate() -> void:
    modulate = _CURSOR_MODULATE if _is_cursor else _NORMAL_MODULATE
    if _bg_sprite != null:
        _bg_sprite.modulate = _SELECTED_MODULATE if _is_selected else _NORMAL_MODULATE
```

- [ ] **Step 2: Create `module_list_item.tscn`**

Create the scene file. The `menu_modules_list_item.png` sprite is the row background. Layout: icon on far left (x ≈ -65), name label top-right, description label bottom-right in smaller font.

```
[gd_scene format=3]

[ext_resource type="Script" path="res://global/ui/dialog_system/playermenu/module_list_item.gd" id="1_mli"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/ui/menu_modules_list_item.png" id="2_bg"]

[node name="ModuleListItem" type="Control"]
script = ExtResource("1_mli")

[node name="ModuleIcon" type="Sprite2D" parent="."]
position = Vector2(-65, 0)
scale = Vector2(0.45, 0.45)

[node name="SelectionBG" type="Sprite2D" parent="."]
texture = ExtResource("2_bg")

[node name="ModuleName" type="Label" parent="SelectionBG"]
offset_left = -40.0
offset_top = -14.0
offset_right = 80.0
offset_bottom = -2.0
text = "Module Name"
vertical_alignment = 1

[node name="ModuleDesc" type="Label" parent="SelectionBG"]
offset_left = -40.0
offset_top = 1.0
offset_right = 80.0
offset_bottom = 14.0
text = "Description text."
vertical_alignment = 1
theme_override_font_sizes/font_size = 9
```

**Note:** After creating, open in editor and adjust label offsets so they fit within the `menu_modules_list_item.png` background sprite visually.

- [ ] **Step 3: Commit**

```bash
git add global/ui/dialog_system/playermenu/module_list_item.gd global/ui/dialog_system/playermenu/module_list_item.tscn
git commit -m "feat: add ModuleListItem scene for module detail rows"
```

---

## Task 5: ModuleList Scene (Detail List Overlay)

A scrollable list of modules for one slot. Overlays the weapon-frames area. Shown only when Space is pressed on a module slot.

**Files:**
- Create: `global/ui/dialog_system/playermenu/module_list.gd`
- Create: `global/ui/dialog_system/playermenu/module_list.tscn`

- [ ] **Step 1: Create `module_list.gd`**

```gdscript
# global/ui/dialog_system/playermenu/module_list.gd
## Overlay list that shows available modules for one slot.
## Caller: PlayerMenu shows this when Space is pressed in col 2.
## Emits confirmed(module_id) when Space selects an item, or cancelled on Esc/Tab.
class_name ModuleList
extends Node2D

signal confirmed(module_id: StringName)
signal cancelled

const _ITEM_SCENE: PackedScene = preload("res://global/ui/dialog_system/playermenu/module_list_item.tscn")
const _ROW_HEIGHT: float = 36.0   ## Taller than weapon options to fit name + desc.
const MAX_ITEMS: int = 8

## Local-space origin for the first list item. Tune to align with frame sprite.
@export var item_origin: Vector2 = Vector2(0.0, -100.0)

var _items: Array[ModuleListItem] = []
var _ids:   Array[StringName] = []
var _cursor_row: int = 0

func _ready() -> void:
    visible = false

## Show the list populated with modules for the given slot.
## `current_id` is the currently equipped module id (or &"" if none).
func open(slot: StringName, current_id: StringName) -> void:
    _clear()
    _ids = ShipModuleState.SLOT_MODULES.get(slot, [&""])
    var count: int = mini(_ids.size(), MAX_ITEMS)
    for i: int in count:
        var item := _ITEM_SCENE.instantiate() as ModuleListItem
        assert(item != null)
        add_child(item)
        item.position = item_origin + Vector2(0.0, i * _ROW_HEIGHT)
        var id: StringName = _ids[i]
        if id == &"":
            item.configure("None", "Remove installed module.", null)
        else:
            var mod := _make_module(id)
            item.configure(
                mod.get_display_name() if mod else String(id),
                mod.get_description() if mod else "",
                mod.get_icon() if mod else null
            )
        _items.append(item)

    ## Initialise cursor on currently equipped item.
    _cursor_row = maxi(0, _ids.find(current_id))
    _refresh_cursor()
    _refresh_selected(current_id)
    visible = true

func close() -> void:
    visible = false
    _clear()

func navigate(delta: int) -> void:
    _cursor_row = clampi(_cursor_row + delta, 0, maxi(_items.size() - 1, 0))
    _refresh_cursor()

func confirm() -> void:
    if _cursor_row < _ids.size():
        confirmed.emit(_ids[_cursor_row])

func _clear() -> void:
    for item: ModuleListItem in _items:
        remove_child(item)
        item.queue_free()
    _items.clear()
    _ids.clear()

func _refresh_cursor() -> void:
    for i: int in _items.size():
        _items[i].set_cursor(i == _cursor_row)

func _refresh_selected(current_id: StringName) -> void:
    for i: int in _items.size():
        _items[i].set_selected(_ids[i] == current_id)

func _make_module(id: StringName) -> ShipModuleBase:
    match id:
        &"armor_plating":   return ArmorPlatingModule.new()
        &"trajectory_calc": return TrajectoryCalcModule.new()
        &"warp":            return WarpModule.new()
        &"overclock":       return OverclockModule.new()
        _:                  return null
```

- [ ] **Step 2: Create `module_list.tscn`**

```
[gd_scene format=3]

[ext_resource type="Script" path="res://global/ui/dialog_system/playermenu/module_list.gd" id="1_ml"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/ui/menu_modules_list_frame.png" id="2_mlf"]

[node name="ModuleList" type="Node2D"]
script = ExtResource("1_ml")

[node name="FrameBackground" type="Sprite2D" parent="."]
texture = ExtResource("2_mlf")
```

**Note:** After creating, open in editor. The `item_origin` export var positions the first list item relative to the frame. Adjust so items appear inside the frame graphic.

- [ ] **Step 3: Commit**

```bash
git add global/ui/dialog_system/playermenu/module_list.gd global/ui/dialog_system/playermenu/module_list.tscn
git commit -m "feat: add ModuleList overlay scene for module slot selection"
```

---

## Task 6: ShipModulesPanel Scene

The visual panel showing the ship scheme (4 overlay sprites) and 4 item frames (equipped module icons). Lives in the PlayerMenu's ShipLayout.

**Files:**
- Create: `global/ui/dialog_system/playermenu/ship_modules_panel.gd`
- Create: `global/ui/dialog_system/playermenu/ship_modules_panel.tscn`

- [ ] **Step 1: Create `ship_modules_panel.gd`**

```gdscript
# global/ui/dialog_system/playermenu/ship_modules_panel.gd
## Visual panel for the ship-modules column.
## Shows 4 scheme sprites (overlaid to form the ship) and 4 item frames.
## Call set_cursor(row) to highlight one slot.
## Call refresh_equipped() to update icons and scheme tints from ShipModuleState.
class_name ShipModulesPanel
extends Node2D

## Modulate colours.
const _NORMAL_COLOR  := Color.WHITE            ## Equipped = full colour.
const _EMPTY_COLOR   := Color(0.4, 0.4, 0.4)  ## Nothing equipped = grey.
const _HOVER_COLOR   := Color(2.0, 0.5, 1.2)  ## Cursor on this slot = pink highlight.

## Slot order: 0=cockpit, 1=armor, 2=weapons, 3=engines.
## Must match ShipModuleState.SLOTS order.
@onready var _scheme_sprites: Array[Sprite2D] = [
    $SchemeCockpit,
    $SchemeArmor,
    $SchemeWeapons,
    $SchemeEngine,
]
@onready var _item_frames: Array[Sprite2D] = [
    $ItemFrameCockpit,
    $ItemFrameArmor,
    $ItemFrameWeapons,
    $ItemFrameEngine,
]
@onready var _item_icons: Array[Sprite2D] = [
    $ItemFrameCockpit/Icon,
    $ItemFrameArmor/Icon,
    $ItemFrameWeapons/Icon,
    $ItemFrameEngine/Icon,
]

## Module icon textures by module id.
const _MODULE_ICONS: Dictionary = {
    &"armor_plating":   preload("res://assault/assets/sprites/ui/icon_ship_module_armor_increased_plating.png"),
    &"trajectory_calc": preload("res://assault/assets/sprites/ui/icon_ship_module_cockpit_time_slow_down.png"),
    &"warp":            preload("res://assault/assets/sprites/ui/icon_ship_module_engine_warp.png"),
    &"overclock":       preload("res://assault/assets/sprites/ui/icon_ship_module_weapon_oveclock.png"),
}

var _cursor_row: int = -1

func _ready() -> void:
    refresh_equipped()

## Set which slot the cursor is on (-1 = none).
func set_cursor(row: int) -> void:
    _cursor_row = row
    _update_visuals()

## Re-read ShipModuleState and update all scheme + icon visuals.
func refresh_equipped() -> void:
    _update_visuals()

func get_slot_count() -> int:
    return 4

func _update_visuals() -> void:
    for i: int in 4:
        var slot: StringName = ShipModuleState.SLOTS[i]
        var equipped_id: StringName = ShipModuleState.get_equipped(slot)
        var has_module: bool = equipped_id != &""
        var is_hovered: bool = i == _cursor_row

        ## Scheme sprite colour.
        if is_hovered:
            _scheme_sprites[i].modulate = _HOVER_COLOR
        elif has_module:
            _scheme_sprites[i].modulate = _NORMAL_COLOR
        else:
            _scheme_sprites[i].modulate = _EMPTY_COLOR

        ## Item frame colour.
        _item_frames[i].modulate = _NORMAL_COLOR if has_module else _EMPTY_COLOR

        ## Item icon.
        var icon: Texture2D = _MODULE_ICONS.get(equipped_id, null)
        _item_icons[i].texture = icon
        _item_icons[i].visible = icon != null
```

- [ ] **Step 2: Create `ship_modules_panel.tscn`**

All four scheme sprites sit at the **same position** (they are different layers of one ship graphic and overlay each other). The item frames are positioned in a column to the right of the scheme, one per slot row.

Estimated positions (adjust after visual check — open editor and move nodes until they look right):
- Scheme sprites: all at position (0, 0) relative to the panel node
- Item frames: at x ≈ 60, y = -45 + slot_index * 30 (vertical column)

```
[gd_scene format=3]

[ext_resource type="Script" path="res://global/ui/dialog_system/playermenu/ship_modules_panel.gd" id="1_smp"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/ui/menu_ship_modules_frame.png" id="2_frame"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/ui/menu_ship_modules_scheme_cockpit.png" id="3_ck"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/ui/menu_ship_modules_scheme_armor.png" id="4_ar"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/ui/menu_ship_modules_scheme_weapons.png" id="5_wp"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/ui/menu_ship_modules_scheme_engine.png" id="6_en"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/ui/menu_ship_modules_item_frame.png" id="7_if"]

[node name="ShipModulesPanel" type="Node2D"]
script = ExtResource("1_smp")

[node name="OuterFrame" type="Sprite2D" parent="."]
texture = ExtResource("2_frame")

[node name="SchemeCockpit" type="Sprite2D" parent="."]
texture = ExtResource("3_ck")

[node name="SchemeArmor" type="Sprite2D" parent="."]
texture = ExtResource("4_ar")

[node name="SchemeWeapons" type="Sprite2D" parent="."]
texture = ExtResource("5_wp")

[node name="SchemeEngine" type="Sprite2D" parent="."]
texture = ExtResource("6_en")

[node name="ItemFrameCockpit" type="Sprite2D" parent="."]
position = Vector2(62, -45)
texture = ExtResource("7_if")

[node name="Icon" type="Sprite2D" parent="ItemFrameCockpit"]
scale = Vector2(0.5, 0.5)

[node name="ItemFrameArmor" type="Sprite2D" parent="."]
position = Vector2(62, -15)
texture = ExtResource("7_if")

[node name="Icon" type="Sprite2D" parent="ItemFrameArmor"]
scale = Vector2(0.5, 0.5)

[node name="ItemFrameWeapons" type="Sprite2D" parent="."]
position = Vector2(62, 15)
texture = ExtResource("7_if")

[node name="Icon" type="Sprite2D" parent="ItemFrameWeapons"]
scale = Vector2(0.5, 0.5)

[node name="ItemFrameEngine" type="Sprite2D" parent="."]
position = Vector2(62, 45)
texture = ExtResource("7_if")

[node name="Icon" type="Sprite2D" parent="ItemFrameEngine"]
scale = Vector2(0.5, 0.5)
```

**Note:** Open editor after creation. Move the panel, item frames, and scheme sprites until the ship graphic looks correct and item frames are cleanly positioned. The scheme sprites should perfectly overlay each other.

- [ ] **Step 3: Commit**

```bash
git add global/ui/dialog_system/playermenu/ship_modules_panel.gd global/ui/dialog_system/playermenu/ship_modules_panel.tscn
git commit -m "feat: add ShipModulesPanel visual scene with scheme sprites and item frames"
```

---

## Task 7: Wire ShipModulesPanel and ModuleList into PlayerMenu

This is the main integration task. Extends `PlayerMenu` with a third column and the module-detail flow.

**Files:**
- Modify: `global/ui/dialog_system/playermenu/player_menu.gd`
- Modify: `global/ui/dialog_system/playermenu/player_menu.tscn`

- [ ] **Step 1: Add nodes to `player_menu.tscn`**

Open `player_menu.tscn` in editor and add:
1. An instance of `ship_modules_panel.tscn` as a child of `ShipLayout`, positioned at approximately **(448, 148)**. Name it `ShipModulesPanel`.
2. An instance of `module_list.tscn` as a direct child of the `PlayerMenu` CanvasLayer (sibling of `ShipLayout`), positioned at approximately **(92, 180)**. Name it `ModuleList`. Set `item_origin` to `Vector2(0, -90)` (tune visually).

The tscn diff (hand-edit the file or use editor):

```
## Inside ShipLayout node, after SubWeaponFrame:
[node name="ShipModulesPanel" parent="ShipLayout" instance=ExtResource("X_smp")]
position = Vector2(448, 148)

## Sibling of ShipLayout (direct child of PlayerMenu CanvasLayer):
[node name="ModuleList" parent="." instance=ExtResource("Y_ml")]
position = Vector2(92, 180)
item_origin = Vector2(0.0, -90.0)
```

- [ ] **Step 2: Replace `player_menu.gd` with the full updated version**

The full updated script — read the current `player_menu.gd` first (already read, see Task 0), then replace it completely:

```gdscript
# global/ui/dialog_system/playermenu/player_menu.gd
## Weapon + ship-module selection menu overlay.
## Tab opens/closes; WASD navigates; Space/F selects.
## Col 0 = main weapons, Col 1 = sub-weapons, Col 2 = ship modules.
## In col 2, Space opens the ModuleList overlay for the hovered slot.
class_name PlayerMenu
extends CanvasLayer

const _MODES_DIR := "res://assault/scenes/player/weapons/modes/"

const _WEAPON_ICONS: Dictionary = {
    &"default":      preload("res://assault/assets/sprites/ui/icon_ship_weapon_laser.png"),
    &"piercing":     preload("res://assault/assets/sprites/ui/icon_ship_weapon_pierce.png"),
    &"spread":       preload("res://assault/assets/sprites/ui/icon_ship_weapon_spread.png"),
    &"gatling":      preload("res://assault/assets/sprites/ui/icon_ship_weapon_gatling.png"),
    &"mining_laser": preload("res://assault/assets/sprites/ui/icon_ship_weapon_mining_laser.png"),
}

const _SUB_WEAPON_ICONS: Array[Texture2D] = [
    preload("res://assault/assets/sprites/ui/icon_ship_subweapon_missiles_barage.png"),
    preload("res://assault/assets/sprites/ui/icon_ship_subweapon_homming_misile.png"),
]
const _SUB_WEAPON_NAMES: Array[String] = ["Missiles Barrage", "Homing Missile"]

@onready var _main_frame:    WeaponFrame       = $ShipLayout/MainWeaponFrame
@onready var _sub_frame:     WeaponFrame       = $ShipLayout/SubWeaponFrame
@onready var _modules_panel: ShipModulesPanel  = $ShipLayout/ShipModulesPanel
@onready var _module_list:   ModuleList        = $ModuleList

var _weapon_state: WeaponState  = null
var _rocket_state: RocketState  = null
var _was_paused_by_us: bool     = false

## Col 0 = main weapons, 1 = sub weapons, 2 = ship modules.
var _cursor_col: int = 0
var _cursor_row: int = 0

## True while the module detail list is open.
var _module_list_open: bool = false

func _ready() -> void:
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    _module_list.confirmed.connect(_on_module_confirmed)
    _module_list.cancelled.connect(_on_module_cancelled)

func connect_states(weapon: WeaponState, rocket: RocketState) -> void:
    _weapon_state = weapon
    _rocket_state = rocket
    _populate_lists()
    _refresh_selection()

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("toggle_player_menu"):
        if _module_list_open:
            _close_module_list()
        else:
            _toggle()
        get_viewport().set_input_as_handled()
        return

    if not visible:
        return

    ## Esc while module list is open → close list, return to modules panel.
    if _module_list_open:
        if event.is_action_pressed("ui_cancel"):
            _close_module_list()
            get_viewport().set_input_as_handled()
        elif event.is_action_pressed("menu_up"):
            _module_list.navigate(-1)
            get_viewport().set_input_as_handled()
        elif event.is_action_pressed("menu_down"):
            _module_list.navigate(1)
            get_viewport().set_input_as_handled()
        elif event.is_action_pressed("menu_confirm"):
            _module_list.confirm()
            get_viewport().set_input_as_handled()
        return  ## All other input blocked while list open.

    if event.is_action_pressed("menu_up"):
        _cursor_row = clampi(_cursor_row - 1, 0, maxi(_current_max_row(), 0))
        _refresh_cursor()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("menu_down"):
        _cursor_row = clampi(_cursor_row + 1, 0, maxi(_current_max_row(), 0))
        _refresh_cursor()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("menu_left"):
        _cursor_col = maxi(0, _cursor_col - 1)
        _cursor_row = clampi(_cursor_row, 0, maxi(_current_max_row(), 0))
        _refresh_cursor()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("menu_right"):
        _cursor_col = mini(2, _cursor_col + 1)
        _cursor_row = clampi(_cursor_row, 0, maxi(_current_max_row(), 0))
        _refresh_cursor()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("menu_confirm"):
        _confirm_selection()
        get_viewport().set_input_as_handled()

func _toggle() -> void:
    if not visible:
        if get_tree().paused:
            return
        visible = true
        get_tree().paused = true
        _was_paused_by_us = true
        _modules_panel.refresh_equipped()
        _init_cursor()
        _refresh_cursor()
    else:
        visible = false
        if _was_paused_by_us:
            get_tree().paused = false
            _was_paused_by_us = false

func _init_cursor() -> void:
    var ids := UpgradeState.unlocked_ids()
    if ids.is_empty():
        _cursor_col = 0
        _cursor_row = 0
        return
    var active_id: StringName = &""
    if _weapon_state != null:
        active_id = _weapon_state.get_active_id()
    var found_row: int = 0
    for i: int in ids.size():
        if ids[i] == active_id:
            found_row = i
            break
    _cursor_col = 0
    _cursor_row = found_row

## Max selectable row index for the current column.
func _current_max_row() -> int:
    match _cursor_col:
        0: return maxi(_main_frame.get_count() - 1, 0)
        1: return maxi(_sub_frame.get_count() - 1, 0)
        2: return maxi(_modules_panel.get_slot_count() - 1, 0)
        _: return 0

func _refresh_cursor() -> void:
    _main_frame.set_cursor(_cursor_row if _cursor_col == 0 else -1)
    _sub_frame.set_cursor(_cursor_row if _cursor_col == 1 else -1)
    _modules_panel.set_cursor(_cursor_row if _cursor_col == 2 else -1)

func _confirm_selection() -> void:
    match _cursor_col:
        0:
            var ids := UpgradeState.unlocked_ids()
            if _cursor_row < ids.size():
                _on_main_weapon_pressed(ids[_cursor_row])
        1:
            _on_sub_weapon_pressed(_cursor_row)
        2:
            _open_module_list()

func _open_module_list() -> void:
    var slot: StringName = ShipModuleState.SLOTS[_cursor_row]
    var current_id: StringName = ShipModuleState.get_equipped(slot)
    ## Hide weapon frames while module list is showing.
    _main_frame.visible = false
    _sub_frame.visible = false
    _module_list.open(slot, current_id)
    _module_list_open = true

func _close_module_list() -> void:
    _module_list.close()
    _main_frame.visible = true
    _sub_frame.visible = true
    _module_list_open = false

func _on_module_confirmed(module_id: StringName) -> void:
    var slot: StringName = ShipModuleState.SLOTS[_cursor_row]
    ShipModuleState.equip(slot, module_id)
    _modules_panel.refresh_equipped()
    _close_module_list()

func _on_module_cancelled() -> void:
    _close_module_list()

func _populate_lists() -> void:
    var ids := UpgradeState.unlocked_ids()
    var main_names: Array[String] = []
    var main_icons: Array[Texture2D] = []
    for id: StringName in ids:
        var mode := _load_mode(id)
        main_names.append(mode.display_name if mode != null else String(id))
        main_icons.append(_WEAPON_ICONS.get(id, null) as Texture2D)
    _main_frame.populate(main_names, main_icons)
    _sub_frame.populate(_SUB_WEAPON_NAMES, _SUB_WEAPON_ICONS)

func _load_mode(id: StringName) -> WeaponModeResource:
    var path := _MODES_DIR + String(id) + ".tres"
    if ResourceLoader.exists(path):
        return load(path) as WeaponModeResource
    return null

func _refresh_selection() -> void:
    var active_id: StringName = &""
    if _weapon_state != null:
        active_id = _weapon_state.get_active_id()
    var ids := UpgradeState.unlocked_ids()
    var selected_main: int = -1
    for i: int in ids.size():
        if ids[i] == active_id:
            selected_main = i
            break
    _main_frame.set_selected(selected_main)

    var active_type: int = -1
    if _rocket_state != null:
        active_type = _rocket_state.get_type()
    _sub_frame.set_selected(active_type)

func _on_main_weapon_pressed(id: StringName) -> void:
    if _weapon_state != null:
        _weapon_state.select_weapon(id)
    _refresh_selection()

func _on_sub_weapon_pressed(type: int) -> void:
    if _rocket_state != null:
        _rocket_state.select_sub_weapon(type)
    _refresh_selection()
```

- [ ] **Step 3: Verify navigation**

Open the game, press Tab to open the menu.
- Press D → cursor moves to sub-weapons column ✓
- Press D again → cursor moves to ship modules panel; scheme sprites light up ✓
- Press W/S → different scheme sprites highlight ✓
- Press Space → weapon frames hidden, module list appears ✓
- Press Esc or Tab → weapon frames reappear ✓
- Press Space on a module item → equip confirmed, list closes, item frame icon updates ✓

- [ ] **Step 4: Commit**

```bash
git add global/ui/dialog_system/playermenu/player_menu.gd global/ui/dialog_system/playermenu/player_menu.tscn
git commit -m "feat: integrate ShipModulesPanel and ModuleList into PlayerMenu with col 2 navigation"
```

---

## Task 8: Visual Polish and Position Tuning

**Files:**
- Modify: `global/ui/dialog_system/playermenu/ship_modules_panel.tscn` (node positions)
- Modify: `global/ui/dialog_system/playermenu/player_menu.tscn` (ShipModulesPanel position, ModuleList position)
- Modify: `global/ui/dialog_system/playermenu/module_list_item.tscn` (label offsets)

- [ ] **Step 1: Tune ShipModulesPanel layout in editor**

Open `ship_modules_panel.tscn` in Godot editor.
- Move all four scheme sprites to the **same position** (center of the outer frame sprite). Confirm they visually form a complete ship.
- Move the four ItemFrame nodes so they appear in a neat vertical column beside the ship scheme. Adjust y-positions so they correspond to the ship part they represent (cockpit at top, engine at bottom).
- Run the game, press Tab, D, D — verify the ship scheme and frames look correct.

- [ ] **Step 2: Tune ModuleList position in editor**

Open `player_menu.tscn`. Select the `ModuleList` node.
- Move it so `menu_modules_list_frame.png` exactly covers or aligns with the area occupied by `MainWeaponFrame` and `SubWeaponFrame`.
- Adjust `item_origin` export var so list items appear inside the frame background.
- Run the game, navigate to a module slot, press Space — verify list items appear neatly inside the frame.

- [ ] **Step 3: Tune ModuleListItem label positions**

Open `module_list_item.tscn`. Move `ModuleName` and `ModuleDesc` labels so they fit cleanly inside `menu_modules_list_item.png`. Verify `ModuleDesc` is visually smaller/lighter than `ModuleName`.

- [ ] **Step 4: Commit**

```bash
git add global/ui/dialog_system/playermenu/ship_modules_panel.tscn global/ui/dialog_system/playermenu/player_menu.tscn global/ui/dialog_system/playermenu/module_list_item.tscn
git commit -m "chore: tune ship modules panel and module list visual positions"
```

---

## Self-Review

### Spec Coverage Check

| Spec requirement | Task covering it |
|-----------------|-----------------|
| Ship modules frame scene with frame sprite | Task 6 |
| 4 scheme sprites forming ship | Task 6 |
| Scheme sprite grey when no module, white when equipped, highlighted when hovered | Task 6 (`_update_visuals`) |
| Only hover highlights, not permanent selection highlight | Task 6 (no set_selected on scheme sprites) |
| item_frame per slot showing equipped module icon | Task 6 |
| Grey item frame when no module | Task 6 |
| A/D navigation between columns (now col 0/1/2) | Task 7 |
| W/S navigation within modules column (4 rows) | Task 7 |
| Space opens module detail list | Task 7 (`_open_module_list`) |
| Weapon + sub-weapon frames hidden when list open | Task 7 (`_open_module_list`) |
| Module detail list uses `menu_modules_list_frame.png` | Task 5 |
| Module detail list uses `menu_modules_list_item.png` | Task 4 |
| List shows name + description | Task 4 (`ModuleListItem`) |
| 8 max items in list | Task 5 (`MAX_ITEMS = 8`) |
| Esc or Tab closes list | Task 7 (`ui_cancel`, `toggle_player_menu`) |
| Increased Armor module — health + armor | Task 2/3 |
| Trajectory Calculation module — H key activates time slow | Task 2/3 |
| Warp module — double-press movement teleports instead of barrel-roll | Task 2/3 (DashState modification) |
| Overclock module — shoot past overheat, self-damage | Task 2/3 |
| Module icons shown in item frames | Tasks 4, 6 |
| No module names on scheme view, only icons | Task 6 (only icons in item frames, no labels) |
| Module can be unequipped (None option) | Task 5 (`&""` first in every list) |

### Placeholder Scan
No TBD, TODO, or placeholder steps detected. All code blocks are complete.

### Type Consistency
- `ShipModuleState.SLOTS`: `Array[StringName]` — used consistently in Tasks 1, 6, 7.
- `ShipModuleBase.apply(player: Node)` — `Node` used (not `PlayerBase`) so modules work from any context; `player.get()/set()` used for property access — consistent throughout Tasks 2/3.
- `ModuleList.open(slot, current_id)` takes `StringName, StringName` — called correctly in Task 7 `_open_module_list()`.
- `ModuleList.confirmed` signal emits `StringName` — received by `_on_module_confirmed(module_id: StringName)` — consistent.
- `ShipModulesPanel.set_cursor(row: int)` and `get_slot_count() -> int` — called correctly in Task 7.
- `_module_pool: Dictionary` in `player_fighter.gd` stores `ShipModuleBase` instances — matches `_get_or_create_module` return type.
