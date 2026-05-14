# Ability-to-Module Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate every remaining ability into the ship-module system, then remove the now-obsolete `AbilityController`, `AbilityState`, and all ability script files.

**Architecture:** Each ability becomes a `ShipModuleBase` subclass placed in `global/ship_modules/`. The `player_fighter._input()` handler already routes H-key to modules (merged in a previous session). The `AbilityController` node is removed from the player scene once every ability has a module equivalent.

**Tech Stack:** Godot 4.3+, GDScript static typing, `ShipModuleBase` interface (`apply / remove / try_activate / tick`), player properties accessed via `player.get()` / `player.set()` / `player.get_node_or_null()`.

---

## Final Module Slot Layout (target state)

| Slot | Module IDs |
|------|-----------|
| cockpit | `""`, `trajectory_calc`, **`emp_blast`** |
| armor | `""`, `armor_plating`, `parry`, **`shield_overload`**, **`final_resort`** |
| weapons | `""`, `overclock`, **`plasma_nova`**, **`overdrive`**, **`overheat_nullifier`** |
| engines | `""`, `warp` |

Bold = new modules created in this plan.

---

## Interfaces & Conventions

All new module files follow the same pattern as existing ones:

```gdscript
class_name XxxModule
extends ShipModuleBase

## Access player components:
##   player.get("health_component")    → Health node
##   player.get("shield_component")    → Shield node
##   player.get("overheat_component")  → Overheat node
##   player.get_node_or_null("SpriteAnchor/ShipSprite2D")  → AnimatedSprite2D
##   player.set("damage_multiplier", 2.0)
##   player.set("fire_rate_multiplier", 2.0)
##   player.set("overdrive_active", true)
##   player.create_tween()
```

---

## Task 1: Create EMPBlastModule

**Files:**
- Create: `global/ship_modules/emp_blast_module.gd`

Stuns all non-immune enemies for 5 seconds. 15-second cooldown. Screen-wide EMP ring visual.

- [ ] **Step 1: Create the file**

```gdscript
# global/ship_modules/emp_blast_module.gd
class_name EMPBlastModule
extends ShipModuleBase

const _STUN_DURATION: float = 5.0
const _COOLDOWN: float = 15.0

## Classes/groups that are immune to the EMP stun.
const _IMMUNE_CLASSES: Array[String] = ["BigAsteroid", "SmallAsteroid", "Asteroid", "RamShip"]

var _cooldown_left: float = 0.0

func get_display_name() -> String: return "EMP Blast"
func get_description() -> String:
	return "Press H to emit a ship-wide electromagnetic pulse. Stuns all nearby enemies for 5 seconds. 15-second cooldown. Asteroids and ram ships are immune."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_cockpit_emp_blast.png")
func get_slot() -> StringName: return &"cockpit"

func apply(_player: Node) -> void:
	pass  ## No passive effect.

func remove(_player: Node) -> void:
	pass  ## Cooldown just stops ticking; no cleanup needed.

func try_activate(player: Node) -> bool:
	if _cooldown_left > 0.0:
		return false
	_cooldown_left = _COOLDOWN
	_spawn_emp_visual(player as Node2D)
	var enemies := player.get_tree().get_nodes_in_group("enemies")
	for e: Node in enemies:
		if _is_immune(e):
			continue
		_stun_enemy(e, player)
	return true

func tick(_player: Node, delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta

func _is_immune(node: Node) -> bool:
	for class_name_str: String in _IMMUNE_CLASSES:
		if node.is_class(class_name_str):
			return true
		var scr: Script = node.get_script() as Script
		if scr != null and scr.get_global_name() == class_name_str:
			return true
	return false

func _stun_enemy(enemy: Node, player: Node) -> void:
	if enemy.process_mode == Node.PROCESS_MODE_DISABLED:
		return  ## Already stunned.
	enemy.set_process_mode(Node.PROCESS_MODE_DISABLED)
	var timer := player.get_tree().create_timer(_STUN_DURATION)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(enemy):
			enemy.set_process_mode(Node.PROCESS_MODE_INHERIT)
	)

func _spawn_emp_visual(actor: Node2D) -> void:
	if actor == null:
		return
	var ring := Node2D.new()
	actor.get_parent().add_child(ring)
	ring.global_position = actor.global_position
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = Color(0.2, 1.0, 0.5, 0.9)
	var pts: PackedVector2Array
	for i: int in 33:
		var angle: float = TAU * i / 32
		pts.append(Vector2(cos(angle), sin(angle)) * 10.0)
	line.points = pts
	ring.add_child(line)
	var t := ring.create_tween()
	t.tween_property(ring, "scale", Vector2(80.0, 80.0), 0.35) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(line, "modulate:a", 0.0, 0.35)
	t.tween_callback(ring.queue_free)
```

