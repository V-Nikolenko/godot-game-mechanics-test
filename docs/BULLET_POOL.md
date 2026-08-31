# Bullet Pool System

## Architecture

```
┌─────────────┐            ┌───────────┐
│ BulletPool  │◄──signal───│  Bullet   │
│  (manager)  │ "expired"  │  (dumb)   │
└──────┬──────┘            └───────────┘
	   │ owns/resets/recycles
	   ▼
   [idle bullets]
```

**Core principle**: The **pool is smart, bullets are dumb**. Bullets know nothing about pooling—they only emit a signal when they're done. The pool observes that signal and handles all recycling.

---

## How It Works

### 1. **Initialization** (`BulletPool._ready()`)

When a ship adds a `BulletPool` as a child:

```gdscript
bullet_pool = BulletPool.new()
bullet_pool.bullet_scene = _BULLET_SCENE
bullet_pool.pool_size = 10
add_child(bullet_pool)  # ← triggers pool._ready()
```

The pool's `_ready()` fires immediately and:

1. **Resolves the active container** via parent chain
   - Pool is a child of the ship
   - Ship is a child of `enemy_container` (or level container)
   - Pool finds it via: `get_parent().get_parent()`

2. **Calls `_prewarm()`** to pre-allocate bullets
   - Creates `pool_size` bullet instances
   - Each bullet starts disabled (`process_mode = DISABLED`) and invisible
   - Each bullet is a child of the pool (idle state)

3. **Connects signals** — the critical decoupling moment
   - For each bullet: `bullet.expired.connect(func(): call_deferred("_recycle", bullet))`
   - The pool listens. The bullet broadcasts. Neither knows the other.
   - This connection is permanent and survives reparenting
   - **Important**: The call is deferred because `expired` often fires from a physics callback (`_on_hit_box_area_entered`), and Godot forbids physics state changes during physics callbacks

### 2. **Firing** (Ship calls `acquire()`)

When a ship fires:

```gdscript
var bullet := bullet_pool.acquire(global_position + Vector2(0, 10)) as EnemyBullet
if not bullet:
	return  # pool exhausted
bullet.set_direction(aim_direction)  # ship configures the bullet
```

The pool's `acquire()`:

1. **Pops a bullet** from the idle array
2. **Reparents it** from the pool to the level container
   - Idle bullets were children of the pool (grandchild of container)
   - Active bullets become direct children of the container
   - This separation ensures bullets travel independently of the ship
3. **Sets position** to the spawn point
4. **Calls `reset()`** on the bullet
   - Clears any state from previous use (rotation, direction, speed)
   - For `Bullet`: resets rotation to 0
   - For `EnemyBullet`: resets direction to DOWN, rotation to 0, speed to 250
5. **Enables the bullet** (`process_mode = INHERIT`, `visible = true`)
6. **Returns it** to the ship

The ship then configures direction/rotation as needed for its attack style.

### 3. **Recycling** (Signal-driven automatic)

When a bullet hits something or goes off-screen, it emits:

```gdscript
# In Bullet or EnemyBullet
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	expired.emit()  # ← the bullet never knows what happens next

func _on_hit_box_area_entered(_area: Area2D) -> void:
	expired.emit()  # ← same here
```

The pool's `_recycle()` method fires automatically (connected during init):

```gdscript
func _recycle(bullet: Node) -> void:
	# Guard against `expired` firing twice (hit AND off-screen in same frame)
	if _idle.has(bullet):
		return
	
	# Deactivate the bullet
	bullet.visible = false
	bullet.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Reclaim it
	if not is_queued_for_deletion():
		bullet.reparent(self, false)  # move back under the pool
		_idle.append(bullet)           # return to idle state
	else:
		# If the pool (and its ship) is being freed, just destroy the bullet
		bullet.queue_free()
```

The bullet is now idle again, awaiting the next `acquire()` call.

---

## Key Design Decisions

### **1. Bullets Are Pool-Agnostic**

