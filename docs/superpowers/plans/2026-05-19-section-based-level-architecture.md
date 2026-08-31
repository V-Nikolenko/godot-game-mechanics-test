# Section-Based Level Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the monolithic clock-driven level system with a `LevelDirector` that sequences `LevelSection` resources. Each section owns section-relative waves and a `BackgroundPhase` — a **state snapshot** the background tweens toward. `Level1Background` becomes a passive renderer with zero phase-clock logic; all timing is driven by Godot Tweens.

**Architecture:** `BackgroundPhase` stores target layer alphas, planet scale, and scroll speeds — a CSS-like "what should this look like". `Level1Background.transition_to(phase, duration)` kills the previous Tween and starts a new one interpolating every property. `LevelDirector` calls this + `wave_manager.load_section()` on each section change. The background's `_process()` only scrolls tiles and positions asteroids; no `_elapsed` phase math remains.

**Tech Stack:** Godot 4.3+, GDScript static typing, `Tween` (parallel), `create_timer`, existing `WaveBuilder` fluent API, `WaveManager`.

---

## What changes and why

| Problem in current code | Fix in this plan |
|-------------------------|-----------------|
| `Level1Background._apply()` hard-codes `_elapsed - deep_space_duration` | Removed entirely — background reads from Tween-animated state variables |
| Wave trigger times are absolute magic numbers (140.0, 190.0) | `load_section()` resets the wave clock; all times are section-relative |
| "Change approach from 110 s → 80 s" requires renumbering 5 other values | Just change `LevelSection.transition_in_duration` + `duration`; waves don't move |
| No concept of "current phase"; nothing emits when a phase ends | `LevelDirector` emits `section_started` / `level_complete` |
| End-of-level logic buried inside `LevelWaves._on_waves_complete()` | `_on_level_complete()` on a dedicated config node; background is unaware |

---

## File Map

| Action | Path | Responsibility |
|--------|------|---------------|
| **Create** | `global/resources/levels/background_phase.gd` | State-snapshot resource: target alphas, planet scale, peel schedule |
| **Create** | `global/resources/levels/level_section.gd` | Waves + phase + end condition + transition_in_duration |
| **Create** | `assault/scenes/systems/level_director/level_director.gd` | Sequences sections; drives background + wave manager |
| **Create** | `assault/scenes/levels/phases/phase_deep_space.tres` | Pure space, no planet, no clouds |
| **Create** | `assault/scenes/levels/phases/phase_planet_approach.tres` | Planet grows, space fades, clouds materialise |
| **Create** | `assault/scenes/levels/phases/phase_cloud_descent.tres` | Clouds peel layer by layer, surface appears |
| **Create** | `assault/scenes/levels/level_1_director.gd` | Level 1 section definitions + post-battle (replaces level_1_waves.gd) |
| **Modify** | `assault/scenes/systems/wave_manager/wave_manager.gd` | Add `load_section()` that resets clock and loads a wave batch |
| **Rewrite** | `assault/scenes/levels/level_1_background.gd` | Passive renderer: state vars + `transition_to()`, no `_elapsed` phase logic |
| **Modify** | `assault/scenes/levels/level_1.tscn` | Add LevelDirector node; swap LevelWaves → level_1_director.gd |
| **Delete** | `assault/scenes/levels/level_1_waves.gd` | Superseded |

---

## Section timeline (Level 1)

| # | Name | Duration / End | transition_in | Waves (section-relative) |
|---|------|---------------|--------------|--------------------------|
| 1 | Deep Space | 30 s | 0 s (instant) | 2.0, 5.0, 8.0, 14.0, 20.0, 22.0, 26.0 |
| 2 | Planet Approach | 110 s | 110 s | none (cinematic) |
| 3 | Cloud Descent | ENEMIES_CLEARED | 2 s | 0.0 (allies), 50.0 (gunship) |

Section 2's `transition_in_duration = 110 s` — the planet spends the **entire** section growing. Background asteroid textures enter when this section starts and fade naturally as `_alpha_stars_base` tweens to 0.

---

## Task 1: BackgroundPhase Resource

**Files:**
- Create: `global/resources/levels/background_phase.gd`

`BackgroundPhase` stores **target values** — where each layer should end up after the transition. It also carries per-layer cloud peel schedules (section-relative timers, since the peel is a multi-layer staggered animation that runs independently of the main tween).

- [ ] **Step 1: Create the file**

