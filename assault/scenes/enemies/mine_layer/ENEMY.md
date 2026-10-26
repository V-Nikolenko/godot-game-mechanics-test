# Mine Layer — area-denial minelayer

**Role:** Flies sideways across an encounter laying mines from its stern, so the player has to remember where the unsafe regions are.
**Fantasy / threat:** A slow, easy-to-hit hull whose threat is what it leaves behind. Enemies steer round its mines too (Phase 6 hazard perception).

> **Build state (Phase 7, t10: shell).** Built: the scene, config, per-variant persistent pools, `drop_mine()`, the rail fallback, the
> APPROACH / DISENGAGE shell and the `WaveBuilder` entry. **Not built yet:** the laying pass (LAY / BREAK_OFF / REPOSITION), the Open Space
> idle, the live-mine cap, the hull art, the wake trail, the hub and level 1 placement. Plan: `docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md` §2.11.

---

## Stats

| Property | Value |
|---|---|
| HP | 140 (`mine_layer_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | 25 contact (`ContactHitBox`, COLLISION); mines deal their own blast |
| Speed | `max_speed` 240, `acceleration` 420, `max_turn_rate` 2.4, `lay_speed` 170, `exit_speed` 300 |
| Body | one `CircleShape2D` r 40 shared by the body, `HurtBox` and `ContactHitBox` |
| Sprite | placeholder: `bomber.png` scaled 0.92, nose-down (the scene rotates the `Sprite2D` by π); replaced by the art task |
| Scene / config | `mine_layer.tscn` / `mine_layer_config.tres` (flat `MineLayerConfig`) |
| Hazards | `hazard_avoidance` 0.8, `hazard_margin` 24, `hazard_resistance` 0.2; leaves a medium wreck 35 % of the time |

---

## Behaviour

- **Brain:** `MineLayerBrain` (`Phase { APPROACH, LAY, BREAK_OFF, REPOSITION, DISENGAGE, IDLE, NOTICING, RETURNING }`, append-only,
  `enter_phase()` seam, `start_engaged` seam). The shell plays APPROACH (seek the player at `max_speed`) and DISENGAGE.
- **DISENGAGE** (Assault, when `engage_seconds` 9 runs out): `mover.release_constraint()` and `mover.max_speed = exit_speed`, as the Bomber does, so the corridor
  never holds an exiting layer in. With no planned pass it leaves along its heading on entry: the velocity direction, else the facing. Freed outside the world rect.
- `accepts_tow()` is false in LAY.

## Mines

- One root `BulletPool` per variant with a weight above 0: `ProximityPool` (`max_live_mines + 2` = 20), `ChainPool` 6, `PulsePool` 5, `HomingPool` 5; `DriftingPool` and
  `EmpPool` only if `w_drifting` / `w_emp` are raised. Each is `persist_after_owner_death`, so mines laid before the layer dies outlive it. Sizes equal
  `EnemyMineScenes.pool_size_for(variant, config)` (gated).
- `MineLayer.drop_mine(variant, rest_point) -> EnemyMine`: acquires at the `Dispenser` (local (0, −38), the stern) and falls back to PROXIMITY when the pool is absent
  or exhausted. It sets **only** `arm_delay` (0.5), `eject_time` (0.3) and the life: Assault `assault_mine_life` 9.0; Open Space `open_space_mine_life` 0 (never fizzles)
  with a `ProjectileLifetime` backstop of `open_space_mine_backstop` 240 s. Trigger, warning and blast numbers are the variant scene's (a pulse mine keeps its blast of 8).
  The eject is launched at `2d / (eject_time − one tick)` so the mine comes to rest on the point (within 4 px).
- `MineLayer._ready()` joins group `enemies` (`BaseEnemy` does not; placed `ALL` mines look for that group).
- **Rail fallback:** while an `EnemyPathMover` owns it, a PROXIMITY mine drops at the dispenser every `rail_mine_interval` 1.6 s (speed 0, Assault life).

## Gates

`tests/integration/test_mine_layer.gd`; the Mine Layer is in the rosters of `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`,
`test_enemy_hurtbox_geometry.gd` and `test_wreck.gd` (`_SHIP_SCENES`); `test_config_instance_isolation.gd` finds it by its directory sweep;
`test_enemy_dual_mode.gd` has the APPROACH case.

Spawn with `b.mine_layer().at(x, y)`. No Mine Layer (or anything else dropping persistent mines) goes in an `ENEMIES_CLEARED` section.
