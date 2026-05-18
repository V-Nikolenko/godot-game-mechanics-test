## Level1Background — space approach, atmospheric descent, cloud peel sequence.
##
## ── Timeline ─────────────────────────────────────────────────────────────────
##  0 → approach_duration         space + planet disc grows; clouds fade in
##  +0   to +cloud_4_dissolve_start    above all 4 cloud layers, ground hidden
##  +cloud_4_dissolve_start             layer 4 peels away (scales up + fades)
##  +surface_appear_start               ground (surface) starts fading in
##  +cloud_3_dissolve_start             layer 3 peels away — ground visible
##  +cloud_12_dissolve_start            layers 1 & 2 peel away together
##  end → only the planet surface scrolling beneath the player
##
## ── Z-ordering (CanvasLayer indices, low = back) ─────────────────────────────
##   SpaceLayer   -10  stars
##   PlanetLayer   -8  approaching planet disc
##   SurfaceLayer  -7  planet ground — behind clouds
##   CloudsLayer   -6  sky base + 4 cloud parallax layers
## ─────────────────────────────────────────────────────────────────────────────
class_name Level1Background
extends Node

# ── Textures ──────────────────────────────────────────────────────────────────
@export var space_texture:   Texture2D = preload("res://assault/assets/sprites/ui/space_bg.png")
@export var planet_texture:  Texture2D = preload("res://assault/assets/sprites/ui/planet_bg.png")
@export var surface_texture: Texture2D = preload("res://assault/assets/sprites/ui/surface_bg.png")

@export_group("Cloud Layer Textures")
@export var cloud_1_texture: Texture2D = preload("res://assault/assets/sprites/ui/clouds_bg_layer_1.png")
@export var cloud_2_texture: Texture2D = preload("res://assault/assets/sprites/ui/clouds_bg_layer_2.png")
@export var cloud_3_texture: Texture2D = preload("res://assault/assets/sprites/ui/clouds_bg_layer_3.png")
@export var cloud_4_texture: Texture2D = preload("res://assault/assets/sprites/ui/clouds_bg_layer_4.png")

# ── Approach (space → atmosphere) ─────────────────────────────────────────────
@export_group("Approach Timing")
## Seconds from start until clouds are fully in and the descent phase begins.
@export var approach_duration: float = 25.0

@export_group("Phase Thresholds (0 – 1 of approach)")
@export_range(0.0, 1.0, 0.01) var planet_grow_start:  float = 0.35
@export_range(0.0, 1.0, 0.01) var clouds_fade_start:  float = 0.70

# ── Descent (cloud peel sequence, seconds after approach completes) ──────────
@export_group("Descent Timing (seconds after approach)")
@export var cloud_4_dissolve_start:  float = 10.0   ## Layer 4 (closest) peels away
@export var cloud_3_dissolve_start:  float = 25.0   ## Layer 3 peels away
@export var cloud_12_dissolve_start: float = 40.0   ## Layers 1 & 2 peel away together
@export var cloud_dissolve_duration: float =  5.0   ## How long each peel animation lasts
@export var cloud_dissolve_scale:    float =  4.0   ## Final scale of a dissolving layer

@export var surface_appear_start:    float = 12.0   ## Ground starts fading in (during layer-4 peel)
@export var surface_appear_duration: float = 10.0   ## Ground fade-in length

# ── Planet motion ─────────────────────────────────────────────────────────────
@export_group("Planet Motion")
@export var planet_y_far:       float = -130.0
@export var planet_y_close:     float =   70.0
@export var planet_scale_far:   float =    0.08
@export var planet_scale_close: float =   14.0

# ── Parallax speeds ───────────────────────────────────────────────────────────
@export_group("Parallax Speeds (px / s)")
@export var speed_stars_far:  float =  6.0
@export var speed_stars_near: float = 18.0
@export var speed_planet:     float = 10.0
@export var speed_surface:    float = 35.0

@export_group("Cloud Layer Speeds (px / s)")
@export var speed_cloud_1: float = 10.0   ## Wispy cirrus      — slowest
@export var speed_cloud_2: float = 25.0   ## Scattered cumulus
@export var speed_cloud_3: float = 50.0   ## Dense cloud bank
@export var speed_cloud_4: float = 80.0   ## Foreground billow — fastest (closest)

