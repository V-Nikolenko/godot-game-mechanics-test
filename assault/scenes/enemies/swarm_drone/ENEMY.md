# Swarm Drone — small explosive rammer

**Role:** Cheap contact drone. Corkscrews in, spirals close, winds up visibly, rams where the player
is *going*, and on a miss curves round for exactly one more pass. Replaces the Kamikaze Drone and the
Open Space PatrolDrone (later tasks of phase 2 do the swap; nothing spawns it in a level yet).
**Fantasy / threat:** A hornet that circles, tenses (yellow light), then lunges (red light) — dodge
the lunge and it swings back once for a second try. Harmless to touch unless its red light is on.

---

## Stats

| Property | Value |
|---|---|
| HP | 30 |
| Damage | 30 contact (only while armed) + 15 blast within 48 px (on contact, or when shot while armed) |
| Speed | 220 cruise / 480 burst / 320 exit (Assault) |
| Sprite | `assault/assets/sprites/enemies/drones.png`, cell `Rect2(2, 2, 38, 38)` — placeholder until its own sprite |
| Scene | `swarm_drone.tscn` |
| Config | `swarm_drone_config.tres` |

---

## Behaviour & Movement

- **Movement:** brain/mover architecture. `SwarmDroneBrain` requests, the sibling `EnemyMover`
  (`constraint_mode = AUTO`: the Assault corridor applies, Open Space has none) moves, through
  `BaseEnemy`'s shared tick. `swarm_drone.gd` defines no `_physics_process`; it copies the config onto
  the health, contact hitbox, contact profile, mover and brain in `_ready()` (the `.tres` wins).
- **Attack:** no projectiles. An EXPLOSIVE `ContactProfile`: the `ContactHitBox` is live only while
  armed (BURST, or permanently under a rail). A touch deals `collision_damage`, detonates a
  `ContactBlast` (48 px, 15 damage) and kills the drone. Shot down while armed, it also detonates.
- **Light:** `StateLight` — yellow (CHARGING) in WINDUP, red (ARMED) in BURST and on rails, off
  otherwise.
- **Death / scoring:** 10 points. A contact death is scored as a kill (`was_killed`), like the
  Kamikaze. Leaving the arena in Assault is an escape.
- **Squad:** `squad` (a `SquadController`) may be set before `add_child`; the drone joins it and
  calls `claim_side` / `release_side` / `release_lead` / `leave`, but still attacks as a LEAD — role
  behaviour is a later task.

---

## State Graph

```
APPROACH ──≤360 px──▶ CLOSE_IN ──on the 200 px ring (or 2.5 s)──▶ WINDUP ──0.4 s──▶ BURST
   ▲                     ▲  │ >460 px back to APPROACH                ▲               │ boost ends
   │                     │                                            │ passes_left   ▼
   └──── >460 px ─── REJOIN ◀────────── no passes left ─────────── OVERSHOOT (0.8 s curve)

 any phase but BURST ──budget expired (Assault only)──▶ DISENGAGE ──outside world rect──▶ freed
```

Phases are an `enum` in `swarm_drone_brain.gd` (no `states/` folder); every transition goes through
`enter_phase()` and emits `phase_changed(new_phase)`.

- **APPROACH** — `Steering.corkscrew` at the player, phase drawn from `rng`.
- **CLOSE_IN** — `Steering.spiral` on a ring shrinking at 120 px/s to 200 px, anchor moving 130 px/s.
- **WINDUP** — hold at the stopping point, face the prediction `clamp(dist / 480, 0.4, 0.8)` s ahead
  (re-evaluated every tick, locked on the last). Entered only if the Assault budget has ≥ 1.29 s left,
  so a burst never straddles the exit.
- **BURST** — `mover.boost()` at 480 px/s for 0.45 s, armed.
- **OVERSHOOT** — each tick `Steering.turn_toward(current velocity, player, 2.4 rad/s)` × 220: a real
  curve (~76° over 0.8 s), never stopping. Then one more WINDUP (`second_passes` 1), then REJOIN.
- **REJOIN** — resets the passes, hands the lead on (only with a mate), back to CLOSE_IN.
- **DISENGAGE** (Assault) — after `engage_seconds` 5.5: release the corridor, seek 64 px past the
  nearest edge of `projectile_world_rect()`, free once strictly outside it.
- **Rails** — an `EnemyPathMover` suspends the brain; the profile is armed and the light red.

---

## Config exports (`swarm_drone_config.gd` / `.tres`)

| Export | Value | Meaning |
|---|---|---|
| `max_health` / `collision_damage` / `score_value` | 30 / 30 / 10 | Kamikaze parity |
| `max_speed` | 220 | cruise and overshoot speed (px/s) |
| `acceleration` / `braking` | 600 / 900 | mover limits (px/s²); braking high enough for the overshoot to curve ≥ 60° |
| `max_turn_rate` | 10 | sprite turn cap (rad/s) |
| `corkscrew_amplitude` / `corkscrew_frequency` | 120 px/s / 0.6 Hz | approach swing ≈ 32 px |
| `windup_seconds` | 0.4 | telegraph |
| `burst_speed` / `burst_seconds` | 480 / 0.45 | the ram |
| `lead_time_min` / `lead_time_max` | 0.4 / 0.8 | prediction clamp |
| `overshoot_seconds` / `overshoot_turn_rate` / `second_passes` | 0.8 / 2.4 / 1 | the miss curve |
| `blast_radius` / `blast_damage` | 48 / 15 | EXPLOSIVE blast |
| `engage_seconds` / `exit_speed` | 5.5 / 320 | Assault exit |

---

## Spawn notes

- Not spawned by any level yet, and no `WaveBuilder` method yet (phase 2 later tasks). Do not attach
  `.move()` unless it is meant to fly a rail (then it rams on contact like the Kamikaze).

## Tests

`tests/integration/test_swarm_drone.gd` (dual-mode spec), plus the contact-damage, contact-geometry,
hurtbox-geometry, config-isolation, sprite-transparency, single-writer and deadline gates.

---

## Files

```
swarm_drone/
├── ENEMY.md                  ← this file
├── swarm_drone.tscn
├── swarm_drone.gd            (SwarmDrone extends BaseEnemy)
├── swarm_drone_brain.gd      (SwarmDroneBrain extends EnemyBrain)
└── swarm_drone_config.gd / .tres
```