- [ ] **Step 2: Verify file saved correctly**

Open `global/ship_modules/emp_blast_module.gd` in the editor. Confirm class name `EMPBlastModule` appears at the top of the Inspector script panel.

> **Icon note:** If `icon_ship_module_cockpit_emp_blast.png` does not exist, replace the `preload(...)` line with `return null`. The icon can be added later without changing any other code.

---

## Task 2: Create ShieldOverloadModule (with Shockwave knockback)

**Files:**
- Create: `global/ship_modules/shield_overload_module.gd`

Drains the player's shield to zero. Each point of shield spent deals 0.5 damage to enemies within 100 px. All enemies in range also receive knockback (280 px/s away from player). Enemy bullets within range are destroyed. No cooldown — the shield is the cost.

- [ ] **Step 1: Create the file**

```gdscript
# global/ship_modules/shield_overload_module.gd
class_name ShieldOverloadModule
extends ShipModuleBase

const _RADIUS: float = 100.0
const _DAMAGE_PER_SHIELD: float = 0.5
const _KNOCKBACK: float = 280.0

## Groups of projectiles cleared by the blast.
const _BULLET_GROUPS: Array[String] = ["enemy_bullets", "bullets"]

func get_display_name() -> String: return "Shield Overload"
func get_description() -> String:
	return "Press H to detonate your shield. Converts every point of shield into 0.5 damage against enemies within 100px and sends them flying. Also destroys nearby projectiles. Requires shield to activate."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_armor_shield_overload.png")
func get_slot() -> StringName: return &"armor"

func apply(_player: Node) -> void:
	pass

func remove(_player: Node) -> void:
	pass

func try_activate(player: Node) -> bool:
	var shield: Shield = player.get("shield_component") as Shield
	if shield == null or shield.current_shield <= 0:
		return false  ## Nothing to spend.

	var actor := player as Node2D
	var shield_spent: int = shield.current_shield

	## Drain shield.
	shield.set_shield(0)

	var damage: int = roundi(shield_spent * _DAMAGE_PER_SHIELD)

	## Damage + knockback enemies in radius.
	var enemies := player.get_tree().get_nodes_in_group("enemies")
	for e: Node in enemies:
		var n := e as Node2D
		if n == null:
			continue
		var dist: float = n.global_position.distance_to(actor.global_position)
		if dist > _RADIUS:
			continue
		## Knockback.
		if n.has_method("apply_knockback"):
			var dir: Vector2 = (n.global_position - actor.global_position).normalized()
			n.apply_knockback(dir * _KNOCKBACK)
		## Damage via HurtBox.
		var hb := n.get_node_or_null("HurtBox") as HurtBox
		if hb:
			hb.received_damage.emit(damage)

	## Destroy projectiles in radius.
	for group: String in _BULLET_GROUPS:
		for node: Node in player.get_tree().get_nodes_in_group(group):
			var n := node as Node2D
			if n == null:
				continue
			if n.global_position.distance_to(actor.global_position) <= _RADIUS:
				n.queue_free()

	## Visual: electric burst ring.
	_spawn_burst(actor)
	return true  ## Consumed input (even though there is no standard cooldown).

func _spawn_burst(actor: Node2D) -> void:
	var ring := Node2D.new()
	actor.get_parent().add_child(ring)
	ring.global_position = actor.global_position
	var line := Line2D.new()
	line.width = 5.0
	line.default_color = Color(0.1, 0.7, 1.0, 1.0)
	var pts: PackedVector2Array
	for i: int in 33:
		var angle: float = TAU * i / 32
		pts.append(Vector2(cos(angle), sin(angle)) * 6.0)
	line.points = pts
	ring.add_child(line)
	var target_scale: float = _RADIUS / 6.0
	var t := ring.create_tween()
	t.tween_property(ring, "scale", Vector2(target_scale, target_scale), 0.2) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(line, "modulate:a", 0.0, 0.2)
	t.tween_callback(ring.queue_free)
```

