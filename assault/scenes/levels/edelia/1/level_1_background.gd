## Level1Background — deep-space drift, planet approach, atmospheric descent.
##
## Exports are organised by layer, in the order layers first take the stage:
##
##   1. Stars Base       (always visible during space phase)
##   2. Stars Overlay    (always visible during space phase)
##   3. Nebula           (always visible during space phase, dim)
##   4. Asteroids Back   (one-shot pass before the planet appears)
##   5. Asteroids Front  (one-shot pass before the planet appears)
##   6. Planet           (deep-space delay → grows from top → fades to clouds)
##   7. Cloud Layer 1    (peels late)
##   8. Cloud Layer 2    (peels late)
##   9. Cloud Layer 3    (peels mid)
##  10. Cloud Layer 4    (peels first)
##  11. Surface          (planet ground, fades in behind the clouds)
##
## ── Z-ordering (CanvasLayer indices, low = back) ─────────────────────────────
##   SpaceLayer   -10  stars + nebula + asteroid section
##   PlanetLayer   -8  approaching planet disc
##   SurfaceLayer  -7  planet ground — behind clouds
##   CloudsLayer   -6  the 4 cloud parallax layers
## ─────────────────────────────────────────────────────────────────────────────
class_name Level1Background
extends BackgroundController

# ─────────────────────────────────────────────────────────────────────────────
# 1. STARS BASE LAYER
# ─────────────────────────────────────────────────────────────────────────────
@export_group("1. Stars Base Layer")
@export var stars_base_texture: Texture2D = preload("res://assault/assets/sprites/missions/edelia/1/space_bg_stars_layer_1.png")
@export var speed_stars_base:   float = 4.0   ## px / s, slowest = most distant

# ─────────────────────────────────────────────────────────────────────────────
# 2. STARS OVERLAY LAYER
# ─────────────────────────────────────────────────────────────────────────────
@export_group("2. Stars Overlay Layer")
@export var stars_overlay_texture: Texture2D = preload("res://assault/assets/sprites/missions/edelia/1/space_bg_stars_layer_2.png")
@export var speed_stars_overlay:   float = 12.0

# ─────────────────────────────────────────────────────────────────────────────
# 3. NEBULA LAYER
# ─────────────────────────────────────────────────────────────────────────────
@export_group("3. Nebula Layer")
@export var nebula_texture: Texture2D = preload("res://assault/assets/sprites/missions/edelia/1/space_bg_nebula_layer_1.png")
@export var speed_nebula:   float = 2.0
## Constant alpha for the nebula — kept dim so it reads as distant gas.
@export_range(0.0, 1.0, 0.01) var nebula_alpha: float = 0.08

# ─────────────────────────────────────────────────────────────────────────────
# 4. ASTEROIDS BACK LAYER  (one-shot pass — enters from top, exits at bottom)
# ─────────────────────────────────────────────────────────────────────────────
@export_group("4. Asteroids Back Layer")
@export var asteroids_back_texture: Texture2D = preload("res://assault/assets/sprites/missions/edelia/1/space_bg_asteroids_layer_1.png")
@export var speed_asteroids_back:   float = 30.0
## Seconds from level start when this layer's bottom edge enters the screen.
@export var asteroids_back_start:   float = 5.0
## Optional force-hide time (seconds from level start). 0 = let it exit naturally
## once it has scrolled past the bottom edge.
@export var asteroids_back_stop:    float = 0.0

# ─────────────────────────────────────────────────────────────────────────────
# 5. ASTEROIDS FRONT LAYER  (one-shot pass — enters from top, exits at bottom)
# ─────────────────────────────────────────────────────────────────────────────
@export_group("5. Asteroids Front Layer")
@export var asteroids_front_texture: Texture2D = preload("res://assault/assets/sprites/missions/edelia/1/space_bg_asteroids_layer_2.png")
@export var speed_asteroids_front:   float = 60.0
@export var asteroids_front_start:   float = 5.0
@export var asteroids_front_stop:    float = 0.0