```gdscript
## BackgroundPhase — a state snapshot describing what the background should look like
## once a section's transition_in completes.
##
## Level1Background.transition_to(phase, duration) Tweens all properties from
## their current values to these targets over [duration] seconds.
##
## Cloud peel schedules run concurrently as section-relative timers; they are
## independent from the main alpha/scale tween.
class_name BackgroundPhase
extends Resource

@export var phase_name: StringName = &""

# ── Target layer alphas ───────────────────────────────────────────────────────
## Stars and nebula share one group; all tween together toward these values.
@export_group("Space Layers")
@export_range(0.0, 1.0, 0.01) var stars_base_alpha:    float = 1.0
@export_range(0.0, 1.0, 0.01) var stars_overlay_alpha: float = 1.0
@export_range(0.0, 1.0, 0.01) var nebula_alpha:         float = 0.08

## Cloud layers tween from current alpha to these values during transition_in.
## During planet approach they tween FROM 0 but start delayed by clouds_appear_fraction.
@export_group("Cloud Layers")
@export_range(0.0, 1.0, 0.01) var cloud_1_alpha: float = 0.0
@export_range(0.0, 1.0, 0.01) var cloud_2_alpha: float = 0.0
@export_range(0.0, 1.0, 0.01) var cloud_3_alpha: float = 0.0
@export_range(0.0, 1.0, 0.01) var cloud_4_alpha: float = 0.0

## Fraction [0-1] of transition_in_duration before clouds begin tweening.
## Set to 0.6 for planet approach (clouds appear only in the last 40 %).
@export_range(0.0, 1.0, 0.01) var clouds_appear_fraction: float = 0.0

## Target alpha for the surface (planet ground) layer.
@export_range(0.0, 1.0, 0.01) var surface_alpha: float = 0.0

# ── Planet ────────────────────────────────────────────────────────────────────
@export_group("Planet")
@export_range(0.0, 1.0, 0.01) var planet_alpha: float = 0.0
## Target scale at end of transition.  Uses EASE_IN CUBIC to mimic ease(t,3).
@export var planet_scale: float = 0.1
## Seconds after section start for the planet to reach planet_alpha.
## Independent from the main transition duration (usually 2 s).
@export var planet_fade_in: float = 2.0

# ── Asteroid entry ────────────────────────────────────────────────────────────
## If true the asteroid layer resets to the top of screen when this phase starts.
## The layer then scrolls downward at its export speed until it exits.
## Alpha tracks _alpha_stars_base (fades with the space layers automatically).
@export_group("Asteroids")
@export var asteroids_back_enter:  bool = false
@export var asteroids_front_enter: bool = false

# ── Cloud peel schedule (section-relative) ────────────────────────────────────
## Peel = fade alpha to 0 + scale up to cloud_peel_scale using EASE_IN QUAD.
## -1.0 = this layer does not peel during this section.
@export_group("Cloud Peel")
@export var cloud_4_peel_start:    float = -1.0
@export var cloud_4_peel_duration: float =  3.0
@export var cloud_3_peel_start:    float = -1.0
@export var cloud_3_peel_duration: float =  5.0
@export var cloud_2_peel_start:    float = -1.0
@export var cloud_2_peel_duration: float =  5.0
@export var cloud_1_peel_start:    float = -1.0
@export var cloud_1_peel_duration: float =  5.0
## Scale reached by the end of the peel animation.
@export var cloud_peel_scale: float = 4.0

## Seconds after section start before surface begins fading in.
## -1.0 = surface does not appear during this section.
@export var surface_appear_start:    float = -1.0
@export var surface_appear_duration: float = 10.0
```

- [ ] **Step 2: Verify Godot recognises the class**

Open the Godot editor. In the FileSystem dock, right-click `global/resources/levels/` → **Reload**. Confirm no parse errors in Output. `BackgroundPhase` should appear in Create Resource dialog.

- [ ] **Step 3: Commit**

```bash
git add global/resources/levels/background_phase.gd
git commit -m "feat: add BackgroundPhase state-snapshot resource"
```

---

## Task 2: LevelSection Resource

**Files:**
- Create: `global/resources/levels/level_section.gd`

- [ ] **Step 1: Create the file**

```gdscript
## LevelSection — one timed segment of a level.
## Bundles section-relative waves with a background target state and an exit condition.
class_name LevelSection
extends Resource

enum EndCondition {
	DURATION,        ## Advance after [duration] seconds.
	WAVES_COMPLETE,  ## Advance after all waves have triggered.
	ENEMIES_CLEARED, ## Advance after waves complete AND enemy_container is empty.
}

@export var section_name: StringName = &""

## Background target state for this section.
@export var background_phase: BackgroundPhase

## How long (seconds) to tween from the previous phase to this one.
## Pass this to background.transition_to(phase, transition_in_duration).
@export var transition_in_duration: float = 2.0

## Waves to load at section start.  trigger_time is SECTION-RELATIVE.
@export var waves: Array[WaveResource] = []

@export var end_condition: EndCondition = EndCondition.DURATION

## Seconds before advancing (only when end_condition == DURATION).
@export var duration: float = 30.0
```

- [ ] **Step 2: Verify in editor — no parse errors**

- [ ] **Step 3: Commit**

```bash
git add global/resources/levels/level_section.gd
git commit -m "feat: add LevelSection resource with transition_in_duration"
```

---

## Task 3: Add `load_section()` to WaveManager

**Files:**
- Modify: `assault/scenes/systems/wave_manager/wave_manager.gd`

- [ ] **Step 1: Add after `load_level()` (around line 60)**

```gdscript
## Clears current waves and loads a new batch with a reset clock.
## Call this when LevelDirector advances to a new section.
## trigger_time on each WaveResource is SECTION-RELATIVE.
func load_section(waves: Array[WaveResource]) -> void:
	_waves.clear()
	_next_wave_index = 0
	_time_elapsed    = 0.0
	for wave: WaveResource in waves:
		var spawns: Array = []
		for entry: SpawnEntryResource in wave.entries:
			spawns.append(_entry_to_dict(entry))
		_waves.append({"trigger": wave.trigger_time, "spawns": spawns})
	print("[WaveManager] Loaded section — %d waves" % _waves.size())
	set_process(not _waves.is_empty())
```

- [ ] **Step 2: Verify — no parse errors in Godot Output**

- [ ] **Step 3: Commit**

```bash
git add assault/scenes/systems/wave_manager/wave_manager.gd
git commit -m "feat: WaveManager.load_section() resets clock and loads section-relative waves"
```

---

## Task 4: Rewrite Level1Background as a Passive Renderer

**Files:**
- Rewrite: `assault/scenes/levels/level_1_background.gd`

This is the biggest task. The new script:
- Holds **state variables** (`_alpha_stars_base`, `_planet_scale`, etc.) that `_apply()` reads directly.
- `transition_to(phase, duration)` Tweens state variables to phase target values.
- `_process()` only accumulates scrolls and moves asteroid Y — zero phase logic.
- Exports (speeds, textures, planet constants) remain for Inspector tuning.
- All `_elapsed`-based `approach_t / descent_t` math is **deleted**.

- [ ] **Step 1: Replace the Runtime State section**