- [ ] **Step 2: Verify file saved correctly**

Open `global/ship_modules/shield_overload_module.gd`. Confirm `class_name ShieldOverloadModule`.

> **Icon note:** If `icon_ship_module_armor_shield_overload.png` does not exist, replace the `preload(...)` with `return null`.

---

## Task 3: Create FinalResortModule

**Files:**
- Create: `global/ship_modules/final_resort_module.gd`

Toggle: on first press, collapses HP to 1, drains shield, triples outgoing damage. On second press, restores HP to the value it was at when activated (capped at current HP if already lower). No cooldown — it's a toggle.

- [ ] **Step 1: Create the file**

```gdscript
# global/ship_modules/final_resort_module.gd
class_name FinalResortModule
extends ShipModuleBase

const _DAMAGE_MULTIPLIER: float = 3.0

var _active: bool = false
var _saved_hp: int = 0

func get_display_name() -> String: return "Final Resort"
func get_description() -> String:
	return "Press H to sacrifice hull and shields for overwhelming firepower. HP drops to 1, shields drain, damage is tripled. Press H again to disengage and restore HP."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_armor_final_resort.png")
func get_slot() -> StringName: return &"armor"

func apply(_player: Node) -> void:
	pass

func remove(player: Node) -> void:
	## If active when unequipped, disengage cleanly.
	if _active:
		_disengage(player)

func try_activate(player: Node) -> bool:
	if not _active:
		_engage(player)
	else:
		_disengage(player)
	return true  ## Always consume input.

func tick(_player: Node, _delta: float) -> void:
	pass  ## No time-limited effect; purely a toggle.

func _engage(player: Node) -> void:
	var health: Health = player.get("health_component") as Health
	if health == null:
		push_warning("FinalResortModule: health_component not found on player")
		return
	_active = true
	_saved_hp = health.current_health

	## Collapse HP to 1.
	health.set_health(1)

	## Drain shield.
	var shield: Shield = player.get("shield_component") as Shield
	if shield:
		shield.set_shield(0)

	## Triple damage.
	player.set("damage_multiplier", _DAMAGE_MULTIPLIER)

	## Blood-red ship tint.
	var sprite := player.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(1.0, 0.1, 0.1, 1.0)

func _disengage(player: Node) -> void:
	_active = false
	var health: Health = player.get("health_component") as Health
	if health:
		## Restore saved HP, but never exceed what HP is right now (can't gain HP from the mode).
		health.set_health(mini(_saved_hp, health.current_health))

	## Restore damage multiplier.
	player.set("damage_multiplier", 1.0)

	## Remove tint.
	var sprite := player.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		player.create_tween().tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.3)
```

- [ ] **Step 2: Verify file saved correctly**

Open `global/ship_modules/final_resort_module.gd`. Confirm `class_name FinalResortModule`.

> **Icon note:** If `icon_ship_module_armor_final_resort.png` does not exist, replace the `preload(...)` with `return null`.

---

## Task 4: Create PlasmaNovaModule

**Files:**
- Create: `global/ship_modules/plasma_nova_module.gd`

Deals 50 damage to every enemy on screen simultaneously. Purple flash overlay. 30-second cooldown.

- [ ] **Step 1: Create the file**

