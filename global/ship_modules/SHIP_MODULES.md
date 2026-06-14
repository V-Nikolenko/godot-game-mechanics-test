# Ship Modules

Reference documentation for the ship-module system. Godot 4.6, GDScript.

Source of truth lives in `global/ship_modules/` and the `ShipModuleState` autoload
(`global/autoloads/ship_module_state.gd`). Do not edit this doc by hand without
re-reading the scripts — values below are read directly from source.

---

## 1. Overview

A **ship module** is a `RefCounted` subclass of `ShipModuleBase`
(`global/ship_modules/ship_module_base.gd`). It is a small behaviour object the
player ship equips into one of four slots. Modules come in two flavours:

- **Passive** — `apply(player)` writes a flag or multiplier onto the player when
  equipped, and `remove(player)` undoes it when unequipped (or on scene change).
  Examples: `ArmorPlatingModule`, `ShootingModule`, `WarpModule`, `PierceModule`,
  `OverclockModule`.
- **Active** — the player presses **H** (the `use_ability` input action). The
  player forwards the press to the equipped modules' `try_activate(player)`; the
  first module that returns `true` consumes the input. `tick(player, delta)` then
  runs every frame to manage cooldowns and timed effects. Examples:
  `TrajectoryCalcModule`, `ParryModule`, `EMPBlastModule`, `PlasmaNovaModule`,
  `EngineBoostModule`. Some modules are hybrid (passive effect + H ability), e.g.
  `OverheatNullifierModule`, `AITargetingModule`, `CockpitHealModule`.

Two pieces of infrastructure tie it together:

- **`ShipModuleState`** (autoload) stores which module id is equipped in each slot,
  persists it to `user://ship_modules.cfg`, and emits `module_equipped` /
  `module_unequipped` signals so gameplay can apply/remove modules live.
- **`ShipModuleBase.create(id)`** is the single instantiation source of truth — a
  `match` that maps each StringName id to its module class. Both the player and the
  UI call it; nothing else should `new()` a module class directly.

On the player side, `assault/scenes/player/player_fighter.gd`:

- On `_ready()`, applies every already-equipped module
  (`ShipModuleState.get_equipped(slot)` → `_apply_module(id)`), and connects the
  equip/unequip signals (`_on_module_equipped` / `_on_module_unequipped`).
- Keeps a lazy `_module_pool` (`{ StringName: ShipModuleBase }`); modules are
  instantiated once via `ShipModuleBase.create()` and reused.
- Every physics frame, ticks **all** pooled modules: `mod.tick(self, _delta)`.
- On the **H** key (`_input`, which fires before `_unhandled_input` so modules get
  first pick), iterates the pool and calls `try_activate(self)`, stopping at the
  first module that returns `true`.
- `_apply_module` / `_remove_module` call the module's `apply` / `remove` and
  add/erase it from the pool.

Modules write to fields declared on `global/entities/player_base.gd`:
`damage_multiplier`, `fire_rate_multiplier`, `damage_reduction`,
`overdrive_active`, `pierce_module_active`, `engine_boost_active`,
`warp_module_active`, `overclock_module_active`. `WeaponState` reads the
multipliers; `_apply_damage` applies `damage_reduction` when health takes a hit.

---

## 2. The `ShipModuleBase` contract

All methods are overridable. Base implementations are no-ops / empty returns.