Bullets have **zero references** to `BulletPool`:
- No `var _pool` property
- No `set_pool()` method
- No dependency on `BulletPool` type

**Why?** Bullets can be used in any context (boss battles, cutscenes, tests) without a pool. The bullet class is reusable and testable in isolation.

### **2. Signal-Based Observation**

Bullets emit `signal expired`. The pool listens.

```gdscript
# Bullet (broadcasts state)
signal expired

func _on_hit() -> void:
	expired.emit()

# Pool (observes)
bullet.expired.connect(_recycle.bind(bullet))
```

**Why?** Decouples bullet behavior from pool mechanics. The bullet doesn't need to know HOW recycling works—it just reports "I'm done." The pool handles the rest.

### **3. Container Separation**

- **Idle bullets** live under the pool (child of pool, grandchild of ship)
- **Active bullets** live under the level container (direct child of container)

**Why?** When the ship moves (especially with `EnemyPathMover`), idle bullets don't move with it. Active bullets travel independently. When the ship dies, active bullets finish their trajectory.

### **4. Pool-Driven Reset**

The pool calls `bullet.reset()` right after `acquire()`, before returning to the ship.

```gdscript
var bullet = _idle.pop_back()
bullet.reparent(_container)
if bullet.has_method("reset"):
	bullet.reset()
bullet.process_mode = Node.PROCESS_MODE_INHERIT
return bullet
```

**Why?** State restoration is the pool's responsibility, not the bullet's. This ensures every acquired bullet starts in a known, clean state.

### **5. Double-Fire Guard**

```gdscript
if _idle.has(bullet):
	return  # already recycled
```

If a bullet goes off-screen AND hits something in the same frame, `expired` fires twice. The guard prevents double-recycling (which would corrupt the idle list).

---

## Container Hierarchy

```
Level
├── EnemyContainer      ← active bullets live here
│   ├── Ship (Fighter)
│   │   └── BulletPool (grandchild of EnemyContainer)
│   │       ├── Bullet (idle) — process disabled, invisible
│   │       └── Bullet (idle)
│   ├── Bullet (active) ← from pool, reparented here
│   ├── Bullet (active)
│   └── ...
└── ...
```

When a ship is created via `WaveManager`:
1. `entity = scene.instantiate()` — creates the ship
2. `entity.global_position = spawn_pos` — position it
3. `enemy_container.add_child(entity)` — add to level, triggers `entity._ready()`
4. In `entity._ready()`: `add_child(bullet_pool)` — pool added as ship child, triggers `pool._ready()`
5. Pool's `_ready()`: `_container = get_parent().get_parent()` → resolves to `enemy_container` ✓

This parent chain is the linchpin of the design. The pool auto-discovers where to deploy active bullets.

---

## Usage From a Ship

### Creating a pool:

```gdscript
class_name LightAssaultShip
extends BaseEnemy

const _BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")
@export var bullet_pool: BulletPool

func _ready() -> void:
	# ... other setup ...
	
	# Create and configure the pool
	bullet_pool = BulletPool.new()
	bullet_pool.bullet_scene = _BULLET_SCENE
	bullet_pool.pool_size = 10
	add_child(bullet_pool)
	
	# Pool._ready() fires on add_child and handles prewarm + container resolution
```

### Firing bullets:

```gdscript
func _fire() -> void:
	# Acquire a bullet
	var bullet := bullet_pool.acquire(global_position + Vector2(0.0, 10.0)) as EnemyBullet
	if not bullet:
		return  # pool exhausted
	
	# Configure it (ship's responsibility)
	if aim_mode == "PLAYER":
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			var dir := ((players[0] as Node2D).global_position - global_position).normalized()
			bullet.set_direction(dir)
	# else: default direction (Vector2.DOWN) is fine
```

That's it. The pool handles the rest automatically.

---

## Failure Modes & Handling

### **Pool Exhausted**

If `acquire()` is called but all bullets are in flight:

```gdscript
if _idle.is_empty():
	push_warning("[BulletPool] Pool exhausted (enemy_bullet.tscn)")
	return null
```