# ─────────────────────────────────────────────────────────────────────────────
# 6. PLANET  (deep-space delay → grows from top edge → fades behind clouds)
# ─────────────────────────────────────────────────────────────────────────────
@export_group("6. Planet")
@export var planet_texture: Texture2D = preload("res://assault/assets/sprites/missions/edelia/1/planet_bg.png")
## Seconds of pure space before the planet first appears at the top edge.
@export var deep_space_duration: float = 30.0
## Seconds the planet takes to grow from a corner-at-top into atmosphere.
@export var approach_duration:   float = 60.0
## Seconds the planet takes to fade in once it first appears.
@export var planet_fade_in:      float = 2.0
## Fraction of [approach_duration] over which the planet fades out once the
## clouds start fading in.  Smaller = sharper hand-off.
@export_range(0.0, 1.0, 0.01) var planet_fade_out_window: float = 0.10
## Vertical anchor for the planet centre (px).  Negative = above the top edge
## so only the bottom curve is ever visible.
@export var planet_y_anchor:        float = -25.0
## Scale when the planet first appears — a small corner at the top.
@export var planet_scale_appear:    float = 0.10
## Scale at the end of the approach — a wide curved horizon.
@export var planet_scale_atmosphere: float = 8.0

# ─────────────────────────────────────────────────────────────────────────────
# 7. CLOUD LAYER 1  (slowest, highest in the sky)
# ─────────────────────────────────────────────────────────────────────────────
@export_group("7. Cloud Layer 1")
@export var cloud_1_texture: Texture2D = preload("res://assault/assets/sprites/missions/edelia/1/clouds_bg_layer_1.png")
@export var speed_cloud_1:   float = 10.0
## Seconds AFTER the approach completes at which this layer starts to peel.
@export var cloud_1_dissolve_start:    float = 40.0
## Seconds this layer's peel animation lasts.
@export var cloud_1_dissolve_duration: float =  5.0

# ─────────────────────────────────────────────────────────────────────────────
# 8. CLOUD LAYER 2
# ─────────────────────────────────────────────────────────────────────────────
@export_group("8. Cloud Layer 2")
@export var cloud_2_texture: Texture2D = preload("res://assault/assets/sprites/missions/edelia/1/clouds_bg_layer_2.png")
@export var speed_cloud_2:   float = 25.0
@export var cloud_2_dissolve_start:    float = 40.0
@export var cloud_2_dissolve_duration: float =  5.0

# ─────────────────────────────────────────────────────────────────────────────
# 9. CLOUD LAYER 3
# ─────────────────────────────────────────────────────────────────────────────
@export_group("9. Cloud Layer 3")
@export var cloud_3_texture: Texture2D = preload("res://assault/assets/sprites/missions/edelia/1/clouds_bg_layer_3.png")
@export var speed_cloud_3:   float = 50.0
@export var cloud_3_dissolve_start:    float = 25.0
@export var cloud_3_dissolve_duration: float =  5.0

# ─────────────────────────────────────────────────────────────────────────────
# 10. CLOUD LAYER 4  (closest, fastest, peels first)
# ─────────────────────────────────────────────────────────────────────────────
@export_group("10. Cloud Layer 4")
@export var cloud_4_texture: Texture2D = preload("res://assault/assets/sprites/missions/edelia/1/clouds_bg_layer_4.png")
@export var speed_cloud_4:   float = 80.0
@export var cloud_4_dissolve_start:    float = 10.0
@export var cloud_4_dissolve_duration: float =  3.0

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDS — COMMON  (shared crossfade / peel animation parameters)
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Clouds — Common")
## Fraction of [approach_duration] at which the clouds start fading in over
## the planet (their entry point — peeling is timed per layer above).
@export_range(0.0, 1.0, 0.01) var clouds_fade_start: float = 0.60
## Final scale a peeling layer grows to before its alpha hits 0 (shared).
@export var cloud_dissolve_scale: float = 4.0