| Method | Signature | Purpose |
|--------|-----------|---------|
| `get_display_name` | `() -> String` | Human-readable name shown in the module detail list. |
| `get_description` | `() -> String` | One-sentence description shown in the detail list. |
| `get_icon` | `() -> Texture2D` | Icon texture for the item frame / detail list (usually a `preload`). |
| `get_slot` | `() -> StringName` | Slot the module belongs to: `&"cockpit"` / `&"armor"` / `&"weapons"` / `&"engines"`. |
| `apply` | `(player: Node) -> void` | Apply passive effect on equip (set flags/multipliers). |
| `remove` | `(player: Node) -> void` | Undo passive effect on unequip or scene change; also used to clean up an active effect if unequipped mid-use. |
| `try_activate` | `(player: Node) -> bool` | Active modules: called on **H**. Return `true` if the input was consumed (effect started or on cooldown gate). Passive modules leave the base `false`. |
| `tick` | `(player: Node, delta: float) -> void` | Active modules: called every physics frame for every pooled module. Handles cooldown countdown and timed-effect expiry. **`delta` is real-time** — `Engine.time_scale` is already applied, so a module that slows time (e.g. `TrajectoryCalcModule`) must divide by its own time scale to recover real seconds. |

`ShipModuleBase.create(id: StringName) -> ShipModuleBase` is a static factory; an
unknown id logs `push_warning` and returns `null`.

---

## 3. Slots

`ShipModuleState.SLOTS` defines four slots; **each slot holds exactly one module**
(empty string `&""` = nothing equipped). Equipping a new module replaces the
previous one in that slot.

| Slot StringName | Modules valid for the slot |
|-----------------|----------------------------|
| `&"cockpit"`  | `trajectory_calc`, `emp_blast`, `ai_targeting`, `cockpit_heal` |
| `&"armor"`    | `armor_plating`, `parry`, `shield_overload`, `final_resort` |
| `&"weapons"`  | `overclock`, `plasma_nova`, `overheat_nullifier`, `pierce`, `shooting` |
| `&"engines"`  | `warp`, `engine_boost` |

(See `ShipModuleState.SLOT_MODULES` for the display-ordered lists, each prefixed
with `&""` for the "None" entry.)

---

## 4. Module roster

One subsection per module, in registration order. Values are read from source.

### 4.1 ArmorPlatingModule — reinforced hull plating

A tankier hull: more max HP and flat damage reduction.

- **id:** `&"armor_plating"` · **class:** `ArmorPlatingModule` · **slot:** `&"armor"` · **type:** passive

**Effect:** `apply()` adds `+40` to `health_component.max_health` and immediately
restores that 40 HP (no phantom empty bar), and adds `+0.25` to the player's
`damage_reduction`. `remove()` subtracts the 40 max HP (clamping current HP to the
new max), and subtracts `0.25` from `damage_reduction` (floored at `0.0`).

- Health bonus: `40`
- Damage reduction: `+0.25` (25%)
- `try_activate` / `tick`: n/a

### 4.2 ParryModule — brace for impact

A short, on-demand invulnerability window.

- **id:** `&"parry"` · **class:** `ParryModule` · **slot:** `&"armor"` · **type:** active

**Effect:** `apply()` does nothing (no passive). `try_activate()` opens a parry
window: saves the current `damage_reduction`, sets it to `1.0` (full immunity),
flashes the ship sprite white-blue, and starts the window. `tick()` counts the
window down by real `delta`; when it expires `_deactivate()` restores the saved
`damage_reduction`, tweens the sprite back to white, and starts the cooldown.
`remove()` cleans up immediately if active. Gated while active or on cooldown.

- Window: `0.5 s`
- Cooldown: `10.0 s`
- During window: `damage_reduction = 1.0`

### 4.3 TrajectoryCalcModule — targeting computers / bullet time

Slows time so the player can read and dodge enemy fire.

- **id:** `&"trajectory_calc"` · **class:** `TrajectoryCalcModule` · **slot:** `&"cockpit"` · **type:** active

**Effect:** `apply()` does nothing. `try_activate()` sets `Engine.time_scale` to
`0.3`, tints the ship sprite blue, and spawns a full-screen blue overlay
(`CanvasLayer` at layer 10). `tick()` decrements the remaining duration by
`delta / 0.3` (recovering real seconds while time is slowed); on expiry `_restore()`
resets `time_scale = 1.0`, removes the overlay, tweens the sprite back, and starts
the cooldown. `remove()` and a `NOTIFICATION_PREDELETE` safety net both restore
`time_scale` and remove the overlay if freed mid-effect.

