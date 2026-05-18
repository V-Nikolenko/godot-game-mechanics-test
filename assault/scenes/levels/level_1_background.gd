## Level1Background — deep-space drift, planet approach, atmospheric descent.
##
## ── Timeline ─────────────────────────────────────────────────────────────────
##  0           → deep_space_duration       only stars; planet is invisible
##  +0          → +approach_duration        planet appears as a corner at the
##                                          top of the screen and grows; near
##                                          the end the clouds fade in.
##  descent +0  → +cloud_4_dissolve_start   above all 4 cloud layers
##  +cloud_4_dissolve_start                 layer 4 peels away (scale + fade)
##  +surface_appear_start                   ground (surface) fades in behind
##  +cloud_3_dissolve_start                 layer 3 peels away
##  +cloud_12_dissolve_start                layers 1 & 2 peel away together
##  end → just the planet surface scrolling beneath the player
##
## ── Z-ordering (CanvasLayer indices, low = back) ─────────────────────────────
##   SpaceLayer   -10  stars
##   PlanetLayer   -8  approaching planet disc
##   SurfaceLayer  -7  planet ground — behind clouds
##   CloudsLayer   -6  the 4 cloud parallax layers
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
## Seconds of pure space before the planet first appears at the top edge.
@export var deep_space_duration: float = 30.0
## Seconds the planet takes to grow from a corner-at-top into atmosphere.
@export var approach_duration: float = 110.0
## Fraction of [approach_duration] at which the clouds start fading in.
@export_range(0.0, 1.0, 0.01) var clouds_fade_start: float = 0.60
## Seconds the planet takes to fade in once it first appears.
@export var planet_fade_in: float = 2.0
## Fraction of [approach_duration] over which the planet fades out once
## [clouds_fade_start] is reached. Smaller = sharper fade.
@export_range(0.0, 1.0, 0.01) var planet_fade_out_window: float = 0.10

@export_group("Planet Approach")
## Vertical screen-space anchor for the planet centre.  Negative = above the
## top edge, so only the bottom curve is ever visible.  The illusion of
## "flying toward" the planet comes from scale, not from moving it down.
@export var planet_y_anchor: float = -25.0
## Scale when the planet first appears — a small corner at the top.
@export var planet_scale_appear:     float = 0.10
## Scale at the end of the approach — a wide curved horizon, then clouds take over.
@export var planet_scale_atmosphere: float = 8.0

# ── Descent (cloud peel sequence, seconds after approach completes) ──────────
@export_group("Descent Timing (seconds after approach)")
@export var cloud_4_dissolve_start:  float = 10.0
@export var cloud_3_dissolve_start:  float = 25.0
@export var cloud_12_dissolve_start: float = 40.0
@export var cloud_dissolve_duration: float =  5.0
@export var cloud_dissolve_scale:    float =  4.0

@export var surface_appear_start:    float = 12.0
@export var surface_appear_duration: float = 10.0

# ── Parallax speeds ───────────────────────────────────────────────────────────
@export_group("Parallax Speeds (px / s)")
@export var speed_stars_far:  float =  6.0
@export var speed_stars_near: float = 18.0
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
	_elapsed        += delta
	_scroll_far     += delta * speed_stars_far
	_scroll_near    += delta * speed_stars_near
	_scroll_cloud_1 += delta * speed_cloud_1
	_scroll_cloud_2 += delta * speed_cloud_2
	_scroll_cloud_3 += delta * speed_cloud_3
	_scroll_cloud_4 += delta * speed_cloud_4
	_scroll_surface += delta * speed_surface

	_apply(get_viewport().get_visible_rect().size)

func _apply(screen: Vector2) -> void:
	# ── Phase clocks ────────────────────────────────────────────────────────
	# `approach_elapsed` < 0  → deep space (no planet)
	# 0 ≤ approach_elapsed ≤ approach_duration → planet is on screen, growing
	# approach_elapsed > approach_duration → descent phase begins
	var approach_elapsed := _elapsed - deep_space_duration
	var approach_t       := clampf(approach_elapsed / approach_duration, 0.0, 1.0)

	# Stars — always scroll
	_scroll_pair(_far_a,  _far_b,  _scroll_far)
	_scroll_pair(_near_a, _near_b, _scroll_near)

	# Planet — anchored at the top of the screen, scale grows over the approach.
	# Center is above the top edge so only the bottom curve is ever visible,
	# and as scale grows that bottom curve sweeps down across the view, giving
	# the impression of flying head-on into the planet.
	_planet.position = Vector2(screen.x * 0.5, planet_y_anchor)
	_planet.scale    = Vector2.ONE * lerpf(planet_scale_appear, planet_scale_atmosphere, ease(approach_t, 3.0))

	# Planet visibility:
	#   • invisible during deep space
	#   • fades in over `planet_fade_in` seconds once approach begins
	#   • fades back out as the clouds fade in at the tail end of approach
	var planet_in: float = 0.0
	if approach_elapsed > 0.0 and planet_fade_in > 0.0:
		planet_in = clampf(approach_elapsed / planet_fade_in, 0.0, 1.0)
	elif approach_elapsed > 0.0:
		planet_in = 1.0

	var clouds_in := smoothstep(clouds_fade_start, 1.0, approach_t)
	var space_t   := 1.0 - clouds_in

	# Planet fades out on its own (faster) curve once clouds start fading in.
	var planet_out := smoothstep(clouds_fade_start, clouds_fade_start + planet_fade_out_window, approach_t)

	_far_a.modulate.a  = space_t;  _far_b.modulate.a  = space_t
	_near_a.modulate.a = space_t;  _near_b.modulate.a = space_t
	_planet.modulate.a = planet_in * (1.0 - planet_out)

	# ── Descent (seconds after approach completes) ──────────────────────────
	var descent_t := approach_elapsed - approach_duration

	var l4_t  := _peel(descent_t, cloud_4_dissolve_start,  cloud_dissolve_duration)
	var l3_t  := _peel(descent_t, cloud_3_dissolve_start,  cloud_dissolve_duration)
	var l12_t := _peel(descent_t, cloud_12_dissolve_start, cloud_dissolve_duration)

	_apply_cloud_layer(_c1_a, _c1_b, screen, _scroll_cloud_1, clouds_in * 0.50, l12_t)
	_apply_cloud_layer(_c2_a, _c2_b, screen, _scroll_cloud_2, clouds_in * 0.70, l12_t)
	_apply_cloud_layer(_c3_a, _c3_b, screen, _scroll_cloud_3, clouds_in * 0.85, l3_t)
	_apply_cloud_layer(_c4_a, _c4_b, screen, _scroll_cloud_4, clouds_in * 1.00, l4_t)

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

## Scroll + dissolve animation (alpha fade + scale-up around screen centre).
## peel_t ∈ [0,1]: 0 = full layer, 1 = fully peeled.
func _apply_cloud_layer(a: TextureRect, b: TextureRect, screen: Vector2,
		scroll: float, base_alpha: float, peel_t: float) -> void:
	_scroll_pair(a, b, scroll)

	var alpha := base_alpha * (1.0 - peel_t)
	a.modulate.a = alpha
	b.modulate.a = alpha

	var sf := lerpf(1.0, cloud_dissolve_scale, ease(peel_t, 2.0))
	a.pivot_offset = screen * 0.5 - a.position
	b.pivot_offset = screen * 0.5 - b.position
	a.scale = Vector2.ONE * sf
	b.scale = Vector2.ONE * sf

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