```gdscript
# global/ship_modules/plasma_nova_module.gd
class_name PlasmaNovaModule
extends ShipModuleBase

const _DAMAGE: int = 50
const _COOLDOWN: float = 30.0

var _cooldown_left: float = 0.0

func get_display_name() -> String: return "Plasma Nova"
func get_description() -> String:
	return "Press H to release a burst of superheated plasma. Deals 50 damage to every enemy on screen simultaneously. 30-second cooldown."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_weapon_plasma_nova.png")
func get_slot() -> StringName: return &"weapons"

func apply(_player: Node) -> void:
	pass

func remove(_player: Node) -> void:
	pass

func try_activate(player: Node) -> bool:
	if _cooldown_left > 0.0:
		return false
	_cooldown_left = _COOLDOWN

	## Damage all enemies.
	var enemies := player.get_tree().get_nodes_in_group("enemies")
	for e: Node in enemies:
		var n := e as Node2D
		if n == null:
			continue
		var hb := n.get_node_or_null("HurtBox") as HurtBox
		if hb:
			hb.received_damage.emit(_DAMAGE)

	## Screen-wide purple flash.
	_spawn_flash(player as Node2D)
	return true

func tick(_player: Node, delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta

func _spawn_flash(actor: Node2D) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.85, 0.5, 1.0, 0.75)
	var canvas := CanvasLayer.new()
	canvas.layer = 128
	canvas.add_child(overlay)
	actor.get_tree().root.add_child(canvas)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t := canvas.create_tween()
	t.tween_property(overlay, "modulate:a", 0.0, 0.5)
	t.tween_callback(canvas.queue_free)
```

- [ ] **Step 2: Verify file saved correctly**

Open `global/ship_modules/plasma_nova_module.gd`. Confirm `class_name PlasmaNovaModule`.

> **Icon note:** If `icon_ship_module_weapon_plasma_nova.png` does not exist, replace the `preload(...)` with `return null`.

---

## Task 5: Create OverdriveModule

**Files:**
- Create: `global/ship_modules/overdrive_module.gd`

Doubles fire rate for 10 seconds. If the effect expires naturally (not toggled/unequipped), the player takes 15 hull damage. 30-second cooldown.

- [ ] **Step 1: Create the file**

```gdscript
# global/ship_modules/overdrive_module.gd
class_name OverdriveModule
extends ShipModuleBase

const _DURATION: float = 10.0
const _FIRE_RATE_MULTIPLIER: float = 2.0
const _EXPIRY_DAMAGE: int = 15
const _COOLDOWN: float = 30.0

var _active: bool = false
var _time_left: float = 0.0
var _cooldown_left: float = 0.0

func get_display_name() -> String: return "Overdrive"
func get_description() -> String:
	return "Press H to push weapons beyond safe limits. Fire rate is doubled for 10 seconds and overheating is suppressed. When the effect expires naturally, the hull takes 15 damage. 30-second cooldown."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_weapon_overdrive.png")
func get_slot() -> StringName: return &"weapons"

func apply(_player: Node) -> void:
	pass

func remove(player: Node) -> void:
	## If active when unequipped, end cleanly without the expiry damage.
	if _active:
		_end(player, false)

func try_activate(player: Node) -> bool:
	if _active or _cooldown_left > 0.0:
		return false
	_active = true
	_time_left = _DURATION
	player.set("fire_rate_multiplier", _FIRE_RATE_MULTIPLIER)
	player.set("overdrive_active", true)
	## Red-orange ship tint.
	var sprite := player.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(1.0, 0.4, 0.1, 1.0)
	return true

func tick(player: Node, delta: float) -> void:
	if _active:
		_time_left -= delta
		if _time_left <= 0.0:
			_end(player, true)  ## Natural expiry — apply damage penalty.
	elif _cooldown_left > 0.0:
		_cooldown_left -= delta

func _end(player: Node, apply_expiry_damage: bool) -> void:
	if not _active:
		return
	_active = false
	_time_left = 0.0
	_cooldown_left = _COOLDOWN
	player.set("fire_rate_multiplier", 1.0)
	player.set("overdrive_active", false)
	if apply_expiry_damage:
		var health: Health = player.get("health_component") as Health
		if health:
			health.decrease(_EXPIRY_DAMAGE)
	var sprite := player.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		player.create_tween().tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.4)

## Safety: restore multipliers if node is freed while active.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _active:
		## Can't safely call player.set() here; rely on player_fighter reset logic.
		_active = false
```