- Duration: `5.0 s` (real time)
- Time scale: `0.3` (30%)
- Cooldown: `20.0 s`

### 4.4 WarpModule — micro-warp teleport

Swaps the barrel-roll dash for a blink.

- **id:** `&"warp"` · **class:** `WarpModule` · **slot:** `&"engines"` · **type:** passive

**Effect:** `apply()` sets `player.warp_module_active = true`; `remove()` sets it
`false`. The flag is read by `DashState`, which teleports ~120 px in the movement
direction on a double-tap instead of rolling. (Actual teleport distance lives in
the dash state, not this module.)

- `try_activate` / `tick`: n/a

### 4.5 OverclockModule — bypass thermal safeties

Keep firing past the heat limit, at the cost of hull damage.

- **id:** `&"overclock"` · **class:** `OverclockModule` · **slot:** `&"weapons"` · **type:** passive

**Effect:** `apply()` sets `player.overclock_module_active = true`; `remove()` sets
it `false`. The player's overheat handling reads this flag to never lock weapons,
even at 100% heat (see `player_fighter.gd`); each shot fired while overheated deals
3 hull damage (enforced by the weapon/overheat side, not this module).

- `try_activate` / `tick`: n/a

### 4.6 EMPBlastModule — electromagnetic pulse

Ship-wide stun that disables nearby enemies.

- **id:** `&"emp_blast"` · **class:** `EMPBlastModule` · **slot:** `&"cockpit"` · **type:** active

**Effect:** `apply()` / `remove()` do nothing (cooldown just stops ticking).
`try_activate()` spawns an expanding green ring and stuns every node in the
`"enemies"` group that isn't immune, by setting `process_mode = DISABLED` and
re-enabling it via a `SceneTree` timer after the stun duration. `tick()` counts the
cooldown down. Immune classes: `BigAsteroid`, `SmallAsteroid`, `Asteroid`,
`RamShip`.

- Stun duration: `5.0 s`
- Cooldown: `15.0 s`

### 4.7 ShieldOverloadModule — detonate your shield

Spend all shields for a radial damage + projectile-clear burst.

- **id:** `&"shield_overload"` · **class:** `ShieldOverloadModule` · **slot:** `&"armor"` · **type:** active

**Effect:** `apply()` / `remove()` do nothing. `try_activate()` reads the player's
`shield_component`; if total shields (`permanent_active + temporary_count`) is `0`
it returns `false` (nothing to detonate). Otherwise it zeroes all shields, deals
`spent * 25` damage to enemies within radius (via their `HurtBox.received_damage`),
applies knockback to enemies that support `apply_knockback`, destroys projectiles in
the `"enemy_bullets"` / `"bullets"` groups within radius, and spawns a burst ring.
No cooldown — it is gated by having shields to spend.

- Radius: `100.0 px`
- Damage per shield consumed: `25`
- Knockback: `280.0`
- `tick`: n/a (no cooldown)

### 4.8 FinalResortModule — sacrifice hull for firepower

A toggle: drop to 1 HP for tripled damage, toggle off to recover.

- **id:** `&"final_resort"` · **class:** `FinalResortModule` · **slot:** `&"armor"` · **type:** active (toggle)

**Effect:** `apply()` does nothing. `try_activate()` toggles: `_engage()` saves
current HP, sets HP to `1`, drains shields (`set_all_zero`), sets
`damage_multiplier = 3.0`, and tints the ship blood-red. A second press
`_disengage()` restores HP to `min(saved_hp, current_hp)` (you can't gain HP from
the mode), resets `damage_multiplier = 1.0`, and removes the tint. `tick()` is a
no-op (pure toggle, no timer). `remove()` disengages cleanly if active.

