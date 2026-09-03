# Assault Combat — Development Plan

> **Goal:** Implement the full Assault mission combat system per the Combat Design (Assault) GDD —
> enemy units, wave spawning, Phase 2 emplacements, and the Assault Carrier boss.

**Architecture:** Enemy AI uses the existing StateMachine/State pattern. A `ScrollController` drives
camera movement and broadcasts scroll distance; `WaveManager` listens and spawns scripted waves.
All enemy ships reuse `light_assault_ship.png` with `modulate` / `scale` variation.

**Tech Stack:** Godot 4.x · GDScript · existing Health / HurtBox / HitBox / StateMachine components.

**Progress legend:** `[ ]` not started · `[x]` done · `[~]` in progress

---

## File Map

### New files

| File | Responsibility |
|---|---|
| `assault/scenes/enemies/base_enemy.gd` | Shared health / death logic for all enemy types |
| `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd` | Directional projectile fired by enemies |
| `assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn` | Enemy bullet scene |
| `assault/scenes/systems/scroll_controller/scroll_controller.gd` | Moves Camera2D upward, tracks scroll distance |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | Spawns scripted waves on scroll-distance triggers |
| `assault/scenes/enemies/light_assault_ship/states/approach_state.gd` | Fighter flies down to hold-Y, fires bursts |
| `assault/scenes/enemies/light_assault_ship/states/strafe_exit_state.gd` | Fighter breaks left/right and exits screen |
| `assault/scenes/enemies/kamikaze_drone/kamikaze_drone.gd` | Locks player pos at spawn, flies at it |
| `assault/scenes/enemies/kamikaze_drone/kamikaze_drone.tscn` | Kamikaze drone scene (red tint, 0.7× scale) |
| `assault/scenes/enemies/sniper_skimmer/sniper_skimmer.gd` | Lateral pass, fires once toward player at midpoint |
| `assault/scenes/enemies/sniper_skimmer/sniper_skimmer.tscn` | Sniper skimmer scene (cyan tint) |
| `assault/scenes/enemies/gunship/gunship.gd` | Holds position, tracks + fires, retreats at 30 % HP |
| `assault/scenes/enemies/gunship/gunship.tscn` | Gunship scene (gold tint, 1.5× scale) |
| `assault/scenes/enemies/bomber/bomb.gd` | Falls, detonates on fuse timer |
| `assault/scenes/enemies/bomber/bomb.tscn` | Bomb scene |
| `assault/scenes/enemies/bomber/bomber.gd` | Slow cross-screen pass, drops bombs |
| `assault/scenes/enemies/bomber/bomber.tscn` | Bomber scene (grey tint, 1.8× scale) |
| `assault/scenes/emplacements/gun_turret/gun_turret.gd` | Rotates to track player, fires bursts |
| `assault/scenes/emplacements/gun_turret/gun_turret.tscn` | Gun turret scene |
| `assault/scenes/emplacements/missile_battery/missile_battery.gd` | Fires homing missiles on timer, drops ammo on death |
| `assault/scenes/emplacements/missile_battery/missile_battery.tscn` | Missile battery scene |
| `assault/scenes/emplacements/energy_barrier/energy_barrier.gd` | Blocks player movement, destroyed by laser / missile only |
| `assault/scenes/emplacements/energy_barrier/energy_barrier.tscn` | Energy barrier scene |
| `assault/scenes/emplacements/heavy_cannon/heavy_cannon.gd` | Fixed direction, timed large slow shots |
| `assault/scenes/emplacements/heavy_cannon/heavy_cannon.tscn` | Heavy cannon scene |
| `assault/player/states/charged_laser_state.gd` | Charge-and-release beam weapon |
| `assault/scenes/enemies/boss_carrier/boss_carrier.gd` | Multi-component boss, global HP escalation |
| `assault/scenes/enemies/boss_carrier/boss_carrier.tscn` | Boss carrier scene |
| `assault/scenes/enemies/boss_carrier/components/launch_bay.gd` | Periodically spawns fighters |
| `assault/scenes/enemies/boss_carrier/components/missile_battery_boss.gd` | Boss-side homing missiles |
| `assault/scenes/enemies/boss_carrier/components/broadside_cannon.gd` | Wide horizontal energy blasts |
| `assault/scenes/enemies/boss_carrier/components/carrier_core.gd` | Final target, unlocks after conditions met |

### Files to modify

| File | Change |
|---|---|
| `assault/scenes/enemies/light_assault_ship/light_assault_ship.gd` | Extend BaseEnemy, add StateMachine AI |
| `assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn` | Add StateMachine + AI state nodes |
| `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd` | Support custom direction via `set_direction()` |
| `assault/scenes/levels/level_1.tscn` | Add Camera2D, ScrollController, WaveManager |

---

## Phase 1 — Foundation

### Task 1 · Base Enemy Class
- [x] Create `assault/scenes/enemies/base_enemy.gd`
- [x] Refactor `light_assault_ship.gd` → `extends BaseEnemy`
- [x] Commit `feat: add BaseEnemy shared class`

### Task 2 · Enemy Bullet
- [x] Create `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd` with `set_direction()`
- [x] Create `assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn`
- [x] Commit `feat: add EnemyBullet directional projectile`

### Task 3 · Scroll Controller
- [x] Create `assault/scenes/systems/scroll_controller/scroll_controller.gd`
- [x] Commit `feat: add ScrollController`

