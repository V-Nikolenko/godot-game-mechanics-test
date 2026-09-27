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
- **Squad:** `squad` (a `SquadController`) may be set before `add_child`; the drone joins it in
  `_ready()` and reads `role_of(self)` every tick (never cached: the board recomputes on every join
  and leave). Without a squad it is a squad of one and its own LEAD.
  - **LEAD** — CLOSE_IN, then rams. Its BURST opens `squad.attack_window_open`; its REJOIN
    `release_lead()`s (with a mate), so the closest mate leads next and it drops to REAR.
  - **FLANK_LEFT / FLANK_RIGHT** — hold a `formation_slot` 200 px from the player at ±70° off its
    heading (right = clockwise in y-down). Each answers an open window **once** with its own
    WINDUP → the pincer. Side claims keep two attackers off the same sector and offset each aim by a
    hull width toward it.
  - **REAR** — circles on the 260 px ring (0.55 rad/s), evenly spaced by `rear_index`, plus its own
    `phase_offset` (±0.35 rad, from `rng`). Never attacks. The ring angle lives on the board
    (`rear_ring_angle`, advanced by rear 0 only) and is never reset, so a drone that becomes REAR
    later may cross the ring to its slot. In Assault the ring centre is kept inside the corridor.
  - A role change during WINDUP/BURST/OVERSHOOT takes effect after that pass. The board closes the
    window whenever the lead changes (death, hand-over, a closer join), so after a kill that moves
    the lead the flanks wait for the new lead's burst — expected, not a bug.
  - Flocking (separation/alignment/cohesion) + an evade within 90 px of the player, as one nudge
    capped at 0.35 × `max_speed`, in APPROACH / CLOSE_IN / FORM / IDLE / RETURNING.
- **Hub idle (Open Space only)** — a squad-wide patrol handover, on top of the ram cycle above:
  each drone owns an `AnchorIdle` (`global/enemy_ai/anchor_idle.gd`) around an exported
  `patrol_anchor` (`Vector2.INF` = "unset", defaulted to the spawn position in `_start()`; a real
  squad spawner sets the SAME anchor on every member before `add_child`, so they share one ring).
  Assault never builds one — `EngagementBudget.active` alone decides combat-from-spawn there, and
  `start_engaged` is a test-only seam that makes an Open Space drone skip idle too, for every test
  written before this behaviour existed.
  - **IDLE** — a slow ring orbit (`idle_radius` 140 px, `idle_speed` 0.6 rad/s) around
    `patrol_anchor`, angle = `phase_offset + join_index × TAU / squad_size + idle_speed × t`, plus
    the flocking nudge. `SquadController.member_index()` / `member_count()` give the whole-squad
    join order (unlike `rear_index()` / `rear_count()`, which only count REARs).
  - A member that perceives the player (`perceive_radius` 380 px) calls
    `squad.set_engaged(self, true)` and enters **NOTICING**: the light blinks once, it faces the
    player for `notice_time` (0.35 s), then hands over to APPROACH from its *current* velocity — no
    `halt()`, no `boost()`, so the mover's own accel/turn-rate caps bound the handover.
  - Any member in IDLE/RETURNING that sees `squad.is_engaged()` calls `force_notice()` too, so the
    whole squad is out of IDLE within one physics tick of the first perceiver. While any member is
    engaged, every member's `hold_combat` stays true, so nobody returns alone; a member drops its own
    `engaged` flag once it is beyond `lose_radius` (620 px) of the player, and once none are engaged,
    hold_combat clears and every member enters **RETURNING** (`arrive` at `patrol_anchor`) together,
    reaching IDLE once within the ring.

---

## State Graph