- Damage multiplier while active: `3.0`
- HP while active: `1`
- Cooldown: n/a (toggle)

### 4.9 PlasmaNovaModule — screen-clearing plasma burst

One big AoE nuke on a long cooldown.

- **id:** `&"plasma_nova"` · **class:** `PlasmaNovaModule` · **slot:** `&"weapons"` · **type:** active

**Effect:** `apply()` / `remove()` do nothing. `try_activate()` deals `50` damage to
every node in the `"enemies"` group simultaneously (via each enemy's `HurtBox`) and
spawns a screen-wide purple flash. `tick()` counts the cooldown down. Gated on
cooldown.

- Damage (all enemies on screen): `50`
- Cooldown: `30.0 s`

### 4.10 OverheatNullifierModule — heat flush (passive + active)

Faster heat dissipation, plus an on-demand full vent.

- **id:** `&"overheat_nullifier"` · **class:** `OverheatNullifierModule` · **slot:** `&"weapons"` · **type:** hybrid (passive + active)

**Effect:** `apply()` finds the player's `overheat_component`, saves its
`cooldown_time`, and halves it (`* 0.5`) — doubling dissipation speed. `remove()`
restores the original `cooldown_time`. `try_activate()` instantly sets the
overheat component's `heat = 0.0`, re-emits the heat signal, flashes the sprite
blue-white, and starts the cooldown. `tick()` counts the cooldown down. Active
part is gated on cooldown and on having an overheat component.

- Dissipation multiplier (passive): `0.5` (halves cooldown_time → 2× faster)
- Active cooldown: `15.0 s`

### 4.11 AITargetingModule — targeting line (passive + active)

A passive aim line plus an instant snap-to-target.

- **id:** `&"ai_targeting"` · **class:** `AITargetingModule` · **slot:** `&"cockpit"` · **type:** hybrid (passive + active)

**Effect:** `apply()` spawns a thin green `Line2D` indicator (top-level, world-space).
`tick()` updates the line each frame to point from the ship to the nearest enemy
(hidden when none within range) and counts the cooldown down. `try_activate()` finds
the nearest enemy within range and snaps the ship's `rotation` to face it (returns
`false` if no target). `remove()` frees the indicator.

- Max range: `900.0 px`
- Active cooldown: `15.0 s`

### 4.12 CockpitHealModule — repair system (passive + active)

Stationary regen plus an instant heal that locks the regen.

- **id:** `&"cockpit_heal"` · **class:** `CockpitHealModule` · **slot:** `&"cockpit"` · **type:** hybrid (passive + active)

**Effect:** `apply()` does nothing. `tick()` runs the passive regen: while the
player's `velocity` length is below the threshold for the still-delay, hull
regenerates at the regen rate (fractional HP accumulated and applied as whole
points, never above `max_health`). `try_activate()` instantly heals a fixed amount
but starts a passive lockout during which regen is disabled (and `tick()` just
counts the lockout down). `remove()` clears lockout/timers.

- Instant heal (active): `25 HP`
- Passive lockout after active: `40.0 s`
- Passive regen rate: `5.0 HP/s`
- Stationary velocity threshold: `15.0 px/s`
- Still-delay before regen starts: `1.5 s`

### 4.13 EngineBoostModule — boost drive

A forward dash burst: invincible, ramming damage, short cooldown.

- **id:** `&"engine_boost"` · **class:** `EngineBoostModule` · **slot:** `&"engines"` · **type:** active

**Effect:** `apply()` does nothing. `try_activate()` saves `damage_reduction` and
sets it to `1.0` (invincible), locks the boost direction to the ship's facing, sets
`velocity` to that direction × the start speed, sets `engine_boost_active = true`
(so `_handle_thrust()` skips damping/cap), and plays the `flame_boost` animation.
`tick()` eases velocity down from start to end speed over the duration
(`progress²` curve), forces both thrusters into the BOOST state, damages enemies in
the hit radius once each, and ends the boost when time runs out. `_end_boost()`
restores `damage_reduction`, clears `engine_boost_active`, and resets the sprite.
`remove()` ends the boost if active. Immune classes (no boost damage): `BigAsteroid`,
`SmallAsteroid`, `Asteroid`, `RamShip`. Gated while active or on cooldown.

