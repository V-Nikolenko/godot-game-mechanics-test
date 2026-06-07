# Race Track — Scrolling-Scene Model: Completion & Polish Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or
> superpowers:executing-plans to implement task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Finish migrating race mode to a **hand-built scrolling `Track` scene** (objects placed
by hand in the editor at real local coordinates; `RaceWorld` scrolls the whole `Track` Node2D
down). Make rivals and furniture share one coordinate space, delete the dead projection code, fix
the inconsistent mine drop, and lay the foundation for an art-directed corridor.

**Background:** This plan implements the converged conclusion of a two-agent design debate
(2026-06-03). Both agents agreed the hand-built scrolling-scene approach is correct for a curated,
art-directed track, but found the in-progress migration is half-finished: rivals still use the
*old* relative projection while furniture scrolls in real Track space (they desync), the old
`TrackObject` projection base is dead code that crashes, and Bogomol's cruise-mine is parented to
the wrong (non-scrolling) node. Streaming/pooling/markers are correctly **deferred** — they would
reintroduce the editor-invisibility the hand-built approach exists to escape, and the track is
9 objects, not hundreds.

**The crux (one line):** furniture at Track-local Y `-F` renders at world Y `_track.position.y - F`.
So a rival at `track_y = R` must render at `_track.position.y - R` to line up. That single formula
replaces the relative `base_screen_y - clamp((R - Pₜ)·scale, ±max)` mapping and dissolves the
`screen_y_scale`/`max_offset_y` machinery (both were only self-consistent at scale = 1, no clamp).

**Tech stack:** Godot 4.6.2, GDScript (static typing). No new dependencies.

---

## Conventions for this plan

- **No automated tests** (no framework). Verify with the headless harness, then F6 playtest:
  ```
  "C:/Users/Lonli/Desktop/Godot_v4.6.2-stable_win64.exe" --headless \
    --path "C:/Users/Lonli/Desktop/game-test-mechanics" \
    "res://assault/scenes/levels/race/race_level_1.tscn" --quit-after 200
  ```
  A clean run shows **only** the two known unrelated messages (`debug_draw_3d` GDExtension binary
  missing; stale UID in `player/weapons/modes/sniper_shot.tres`). Any `SCRIPT ERROR` / `Invalid` /
  `Nonexistent` line referencing a `race/` file is a failure.
- **No commit steps.** The user handles all git commits.
- **Static typing everywhere.** Match existing style (TAB indent).
- **WYSIWYG is the design principle.** Authoring fidelity (the designer sees the real object in the
  editor) takes priority over runtime cleverness. Do not replace placed objects with spawn-markers.

## Coordinate convention (document this; it governs the whole mode)

- `Track` is a `Node2D` in group `race_track`. On race start `RaceWorld` sets
  `Track.position.y = base_screen_y` (default 520) and each physics frame does
  `Track.position.y += player.current_speed * delta`.
- **Invariant:** `Track.position.y == base_screen_y + player.track_y` (both advance at the player's
  speed). *(Caveat: a player dash-panel **lunge** bumps `player.track_y` without bumping the Track
  scroll, so the invariant briefly slips during a player lunge — see Task 9.)*
- **Author track objects as children of `Track` at local Y = −(race distance).** A panel meant to
  be reached at distance 3000 → `position = (lane_x, -3000)`. The finish at distance 18000 →
  `(lane_x, -18000)`. X is the screen lane.

---

# PHASE P0 — Correctness (the migration is not done without these)

## Task 1: Unify rival screen-Y onto Track space

**Files:**
- Modify: `assault/scenes/race/core/race_world.gd`

- [ ] **Step 1: Replace `get_screen_y` and drop the obsolete exports**

In `race_world.gd`, the current body is:
```gdscript
## How many screen pixels apart two racers appear per unit of track_y difference.
@export var screen_y_scale: float = 1.0
## Maximum pixels a rival can appear above/below base_screen_y (clamps very far ships).
@export var max_offset_y: float = 420.0
...
func get_screen_y(p: RaceParticipant) -> float:
	var player := _director.get_player() if _director else null
	if player == null or p == player:
		return base_screen_y
	var delta := p.track_y - player.track_y
	var offset := clampf(delta * screen_y_scale, -max_offset_y, max_offset_y)
	return base_screen_y - offset
```

Delete the two exports `screen_y_scale` and `max_offset_y` (and their doc comments), and replace
`get_screen_y` with:
```gdscript
## Screen Y for a racer, derived from the SAME scrolling Track the furniture uses, so a rival at
## track_y = R lines up exactly with furniture authored at Track-local Y = -R. (Furniture at
## local -R sits at world Y = _track.position.y - R; this puts the rival at the same place.)
func get_screen_y(p: RaceParticipant) -> float:
	if _track == null:
		return base_screen_y
	return _track.position.y - p.track_y
```