# ─────────────────────────────────────────────────────────────────────────────
# 11. SURFACE  (planet ground — fades in behind the clouds during descent)
# ─────────────────────────────────────────────────────────────────────────────
@export_group("11. Surface (Ground)")
@export var surface_texture: Texture2D = preload("res://assault/assets/sprites/missions/edelia/1//surface_bg.png")
@export var speed_surface:   float = 35.0
## Seconds after approach completes when the surface starts to fade in.
@export var surface_appear_start:    float = 12.0
@export var surface_appear_duration: float = 10.0

# ── Scene nodes ───────────────────────────────────────────────────────────────
@onready var _stars_base_a:      TextureRect = $SpaceLayer/StarsBase_A
@onready var _stars_base_b:      TextureRect = $SpaceLayer/StarsBase_B
@onready var _stars_overlay_a:   TextureRect = $SpaceLayer/StarsOverlay_A
@onready var _stars_overlay_b:   TextureRect = $SpaceLayer/StarsOverlay_B
@onready var _nebula_a:          TextureRect = $SpaceLayer/Nebula_A
@onready var _nebula_b:          TextureRect = $SpaceLayer/Nebula_B
@onready var _asteroids_back:    TextureRect = $SpaceLayer/AsteroidsBack
@onready var _asteroids_front:   TextureRect = $SpaceLayer/AsteroidsFront

@onready var _planet:    Sprite2D    = $PlanetLayer/Planet

@onready var _surface_a: TextureRect = $SurfaceLayer/Surface_A
@onready var _surface_b: TextureRect = $SurfaceLayer/Surface_B

@onready var _c1_a:      TextureRect = $CloudsLayer/Layer1_A
@onready var _c1_b:      TextureRect = $CloudsLayer/Layer1_B
@onready var _c2_a:      TextureRect = $CloudsLayer/Layer2_A
@onready var _c2_b:      TextureRect = $CloudsLayer/Layer2_B
@onready var _c3_a:      TextureRect = $CloudsLayer/Layer3_A
@onready var _c3_b:      TextureRect = $CloudsLayer/Layer3_B
@onready var _c4_a:      TextureRect = $CloudsLayer/Layer4_A
@onready var _c4_b:      TextureRect = $CloudsLayer/Layer4_B

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
var _asteroids_back_y:       float = 0.0
var _asteroids_back_active:  bool  = false
var _asteroids_front_y:      float = 0.0
var _asteroids_front_active: bool  = false

# ── Scroll accumulators ───────────────────────────────────────────────────────
var _scroll_stars_base:    float = 0.0
var _scroll_stars_overlay: float = 0.0
var _scroll_nebula:        float = 0.0
var _scroll_cloud_1:       float = 0.0
var _scroll_cloud_2:       float = 0.0
var _scroll_cloud_3:       float = 0.0
var _scroll_cloud_4:       float = 0.0
var _scroll_surface:       float = 0.0

# ── Setup ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	var screen := get_viewport().get_visible_rect().size

	# Space layers — stars (base + overlay), nebula
	_setup_tile_pair(_stars_base_a,    _stars_base_b,    screen, stars_base_texture)
	_setup_tile_pair(_stars_overlay_a, _stars_overlay_b, screen, stars_overlay_texture)
	_setup_tile_pair(_nebula_a,        _nebula_b,        screen, nebula_texture)

	# Asteroid layers — single rects (one-shot pass from top to bottom).
	_setup_single_rect(_asteroids_back,  screen, asteroids_back_texture)
	_setup_single_rect(_asteroids_front, screen, asteroids_front_texture)

	# Planet — anchored at the top edge, invisible until approach begins
	_planet.texture        = planet_texture
	_planet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_planet.position       = Vector2(screen.x * 0.5, planet_y_anchor)
	_planet.scale          = Vector2.ONE * planet_scale_appear
	_planet.modulate.a     = 0.0

	# Cloud layers + surface
	_setup_tile_pair(_c1_a, _c1_b, screen, cloud_1_texture)
	_setup_tile_pair(_c2_a, _c2_b, screen, cloud_2_texture)
	_setup_tile_pair(_c3_a, _c3_b, screen, cloud_3_texture)
	_setup_tile_pair(_c4_a, _c4_b, screen, cloud_4_texture)
	_setup_tile_pair(_surface_a, _surface_b, screen, surface_texture)

	_apply(screen)