- [ ] **Step 2: Verify file saved correctly**

Open `global/ship_modules/overdrive_module.gd`. Confirm `class_name OverdriveModule`.

> **Icon note:** If `icon_ship_module_weapon_overdrive.png` does not exist, replace the `preload(...)` with `return null`.

---

## Task 6: Create OverheatNullifierModule

**Files:**
- Create: `global/ship_modules/overheat_nullifier_module.gd`

Instantly resets the overheat gauge to zero. Blue-white flash on the ship. 15-second cooldown.

- [ ] **Step 1: Create the file**

```gdscript
# global/ship_modules/overheat_nullifier_module.gd
class_name OverheatNullifierModule
extends ShipModuleBase

const _COOLDOWN: float = 15.0

var _cooldown_left: float = 0.0

func get_display_name() -> String: return "Heat Flush"
func get_description() -> String:
	return "Press H to instantly vent all accumulated heat. Resets the overheat gauge to zero. 15-second cooldown. Has no effect in open space (no overheat system)."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_weapon_heat_flush.png")
func get_slot() -> StringName: return &"weapons"

func apply(_player: Node) -> void:
	pass

func remove(_player: Node) -> void:
	pass

func try_activate(player: Node) -> bool:
	if _cooldown_left > 0.0:
		return false
	var overheat: Overheat = player.get("overheat_component") as Overheat
	if overheat == null:
		return false  ## Not available without an overheat component (open space).
	_cooldown_left = _COOLDOWN
	overheat.heat = 0.0
	overheat._emit_heat()
	## Visual: blue-white flash.
	var sprite := player.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		var t := player.create_tween()
		t.tween_property(sprite, "modulate", Color(0.6, 0.9, 1.0, 1.0), 0.05)
		t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.25)
	return true

func tick(_player: Node, delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
```

- [ ] **Step 2: Verify file saved correctly**

Open `global/ship_modules/overheat_nullifier_module.gd`. Confirm `class_name OverheatNullifierModule`.

> **Icon note:** If `icon_ship_module_weapon_heat_flush.png` does not exist, replace the `preload(...)` with `return null`.

---

## Task 7: Register All New Modules

**Files:**
- Modify: `global/autoloads/ship_module_state.gd`
- Modify: `assault/scenes/player/player_fighter.gd`
- Modify: `global/ui/dialog_system/playermenu/module_list.gd`

Wire the six new modules into every place that maps module ID strings to instances.

- [ ] **Step 1: Update `ship_module_state.gd` — expand `SLOT_MODULES`**

In `global/autoloads/ship_module_state.gd`, replace the `SLOT_MODULES` constant and update the header comment:

Old:
```gdscript
## Module IDs per slot:
##   cockpit  → &"trajectory_calc"
##   armor    → &"armor_plating"  |  &"parry"
##   weapons  → &"overclock"
##   engines  → &"warp"
## Empty string means nothing equipped.

const SLOTS: Array[StringName] = [&"cockpit", &"armor", &"weapons", &"engines"]

## Maps slot → list of available module IDs (in display order).
## First entry is always &"" (None / unequip).
const SLOT_MODULES: Dictionary = {
	&"cockpit":  [&"", &"trajectory_calc"],
	&"armor":    [&"", &"armor_plating", &"parry"],
	&"weapons":  [&"", &"overclock"],
	&"engines":  [&"", &"warp"],
}
```

New:
```gdscript
## Module IDs per slot:
##   cockpit  → &"trajectory_calc"  |  &"emp_blast"
##   armor    → &"armor_plating"  |  &"parry"  |  &"shield_overload"  |  &"final_resort"
##   weapons  → &"overclock"  |  &"plasma_nova"  |  &"overdrive"  |  &"overheat_nullifier"
##   engines  → &"warp"
## Empty string means nothing equipped.

const SLOTS: Array[StringName] = [&"cockpit", &"armor", &"weapons", &"engines"]

## Maps slot → list of available module IDs (in display order).
## First entry is always &"" (None / unequip).
const SLOT_MODULES: Dictionary = {
	&"cockpit":  [&"", &"trajectory_calc", &"emp_blast"],
	&"armor":    [&"", &"armor_plating", &"parry", &"shield_overload", &"final_resort"],
	&"weapons":  [&"", &"overclock", &"plasma_nova", &"overdrive", &"overheat_nullifier"],
	&"engines":  [&"", &"warp"],
}
```