Leave `base_screen_y`, `bg_scroll_min`, `bg_scroll_max`, `_ready`, and `_physics_process`
unchanged. (`_track` is already cached in `_ready` via group `race_track`.)

- [ ] **Step 2: Verify**

Run the headless harness. Expected: clean (only the two known unrelated messages). In an F6
playtest the AI rivals should now slide past dash panels at the *same* rate the panels scroll —
a rival sitting on a panel's lane crosses it visibly, and a rival far ahead simply leaves the top
of the screen (no edge-pinning "wind-up").

> **Note:** if any other script referenced `screen_y_scale` or `max_offset_y`, the headless run
> will flag it. Grep first: `screen_y_scale|max_offset_y` should match only the (now-removed)
> lines in `race_world.gd`.

---

## Task 2: Remove the dead projection base; make obstacles plain scrolling Track children

The old `TrackObject` base still projects via `_world.screen_y_for(track_y)` — a method that no
longer exists on `RaceWorld` — so any `TrackObject`/`TrackObstacle` instance crashes every physics
frame. `dash_panel.gd`, `mine.gd`, `finish_line.gd` were already rebased to plain `Node2D`; only
`obstacle.gd` still extends the dead base.

**Files:**
- Delete: `assault/scenes/race/track/track_object.gd` (+ `.uid`)
- Rewrite: `assault/scenes/race/track/obstacle.gd`
- Modify: `assault/scenes/race/track/obstacle.tscn`

- [ ] **Step 1: Confirm nothing else extends `TrackObject`**

Grep `extends TrackObject` and `: TrackObject` and `screen_y_for` across the repo. Expected: only
`obstacle.gd` extends it; nothing calls `screen_y_for`. If anything else does, stop and report.

- [ ] **Step 2: Rewrite `obstacle.gd` as a plain scrolling Track child**

```gdscript
## TrackObstacle — a hand-placed hazard authored as a child of the Track node. Because Track
## scrolls, its global_position is always correct without per-object projection. Any ship that
## touches it takes damage (which also costs top speed via DamageReaction / the player's hurt
## handler), and it sits in group "asteroids" so racer Sensors / LateralMover already avoid it.
## Contact is polled (ships are positioned by direct assignment, so Area2D body_entered is
## unreliable). Place at Track local Y = -(distance), X = lane.
class_name TrackObstacle
extends Node2D

@export var damage: int = 18
@export var contact_radius: float = 42.0
@export var hit_cooldown: float = 1.0      ## per-ship re-hit guard
@export var cull_margin: float = 160.0

var _cooldowns: Dictionary = {}            ## ship Node2D -> seconds remaining

func _ready() -> void:
	add_to_group("asteroids")

func _physics_process(delta: float) -> void:
	# Cull once scrolled off the bottom of the screen.
	if global_position.y > get_viewport_rect().size.y + cull_margin:
		queue_free()
		return
	# Cheap guard: do nothing while still well above the screen (not yet reachable).
	if global_position.y < -cull_margin:
		return
	for k in _cooldowns.keys():
		_cooldowns[k] -= delta
	for k in _cooldowns.keys().filter(func(x): return _cooldowns[x] <= 0.0):
		_cooldowns.erase(k)
	for grp in ["player", "racers"]:
		for n in get_tree().get_nodes_in_group(grp):
			var s := n as Node2D
			if s == null or _cooldowns.has(s):
				continue
			if global_position.distance_to(s.global_position) <= contact_radius:
				var hb := s.get_node_or_null("HurtBox") as HurtBox
				if hb:
					hb.received_damage.emit(damage)
				_cooldowns[s] = hit_cooldown
```

- [ ] **Step 3: Re-point `obstacle.tscn` root to `Node2D`**

Open `assault/scenes/race/track/obstacle.tscn`. Change the root node `type` from `Area2D` to
`Node2D` (it keeps the `obstacle.gd` script). Remove the `stand.png` sprite the user disliked —
leave the obstacle **visual-less** for now (it still works: collision is polled, group membership
intact), or assign a placeholder of your choice. Keep any `CollisionShape2D` only if you want it
for editor visualization; it is not used by the polled logic.

Minimal scene:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://assault/scenes/race/track/obstacle.gd" id="1"]

