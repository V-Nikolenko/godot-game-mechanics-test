# Light Assault Ship — Standard fighter

**Role:** The baseline shooter. Path-following workhorse that flies in, holds a line, and fires aimed (or forward) shots. Has its own fallback state machine for when no path is attached.
**Fantasy / threat:** Bread-and-butter opposition. Manageable alone; dangerous in formations where overlapping fire pins the player down.

---

## Stats

| Property | Value |
|---|---|
| HP | 60 (from `fighter_config.tres`; the `.tscn` Health node has no explicit max, so config sets it) |
| Damage | 20 contact (`collision_damage`) / 8 per bullet (`bullet_damage`) |
| Speed | 100 (`movement_speed`, AI fallback only); StrafeExit `strafe_speed` 120, Approach `speed` 80 |
| Sprite | `assault.png` |
| Scene | `light_assault_ship.tscn` |
| Config | `fighter_config.tres` |

---

## Behaviour & Movement

- **Movement:** Normally fully delegated to `EnemyPathMover` via `.move()`. If no `EnemyPathMover` is attached, the built-in `AIStateMachine` (`ApproachState` → `StrafeExitState`) drives it instead. `EnemyPathMover` disables this state machine via `process_mode = DISABLED`.
- **Attack:** `AttackController` driving an `AimedAttackPattern` built in `_ready()`. `aim_mode` comes from spawn props (`shoot_forward()`/`shoot_at_player()`) or the config default `"PLAYER"`. PLAYER: `fire_interval` 0.8 s, bullet speed 250, aims at player. FORWARD: faster `fire_interval` 0.3 s, bullet speed 420, fires straight down. `bullet_damage` 8 either way; bullets pooled (size 20).
- **Death / scoring:** Awards `score_value` 25 on kill.

---

## State Graph

```
ApproachState ──reaches hold line (hold_y_offset)──▶ StrafeExitState
   │                                                      │
descend at `speed`                            strafe sideways (random L/R) +
until hold_y                                  downward drift → free at screen edge
```

**Initial state:** `ApproachState` (set on the `AIStateMachine` node). Active ONLY when no `EnemyPathMover` is attached.

### APPROACH (`states/approach_state.gd`)
- On `enter()`, computes `_hold_y = cam.y - viewport.y*0.5 + hold_y_offset`.
- Each physics frame, moves down at `speed` until `global_position.y ≥ _hold_y`, then emits a transition to the strafe state.
- Firing is handled by the ship's `AttackController`, not this state.

| Export | Default | Meaning |
|---|---|---|
| `actor` | (NodePath `../..`) | The LightAssaultShip this state drives. |
| `speed` | `80.0` | Downward approach speed (px/s). |
| `hold_y_offset` | `80.0` | Px below the top edge where it stops descending. |
| `strafe_state` | (NodePath to StrafeExitState) | State to transition to on arrival. |

### STRAFE EXIT (`states/strafe_exit_state.gd`)
- On `enter()`, picks a random horizontal direction (`±1`).
- Each frame, moves `Vector2(_direction * strafe_speed, downward_drift)`; frees itself once past the left/right screen edge (+60 px).

| Export | Default | Meaning |
|---|---|---|
| `actor` | (NodePath `../..`) | The LightAssaultShip this state drives. |
| `strafe_speed` | `120.0` | Horizontal strafe speed (px/s). |
| `downward_drift` | `20.0` | Constant downward drift while strafing (px/s). |

---

## Config exports

| Export | Default | Meaning |
|---|---|---|
| `max_health` | `60` | HP. |
| `collision_damage` | `20` | Contact HitBox damage. |
| `score_value` | `25` | Points on kill. |
| `counts_toward_wave_clear` | `true` | Counts toward wave-clear bonus. |
| `movement_speed` | `100.0` | Used by the AI fallback when no `EnemyPathMover` is present; otherwise irrelevant. |
| `fire_interval` | `0.8` | Seconds between shots in PLAYER mode (FORWARD overrides to 0.3). |
| `bullet_damage` | `8` | Per-bullet damage. |
| `aim_mode` | `"PLAYER"` | `"PLAYER"` (aim at player) or `"FORWARD"` (shoot down). |

(Read the real defaults from `fighter_config.gd` and `fighter_config.tres`.)

---

## Spawn notes

- WaveBuilder method: `b.fighter()` — see `docs/enemy-roster.md`. **Always add `.move()`.**
- Combine with `.shoot_at_player()` / `.shoot_forward()` and formations (`b.v_formation`, `b.diagonal_formation`). Side entries need `.free_after()`.

---

## Files

```
light_assault_ship/
├── ENEMY.md            ← this file
├── light_assault_ship.tscn
├── light_assault_ship.gd
├── fighter_config.gd / .tres
└── states/
    ├── approach_state.gd
    └── strafe_exit_state.gd
```
