# Sniper Shot — Design Spec

**Date:** 2026-05-22
**Author:** brainstorming session
**Status:** Approved

---

## 1. Purpose

Add a new chargeable main weapon — the **Sniper Shot** — that replaces the existing `piercing` weapon. The shot pierces every regular enemy with no damage decay or pierce-count limit, but is stopped by asteroids and ram-ships. Charging the shot reduces aim spread from a wide cone down to a single perfectly straight line over 2 seconds.

This sits as a standard entry in the weapon-select cycle, alongside the default gun, spread, gatling, mining laser, and long-range modes.

---

## 2. User-facing behavior

| Step | What the player sees |
|---|---|
| Press J (shoot) | 5 red lines appear from the muzzle: 2 outer cone borders (±25°) plus 3 inner lines at random angles inside the cone. |
| Hold J | All 5 lines narrow linearly toward the ship's forward axis. After 2 s, all overlap into a single straight line. |
| Release J | A projectile is fired along **one of the 3 inner lines**, chosen uniformly at random. The cone-border lines are aim guides only. |
| Bullet flight | Passes through every regular enemy at full damage. Stops on impact with an asteroid or ram-ship, dealing no damage to them. |

If the player switches weapons, dies, or overheats during the charge, the charge is cancelled (visualizer is destroyed, no projectile fires).

---

## 3. Balance numbers

| Property | Value |
|---|---|
| Damage | 40 |
| Heat per shot | 6.0 |
| After-fire cooldown | 0.5 s |
| Projectile speed | 800 px/s |
| Pierce limit | none (unlimited) |
| Pierce damage decay | none (full damage every pierce) |
| Charge time to full aim | 2.0 s |
| Initial cone half-width | 25° (so 50° total) |

---

## 4. Architecture

Three new things slot into the existing weapon framework:

- `SniperBehavior` — implements the press / hold / release lifecycle (existing behaviors only handle one-shot fire on press)
- `SniperAimVisualizer` — Node2D that draws the 5 red lines and recomputes their angles each frame from the converging charge
- `SniperBullet` — Bullet variant with `unlimited_pierce` and `no_damage_decay` flags, plus a group check that despawns on asteroid / ram-ship contact without dealing damage

Plus:
- New enum value `WeaponModeResource.Behavior.SNIPER`
- New resource file `assault/scenes/player/weapons/modes/sniper_shot.tres`
- A small dispatch change in `WeaponState._physics_process` to handle the SNIPER lifecycle
- Existing `piercing.tres` deleted, and `UpgradeState.ALL_IDS` swaps `&"piercing"` for `&"sniper_shot"`