[node name="Obstacle" type="Node2D"]
script = ExtResource("1")
```

- [ ] **Step 4: Delete `track_object.gd`**

Delete `assault/scenes/race/track/track_object.gd` and `track_object.gd.uid`.

- [ ] **Step 5: Verify**

Headless run clean. Then drop one `obstacle.tscn` into `Track` at e.g. `(640, -2400)` in
`race_level_1.tscn`, run F6: it should scroll down with the track and damage a ship that flies
into it (top speed drops, ship flashes). Remove the test instance or keep it as you like.

---

## Task 3: Fix Bogomol's cruise-mine (parent to the scrolling Track)

`bogomol_cruise_state.gd` parents its mine to `host.get_parent()` (the non-scrolling `Racers`
node) and sets `mine.track_y` (a property `Mine` no longer has). Those mines hang in screen space
instead of scrolling with the world. Mirror the correct path in `bogomol_mine_state.gd`.

**Files:**
- Modify: `assault/scenes/race/racers/bogomol/states/bogomol_cruise_state.gd`

- [ ] **Step 1: Replace the mine-drop block**

Replace:
```gdscript
	_t -= delta
	if _t <= 0.0:
		_t = lay_interval
		var mine := _MINE.instantiate() as Mine
		mine.track_y = host.participant.track_y - 30.0
		mine.position = host.global_position + Vector2(0.0, 40.0)
		host.get_parent().add_child(mine)
```
with:
```gdscript
	_t -= delta
	if _t <= 0.0:
		_t = lay_interval
		var mine := _MINE.instantiate() as Mine
		var drop_pos := host.global_position + Vector2(0.0, 40.0)   ## just behind on the lane
		var track := host.get_tree().get_first_node_in_group("race_track") as Node2D
		if track:
			mine.position = track.to_local(drop_pos)   ## scrolls with the world
			track.add_child(mine)
		else:
			mine.global_position = drop_pos
			host.get_parent().add_child(mine)
```

- [ ] **Step 2: Verify**

Headless run clean. F6: while Bogomol is in CRUISE (no panel reachable) it drops mines that
**scroll down with the track** (they no longer hover in fixed screen positions) and damage ships
that follow.

---

## Task 4: Single source of truth for finish distance (`track_length`)

The `Finish` node is authored at Track-local Y `-18000`; `RaceDirector.track_length` defaults to
`18000`. They must not drift. Make the authored finish position the source and derive
`track_length` from it (WYSIWYG-consistent: the designer places the finish visually).

**Files:**
- Modify: `assault/scenes/race/track/finish_line.gd`
- Modify: `assault/scenes/race/race_level_config.gd`

- [ ] **Step 1: Have the finish line register itself**

In `finish_line.gd`, add to a group on ready so the config can find it. Add an `_ready`:
```gdscript
func _ready() -> void:
	add_to_group("finish_line")
```
(Keep the existing `_physics_process` cull.)

- [ ] **Step 2: Derive `track_length` from the authored finish in `RaceLevelConfig`**

In `race_level_config.gd._ready()`, after the `if director:` block that connects `race_failed`,
add:
```gdscript
	# Single source of truth: the hand-placed Finish node's Track-local Y defines the race length.
	# (Object at Track-local Y = -N is reached at distance N, so track_length = -finish.position.y.)
	var finish := get_tree().get_first_node_in_group("finish_line") as Node2D
	if director and finish:
		director.track_length = absf(finish.position.y)
```

- [ ] **Step 3: Verify**

Headless run clean. Move the `Finish` node in `race_level_1.tscn` to e.g. `(640, -9000)`, run F6:
the race should now end (player finish / standings resolve) at the new shorter distance, proving
`track_length` followed the authored position. Restore to `-18000` (or your preferred length).

---

# PHASE P1 — Feature & hygiene (soon)

## Task 5: Reusable corridor template (the "make it look nice" feature)

This is the user's actual goal: an art-directed corridor authored once and reused per level. Build
a `Track`-rooted **corridor scene** carrying the wall/scenery art so every level is "paint the
corridor, drop panels/obstacles/lasers, place the finish."

**Files:**
- Create: `assault/scenes/race/track/corridor.tscn` (+ optional `corridor.gd` if you want
  parameters like length)
- Assets: `assault/assets/sprites/racers/race track walls*.png`, `laser_wall.png`, etc.

- [ ] **Step 1: Decide the corridor representation**

Two viable options — pick per art style:
- **`TileMapLayer`** (recommended for tiled boundary walls): import the `race track walls*.png` as a
  tileset, paint left/right walls + floor down the corridor. Batched, cheap, scroll-for-free as a
  Track child. Best when the walls tile cleanly.
- **Tiled `Sprite2D` strips**: if the wall art is a long strip, stack/`region`-tile `Sprite2D`s
  down the corridor. Simpler import, fine for a handful of strips.

- [ ] **Step 2: Build `corridor.tscn`**

Root `Node2D` (so it drops in as a child of `Track`). Add the wall/floor `TileMapLayer` (or sprite
strips) spanning Y = 0 down to Y = −(track length). Add decorative scenery (`stand`-style props,
banners) at chosen local positions. Keep it **purely visual** — no scripts, no collision needed
(boundaries are enforced by the player/racer X-clamps in `LateralMover` / movement, not by the art).

- [ ] **Step 3: Use it in the level**

In `race_level_1.tscn`, add a `Corridor` instance as the **first** child of `Track` (so it renders
behind panels/obstacles). Confirm panels/obstacles/finish read clearly against the corridor art.

- [ ] **Step 4: Verify**

F6: the corridor scrolls with the track as one piece; panels/obstacles sit visibly inside it; the
track now *looks* like a track. Tune lane X bounds (`LateralMover.min_x`/`max_x` on racers, and the
player's clamp) to match the corridor walls so ships stay on the visible road.

## Task 6: Cheap off-screen guard on per-frame trigger scans

Add the same top-of-screen early-out used in Task 2's obstacle to the other polled track objects,
so off-screen furniture skips its `get_nodes_in_group` scan. Free hygiene that makes the design
self-limiting as tracks grow.

**Files:**
- Modify: `assault/scenes/race/track/dash_panel.gd`, `assault/scenes/race/track/mine.gd`

- [ ] **Step 1: Add the guard**

In each `_physics_process`, immediately after the existing bottom-cull check, add:
```gdscript
	if global_position.y < -cull_margin:
		return   # still above the screen; no ship can reach it yet
