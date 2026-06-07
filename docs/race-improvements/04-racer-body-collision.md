# Step 04 — Racer Body Collision Damage

**Priority:** High — gives physical collisions meaning; reinforces lane-based play  
**Effort:** Medium — new collision check system added to an existing file  
**File:** `assault/scenes/race/race_level_config.gd`

---

## Problem

All AI racers use `global_position = Vector2(x, y)` direct assignment every frame. Godot's `CharacterBody2D` collision response (`move_and_slide`) never runs between racers. Ships freely overlap with zero consequence.

The player uses `move_and_slide()` — so the `StaticBody2D` walls on the dash panels DO block the player. But no racer-vs-racer body physics exist at all.

Result: you can fly directly into Fang or Bogomol and nothing happens.

---

## Design

- Every physics frame, check all unique ship pairs (player + all AI racers).
- If any pair is closer than `COLLISION_RADIUS` px (sum of two ship radii ≈ 36 px), both ships:
  1. Take a small bump damage
  2. Are pushed apart laterally
- A **per-pair cooldown** prevents per-frame damage spam.
- Bump damage is small per hit (8–12 HP) but meaningful over repeated contact.

This matches the existing pattern used by `mine.gd`, `obstacle.gd`, and the lunge/dash scan — geometric proximity poll, direct `HurtBox.received_damage.emit()`, manual cooldown dictionary.

---

## Implementation

Add to `assault/scenes/race/race_level_config.gd`:

### New constants / vars

```gdscript
const BUMP_RADIUS: float = 36.0        ## px — sum of two ship radii (18 + 18)
const BUMP_DAMAGE: int = 10            ## HP per bump event
const BUMP_COOLDOWN: float = 0.8       ## seconds between re-hits for the same pair
const BUMP_PUSH_AI: float = 50.0       ## how far to nudge an AI racer's desired_x
const BUMP_PUSH_PLAYER: float = 140.0  ## velocity.x nudge for the player

var _bump_cds: Dictionary = {}         ## String key → float (seconds remaining)
```

### New helper: pair key

```gdscript
func _bump_key(a: Node2D, b: Node2D) -> String:
    var id_a := a.get_instance_id()
    var id_b := b.get_instance_id()
    ## Always smaller id first so a→b and b→a produce the same key
    return str(mini(id_a, id_b)) + "_" + str(maxi(id_a, id_b))
```

**Important:** GDScript Arrays use reference equality as Dictionary keys, so `[a_id, b_id]` would never match on lookup. Always use a String key as shown above.

### New method: `_check_racer_collisions(delta)`

```gdscript
func _check_racer_collisions(delta: float) -> void:
    ## Tick down and remove expired cooldowns
    for key in _bump_cds.keys():
        _bump_cds[key] -= delta
    for key in _bump_cds.keys().filter(func(k): return _bump_cds[k] <= 0.0):
        _bump_cds.erase(key)

    ## Collect all ships: player first, then AI racers
    var ships: Array[Node2D] = []
    for n in get_tree().get_nodes_in_group("player"):
        var s := n as Node2D
        if s:
            ships.append(s)
    for n in get_tree().get_nodes_in_group("racers"):
        var s := n as Node2D
        if s:
            ships.append(s)

    ## Check every unique pair
    for i in range(ships.size()):
        for j in range(i + 1, ships.size()):
            var a := ships[i]
            var b := ships[j]
            var key := _bump_key(a, b)
            if _bump_cds.has(key):
                continue
            if a.global_position.distance_to(b.global_position) > BUMP_RADIUS:
                continue

            ## Hit both ships
            _bump_cds[key] = BUMP_COOLDOWN
            _apply_bump_damage(a, BUMP_DAMAGE)
            _apply_bump_damage(b, BUMP_DAMAGE)
            _apply_bump_push(a, b)

func _apply_bump_damage(ship: Node2D, damage: int) -> void:
    var hb := ship.get_node_or_null("HurtBox") as HurtBox
    if hb:
        hb.received_damage.emit(damage)

func _apply_bump_push(a: Node2D, b: Node2D) -> void:
    var dir := (a.global_position - b.global_position)
    if dir == Vector2.ZERO:
        dir = Vector2(1.0, 0.0)   ## fallback if perfectly overlapping
    dir = Vector2(signf(dir.x), 0.0)   ## only lateral component — no vertical push

    _push_ship(a,  dir.x)
    _push_ship(b, -dir.x)

func _push_ship(ship: Node2D, push_x: float) -> void:
    if ship.has_method("steer_toward"):
        ## AI racer: nudge desired_x (LateralMover will glide toward it)
        ship.steer_toward(ship.global_position.x + push_x * BUMP_PUSH_AI)
    else:
        ## Player: add to velocity.x so move_and_slide carries it
        ship.velocity.x += push_x * BUMP_PUSH_PLAYER
```

### Wire into `_physics_process`

```gdscript
func _physics_process(delta: float) -> void:
    _check_racer_collisions(delta)
    ## (rest of existing _physics_process body unchanged)
```

---

## Behaviour Notes

### AI vs AI
`steer_toward()` writes `desired_x` on the `RaceShip`. `LateralMover.step()` applies a critically-damped glide (tau=0.12 s) toward it every frame, so the push is smooth, not a jerk. The AI's own FSM will immediately start steering back to its desired lane after the nudge, which is correct.

### Player vs AI
The player's `velocity.x` is nudged; `move_and_slide()` in the player's physics loop carries it one frame. The player already has world-bound clamping in `move_state.gd` (`actor.global_position.x = clamp(...)`) and in `player_race_controller.gd`, so the push cannot send them off screen.

### Vertical component
The push is **lateral-only** (no Y component). This is intentional — in race space, "up" means ahead, and giving ships a Y push would change their `track_y` which belongs solely to `RaceParticipant`. Keep collision effects in the lateral dimension only.

### Why cooldown 0.8 s?
Two overlapping ships at slightly different speeds will re-enter each other's radius multiple times per second. Without a cooldown, the damage would be enormous. 0.8 s means a prolonged side-by-side contact deals at most 12 DPS — uncomfortable but survivable. Adjust down to 0.5 s for more punishing contact, up to 1.2 s for lighter.

---

## Tuning Reference

| Constant | Default | Effect of increasing |
|---|---|---|
| `BUMP_RADIUS` | 36 px | Collision triggers at longer range (ships don't need to visually overlap) |
| `BUMP_DAMAGE` | 10 HP | Higher per-contact damage |
| `BUMP_COOLDOWN` | 0.8 s | Fewer hits per prolonged contact (less DPS) |
| `BUMP_PUSH_AI` | 50 px | Larger AI nudge (more visible lateral separation) |
| `BUMP_PUSH_PLAYER` | 140 px/s | Stronger player kick on collision |