The existing `PierceModule` is untouched. Sniper Shot pierces by its own rules (the module's `pierce_module_active` flag is ignored for sniper bullets).

---

## 5. Aim visualization mechanics

### Charge start

On `Input.is_action_just_pressed("shoot")` while sniper mode is active:

1. Sample 3 random angles uniformly from `[-25°, +25°]`. These are **fixed for the duration of the charge** — predictable enough that the player can aim around obstacles.
2. Spawn a `SniperAimVisualizer` instance, set its initial angles to the 5 line angles (the 2 borders ±25° plus the 3 sampled inner angles), and add it as a child of the active muzzle.
3. Reset the charge timer to 0.
4. Lock to the muzzle that was active at press time. Don't alternate muzzles mid-charge.

### Per-frame update (while held)

```
t = clamp(charge_time / 2.0, 0.0, 1.0)
for each line: current_angle = initial_angle × (1.0 - t)
```

At `t = 1.0`, every line's angle is 0, so all five overlap into a single straight line pointing forward.

Each line is drawn from the muzzle position, extending 600 px in its current direction. Color is solid red, ~1 px wide, ~70% alpha. The visualizer rotates with the ship (it's a child of the muzzle).

### Release

On `Input.is_action_just_released("shoot")`:

1. Pick uniformly from the 3 inner-line current angles.
2. Spawn a `SniperBullet` at the muzzle's global position, with rotation `actor.rotation + chosen_inner_angle`.
3. Destroy the visualizer.
4. Apply the 0.5 s cooldown so the player can't immediately re-charge.

---

## 6. SniperBullet

Extends the existing `Bullet` scene/script with two new exported flags:

```
@export var unlimited_pierce: bool = false
@export var no_damage_decay: bool = false
```

For sniper bullets, both are `true`. The existing `_on_hit_box_area_entered` is amended:

- If the hit `area.get_parent()` is in group `"asteroids"` or `"ram_ships"` (or equivalent type check), emit `expired` and `queue_free()` immediately, without applying damage. (The HitBox.damage = 0 trick is the cleanest implementation — set damage to 0 before the call_deferred frees the bullet, so the area_entered fires for that one frame with no damage.)
- Otherwise, if `unlimited_pierce` is `true`, skip the `pierces_remaining` decrement and the damage-decay multiplier — the bullet continues at full damage.
- If `unlimited_pierce` is `false` (regular bullet), original behavior applies.

The 3 enemy groups to add to or check for:
- `"asteroids"` — already present on big_asteroid / small_asteroid
- `"ram_ships"` — needs to be added to `ram_ship.tscn` if not already present

(Verify these group names exist in the implementation phase.)

---

## 7. WeaponState integration

The current `_physics_process` has:

```gdscript
if mode.behavior == BEAM:
    # beam handling
else:
    if Input.is_action_pressed("shoot"):
        _try_fire_once()
```

New SNIPER branch (added before the else):

```gdscript
elif mode.behavior == SNIPER:
    var sniper: SniperBehavior = _behaviors[SNIPER]
    if Input.is_action_just_pressed("shoot") and actor.can_attack and _cooldown <= 0.0:
        _gun_index = (_gun_index + 1) % weapon_muzzles.size()
        sniper.start_charge(self, mode, weapon_muzzles[_gun_index])
    if sniper.is_charging():
        sniper.tick(delta)
    if Input.is_action_just_released("shoot") and sniper.is_charging():
        sniper.fire_from_charge(self, mode)
        _cooldown = mode.fire_interval / max(actor.fire_rate_multiplier, 0.01)
```

`SniperBehavior` owns its charge state internally (timer, visualizer reference, sampled angles, muzzle ref). It exposes:
- `start_charge(state, mode, muzzle)` — spawn visualizer, sample angles, start timer
- `is_charging() -> bool` — true between start_charge and fire_from_charge / cancel
- `tick(delta)` — advance timer, update visualizer line angles
- `fire_from_charge(state, mode)` — spawn bullet, destroy visualizer, clear state
- `cancel()` — destroy visualizer, clear state (no shot)

`_cycle()` and `select_weapon()` in WeaponState call `sniper.cancel()` alongside the existing `beam.release(self)`.

---

## 8. Edge cases

| Situation | Behavior |
|---|---|
| Player switches weapon mid-charge | `sniper.cancel()` — visualizer freed, no shot, no cooldown applied |
| Player dies mid-charge | Visualizer is a child of the muzzle, which is a child of the ship — freed automatically when the ship is freed. State self-clears on next `tick()` no-op. |
| Heat reaches limit mid-charge (`can_attack` flips false) | Treat as cancel: destroy visualizer, no shot |
| Pause menu opens mid-charge | Tree pauses, so `_physics_process` stops. Charge timer pauses with it. On resume, charge continues from where it was. |
| Player holds J for 10 s (way past 2 s) | Lines stay overlapped at perfect aim; release fires at perfect aim |
| Player taps J quickly (< 1 frame) | Press + release on same frame — visualizer briefly spawned, immediately fires along one of 3 random initial angles. This is acceptable — the spread cone is large enough that the shot is intentionally inaccurate when not charged. |

---

## 9. Files to create / modify / delete

**Create:**
- `assault/scenes/player/weapons/behaviors/sniper_behavior.gd`
- `assault/scenes/player/weapons/visualizers/sniper_aim_visualizer.gd`
- `assault/scenes/projectiles/bullets/sniper_bullet.tscn` (or just reuse bullet.tscn with new flag values via the resource)
- `assault/scenes/player/weapons/modes/sniper_shot.tres`

**Modify:**
- `assault/scenes/player/weapons/weapon_mode.gd` — add `SNIPER` enum value
- `assault/scenes/player/states/weapon_state.gd` — register SniperBehavior; add SNIPER branch in `_physics_process`; call `sniper.cancel()` in `_cycle()` and `select_weapon()`
- `assault/scenes/projectiles/bullets/bullet.gd` — add `unlimited_pierce` and `no_damage_decay` flags; amend `_on_hit_box_area_entered`; add asteroid / ram-ship despawn check
- `global/autoloads/upgrade_state.gd` — replace `&"piercing"` with `&"sniper_shot"` in `ALL_IDS`
- `assault/scenes/enemies/ram_ship/ram_ship.gd` (or `.tscn`) — add to `"ram_ships"` group if not already present

**Delete:**
- `assault/scenes/player/weapons/modes/piercing.tres`

---

## 10. Testing checklist

1. Press J in sniper mode → 5 red lines appear (1 left border, 1 right border, 3 inner)
2. Hold 1 s → lines roughly half-converged
3. Hold ≥ 2 s → all 5 lines overlap into one straight line
4. Release → projectile fires along one of the 3 inner-line angles
5. Bullet passes through fighter → drone → sniper without damage loss
6. Bullet hits big asteroid → stops, asteroid takes no damage
7. Bullet hits ram-ship → stops, ram-ship takes no damage
8. Switch weapon mid-charge (cycle key) → lines vanish, no shot fired
9. Take damage to 0 HP mid-charge → no crash, lines vanish cleanly
10. Overheat (≥ heat limit) → can_attack flips; verify charge cancels and no shot is fired
11. Cooldown: after firing, pressing J again within 0.5 s does nothing