# ── Scene nodes ───────────────────────────────────────────────────────────────
@onready var _far_a:    TextureRect = $SpaceLayer/FarStars_A
@onready var _far_b:    TextureRect = $SpaceLayer/FarStars_B
@onready var _near_a:   TextureRect = $SpaceLayer/NearStars_A
@onready var _near_b:   TextureRect = $SpaceLayer/NearStars_B

@onready var _planet:   Sprite2D    = $PlanetLayer/Planet

@onready var _surface_a: TextureRect = $SurfaceLayer/Surface_A
@onready var _surface_b: TextureRect = $SurfaceLayer/Surface_B

@onready var _c1_a:     TextureRect = $CloudsLayer/Layer1_A
@onready var _c1_b:     TextureRect = $CloudsLayer/Layer1_B
@onready var _c2_a:     TextureRect = $CloudsLayer/Layer2_A
@onready var _c2_b:     TextureRect = $CloudsLayer/Layer2_B
@onready var _c3_a:     TextureRect = $CloudsLayer/Layer3_A
@onready var _c3_b:     TextureRect = $CloudsLayer/Layer3_B
@onready var _c4_a:     TextureRect = $CloudsLayer/Layer4_A
@onready var _c4_b:     TextureRect = $CloudsLayer/Layer4_B

# ── Runtime state ─────────────────────────────────────────────────────────────
var _elapsed:        float = 0.0
var _scroll_far:     float = 0.0
var _scroll_near:    float = 0.0
var _scroll_planet:  float = 0.0
var _scroll_cloud_1: float = 0.0
var _scroll_cloud_2: float = 0.0
var _scroll_cloud_3: float = 0.0
var _scroll_cloud_4: float = 0.0
var _scroll_surface: float = 0.0

# ── Setup ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	var screen := get_viewport().get_visible_rect().size

	# Stars
	_setup_tile_pair(_far_a,  _far_b,  screen, space_texture)
	_setup_tile_pair(_near_a, _near_b, screen, space_texture)
	_near_a.self_modulate.a = 0.5
	_near_b.self_modulate.a = 0.5

	# Planet disc
	_planet.texture        = planet_texture
	_planet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_planet.position       = Vector2(screen.x * 0.5, screen.y * 0.5 + planet_y_far)
	_planet.scale          = Vector2.ONE * planet_scale_far

	# Cloud layers + surface
	_setup_tile_pair(_c1_a, _c1_b, screen, cloud_1_texture)
	_setup_tile_pair(_c2_a, _c2_b, screen, cloud_2_texture)
	_setup_tile_pair(_c3_a, _c3_b, screen, cloud_3_texture)
	_setup_tile_pair(_c4_a, _c4_b, screen, cloud_4_texture)
	_setup_tile_pair(_surface_a, _surface_b, screen, surface_texture)

	_apply(screen)

# ── Per-frame ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_elapsed        += delta
	_scroll_far     += delta * speed_stars_far
	_scroll_near    += delta * speed_stars_near
	_scroll_planet  += delta * speed_planet
	_scroll_cloud_1 += delta * speed_cloud_1
	_scroll_cloud_2 += delta * speed_cloud_2
	_scroll_cloud_3 += delta * speed_cloud_3
	_scroll_cloud_4 += delta * speed_cloud_4
	_scroll_surface += delta * speed_surface

	_apply(get_viewport().get_visible_rect().size)