```
            ┌─ LEAD ──▶ CLOSE_IN ──on the 200 px ring (or 2.5 s)──┐
APPROACH ≤360 px                                                  ▼
            └─ other ─▶ FORM ──FLANK: window open, not answered──▶ WINDUP ──0.4 s──▶ BURST
                         ▲  (REAR never leaves FORM to attack)       ▲               │ boost ends
                         │                                           │ passes_left,  ▼
   >460 px back to APPROACH from CLOSE_IN / FORM / REJOIN            │ same role   OVERSHOOT (0.8 s curve)
                         └──── REJOIN (→ CLOSE_IN if LEAD) ◀── no passes left / role changed

 any phase but BURST ──budget expired (Assault only)──▶ DISENGAGE ──outside world rect──▶ freed
 (a REAR in APPROACH/FORM expires at rear_engage_seconds; everyone else at engage_seconds)

 Open Space only, cold start:
 IDLE ──perceives (or a squad mate does)──▶ NOTICING ──notice_time──▶ APPROACH (current velocity)
   ▲                                                                        │
   └──arrives at patrol_anchor────────────────── RETURNING ◀──beyond lose_radius, nobody engaged──┘
      (any phase but BURST)
```

Phases are an `enum` in `swarm_drone_brain.gd` (no `states/` folder); every transition goes through
`enter_phase()` and emits `phase_changed(new_phase)`.

- **APPROACH** — `Steering.corkscrew` at the player, phase drawn from `rng`.
- **CLOSE_IN** (LEAD only) — `Steering.spiral` on a ring shrinking at 120 px/s to `flank_distance` 200 px, anchor moving 130 px/s.
- **WINDUP** — hold at the stopping point, face the prediction `clamp(dist / 480, 0.4, 0.8)` s ahead
  (re-evaluated every tick, locked on the last). Entered only if the Assault budget has ≥ 1.29 s left,
  so a burst never straddles the exit.
- **BURST** — `mover.boost()` at 480 px/s for 0.45 s, armed.
- **OVERSHOOT** — each tick `Steering.turn_toward(current velocity, player, 2.4 rad/s)` × 220: a real
  curve (~76° over 0.8 s), never stopping. Then one more WINDUP (`second_passes` 1), then REJOIN.
- **FORM** — by role: a FLANK holds its slot (and answers the window), a REAR circles the ring.
  A LEAD in FORM goes to CLOSE_IN; a non-LEAD in CLOSE_IN goes to FORM.
- **REJOIN** — resets the passes; after a pass made as LEAD by a drone that still leads, hands the
  lead on (only with a mate; a sole member closes its own window instead). Then CLOSE_IN (LEAD) or
  FORM.
- **DISENGAGE** (Assault) — after `engage_seconds` 5.5: release the corridor, seek 64 px past the
  nearest edge of `projectile_world_rect()`, free once strictly outside it.
- **Rails** — an `EnemyPathMover` suspends the brain; the profile is armed and the light red.
- **IDLE** (Open Space only) — `Steering.orbit` around `patrol_anchor` at `idle_radius` 140 px.
- **NOTICING** — blink the light once, `face_toward` the player for `notice_time` 0.35 s.
- **RETURNING** — `mover.arrive` at `patrol_anchor`; reaches IDLE within the ring, or NOTICING again
  if the player re-enters `perceive_radius` first.

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
| `rear_orbit_radius` / `rear_orbit_speed` | 260 / 0.55 | REAR ring; APPROACH hands over at radius + 100, falls back beyond radius + 200 |
| `flank_distance` / `flank_angle_deg` | 200 / 70 | FLANK slots; also the LEAD's CLOSE_IN ring |
| `separation_radius` / `flock_nudge_cap` / `evade_radius` | 30 / 0.35 / 90 | the nudge (cap 0 = off) |
| `rear_engage_seconds` | 5.5 | Assault: a REAR leaves after this; ≤ `engage_seconds` (t15 lever) |
| `perceive_radius` / `lose_radius` / `notice_time` | 380 / 620 / 0.35 | Open Space idle: enter / drop combat, and the NOTICING beat |
| `idle_radius` / `idle_speed` | 140 / 0.6 | Open Space patrol ring radius (px) and angular speed (rad/s) |

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