```
(`dash_panel.gd` already has `cull_margin`; `mine.gd` does not have one — add
`@export var cull_margin: float = 160.0` to it, or reuse a literal `-200.0`.)

- [ ] **Step 2: Verify** — headless clean; panels/mines still trigger correctly when on screen.

## Task 7: One shared speed source for Track scroll + parallax background

Today the Track scrolls by `player.current_speed * delta` while the parallax background scrolls by
`lerp(bg_scroll_min, bg_scroll_max, player.top_speed_fraction())` — two unrelated clocks that will
drift in feel. Unify them so the world reads as one moving environment.

**Files:**
- Modify: `assault/scenes/race/core/race_world.gd`

- [ ] **Step 1:** Drive the background multiplier from the *same* `player.current_speed` the Track
  uses (e.g. map `current_speed` through a normalized factor into `set_throttle_scroll`), or
  document that the parallax is intentionally a *depth* layer at a fraction of Track speed and pick
  the fraction deliberately. Keep `base_screen_y`/Track scroll as the single forward-speed authority.
- [ ] **Step 2: Verify** — F6: background and track accelerate/decelerate together on panel boosts
  and decay; no visual "slipping" between the road and the backdrop.

---

# PHASE P2 — Deferred (do NOT build until the trigger fires)

## Task 8: Segment streaming + pooling + marker spawning

**Trigger (build only when one is true):** a single track exceeds roughly a few screen-heights of
unique authored content, OR the project ships a 2nd reusable corridor and needs segment reuse, OR
tracks become procedural/very long.

When triggered: author reusable **segment sub-scenes**, instantiate a sliding window of 2–3 ahead
and free behind; pool mines/bullets; switch *fire-and-forget* spawns (not curated hand-placed
furniture) to `Marker2D`-driven instantiation. Keep hand-placed curated furniture as real objects
(do not marker-ize them — that would destroy the WYSIWYG authoring this whole model exists for).

*Until the trigger fires, this is intentionally not implemented (YAGNI: the current track is ~9
objects).*

---

## Task 9 (optional polish): Player lunge vs world-scroll desync

When the **player** crosses a dash panel, `RaceParticipant` adds a `panel_lunge` to the player's
`track_y` that the Track scroll does not include, so the player's logical progress briefly runs
ahead of the world scroll (the invariant `Track.position.y == base_screen_y + player.track_y`
slips for the duration of the lunge bleed). Standings/HUD stay correct (they use `track_y`); only
the visual world-vs-player coupling is briefly off.

Two clean options if it reads badly in playtest:
- **(a)** Fold the player's lunge into the Track scroll: have `RaceWorld` advance
  `Track.position.y` by the player's *actual* `track_y` delta this frame (lunge included) instead
  of `current_speed * delta`. Keeps the invariant exact at all times.
- **(b)** Remove the player's panel lunge entirely and rely on the `panel_gain` top-speed surge for
  the boost feel (rivals can keep their lunge).

Decide by feel in F6; not required for correctness.

---

## Self-Review — coverage

- Rival/furniture coordinate unification (debate crux) → Task 1.
- Dead `TrackObject` crash + hand-placeable obstacles → Task 2.
- Bogomol cruise-mine parenting bug → Task 3.
- Finish ↔ `track_length` single source → Task 4.
- Art-directed corridor (the user's goal) → Task 5.
- Cheap perf guard (both agents) → Tasks 2 & 6.
- Two-scroll-clock drift → Task 7.
- Streaming/pooling/markers deferred behind explicit trigger → Task 8.
- Player lunge desync caveat → Task 9.