- [ ] **Step 2: Update `player_fighter.gd` — expand `_create_module()`**

In `assault/scenes/player/player_fighter.gd`, find `_create_module()` and add the six new entries:

Old:
```gdscript
func _create_module(id: StringName) -> ShipModuleBase:
	match id:
		&"armor_plating":   return ArmorPlatingModule.new()
		&"parry":           return ParryModule.new()
		&"trajectory_calc": return TrajectoryCalcModule.new()
		&"warp":            return WarpModule.new()
		&"overclock":       return OverclockModule.new()
		_:
			push_warning("AssaultPlayer: unknown module id '%s'" % id)
			return null
```

New:
```gdscript
func _create_module(id: StringName) -> ShipModuleBase:
	match id:
		&"armor_plating":      return ArmorPlatingModule.new()
		&"parry":              return ParryModule.new()
		&"trajectory_calc":    return TrajectoryCalcModule.new()
		&"warp":               return WarpModule.new()
		&"overclock":          return OverclockModule.new()
		&"emp_blast":          return EMPBlastModule.new()
		&"shield_overload":    return ShieldOverloadModule.new()
		&"final_resort":       return FinalResortModule.new()
		&"plasma_nova":        return PlasmaNovaModule.new()
		&"overdrive":          return OverdriveModule.new()
		&"overheat_nullifier": return OverheatNullifierModule.new()
		_:
			push_warning("AssaultPlayer: unknown module id '%s'" % id)
			return null
```

- [ ] **Step 3: Update `module_list.gd` — expand `_make_module()`**

In `global/ui/dialog_system/playermenu/module_list.gd`, find `_make_module()` and add the six new entries:

Old:
```gdscript
func _make_module(id: StringName) -> ShipModuleBase:
	match id:
		&"armor_plating":   return ArmorPlatingModule.new()
		&"parry":           return ParryModule.new()
		&"trajectory_calc": return TrajectoryCalcModule.new()
		&"warp":            return WarpModule.new()
		&"overclock":       return OverclockModule.new()
		_:                  return null
```

New:
```gdscript
func _make_module(id: StringName) -> ShipModuleBase:
	match id:
		&"armor_plating":      return ArmorPlatingModule.new()
		&"parry":              return ParryModule.new()
		&"trajectory_calc":    return TrajectoryCalcModule.new()
		&"warp":               return WarpModule.new()
		&"overclock":          return OverclockModule.new()
		&"emp_blast":          return EMPBlastModule.new()
		&"shield_overload":    return ShieldOverloadModule.new()
		&"final_resort":       return FinalResortModule.new()
		&"plasma_nova":        return PlasmaNovaModule.new()
		&"overdrive":          return OverdriveModule.new()
		&"overheat_nullifier": return OverheatNullifierModule.new()
		_:                     return null
```

- [ ] **Step 4: Smoke-test in Godot**

Boot the game. Open the ship modules menu. Navigate to each slot — the new module names should appear in the lists. Equip each new module and press H in gameplay to confirm activation (basic functionality check).

---

## Task 8: Remove Legacy Ability System

**Files:**
- Modify: `assault/scenes/player/player_fighter.tscn` — remove AbilityController node
- Modify: `project.godot` — remove AbilityState autoload entry
- Delete: all files listed below

Only do this after Task 7 is verified working.

- [ ] **Step 1: Remove AbilityController node from `player_fighter.tscn`**

In `assault/scenes/player/player_fighter.tscn`, delete these lines (the AbilityController node definition):

```
[node name="AbilityController" type="Node" parent="." node_paths=PackedStringArray("actor", "health", "shield", "overheat")]
script = ExtResource("16_abctl")
actor = NodePath("..")
health = NodePath("../HealthComponent")
shield = NodePath("../ShieldComponent")
overheat = NodePath("../OverheatComponent")
```