Ships check for `null` and skip firing:

```gdscript
var bullet := bullet_pool.acquire(pos)
if not bullet:
	return
```

**Mitigation**: Size pools conservatively. A fighter with `fire_interval = 0.8s` and bullets lasting 3-4s won't exceed pool_size = 10 in normal play.

### **Double-Fire of `expired` Signal**

If a bullet goes off-screen AND hits something simultaneously:

```gdscript
func _recycle(bullet: Node) -> void:
	if _idle.has(bullet):
		return  # already in idle list, skip
```

The first `expired.emit()` triggers recycle, puts bullet in `_idle`. The second call sees it's already idle and returns silently.

### **Ship Dies While Bullets Are In Flight**

```gdscript
def _recycle(bullet: Node) -> void:
	if not is_queued_for_deletion():
		bullet.reparent(self, false)
		_idle.append(bullet)
	else:
		# Pool is being freed, so just destroy the bullet too
		bullet.queue_free()
```

If the pool's `_ready()` never fires (ship not added to tree), `_container` remains null and `acquire()` will crash on `bullet.reparent(_container)`. But this shouldn't happen in normal flow since ships are spawned via `WaveManager`, which guarantees `add_child()` before ship's `_ready()`.

---

## Physics Safety

### The Physics Callback Problem

When a bullet hits something, the signal fires **inside a physics callback**:

```gdscript
# In EnemyBullet._on_hit_box_area_entered()
func _on_hit_box_area_entered(_area: Area2D) -> void:
	expired.emit()  # ← we're inside a Godot physics frame right now
```

If `_recycle()` tries to disable physics immediately, Godot throws:
```
Disabling a CollisionObject node during a physics callback is not allowed
Can't change this state while flushing queries
```

### The Solution: Deferred Calls

In `BulletPool._prewarm()`, we defer the recycle operation:

```gdscript
bullet.expired.connect(func(): call_deferred("_recycle", bullet))
```

Instead of calling `_recycle()` directly, we **queue it for later**. Godot runs the deferred call after the physics frame completes, when it's safe to modify physics state.

**Why this works**:
1. Physics callback fires: `expired.emit()`
2. Signal handler queues: `call_deferred("_recycle", bullet)`
3. Physics frame finishes
4. Deferred calls execute: `_recycle()` now safely disables physics

This is Godot best practice for physics-triggered events.

---

## Testing & Debugging

### **Verify Pool-Agnosticism**

Instantiate a `Bullet` or `EnemyBullet` standalone (no pool):

```gdscript
var bullet = EnemyBullet.new()
bullet.set_direction(Vector2.DOWN)
get_parent().add_child(bullet)
```

It works fine—it just travels and emits `expired` to nobody. This proves bullets have no pool dependency.

### **Monitor Pool State**

Add temporary debug output in `_prewarm()` and `_recycle()`:

```gdscript
func _prewarm() -> void:
	print("[Pool] Initializing %d bullets for %s" % [pool_size, bullet_scene.resource_path.get_file()])

func _recycle(bullet: Node) -> void:
	print("[Pool] Recycling bullet, idle count: %d" % [_idle.size()])
```

### **Check Idle Count**

If bullets are mysteriously disappearing, check if they're stuck in active state:

```gdscript
print("Idle bullets: %d / %d" % [bullet_pool._idle.size(), bullet_pool.pool_size])
```

---

## Summary

| Aspect | Implementation |
|--------|---|
| **Ownership** | Pool owns bullets; ships acquire and use them |
| **Signal** | `expired` — emitted by bullet when done, observed by pool |
| **Reset** | Pool calls `bullet.reset()` on acquire |
| **Container** | Active bullets live in level container, idle bullets under pool |
| **Recycling** | Automatic via signal; ships never touch recycle logic |
| **Decoupling** | Bullets have zero knowledge of pool; pool is self-contained |

The result: bullets are reusable everywhere, pools are self-managing, and ships just acquire and configure—nothing else.