func _apply(screen: Vector2) -> void:
	# ── Approach progress (0 → 1) ────────────────────────────────────────────
	var approach_t := clampf(_elapsed / approach_duration, 0.0, 1.0)

	# Stars — scroll always; fade out as clouds fade in
	_scroll_pair(_far_a,  _far_b,  _scroll_far)
	_scroll_pair(_near_a, _near_b, _scroll_near)

	# Planet disc — drifts down + grows during approach, fades as clouds arrive
	var planet_y := lerpf(planet_y_far, planet_y_close, ease(approach_t, 2.0))
	var drift    := fmod(_scroll_planet, screen.y)
	_planet.position = Vector2(screen.x * 0.5, screen.y * 0.5 + planet_y + drift)

	var grow_t := clampf((approach_t - planet_grow_start) / (1.0 - planet_grow_start), 0.0, 1.0)
	_planet.scale = Vector2.ONE * lerpf(planet_scale_far, planet_scale_close, ease(grow_t, 3.0))

	# Clouds fade in across the tail of the approach
	var clouds_in := smoothstep(clouds_fade_start, 1.0, approach_t)
	var space_t   := 1.0 - clouds_in
	_far_a.modulate.a  = space_t;  _far_b.modulate.a  = space_t
	_near_a.modulate.a = space_t;  _near_b.modulate.a = space_t
	_planet.modulate.a = space_t

	# ── Descent (seconds after approach completes) ──────────────────────────
	var descent_t := _elapsed - approach_duration

	var l4_t  := _peel(descent_t, cloud_4_dissolve_start,  cloud_dissolve_duration)
	var l3_t  := _peel(descent_t, cloud_3_dissolve_start,  cloud_dissolve_duration)
	var l12_t := _peel(descent_t, cloud_12_dissolve_start, cloud_dissolve_duration)

	# Cloud layers — each peels independently (alpha goes to 0, scale grows)
	_apply_cloud_layer(_c1_a, _c1_b, screen, _scroll_cloud_1, clouds_in * 0.50, l12_t)
	_apply_cloud_layer(_c2_a, _c2_b, screen, _scroll_cloud_2, clouds_in * 0.70, l12_t)
	_apply_cloud_layer(_c3_a, _c3_b, screen, _scroll_cloud_3, clouds_in * 0.85, l3_t)
	_apply_cloud_layer(_c4_a, _c4_b, screen, _scroll_cloud_4, clouds_in * 1.00, l4_t)

	# Surface — fades in during the layer-4 peel, stays scrolling forever after
	var surf_t := clampf((descent_t - surface_appear_start) / surface_appear_duration, 0.0, 1.0)
	_scroll_pair(_surface_a, _surface_b, _scroll_surface)
	_surface_a.modulate.a = surf_t
	_surface_b.modulate.a = surf_t

# ── Helpers ───────────────────────────────────────────────────────────────────

## Returns 0 before [start], ramps to 1 over [duration], stays at 1 after.
func _peel(now: float, start: float, duration: float) -> float:
	if duration <= 0.0:
		return 1.0 if now >= start else 0.0
	return clampf((now - start) / duration, 0.0, 1.0)

## Applies scroll + dissolve animation (alpha fade + scale-up around screen
## centre) to a parallax tile pair. `peel_t` ∈ [0,1]: 0 = full layer, 1 = gone.
func _apply_cloud_layer(a: TextureRect, b: TextureRect, screen: Vector2,
		scroll: float, base_alpha: float, peel_t: float) -> void:
	_scroll_pair(a, b, scroll)

	var alpha := base_alpha * (1.0 - peel_t)
	a.modulate.a = alpha
	b.modulate.a = alpha

	var sf := lerpf(1.0, cloud_dissolve_scale, ease(peel_t, 2.0))
	# pivot_offset is in rect-local coords. To scale around the screen centre
	# we offset by (screen/2 − tile.position) so the effective world pivot
	# (position + pivot_offset) lands on the screen centre.
	a.pivot_offset = screen * 0.5 - a.position
	b.pivot_offset = screen * 0.5 - b.position
	a.scale = Vector2.ONE * sf
	b.scale = Vector2.ONE * sf

## Sizes each tile to a whole multiple of the texture height that covers the
## screen. This is what fixes the "jumping" — the wrap interval is the tile
## height, which is itself a whole multiple of the texture, so the pattern at
## the wrap moment is always continuous.
func _setup_tile_pair(a: TextureRect, b: TextureRect, screen: Vector2, tex: Texture2D) -> void:
	var tex_h: float = tex.get_height()
	var n_tiles: int = maxi(1, int(ceil(screen.y / tex_h)))
	var tile_h: float = tex_h * n_tiles
	for tile: TextureRect in [a, b]:
		tile.texture        = tex
		tile.size           = Vector2(screen.x, tile_h)
		tile.stretch_mode   = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.pivot_offset   = Vector2.ZERO
		tile.scale          = Vector2.ONE

func _scroll_pair(a: TextureRect, b: TextureRect, scroll: float) -> void:
	var tile_h: float = a.size.y
	if tile_h <= 0.0:
		return
	var offset: float = fmod(scroll, tile_h)
	a.position = Vector2(0.0, offset)
	b.position = Vector2(0.0, offset - tile_h)