Find the `# ── Runtime state ──` block (currently one `_elapsed` float + 8 scroll floats). Replace entirely with:

```gdscript
# ── Tween handle ─────────────────────────────────────────────────────────────
var _transition_tween: Tween = null

# ── Rendered state — what _apply() reads ─────────────────────────────────────
var _alpha_stars_base:    float = 1.0
var _alpha_stars_overlay: float = 1.0
var _alpha_nebula:        float = 0.08
var _alpha_planet:        float = 0.0
var _planet_scale:        float = 0.10

var _alpha_cloud_1: float = 0.0
var _alpha_cloud_2: float = 0.0
var _alpha_cloud_3: float = 0.0
var _alpha_cloud_4: float = 0.0
var _scale_cloud_1: float = 1.0
var _scale_cloud_2: float = 1.0
var _scale_cloud_3: float = 1.0
var _scale_cloud_4: float = 1.0

var _alpha_surface: float = 0.0

# ── Asteroid scroll state ─────────────────────────────────────────────────────
var _asteroids_back_y:      float = 0.0
var _asteroids_back_active: bool  = false
var _asteroids_front_y:     float = 0.0
var _asteroids_front_active: bool = false

# ── Scroll accumulators ───────────────────────────────────────────────────────
var _scroll_stars_base:    float = 0.0
var _scroll_stars_overlay: float = 0.0
var _scroll_nebula:        float = 0.0
var _scroll_cloud_1:       float = 0.0
var _scroll_cloud_2:       float = 0.0
var _scroll_cloud_3:       float = 0.0
var _scroll_cloud_4:       float = 0.0
var _scroll_surface:       float = 0.0
```

- [ ] **Step 2: Replace `_process()`**

```gdscript
func _process(delta: float) -> void:
	_scroll_stars_base    += delta * speed_stars_base
	_scroll_stars_overlay += delta * speed_stars_overlay
	_scroll_nebula        += delta * speed_nebula
	_scroll_cloud_1       += delta * speed_cloud_1
	_scroll_cloud_2       += delta * speed_cloud_2
	_scroll_cloud_3       += delta * speed_cloud_3
	_scroll_cloud_4       += delta * speed_cloud_4
	_scroll_surface       += delta * speed_surface

	var screen := get_viewport().get_visible_rect().size

	if _asteroids_back_active:
		_asteroids_back_y += delta * speed_asteroids_back
		if _asteroids_back_y > screen.y:
			_asteroids_back_active = false

	if _asteroids_front_active:
		_asteroids_front_y += delta * speed_asteroids_front
		if _asteroids_front_y > screen.y:
			_asteroids_front_active = false

	_apply(screen)
```

- [ ] **Step 3: Add `transition_to()` before `_apply()`**

```gdscript
## Called by LevelDirector when a new section begins.
## Tweens all visual state variables from their current values toward [phase]
## over [duration] seconds.  Cloud peel animations are scheduled as independent
## timers that fire after [phase.cloud_N_peel_start] seconds.
func transition_to(phase: BackgroundPhase, duration: float) -> void:
	print("[Background] transition_to: %s  over %.1f s" % [phase.phase_name, duration])

	# ── Cancel previous transition ────────────────────────────────────────────
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()

	# ── Asteroid entry (immediate — position reset) ───────────────────────────
	if phase.asteroids_back_enter:
		_asteroids_back_y      = -_asteroids_back.size.y
		_asteroids_back_active = true
	if phase.asteroids_front_enter:
		_asteroids_front_y      = -_asteroids_front.size.y
		_asteroids_front_active = true

	# ── Reset cloud peel scales ───────────────────────────────────────────────
	_scale_cloud_1 = 1.0
	_scale_cloud_2 = 1.0
	_scale_cloud_3 = 1.0
	_scale_cloud_4 = 1.0

	if duration <= 0.0:
		# ── Instant snap ─────────────────────────────────────────────────────
		_alpha_stars_base    = phase.stars_base_alpha
		_alpha_stars_overlay = phase.stars_overlay_alpha
		_alpha_nebula        = phase.nebula_alpha
		_alpha_planet        = phase.planet_alpha
		_planet_scale        = phase.planet_scale
		_alpha_cloud_1       = phase.cloud_1_alpha
		_alpha_cloud_2       = phase.cloud_2_alpha
		_alpha_cloud_3       = phase.cloud_3_alpha
		_alpha_cloud_4       = phase.cloud_4_alpha
		_alpha_surface       = phase.surface_alpha
		_schedule_peel_timers(phase)
		return

	# ── Parallel Tween ────────────────────────────────────────────────────────
	_transition_tween = create_tween().set_parallel(true)

	# Space layers
	_transition_tween.tween_property(self, "_alpha_stars_base",    phase.stars_base_alpha,    duration)
	_transition_tween.tween_property(self, "_alpha_stars_overlay", phase.stars_overlay_alpha, duration)
	_transition_tween.tween_property(self, "_alpha_nebula",        phase.nebula_alpha,        duration)

	# Planet — scale tweens EASE_IN CUBIC to mimic ease(t, 3.0); fade-in is short
	_transition_tween.tween_property(self, "_planet_scale", phase.planet_scale, duration)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	var planet_fade_dur := minf(phase.planet_fade_in, duration)
	_transition_tween.tween_property(self, "_alpha_planet", phase.planet_alpha, planet_fade_dur)

	# Cloud alphas — optionally delayed so clouds appear only in the last fraction
	var clouds_delay := duration * phase.clouds_appear_fraction
	var clouds_dur   := maxf(duration - clouds_delay, 0.01)

	# Only tween cloud alphas for layers NOT being peeled (peel timer handles those)
	var peeled := []
	if phase.cloud_4_peel_start >= 0.0: peeled.append(4)
	if phase.cloud_3_peel_start >= 0.0: peeled.append(3)
	if phase.cloud_2_peel_start >= 0.0: peeled.append(2)
	if phase.cloud_1_peel_start >= 0.0: peeled.append(1)

	if 1 not in peeled:
		_transition_tween.tween_property(self, "_alpha_cloud_1", phase.cloud_1_alpha, clouds_dur).set_delay(clouds_delay)
	if 2 not in peeled:
		_transition_tween.tween_property(self, "_alpha_cloud_2", phase.cloud_2_alpha, clouds_dur).set_delay(clouds_delay)
	if 3 not in peeled:
		_transition_tween.tween_property(self, "_alpha_cloud_3", phase.cloud_3_alpha, clouds_dur).set_delay(clouds_delay)
	if 4 not in peeled:
		_transition_tween.tween_property(self, "_alpha_cloud_4", phase.cloud_4_alpha, clouds_dur).set_delay(clouds_delay)

	# Surface (tweened from 0 by the peel timer, or by this tween if no peel)
	if phase.surface_appear_start < 0.0:
		_transition_tween.tween_property(self, "_alpha_surface", phase.surface_alpha, duration)

	_schedule_peel_timers(phase)


func _schedule_peel_timers(phase: BackgroundPhase) -> void:
	var peel_pairs: Array = [
		[4, phase.cloud_4_peel_start, phase.cloud_4_peel_duration],
		[3, phase.cloud_3_peel_start, phase.cloud_3_peel_duration],
		[2, phase.cloud_2_peel_start, phase.cloud_2_peel_duration],
		[1, phase.cloud_1_peel_start, phase.cloud_1_peel_duration],
	]
	for pair in peel_pairs:
		var layer: int   = pair[0]
		var delay: float = pair[1]
		var dur:   float = pair[2]
		if delay < 0.0:
			continue
		var t := get_tree().create_timer(delay)
		t.timeout.connect(_run_peel.bind(layer, dur, phase.cloud_peel_scale))

	if phase.surface_appear_start >= 0.0:
		var t := get_tree().create_timer(phase.surface_appear_start)
		t.timeout.connect(_run_surface_appear.bind(phase.surface_appear_duration))


func _run_peel(layer: int, duration: float, target_scale: float) -> void:
	var tw := create_tween().set_parallel(true)
	match layer:
		1:
			tw.tween_property(self, "_alpha_cloud_1", 0.0, duration)
			tw.tween_property(self, "_scale_cloud_1", target_scale, duration)\
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		2:
			tw.tween_property(self, "_alpha_cloud_2", 0.0, duration)
			tw.tween_property(self, "_scale_cloud_2", target_scale, duration)\
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		3:
			tw.tween_property(self, "_alpha_cloud_3", 0.0, duration)
			tw.tween_property(self, "_scale_cloud_3", target_scale, duration)\
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		4:
			tw.tween_property(self, "_alpha_cloud_4", 0.0, duration)
			tw.tween_property(self, "_scale_cloud_4", target_scale, duration)\
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _run_surface_appear(duration: float) -> void:
	create_tween().tween_property(self, "_alpha_surface", 1.0, duration)
```