### Task 4 · Wave Manager
- [x] Create `assault/scenes/systems/wave_manager/wave_manager.gd`
- [x] Commit `feat: add WaveManager`

### Task 5 · Fighter AI + Full Phase 1 Wave Design
- [x] Create `approach_state.gd` — fly to hold-Y firing bursts
- [x] Create `strafe_exit_state.gd` — break and exit screen
- [x] Update `light_assault_ship.tscn` — add StateMachine + states
- [x] Add Camera2D + ScrollController + WaveManager to `level_1.tscn`
- [x] Extend WaveManager — `spawn_edge`, `on_spawned` callback, scroll-speed override
- [x] Rewrite `level_1_waves.gd` — 10 waves covering all GDD Phase 1 types
  - Wave 1: V formation (5 fighters)
  - Wave 2: Kamikaze surprise cluster (4 drones)
  - Wave 3: Suppression (Gunship + 4 fighters)
  - Wave 4: Diagonal line (5 fighters)
  - Wave 5: Sniper pass (2 skimmers opposite sides + 3 fighters)
  - Wave 6: Bomber pass + covering fire (3 fighters)
  - Wave 7: Pincer 3+3 + kamikaze center (3 drones)
  - Wave 8: Dual suppression (2 gunships + 5 fighters)
  - Wave 9: Asymmetric pincer (2 bombers opposite + 3 fighters + 2 drones)
  - Wave 10: Elite Encounter — scroll 50%, elite Gunship (500 HP) + 3 escort; scroll resumes on death
- [x] Commit `feat: full GDD Phase 1 wave design`

---

## Phase 2 — Light Units

### Task 6 · Kamikaze Drone
- [x] Create `kamikaze_drone.gd` — lock-on-spawn, accelerate to target position
- [x] Create `kamikaze_drone.tscn` — red modulate, 0.7× scale
- [x] Commit `feat: add Kamikaze Drone`

### Task 7 · Sniper Skimmer
- [x] Create `sniper_skimmer.gd` — lateral pass, fire once at midpoint
- [x] Create `sniper_skimmer.tscn` — cyan modulate
- [x] Commit `feat: add Sniper Skimmer`

---

## Phase 3 — Medium Units

### Task 8 · Gunship
- [x] Create `gunship.gd` — enter, hold position, track + fire, retreat at 30 % HP
- [x] Create `gunship.tscn` — gold modulate, 1.5× scale
- [ ] Commit `feat: add Gunship`

### Task 9 · Bomber + Bomb
- [x] Create `bomb.gd` — falls, area-damage on fuse expiry
- [x] Create `bomb.tscn`
- [x] Create `bomber.gd` — cross screen at low speed, drop bombs at interval
- [x] Create `bomber.tscn` — grey modulate, 1.8× scale
- [ ] Commit `feat: add Bomber and Bomb`

---

## Phase 4 — Phase 2 Emplacements

### Task 10 · Gun Turret
- [ ] Create `gun_turret.gd` — rotates to track, burst-fires
- [ ] Create `gun_turret.tscn`
- [ ] Commit `feat: add Gun Turret`

### Task 11 · Missile Battery
- [ ] Create `missile_battery.gd` — homing missile on timer, ammo drop on death
- [ ] Create `missile_battery.tscn`
- [ ] Commit `feat: add Missile Battery`

### Task 12 · Energy Barrier + Charged Laser
- [ ] Create `energy_barrier.gd` — blocks movement, only laser/missile damage accepted
- [ ] Create `energy_barrier.tscn`
- [ ] Create `charged_laser_state.gd` — charge-and-release beam, pierces barrier
- [ ] Commit `feat: add Energy Barrier and Charged Laser`

### Task 13 · Heavy Cannon
- [ ] Create `heavy_cannon.gd` — fixed direction, timed large projectile
- [ ] Create `heavy_cannon.tscn`
- [ ] Commit `feat: add Heavy Cannon`

---

## Phase 5 — Boss

### Task 14 · Assault Carrier
- [ ] Create `boss_carrier.gd` — global HP pool + 4-threshold escalation system
- [ ] Create `launch_bay.gd` — spawns fighters periodically; rate accelerates with carrier damage
- [ ] Create `missile_battery_boss.gd` — homing missiles on timer (x2 instances)
- [ ] Create `broadside_cannon.gd` — wide horizontal energy bands on timer
- [ ] Create `carrier_core.gd` — exposed when Launch Bay + 1 other component destroyed
- [ ] Create `boss_carrier.tscn` — full scene wiring all components
- [ ] Commit `feat: add Assault Carrier boss`

---

## Deferred

- **Electronic Warfare Ship** — requires player shield system (not yet in scope)

---

## Progress Tracker

| # | Task | Status |
|---|---|---|
| 1 | Base Enemy Class | `[x]` |
| 2 | Enemy Bullet | `[x]` |
| 3 | Scroll Controller | `[x]` |
| 4 | Wave Manager | `[x]` |
| 5 | Fighter AI | `[x]` |
| 6 | Kamikaze Drone | `[x]` |
| 7 | Sniper Skimmer | `[x]` |
| 8 | Gunship | `[x]` |
| 9 | Bomber + Bomb | `[x]` |
| 10 | Gun Turret | `[ ]` |
| 11 | Missile Battery | `[ ]` |
| 12 | Energy Barrier + Charged Laser | `[ ]` |
| 13 | Heavy Cannon | `[ ]` |
| 14 | Boss — Assault Carrier | `[ ]` |