Also delete the `ext_resource` declaration for the ability_controller script near the top:

```
[ext_resource type="Script" path="res://global/abilities/ability_controller.gd" id="16_abctl"]
```

Update the `load_steps` count at the very top of the file from its current value to one less (e.g., if it says `load_steps=30`, change to `load_steps=29`).

- [ ] **Step 2: Remove AbilityState autoload from `project.godot`**

Open `project.godot`. Find and delete the line that registers AbilityState (it looks like):

```
AbilityState="*res://global/autoloads/ability_state.gd"
```

Leave `ShipModuleState` and all other autoloads intact.

- [ ] **Step 3: Delete legacy ability files**

Delete all of the following files (they are fully replaced by modules):

```
global/abilities/ability_base.gd
global/abilities/ability_controller.gd
global/abilities/ability_state.gd
global/abilities/armor_plating_ability.gd
global/abilities/emp_blast_ability.gd
global/abilities/final_resort_ability.gd
global/abilities/overdrive_ability.gd
global/abilities/overheat_nullifier_ability.gd
global/abilities/parry_ability.gd
global/abilities/plasma_nova_ability.gd
global/abilities/shield_overload_ability.gd
global/abilities/shield_recharge_ability.gd
global/abilities/shockwave_ability.gd
global/abilities/teleport_ability.gd
global/abilities/trajectory_calc_ability.gd
```

If the `global/abilities/` directory is empty after deletion, delete the directory too.

- [ ] **Step 4: Update `player_base.gd` comment**

In `global/entities/player_base.gd`, line 20, update the stale comment:

Old:
```gdscript
## Multipliers written by AbilityController / abilities.
```

New:
```gdscript
## Multipliers written by ship modules (OverdriveModule, FinalResortModule, etc.).
```

- [ ] **Step 5: Boot and verify**

1. Open the game in Godot — confirm no parsing errors or missing script warnings.
2. Load the assault level — player spawns correctly.
3. Press H with no module equipped — nothing happens (no ability fires).
4. Equip `overdrive` in weapons slot — press H — fire rate doubles for 10 s.
5. Equip `shield_overload` in armor slot — press H with shield charged — enemies in radius take damage and fly back.
6. Equip `emp_blast` in cockpit slot — press H — enemies freeze for 5 s.
7. Equip `plasma_nova` in weapons slot — press H — all enemies on screen take 50 damage with purple flash.
8. Equip `final_resort` in armor slot — press H — HP drops to 1, red tint. Press H again — HP restores.
9. Equip `overheat_nullifier` in weapons slot — fire until overheating — press H — heat gauge resets to zero.

---

## Files Changed Summary

| Task | File | Action |
|------|------|--------|
| 1 | `global/ship_modules/emp_blast_module.gd` | Create |
| 2 | `global/ship_modules/shield_overload_module.gd` | Create |
| 3 | `global/ship_modules/final_resort_module.gd` | Create |
| 4 | `global/ship_modules/plasma_nova_module.gd` | Create |
| 5 | `global/ship_modules/overdrive_module.gd` | Create |
| 6 | `global/ship_modules/overheat_nullifier_module.gd` | Create |
| 7 | `global/autoloads/ship_module_state.gd` | Modify |
| 7 | `assault/scenes/player/player_fighter.gd` | Modify |
| 7 | `global/ui/dialog_system/playermenu/module_list.gd` | Modify |
| 8 | `assault/scenes/player/player_fighter.tscn` | Modify |
| 8 | `project.godot` | Modify |
| 8 | `global/abilities/*.gd` (15 files) | Delete |
| 8 | `global/entities/player_base.gd` | Modify (comment) |

---

## Rollback Plan

- Tasks 1–6 are purely additive (new files, no changes to existing code). Safe to add and test before touching anything else.
- Task 7 only adds new IDs to dictionaries / match blocks — existing modules are unchanged.
- Task 8 is the only destructive step. Do it last and only after full verification. Use `git stash` or keep the old files in a backup branch if uncertain.