# ── Per-frame ─────────────────────────────────────────────────────────────────

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

## Called by LevelDirector when a new section begins.
## Tweens all visual state variables from their current values toward [phase]
## over [duration] seconds. Cloud peel animations are scheduled as independent
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
		return

	# ── Parallel Tween ────────────────────────────────────────────────────────
	_transition_tween = create_tween().set_parallel(true)

	# Space layers — delayed when space_fade_start_fraction > 0 so stars hold
	# until the planet is large before the sky brightens.
	var space_delay := duration * phase.space_fade_start_fraction
	var space_dur   := maxf(duration - space_delay, 0.01)
	_transition_tween.tween_property(self, "_alpha_stars_base",    phase.stars_base_alpha,    space_dur).set_delay(space_delay)
	_transition_tween.tween_property(self, "_alpha_stars_overlay", phase.stars_overlay_alpha, space_dur).set_delay(space_delay)
	_transition_tween.tween_property(self, "_alpha_nebula",        phase.nebula_alpha,        space_dur).set_delay(space_delay)

	# Planet — scale tweens EASE_IN CUBIC; alpha fade-in is short
	_transition_tween.tween_property(self, "_planet_scale", phase.planet_scale, duration)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	var planet_fade_dur := minf(phase.planet_fade_in, duration)
	_transition_tween.tween_property(self, "_alpha_planet", phase.planet_alpha, planet_fade_dur)
	# Delayed fade-out — makes the planet disappear behind clouds during approach
	# rather than lingering at full opacity until the next section starts.
	if phase.planet_fade_out_start >= 0.0:
		_transition_tween.tween_property(self, "_alpha_planet", 0.0, phase.planet_fade_out_duration)\
			.set_delay(phase.planet_fade_out_start)

	# Cloud alphas — optionally delayed so clouds appear only in a later fraction
	var clouds_delay := duration * phase.clouds_appear_fraction
	var clouds_dur   := maxf(duration - clouds_delay, 0.01)

	# Only tween cloud alphas for layers NOT being peeled (peel timer handles those)
	var peeled: Array = []
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

	# Cloud peels — scheduled on the main tween so kill() cancels them when
	# transition_to() is called again.
	if phase.cloud_4_peel_start >= 0.0:
		_add_peel_to_tween(4, phase.cloud_4_peel_start, phase.cloud_4_peel_duration, phase.cloud_peel_scale)
	if phase.cloud_3_peel_start >= 0.0:
		_add_peel_to_tween(3, phase.cloud_3_peel_start, phase.cloud_3_peel_duration, phase.cloud_peel_scale)
	if phase.cloud_2_peel_start >= 0.0:
		_add_peel_to_tween(2, phase.cloud_2_peel_start, phase.cloud_2_peel_duration, phase.cloud_peel_scale)
	if phase.cloud_1_peel_start >= 0.0:
		_add_peel_to_tween(1, phase.cloud_1_peel_start, phase.cloud_1_peel_duration, phase.cloud_peel_scale)

	# Surface — use a straight alpha tween when no delayed appear is needed,
	# otherwise schedule the delayed appear on the main tween.
	if phase.surface_appear_start < 0.0:
		_transition_tween.tween_property(self, "_alpha_surface", phase.surface_alpha, duration)
	else:
		_transition_tween.tween_property(self, "_alpha_surface", 1.0, phase.surface_appear_duration)\
			.set_delay(phase.surface_appear_start)


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
		_asteroids_back.position   = Vector2((screen.x - _asteroids_back.size.x) * 0.5, _asteroids_back_y)
		_asteroids_back.modulate.a = _alpha_stars_base
	else:
		_asteroids_back.visible = false

	if _asteroids_front_active:
		_asteroids_front.visible    = true
		_asteroids_front.position   = Vector2((screen.x - _asteroids_front.size.x) * 0.5, _asteroids_front_y)
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