- [ ] **Step 4: Replace `_apply()` — reads only from state variables**

Delete the old `_apply()` entirely (it had all the `approach_t`, `clouds_in`, `space_t`, etc.). Replace with:

```gdscript
func _apply(screen: Vector2) -> void:
	# ── Stars + nebula ────────────────────────────────────────────────────────
	_scroll_pair(_stars_base_a,    _stars_base_b,    _scroll_stars_base)
	_scroll_pair(_stars_overlay_a, _stars_overlay_b, _scroll_stars_overlay)
	_scroll_pair(_nebula_a,        _nebula_b,        _scroll_nebula)
	_stars_base_a.modulate.a    = _alpha_stars_base
	_stars_base_b.modulate.a    = _alpha_stars_base
	_stars_overlay_a.modulate.a = _alpha_stars_overlay
	_stars_overlay_b.modulate.a = _alpha_stars_overlay
	_nebula_a.modulate.a        = _alpha_nebula
	_nebula_b.modulate.a        = _alpha_nebula

	# ── Planet ────────────────────────────────────────────────────────────────
	_planet.position   = Vector2(screen.x * 0.5, planet_y_anchor)
	_planet.scale      = Vector2.ONE * _planet_scale
	_planet.modulate.a = _alpha_planet

	# ── Asteroids (alpha tracks space layers so they fade with the stars) ─────
	if _asteroids_back_active:
		_asteroids_back.visible    = true
		_asteroids_back.position   = Vector2(0.0, _asteroids_back_y)
		_asteroids_back.modulate.a = _alpha_stars_base
	else:
		_asteroids_back.visible = false

	if _asteroids_front_active:
		_asteroids_front.visible    = true
		_asteroids_front.position   = Vector2(0.0, _asteroids_front_y)
		_asteroids_front.modulate.a = _alpha_stars_base
	else:
		_asteroids_front.visible = false

	# ── Clouds ────────────────────────────────────────────────────────────────
	_apply_cloud_layer(_c1_a, _c1_b, screen, _scroll_cloud_1, _alpha_cloud_1, _scale_cloud_1)
	_apply_cloud_layer(_c2_a, _c2_b, screen, _scroll_cloud_2, _alpha_cloud_2, _scale_cloud_2)
	_apply_cloud_layer(_c3_a, _c3_b, screen, _scroll_cloud_3, _alpha_cloud_3, _scale_cloud_3)
	_apply_cloud_layer(_c4_a, _c4_b, screen, _scroll_cloud_4, _alpha_cloud_4, _scale_cloud_4)

	# ── Surface ───────────────────────────────────────────────────────────────
	_scroll_pair(_surface_a, _surface_b, _scroll_surface)
	_surface_a.modulate.a = _alpha_surface
	_surface_b.modulate.a = _alpha_surface
```