- Boost start speed: `1500.0 px/s`
- Boost end speed: `500.0 px/s`
- Boost duration: `0.55 s`
- Ramming damage per enemy: `45`
- Hit radius: `32.0 px`
- Cooldown: `2.0 s`
- During boost: `damage_reduction = 1.0` (invincible)

### 4.14 PierceModule — penetrating rounds

Bullets pass through multiple enemies.

- **id:** `&"pierce"` · **class:** `PierceModule` · **slot:** `&"weapons"` · **type:** passive

**Effect:** `apply()` sets `player.pierce_module_active = true`; `remove()` sets it
`false`. Weapon behaviours read the flag and assign `Bullet.MAX_PIERCE` (`3`) to each
spawned projectile; each pierce past the first reduces damage by ~45%
(`Bullet.PIERCE_DAMAGE_FACTOR = 0.55`). The pierce count and damage factor live on
`Bullet`, not this module.

- Max pierce: `3` (via `Bullet.MAX_PIERCE`)
- Damage falloff per pierce: ~45% (`Bullet.PIERCE_DAMAGE_FACTOR = 0.55`)
- `try_activate` / `tick`: n/a

### 4.15 ShootingModule — targeting matrix

Faster weapon fire rate.

- **id:** `&"shooting"` · **class:** `ShootingModule` · **slot:** `&"weapons"` · **type:** passive

**Effect:** `apply()` adds `+0.65` to the player's `fire_rate_multiplier` (e.g.
`1.0 → 1.65`); `remove()` subtracts it (floored at `1.0`). `WeaponState` uses
`_cooldown = fire_interval / fire_rate_multiplier`, so a higher multiplier means
shorter cooldowns.

- Fire-rate bonus: `+0.65` (+65%)
- `try_activate` / `tick`: n/a

---

## 5. How to add a new module

1. **Create the script** `global/ship_modules/<name>_module.gd`:

   ```gdscript
   class_name MyNewModule
   extends ShipModuleBase
   ```

2. **Override the methods you need.** At minimum `get_display_name`,
   `get_description`, `get_icon`, and `get_slot`. Then:
   - Passive: implement `apply(player)` to set a flag/multiplier and `remove(player)`
     to undo it. If you need a brand-new flag, declare it on
     `global/entities/player_base.gd` and have the relevant system read it.
   - Active: implement `try_activate(player)` (return `true` only when the input is
     consumed) and `tick(player, delta)` for cooldown/duration. Remember `delta` is
     real-time. Always restore any global state (e.g. `Engine.time_scale`) in
     `remove()` and a `NOTIFICATION_PREDELETE` safety net if you mutate it.

3. **Register the id** in `ShipModuleBase.create()`
   (`global/ship_modules/ship_module_base.gd`) — add a `match` arm mapping the new
   StringName id to `MyNewModule.new()`. This is the only place modules are
   instantiated.

4. **Assign it to a slot** in `ShipModuleState`
   (`global/autoloads/ship_module_state.gd`): add the id to the appropriate list in
   `SLOT_MODULES` (keep `&""` first), matching the slot returned by your module's
   `get_slot()`.

5. **Add data/icon.** Make `get_icon()` `preload` a texture under
   `res://global/assets/sprites/player_menu_ui/ship_menu_ui/module_icons/`, and write
   a clear `get_display_name()` / `get_description()`.

6. **Update the docs.** Per the project rule, after adding or changing a module,
   invoke the `updating-project-docs` skill to refresh this file and any related
   documentation.
