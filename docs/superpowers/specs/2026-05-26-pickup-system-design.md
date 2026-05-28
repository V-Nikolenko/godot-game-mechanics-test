# Pickup System Design

## Goal

Add collectible pickups that the player can fly through in any mission. Each pickup applies an immediate or timed effect. Some show a one-line notification dialog. One type (ship module unlocker) permanently equips a ship module.

---

## Pickup Types

| Scene | Texture | Effect | Dialog |
|---|---|---|---|
| `health_tank_pickup` | `health_tank.png` | `health.increase(40)` | **No** |
| `armor_tank_pickup` | `armor_tank.png` | `shield.restore_all_permanent()` | **No** |
| `ship_shield_up_pickup` | `ship_shield_up.png` | `ShipProgressionState.add_permanent_shield()` | Yes — "Permanent shield slot unlocked!" |
| `temporary_shield_up_pickup` | `temporary_shield_up.png` | `shield.add_temporary()` | Yes — "Temporary shield restored!" |
| `armor_and_health_pickup` | `armor_and_health.png` | `health.increase(40)` + `shield.restore_all_permanent()` | Yes — "Hull and shields restored!" |
| `temporary_health_up_pickup` | `temporary_health_up.png` | `temp_health.add_stack(max_health)` | Yes — "Emergency hull reinforcement active!" |
| `temporary_health_shield_up_pickup` | `temporary_health_shield_up.png` | `temp_health.add_stack(max_health)` + `shield.add_temporary()` | Yes — "Combat stims active! Hull and shields reinforced!" |
| `temporary_damage_up_pickup` | `temporary_damage_up.png` | `player.apply_temp_damage_buff(0.5, 15.0)` | Yes — "Weapon output overcharged!" |
| `ship_module_unlocker_pickup` | `ship_module_unlocker.png` | `ShipModuleState.equip(slot, id)` | Yes — "[Module name] acquired!" |

---

## Architecture

### PickupBase (`res://global/pickups/pickup_base.gd`)

Extends `Area2D`. Common logic: detect player body_entered, call `_collect(player)`, show dialog if `_get_dialog_text()` returns a non-empty string, then `queue_free()`.

- `collision_layer = 16` (bit 4, unused layer)
- `collision_mask = 4` (matches player CharacterBody2D collision_layer)
- `_collect(player: PlayerBase) -> void` — abstract, overridden per pickup type
- `_get_dialog_text() -> String` — returns `""` for no-dialog pickups

Dialog is built dynamically in code using `DialogLineResource` + `DialogScriptResource`. No .tres resource files per dialog. `pause_gameplay = false` so the mission continues while the one-liner is displayed. Side = `INNER_THOUGHT` (italic text, no portrait).

### TempHealth Component (`res://global/components/temp_health_component.gd`)

New `Node` component, `class_name TempHealth`. Added to both player .tscn files.

```
var current_temp: int = 0     ## current temporary HP
var _stack_hp: int = 0        ## value of one stack (computed: max_health / 2)
const MAX_STACKS: int = 5

signal amount_changed(current: int, maximum: int)

func add_stack(base_health: int) -> bool
    ## Adds base_health/2 temp HP. Cap: MAX_STACKS * stack_hp. Returns false if full.

func take_damage(amount: int) -> int
    ## Drains current_temp. Returns overflow (damage that passes through).
```

`PlayerBase._apply_damage` is modified to drain temp HP before regular HP (after shield check).

### Temp Damage Buff (fields on PlayerBase)

No new node. Two fields:
```
var _temp_damage_bonus: float = 0.0
var _temp_damage_timer: Timer    ## one_shot, created in _ready
```

`apply_temp_damage_buff(bonus: float, duration: float)`:
- Removes old bonus if timer still running
- Sets `damage_multiplier += bonus`, `_temp_damage_bonus = bonus`
- Starts timer; on timeout: `damage_multiplier -= _temp_damage_bonus`, `_temp_damage_bonus = 0.0`

### HUD — Temp Health Bar

`HealthShieldBar` gains a second `ProgressBar` node (`TempHealthBar`) that sits in front of `HealthBar`. Invisible when `current_temp == 0`. `setup()` gains optional `TempHealth` parameter. `mission_hud.gd` passes it when the component exists.

---

## File Layout

**New — scripts:**
```
res://global/pickups/pickup_base.gd
res://global/pickups/health_tank_pickup.gd
res://global/pickups/armor_tank_pickup.gd
res://global/pickups/ship_shield_up_pickup.gd
res://global/pickups/temporary_shield_up_pickup.gd
res://global/pickups/armor_and_health_pickup.gd
res://global/pickups/temporary_health_up_pickup.gd
res://global/pickups/temporary_health_shield_up_pickup.gd
res://global/pickups/temporary_damage_up_pickup.gd
res://global/pickups/ship_module_unlocker_pickup.gd
res://global/components/temp_health_component.gd
```

**New — scenes:**
```
res://global/pickups/scenes/health_tank_pickup.tscn
res://global/pickups/scenes/armor_tank_pickup.tscn
res://global/pickups/scenes/ship_shield_up_pickup.tscn
res://global/pickups/scenes/temporary_shield_up_pickup.tscn
res://global/pickups/scenes/armor_and_health_pickup.tscn
res://global/pickups/scenes/temporary_health_up_pickup.tscn
res://global/pickups/scenes/temporary_health_shield_up_pickup.tscn
res://global/pickups/scenes/temporary_damage_up_pickup.tscn
res://global/pickups/scenes/ship_module_unlocker_pickup.tscn
```

**Modified:**
```
res://global/entities/player_base.gd
res://global/components/temp_health_component.gd  (new)
res://assault/scenes/player/player_fighter.tscn
res://open_space/scenes/entities/player/player_ship.tscn
res://assault/scenes/gui/health_shield_bar.gd
res://assault/scenes/gui/health_shield_bar.tscn
res://global/ui/mission_hud.gd
```

---

## Constraints

- Getting additional upgrades does NOT restore permanent health or shields (health cap stays at 50)
- Temp HP stacks up to 5 times; each stack = `max_health / 2` = 25 HP → max 125 temp HP
- Temp shields capped at 5 (already enforced by `Shield.max_temporary`)
- Module unlocker writes to `ShipModuleState` permanently (persisted to disk)
- Pickups placed by hand in level scenes, or spawned by WaveManager / enemy drops in future
- No new autoloads needed