- [ ] **Step 5: Update `_apply_cloud_layer()` signature**

The helper now receives `base_alpha` and `scale_factor` directly (no more peel_t):

```gdscript
func _apply_cloud_layer(a: TextureRect, b: TextureRect, screen: Vector2,
		scroll: float, base_alpha: float, scale_factor: float) -> void:
	_scroll_pair(a, b, scroll)
	a.modulate.a = base_alpha
	b.modulate.a = base_alpha
	a.pivot_offset = screen * 0.5 - a.position
	b.pivot_offset = screen * 0.5 - b.position
	a.scale = Vector2.ONE * scale_factor
	b.scale = Vector2.ONE * scale_factor
```

- [ ] **Step 6: Delete now-unused methods**

Delete these methods (they're fully replaced):
- `_peel()` (the old static helper)
- Old `_apply_asteroid_layer()` (asteroid state is now in `_process`)

Keep: `_setup_tile_pair()`, `_setup_single_rect()`, `_scroll_pair()`.

- [ ] **Step 7: Verify backward compatibility**

Run the game (F5). `LevelDirector` isn't wired yet, so `transition_to()` is never called. The state variables default to the same starting values as the old code (`_alpha_stars_base = 1.0`, `_alpha_planet = 0.0`, etc.), so the level starts in deep space correctly. Nothing moves (no transitions fire) but the background scrolls — confirm stars and nebula scroll.

- [ ] **Step 8: Commit**

```bash
git add assault/scenes/levels/level_1_background.gd
git commit -m "refactor: Level1Background is now a passive renderer — transition_to() drives Tweens, no _elapsed phase logic"
```

---

## Task 5: Create LevelDirector

**Files:**
- Create: `assault/scenes/systems/level_director/level_director.gd`

- [ ] **Step 1: Create file**

```gdscript
## LevelDirector — sequences LevelSection resources in order.
##
## On each section start:
##   background.transition_to(section.background_phase, section.transition_in_duration)
##   wave_manager.load_section(section.waves)
##
## Add sections via add_section(), then call start().
class_name LevelDirector
extends Node

signal section_started(index: int, section_name: StringName)
signal level_complete

@export var background:   Level1Background
@export var wave_manager: WaveManager

var _sections:        Array[LevelSection] = []
var _current_index:   int   = -1
var _section_elapsed: float = 0.0

func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	if _current_index < 0 or _current_index >= _sections.size():
		return
	_section_elapsed += delta
	var s := _sections[_current_index]
	if s.end_condition == LevelSection.EndCondition.DURATION and _section_elapsed >= s.duration:
		_advance()

## Append a section to the sequence.
func add_section(s: LevelSection) -> void:
	_sections.append(s)

## Start sequencing from section 0.
func start() -> void:
	_current_index = -1
	_advance()

# ── Internal ──────────────────────────────────────────────────────────────────

func _advance() -> void:
	_current_index += 1
	if _current_index >= _sections.size():
		print("[LevelDirector] All sections complete")
		level_complete.emit()
		set_process(false)
		return

	_section_elapsed = 0.0
	var s := _sections[_current_index]
	print("[LevelDirector] Section %d: '%s'  end=%s  transition_in=%.1f s" % [
		_current_index, s.section_name,
		LevelSection.EndCondition.keys()[s.end_condition],
		s.transition_in_duration
	])
	section_started.emit(_current_index, s.section_name)

	if background and s.background_phase:
		background.transition_to(s.background_phase, s.transition_in_duration)

	if wave_manager:
		wave_manager.load_section(s.waves)

	match s.end_condition:
		LevelSection.EndCondition.DURATION:
			set_process(true)
		LevelSection.EndCondition.WAVES_COMPLETE:
			set_process(false)
			wave_manager.waves_complete.connect(_advance, CONNECT_ONE_SHOT)
		LevelSection.EndCondition.ENEMIES_CLEARED:
			set_process(false)
			wave_manager.waves_complete.connect(_wait_enemies_cleared, CONNECT_ONE_SHOT)


func _wait_enemies_cleared() -> void:
	var container: Node = wave_manager.enemy_container
	var waited := 0.0
	while container.get_child_count() > 0 and waited < 10.0:
		await get_tree().create_timer(0.15).timeout
		waited += 0.15
	print("[LevelDirector] Enemies cleared (%.1f s) — %d remaining" % [
		waited, container.get_child_count()
	])
	await get_tree().create_timer(0.2).timeout
	_advance()
```

- [ ] **Step 2: Verify parse in Godot — no errors**

- [ ] **Step 3: Commit**

```bash
git add assault/scenes/systems/level_director/level_director.gd
git commit -m "feat: add LevelDirector node — sequences sections, drives background + waves"
```

---

## Task 6: Create Phase `.tres` Files

**Files:**
- Create: `assault/scenes/levels/phases/phase_deep_space.tres`
- Create: `assault/scenes/levels/phases/phase_planet_approach.tres`
- Create: `assault/scenes/levels/phases/phase_cloud_descent.tres`

Write verbatim — Godot assigns UIDs on first import.

- [ ] **Step 1: Create the directory**

```bash
mkdir -p assault/scenes/levels/phases
```

- [ ] **Step 2: Write `phase_deep_space.tres`**

Full space, nothing else. Asteroids don't enter here — they enter when the planet approach begins.

```
[gd_resource type="BackgroundPhase" script_class="BackgroundPhase" load_steps=2 format=3]

[ext_resource type="Script" path="res://global/resources/levels/background_phase.gd" id="1_script"]

[resource]
script = ExtResource("1_script")
phase_name = &"deep_space"
stars_base_alpha = 1.0
stars_overlay_alpha = 1.0
nebula_alpha = 0.08
cloud_1_alpha = 0.0
cloud_2_alpha = 0.0
cloud_3_alpha = 0.0
cloud_4_alpha = 0.0
clouds_appear_fraction = 0.0
surface_alpha = 0.0
planet_alpha = 0.0
planet_scale = 0.1
planet_fade_in = 2.0
asteroids_back_enter = false
asteroids_front_enter = false
cloud_4_peel_start = -1.0
cloud_3_peel_start = -1.0
cloud_2_peel_start = -1.0
cloud_1_peel_start = -1.0
surface_appear_start = -1.0
```

- [ ] **Step 3: Write `phase_planet_approach.tres`**

Space fades to 0, planet grows to atmosphere scale (8.0), clouds materialise in the last 40 % of the 110 s transition. Background asteroid textures enter at section start.

```
[gd_resource type="BackgroundPhase" script_class="BackgroundPhase" load_steps=2 format=3]

[ext_resource type="Script" path="res://global/resources/levels/background_phase.gd" id="1_script"]

[resource]
script = ExtResource("1_script")
phase_name = &"planet_approach"
stars_base_alpha = 0.0
stars_overlay_alpha = 0.0
nebula_alpha = 0.0
planet_alpha = 1.0
planet_scale = 8.0
planet_fade_in = 2.0
asteroids_back_enter = true
asteroids_front_enter = true
cloud_1_alpha = 0.5
cloud_2_alpha = 0.7
cloud_3_alpha = 0.85
cloud_4_alpha = 1.0
clouds_appear_fraction = 0.6
surface_alpha = 0.0
cloud_4_peel_start = -1.0
cloud_3_peel_start = -1.0
cloud_2_peel_start = -1.0
cloud_1_peel_start = -1.0
surface_appear_start = -1.0
```

- [ ] **Step 4: Write `phase_cloud_descent.tres`**

Planet fades (already at 0 via transition), space already 0. Clouds peel in staggered order; surface appears after L4 peel.

The **transition_in for this section is 2 s** (quick snap to full clouds). The peel timers fire after section start, independently:
- L4 peels at t = 10 s (3 s duration)
- L3 peels at t = 25 s (5 s duration)
- L2 peels at t = 40 s (5 s duration)
- L1 peels at t = 40 s (5 s duration)
- Surface appears at t = 12 s (10 s duration)

```
[gd_resource type="BackgroundPhase" script_class="BackgroundPhase" load_steps=2 format=3]

[ext_resource type="Script" path="res://global/resources/levels/background_phase.gd" id="1_script"]

[resource]
script = ExtResource("1_script")
phase_name = &"cloud_descent"
stars_base_alpha = 0.0
stars_overlay_alpha = 0.0
nebula_alpha = 0.0
planet_alpha = 0.0
planet_scale = 8.0
planet_fade_in = 0.0
asteroids_back_enter = false
asteroids_front_enter = false
cloud_1_alpha = 0.0
cloud_2_alpha = 0.0
cloud_3_alpha = 0.0
cloud_4_alpha = 0.0
clouds_appear_fraction = 0.0
surface_alpha = 1.0
cloud_4_peel_start = 10.0
cloud_4_peel_duration = 3.0
cloud_3_peel_start = 25.0
cloud_3_peel_duration = 5.0
cloud_2_peel_start = 40.0
cloud_2_peel_duration = 5.0
cloud_1_peel_start = 40.0
cloud_1_peel_duration = 5.0
cloud_peel_scale = 4.0
surface_appear_start = 12.0
surface_appear_duration = 10.0
```

- [ ] **Step 5: Verify in editor**

Navigate to `assault/scenes/levels/phases/` in the FileSystem dock. Double-click each `.tres`. Inspector should show all properties with the values above, no errors.

- [ ] **Step 6: Commit**

```bash
git add assault/scenes/levels/phases/
git commit -m "feat: phase .tres resources for deep_space, planet_approach, cloud_descent"
```

---

## Task 7: Create `level_1_director.gd`

**Files:**
- Create: `assault/scenes/levels/level_1_director.gd`

Replaces `level_1_waves.gd`. Builds three sections via `WaveBuilder`, registers them on `LevelDirector`, listens for `level_complete`.

- [ ] **Step 1: Write the file**

```gdscript
## Level 1 — section definitions.
## Replaces level_1_waves.gd.
extends Node

@export var level_director: LevelDirector
@export var wave_manager:   WaveManager

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS

	print("[LEVEL] Level 1 — building sections")

	var existing := get_tree().root.get_node_or_null("HUD")
	if existing:
		existing.queue_free()
	get_tree().root.call_deferred(
		"add_child", preload("res://assault/scenes/gui/hud.tscn").instantiate()
	)

	var b := WaveBuilder.new()
	var L := b.LEFT
	var R := b.RIGHT

	# ── Phases ────────────────────────────────────────────────────────────────
	var phase_space  := preload("res://assault/scenes/levels/phases/phase_deep_space.tres")       as BackgroundPhase
	var phase_planet := preload("res://assault/scenes/levels/phases/phase_planet_approach.tres")  as BackgroundPhase
	var phase_clouds := preload("res://assault/scenes/levels/phases/phase_cloud_descent.tres")    as BackgroundPhase

	# ── Section 1: Deep Space (30 s) ──────────────────────────────────────────
	var s1 := LevelSection.new()
	s1.section_name          = &"deep_space"
	s1.background_phase      = phase_space
	s1.transition_in_duration = 0.0          # instant — this is the starting state
	s1.end_condition         = LevelSection.EndCondition.DURATION
	s1.duration              = 30.0
	s1.waves = b.level("s1", [
		b.wave(2.0, [
			b.fighter().at(-150, -150).move(b.straight(120)).delay(0.5)
				.formation(b.v_formation(5)).shoot_forward(),
		]),
		b.wave(5.0, [
			b.fighter().at(220, -150).move(b.u_sweep(420, 600, 9)).delay(0.5)
				.free_after(10).formation(b.v_formation(3)).shoot_forward(),
		]),
		b.wave(8.0, [
			b.fighter().at(300, -200).move(b.straight(200, -PI/3.6))
				.formation(b.diagonal_formation(5, 30, 35)).shoot_forward(),
			b.ally().at(0, 180).move(b.straight(140, PI)).delay(0.2),
		]),
		b.wave(14.0, [
			b.fighter().at(-300, -200).move(b.straight(200, PI/3.6))
				.formation(b.diagonal_formation(5, -30, 35)).shoot_forward(),
		]),
		b.wave(20.0, [
			b.fighter().at( 220, -150).move(b.u_sweep( 180, 300, 4)).delay(0.5).free_after(5).shoot_forward(),
			b.fighter().at(-220, -150).move(b.u_sweep(-180, 300, 4)).delay(0.5).free_after(5).shoot_forward(),
		]),
		b.wave(22.0, [
			b.drone().at(-50, -180).move(b.sine(140, 45)),
			b.drone().at(  0, -180).move(b.sine(140, 45)),
			b.drone().at( 50, -180).move(b.sine(140, 45)),
			b.drone().at( 25, -165).move(b.sine(140, 45)).delay(0.2),
		]),
		b.wave(26.0, [
			b.big_asteroid().at(-140, -180).move(b.straight(210)),
			b.big_asteroid().at( 190, -180).move(b.straight(260)).delay(0.7),
			b.big_asteroid().at(  90, -180).move(b.straight(230)).delay(1.0),
			b.big_asteroid().at( 160, -180).move(b.straight(210)).delay(1.6),
			b.big_asteroid().at(-150, -180).move(b.straight(260)).delay(1.6),
			b.big_asteroid().at(  10, -180).move(b.straight(210)).delay(1.0),
		]),
	]).waves

	# ── Section 2: Planet Approach (110 s cinematic) ──────────────────────────
	var s2 := LevelSection.new()
	s2.section_name          = &"planet_approach"
	s2.background_phase      = phase_planet
	s2.transition_in_duration = 110.0       # planet grows over the entire section
	s2.end_condition         = LevelSection.EndCondition.DURATION
	s2.duration              = 110.0
	s2.waves                 = []

	# ── Section 3: Cloud Descent (until enemies cleared) ──────────────────────
	# trigger_time = 0.0  → allies arrive immediately when this section starts.
	# trigger_time = 50.0 → gunship + escort arrive 50 s into descent.
	var s3 := LevelSection.new()
	s3.section_name          = &"cloud_descent"
	s3.background_phase      = phase_clouds
	s3.transition_in_duration = 2.0        # quick snap to full-cloud state
	s3.end_condition         = LevelSection.EndCondition.ENEMIES_CLEARED
	s3.waves = b.level("s3", [
		b.wave(0.0, [
			b.ally().at(  0, 180).move(b.straight(160, PI)),
			b.ally().at(-40,   0).move(b.straight(140, PI - 0.18)).delay(0.2),
			b.ally().at( 40,   0).move(b.straight(140, PI + 0.18)).delay(0.2),
			b.ally().at(-80, 180).move(b.straight(125, PI - 0.32)).delay(0.4),
			b.ally().at( 80, 180).move(b.straight(125, PI + 0.32)).delay(0.4),
		]),
		b.wave(50.0, [
			b.gunship().at(  0, -150).move(b.straight(35)),
			b.fighter().at(-50, -150).move(b.arc(L, 120, 4.0)).delay(0.8).free_after(4.0),
			b.fighter().at(  0, -150).move(b.straight(80))    .delay(0.8),
			b.fighter().at( 50, -150).move(b.arc(R, 120, 4.0)).delay(0.8).free_after(4.0),
		]),
	]).waves

	# ── Register + start ─────────────────────────────────────────────────────
	level_director.add_section(s1)
	level_director.add_section(s2)
	level_director.add_section(s3)
	level_director.level_complete.connect(_on_level_complete)
	level_director.start()


func _on_level_complete() -> void:
	print("[LEVEL] Level complete — post-battle dialog")

	await DialogPlayer.play(preload("res://dialog/scripts/level1_debrief.tres"))

	LevelExitCutscene.go_to_hub = MissionState.is_complete(1)
	MissionState.complete(1, 1)

	var hud := get_tree().root.get_node_or_null("HUD")
	if hud:
		hud.queue_free()

	get_tree().change_scene_to_file("res://cutscenes/level_exit/level_exit_cutscene.tscn")
```

- [ ] **Step 2: Verify parse — no errors in Godot Output**

- [ ] **Step 3: Commit**

```bash
git add assault/scenes/levels/level_1_director.gd
git commit -m "feat: level_1_director.gd — 3 sections with section-relative wave timing"
```

---

## Task 8: Wire in `level_1.tscn` and Clean Up

**Files:**
- Modify: `assault/scenes/levels/level_1.tscn`
- Delete: `assault/scenes/levels/level_1_waves.gd`

- [ ] **Step 1: Read the current tscn to find existing ext_resource ids**

Open `assault/scenes/levels/level_1.tscn` in a text editor. Note the `id=` value on:
- The `level_1_waves.gd` ext_resource (e.g. `id="12_waves"`) — we'll change its path.
- The `WaveManager` ext_resource (needed for node_paths).
- The `Level1Background` instance ext_resource.

- [ ] **Step 2: Add LevelDirector script ext_resource**

Add one line with the next available id (e.g. `"15_director"`) alongside the other ext_resources at the top:

```
[ext_resource type="Script" path="res://assault/scenes/systems/level_director/level_director.gd" id="15_director"]
```

- [ ] **Step 3: Update the LevelWaves script path**

Find the line:
```
[ext_resource type="Script" ... path="res://assault/scenes/levels/level_1_waves.gd" id="12_waves"]
```
Change the path:
```
[ext_resource type="Script" path="res://assault/scenes/levels/level_1_director.gd" id="12_waves"]
```

- [ ] **Step 4: Update the LevelWaves node block**

Find the node block for `LevelWaves`. Replace it so it exports `level_director` + `wave_manager`:

```
[node name="LevelDirectorConfig" type="Node" parent="." node_paths=PackedStringArray("level_director", "wave_manager")]
script = ExtResource("12_waves")
level_director = NodePath("../LevelDirector")
wave_manager = NodePath("../WaveManager")
```

(Keep `unique_id=...` if one existed on the original node.)

- [ ] **Step 5: Add LevelDirector node before LevelDirectorConfig**

Insert this block immediately before the `LevelDirectorConfig` node:

```
[node name="LevelDirector" type="Node" parent="." node_paths=PackedStringArray("background", "wave_manager")]
script = ExtResource("15_director")
background = NodePath("../Level1Background")
wave_manager = NodePath("../WaveManager")
```

- [ ] **Step 6: Run the game — full end-to-end verification**

Press F5. Watch Output and the game window. Expected sequence:

```
[LEVEL] Level 1 — building sections
[LevelDirector] Section 0: 'deep_space'  end=DURATION  transition_in=0.0 s
[Background] transition_to: deep_space  over 0.0 s
[WaveManager] Loaded section — 7 waves
[Wave 0] TRIGGERED at 2.0s ...   ← fighters
[Wave 1] TRIGGERED at 5.0s ...
...
[Wave 6] TRIGGERED at 26.0s ...  ← big asteroids
[LevelDirector] Section 1: 'planet_approach'  end=DURATION  transition_in=110.0 s
[Background] transition_to: planet_approach  over 110.0 s
[WaveManager] Loaded section — 0 waves
```

*(110 s later)*

```
[LevelDirector] Section 2: 'cloud_descent'  end=ENEMIES_CLEARED  transition_in=2.0 s
[Background] transition_to: cloud_descent  over 2.0 s
[WaveManager] Loaded section — 2 waves
[Wave 0] TRIGGERED at 0.0s ...   ← allies
[Wave 1] TRIGGERED at 50.0s ...  ← gunship
[LevelDirector] Enemies cleared — ...
[LEVEL] Level complete — post-battle dialog
```

**Visually verify:**
- Deep space: stars + nebula scrolling. ✓
- After 30 s: planet begins growing slowly from top edge; background asteroids enter from top. ✓
- Through approach: space layers fade to black; clouds materialise in final 44 s. ✓
- Cloud descent: clouds snap to full; L4 peels at 10 s, L3 at 25 s, L1+L2 at 40 s; surface fades in from 12 s. ✓
- No visual jump between sections. ✓

- [ ] **Step 7: Delete old files**

```bash
git rm assault/scenes/levels/level_1_waves.gd
git rm assault/scenes/levels/level_1_waves.gd.uid
```

- [ ] **Step 8: Final commit**

```bash
git add assault/scenes/levels/level_1.tscn
git commit -m "feat: wire LevelDirector into level_1.tscn; remove level_1_waves.gd — section-based architecture complete"
```

---

## Verification Checklist

| Check | How to verify |
|-------|--------------|
| Stars + nebula scroll from frame 1 | Run level, watch immediately |
| Combat waves fire at 2, 5, 8, 14, 20, 22, 26 s | Output panel |
| Planet appears at ~30 s and grows slowly | Watch top edge of screen |
| Asteroid textures enter from top during planet approach | Watch screen at ~30 s |
| Space layers fade as planet fills | Stars should be gone by ~120 s |
| Clouds appear in last 44 s of approach (~96-140 s) | Watch for cloud layers |
| Cloud descent: quick snap to full clouds | Watch at 140 s mark |
| L4 peels at 10 s (descent-relative), L3 at 25 s, etc. | Watch cloud layers dissolve |
| Surface fades in starting 12 s into descent | Ground texture appears |
| Allies arrive immediately at cloud descent start | Check first wave trigger |
| Gunship + escort arrive 50 s into descent | Check second wave trigger |
| Post-battle dialog plays after enemies clear | Debrief dialog appears |
| Changing `s2.duration` to 5 (for testing) advances section fast | Easy to test and revert |

---

## Self-Review

**Design correctness:**
- ✅ `BackgroundPhase` is a pure state snapshot — alphas, scale, speed, flags
- ✅ `Level1Background` is a passive renderer — `_apply()` reads only state vars, no `_elapsed` math
- ✅ All transitions are Tweens — changing `transition_in_duration` changes the look without touching any other value
- ✅ Cloud peel is section-relative timers, independent from the main state tween
- ✅ Asteroid alpha tracks `_alpha_stars_base` — fades naturally with space layers
- ✅ Wave times are section-relative — reordering sections doesn't renumber anything

**Type consistency:**
- `BackgroundPhase` used consistently: created in `.tres`, loaded in `level_1_director.gd`, consumed in `Level1Background.transition_to(phase: BackgroundPhase, ...)`
- `LevelSection.waves: Array[WaveResource]` matches `WaveManager.load_section(waves: Array[WaveResource])`
- `b.level(...).waves` returns `Array[WaveResource]` — correct extraction

**Known simplifications vs original code:**
- Planet scale tween uses `EASE_IN CUBIC` (Godot built-in) instead of Godot's `ease(t, 3.0)` — visually very similar
- Cloud alpha tween uses `.set_delay(clouds_delay)` — matches original `smoothstep(0.6, 1.0, approach_t)` start point
- Background asteroid textures now enter at section 2 start (30 s) instead of 23 s — slightly later but more coherent (you're in the asteroid zone as you approach the planet)