# ── Helpers ───────────────────────────────────────────────────────────────────

func _add_peel_to_tween(layer: int, delay: float, duration: float, target_scale: float) -> void:
	if not _transition_tween or not _transition_tween.is_valid():
		return
	var alpha_prop := "_alpha_cloud_%d" % layer
	var scale_prop := "_scale_cloud_%d" % layer
	_transition_tween.tween_property(self, alpha_prop, 0.0, duration).set_delay(delay)
	_transition_tween.tween_property(self, scale_prop, target_scale, duration)\
		.set_delay(delay)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


## Scroll + scale animation — scale_factor driven by Tween state variables.
func _apply_cloud_layer(a: TextureRect, b: TextureRect, screen: Vector2,
		scroll: float, base_alpha: float, scale_factor: float) -> void:
	_scroll_pair(a, b, scroll)
	a.modulate.a = base_alpha
	b.modulate.a = base_alpha
	a.pivot_offset = screen * 0.5 - a.position
	b.pivot_offset = screen * 0.5 - b.position
	a.scale = Vector2.ONE * scale_factor
	b.scale = Vector2.ONE * scale_factor

## One-shot rect (no vertical wrap) — used for the asteroid sweep.
func _setup_single_rect(rect: TextureRect, screen: Vector2, tex: Texture2D) -> void:
	rect.texture        = tex
	## Use the full texture width so wider-than-screen textures can be centred.
	rect.size           = Vector2(tex.get_width(), tex.get_height())
	rect.stretch_mode   = TextureRect.STRETCH_TILE
	rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	rect.pivot_offset   = Vector2.ZERO
	rect.scale          = Vector2.ONE
	# Start fully above the screen so it isn't visible until its start time.
	rect.position       = Vector2((screen.x - rect.size.x) * 0.5, -rect.size.y)

func _setup_tile_pair(a: TextureRect, b: TextureRect, screen: Vector2, tex: Texture2D) -> void:
	var tex_h: float = tex.get_height()
	var n_tiles: int = maxi(1, int(ceil(screen.y / tex_h)))
	var tile_h: float = tex_h * n_tiles
	for tile: TextureRect in [a, b]:
		tile.texture        = tex
		## Use the full texture width so wider-than-screen textures are centred
		## by _scroll_pair rather than clipped to the left edge.
		tile.size           = Vector2(tex.get_width(), tile_h)
		tile.stretch_mode   = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.pivot_offset   = Vector2.ZERO
		tile.scale          = Vector2.ONE

func _scroll_pair(a: TextureRect, b: TextureRect, scroll: float) -> void:
	var tile_h: float = a.size.y
	if tile_h <= 0.0:
		return
	## Centre the rect horizontally so textures wider than the screen
	## (e.g. 740 px on a 640 px canvas) extend equally on both sides.
	## x_pos = 0 for same-width textures; x_pos = -50 for 740 px textures.
	## arena_camera.gd shifts CanvasLayers by ±50 px to pin the background;
	## the 50 px overhang on each side absorbs that shift with no gaps.
	var screen_w: float = get_viewport().get_visible_rect().size.x
	var x_pos: float    = (screen_w - a.size.x) * 0.5
	var offset: float   = roundf(fmod(scroll, tile_h))
	a.position = Vector2(x_pos, offset)
	b.position = Vector2(x_pos, offset - tile_h)
