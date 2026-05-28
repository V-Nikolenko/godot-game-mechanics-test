# open_space/scenes/gui/mission_select_menu.gd
## Full-screen mission select overlay driven entirely by a PlanetConfigResource.
## Pauses the scene tree while open so the ship cannot move.
## Emits signals back to MissionTrigger.
class_name MissionSelectMenu
extends CanvasLayer

signal mission_confirmed(scene_path: String)
signal cancelled
## Fires whenever the cursor row changes so point highlights can sync.
signal cursor_changed(index: int)

const _ITEM_SCENE               := preload("res://open_space/scenes/mission_select_ui/mission_list_item.tscn")
## Active/selected point — brighter sprite shown when cursor is here.
const _POINT_TEXTURE_ACTIVE    := preload("res://open_space/assets/sprites/mission_select_ui/menu/menu_mission_select_point.png")
## Inactive/unselected point — dimmer sprite shown for all other points.
const _POINT_TEXTURE_INACTIVE  := preload("res://open_space/assets/sprites/mission_select_ui/menu/menu_mission_select_point_unselected.png")
## Blur shader applied to the planet and point sprites during navigation.
const _BLUR_SHADER              := preload("res://open_space/scenes/mission_select_ui/planet_motion_blur.gdshader")
## X offset from sprite center to the diamond; line endpoints anchor here.
const _POINT_LINE_ANCHOR       := Vector2(-15.0, 0.0)
## Position of the number label inside the right text-box area of the icon.
const _POINT_LABEL_OFFSET      := Vector2(6.0, -4.0)
const _POINT_LABEL_FONT_SIZE   := 5

const _ROW_STRIDE: float = 34.0

const _POINT_NORMAL   := Color.WHITE
const _POINT_SELECTED := Color(1.4, 1.4, 1.0)
const _POINT_LOCKED   := Color(0.45, 0.45, 0.45)

## Blur peak strength in texture-pixels (≈ screen-pixels / planet_scale).
## Raise for more dramatic smear, lower for subtlety.
const _BLUR_PEAK: float = 4.5

## Control wrapper that moves both the planet sprite and points together for panning.
@onready var _planet_container: Control  = $Planet
## Sprite2D inside the Control — animated for the zoom-in effect on open.
@onready var _planet_sprite:    Sprite2D = $Planet/Planet
## PointsContainer sibling of the sprite — animated for zoom, read for scale/centering.
@onready var _points_container: Node2D   = $Planet/PointsContainer
## Screen panel: name, description, mission image preview.
@onready var _central_screen:   Control  = $CentralScreen
@onready var _mission_preview:  Sprite2D = $CentralScreen/MissionImagePreview
@onready var _list_container:   Node2D   = $ListContainer
@onready var _cockpit:          Control  = $Cockpit
@onready var _hands:            Control  = $Hands
## SpaceShip container + dive sprite used in the confirm cinematic.
@onready var _ship_dive_in:     Sprite2D = $SpaceShip/ShipDiveIn
@onready var _name_label:       Label    = $CentralScreen/NameLabel
@onready var _class_label:      Label    = $CentralScreen/DescriptionLabel
@onready var _desc_label:       Label    = $CentralScreen/DescLabel

const _LINE_COLOR_UNLOCKED := Color(0.2, 0.85, 1.0)
const _LINE_COLOR_LOCKED   := Color(0.45, 0.45, 0.45)
const _LINE_WIDTH: float   = 1.5

var _config:        PlanetConfigResource   = null
var _items:         Array[MissionListItem] = []
var _points:        Array[Sprite2D]        = []
var _point_labels:  Array[Label]           = []
var _lines:         Array[Line2D]          = []
var _cursor:        int = 0

## Animation state — originals captured in _ready(), restored on close().
var _open_tween:        Tween          = null
var _planet_tween:      Tween          = null
var _blur_tween:        Tween          = null
## Single ShaderMaterial shared by the planet sprite and all point sprites.
## Changing one parameter updates the blur on all of them simultaneously.
var _blur_mat:          ShaderMaterial = null
var _orig_map_pos:      Vector2   ## _planet_container.position
var _orig_list_pos:     Vector2
var _orig_central_pos:  Vector2   ## _central_screen.position
var _orig_planet_scale: Vector2   ## _planet_sprite / _points_container original scale
## True from the moment the player confirms until the cinematic ends.
## Prevents a second confirm input from double-firing the sequence.
var _confirming:        bool = false

func _ready() -> void:
	_orig_map_pos         = _planet_container.position
	_orig_list_pos        = _list_container.position
	_orig_central_pos     = _central_screen.position
	_orig_planet_scale    = _planet_sprite.scale
	_ship_dive_in.visible = false   ## only shown during the confirm cinematic
	_setup_blur_material()

## Creates the shared blur ShaderMaterial and assigns it to the planet sprite.
## Point sprites receive the same material instance when built in open().
func _setup_blur_material() -> void:
	_blur_mat        = ShaderMaterial.new()
	_blur_mat.shader = _BLUR_SHADER
	_blur_mat.set_shader_parameter("blur_amount_px", 0.0)
	_blur_mat.set_shader_parameter("blur_dir", Vector2.RIGHT)
	_planet_sprite.material = _blur_mat

## Entry point called by MissionTrigger after adding this node to the tree.
func open(config: PlanetConfigResource) -> void:
	_config = config

	_planet_sprite.texture = config.sprite_texture
	_name_label.text       = config.display_name
	_class_label.text      = config.description
	_class_label.add_theme_font_size_override("font_size", config.description_font_size)

	## Build list items.
	for item: MissionListItem in _items:
		item.queue_free()
	_items.clear()

	for i: int in config.missions.size():
		var m: MissionConfigResource = config.missions[i]
		var locked: bool = _is_locked(m)
		var item := _ITEM_SCENE.instantiate() as MissionListItem
		_list_container.add_child(item)
		item.position = Vector2(93, 18 + i * _ROW_STRIDE)
		item.configure(m, locked)
		_items.append(item)

	## Build planet map points and connecting lines.
	for p: Sprite2D in _points:
		p.queue_free()
	_points.clear()
	for l: Line2D in _lines:
		l.queue_free()
	_lines.clear()

	## Lines first so they render beneath the point sprites.
	for i: int in config.missions.size() - 1:
		## Skip if the destination mission has connect_line disabled.
		if not config.missions[i + 1].connect_line:
			continue
		## Hide line if either endpoint is locked (its point is hidden).
		if _is_locked(config.missions[i]) or _is_locked(config.missions[i + 1]):
			continue
		var a: Vector2 = config.point_positions[i] \
				if i     < config.point_positions.size() else Vector2.ZERO
		var b: Vector2 = config.point_positions[i + 1] \
				if i + 1 < config.point_positions.size() else Vector2.ZERO
		var line := Line2D.new()
		line.width         = _LINE_WIDTH
		line.antialiased   = true
		line.default_color = _LINE_COLOR_UNLOCKED
		## Anchor to diamond (left part of icon) instead of sprite center.
		line.add_point(a + _POINT_LINE_ANCHOR)
		line.add_point(b + _POINT_LINE_ANCHOR)
		_points_container.add_child(line)
		_lines.append(line)

	## Point sprites and number labels (labels as siblings so modulate is set independently).
	for l: Label in _point_labels:
		l.queue_free()
	_point_labels.clear()

	for i: int in config.missions.size():
		var pos: Vector2 = config.point_positions[i] \
				if i < config.point_positions.size() else Vector2.ZERO
		var sp := Sprite2D.new()
		sp.texture  = _POINT_TEXTURE_INACTIVE
		sp.modulate = _POINT_NORMAL
		sp.position = pos
		## Share the blur material so all points blur in sync with the planet.
		sp.material = _blur_mat
		_points_container.add_child(sp)
		_points.append(sp)

		var lbl := Label.new()
		lbl.text     = "%02d" % config.missions[i].mission_number
		lbl.position = pos + _POINT_LABEL_OFFSET
		lbl.add_theme_font_size_override("font_size", _POINT_LABEL_FONT_SIZE)
		lbl.modulate = _POINT_NORMAL
		_points_container.add_child(lbl)
		_point_labels.append(lbl)

	_cursor = 0
	## Snap planet to first point instantly — no tween during open animation.
	_refresh(true)
	visible = true
	_animate_open()

func close() -> void:
	if _open_tween and _open_tween.is_valid():
		_open_tween.kill()
	if _planet_tween and _planet_tween.is_valid():
		_planet_tween.kill()
	if _blur_tween and _blur_tween.is_valid():
		_blur_tween.kill()
	## Restore originals so next open() starts clean.
	_planet_container.position = _orig_map_pos
	_planet_sprite.scale       = _orig_planet_scale
	_points_container.scale    = _orig_planet_scale
	_list_container.position   = _orig_list_pos
	_central_screen.position   = _orig_central_pos
	offset                     = Vector2.ZERO
	if _blur_mat:
		_blur_mat.set_shader_parameter("blur_amount_px", 0.0)
	visible = false
	for item: MissionListItem in _items:
		item.queue_free()
	_items.clear()
	for p: Sprite2D in _points:
		p.queue_free()
	_points.clear()
	for lbl: Label in _point_labels:
		lbl.queue_free()
	_point_labels.clear()
	for l: Line2D in _lines:
		l.queue_free()
	_lines.clear()
	_config     = null
	_confirming = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("move_up"):
		_cursor = wrapi(_cursor - 1, 0, _config.missions.size())
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_cursor = wrapi(_cursor + 1, 0, _config.missions.size())
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_try_confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		close()
		cancelled.emit()
		get_viewport().set_input_as_handled()

## snap=true: position planet instantly (used on open); snap=false: smooth tween + effects.
func _refresh(snap: bool = false) -> void:
	cursor_changed.emit(_cursor)
	for i: int in _items.size():
		_items[i].set_hovered(i == _cursor)
	for i: int in _points.size():
		var selected: bool = i == _cursor
		var locked: bool   = _is_locked(_config.missions[i])
		_points[i].visible        = not locked
		_point_labels[i].visible  = not locked
		if locked:
			continue
		var color: Color = _POINT_SELECTED if selected else _POINT_NORMAL
		_points[i].texture        = _POINT_TEXTURE_ACTIVE if selected else _POINT_TEXTURE_INACTIVE
		_points[i].modulate       = color
		_point_labels[i].modulate = color
	var m: MissionConfigResource = _config.missions[_cursor]
	_mission_preview.texture = m.mission_image
	_desc_label.text = m.description if not _is_locked(m) else m.locked_description
	if snap:
		_planet_container.position = _get_cursor_planet_pos()
	else:
		_move_planet_to_cursor()

## Returns the Planet Control position that centers the selected point at the planet visual origin.
## Formula: control_pos + container_pos + point * scale = container_pos
##       →  control_pos = _orig_map_pos − point * _points_container.scale
func _get_cursor_planet_pos() -> Vector2:
	if _config == null or _config.point_positions.is_empty():
		return _orig_map_pos
	var i := mini(_cursor, _config.point_positions.size() - 1)
	return _orig_map_pos - _config.point_positions[i] * _points_container.scale

## Smoothly pan the planet so the selected point sits at the planet visual origin,
## then blur along the movement direction and fade it out as the planet settles.
func _move_planet_to_cursor() -> void:
	var target: Vector2 = _get_cursor_planet_pos()
	var delta:  Vector2 = target - _planet_container.position

	## Pan.
	if _planet_tween and _planet_tween.is_valid():
		_planet_tween.kill()
	_planet_tween = create_tween()
	_planet_tween.tween_property(_planet_container, "position", target, 0.65) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	## Blur along the movement direction; skip if standing still.
	if delta.length_squared() > 1.0:
		_apply_motion_blur(delta.normalized())

	_cockpit_shake()

## Ramps blur_amount_px up quickly then fades it back to zero as the planet settles.
## direction: normalised screen-space movement vector passed to the shader.
func _apply_motion_blur(direction: Vector2) -> void:
	if _blur_mat == null:
		return
	if _blur_tween and _blur_tween.is_valid():
		_blur_tween.kill()
	_blur_mat.set_shader_parameter("blur_dir", direction)
	_blur_tween = create_tween()
	## Quick ramp-up (matches the initial burst of the planet moving).
	_blur_tween.tween_property(_blur_mat, "shader_parameter/blur_amount_px", _BLUR_PEAK, 0.08) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	## Slow fade-out (matches the cubic deceleration of the planet tween).
	_blur_tween.tween_property(_blur_mat, "shader_parameter/blur_amount_px", 0.0, 0.57) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

## Short micro-shake on the CanvasLayer to sell the sensation of the ship
## nudging as the planet pans across the viewport.
func _cockpit_shake() -> void:
	var t := create_tween()
	t.tween_property(self, "offset", Vector2(3.0,  1.5),  0.04)
	t.tween_property(self, "offset", Vector2(-2.0, -1.0), 0.05)
	t.tween_property(self, "offset", Vector2(1.0,  0.5),  0.04)
	t.tween_property(self, "offset", Vector2.ZERO,        0.06)

func _try_confirm() -> void:
	if _confirming:
		return
	var m: MissionConfigResource = _config.missions[_cursor]
	if _is_locked(m):
		return
	_confirming = true
	## Play forward animation on pilot hands, then start the cinematic after 0.5 s.
	for name: String in ["HandLeft", "HandRight"]:
		var hand := _hands.get_node_or_null(name) as AnimatedSprite2D
		if hand:
			hand.play(&"forward")
	await get_tree().create_timer(0.6).timeout
	_play_dive_cinematic(m.scene_path)

## Hides the UI and plays a 2-second cinematic: ship flies through the camera
## lens and recedes into the mission, then fires mission_confirmed.
func _play_dive_cinematic(scene_path: String) -> void:
	## Hide cockpit frame/glass/hands and info panels.
	## Background (stars) and Planet stay visible throughout.
	_cockpit.visible        = false
	_hands.visible          = false
	_central_screen.visible = false
	_list_container.visible = false

	var vp_size: Vector2 = get_viewport().get_visible_rect().size

	## Resolve the selected point's screen-space position.
	var pi: int     = mini(_cursor, _config.point_positions.size() - 1)
	var pt_local    = _config.point_positions[pi] if not _config.point_positions.is_empty() \
			else Vector2.ZERO
	var target: Vector2 = _points_container.to_global(pt_local)

	## Screen shake — sell the sensation of the ship passing through the camera.
	_dive_entry_shake()

	## ── Vignette (bottom layer) ───────────────────────────────────────────────
	var vignette := ColorRect.new()
	vignette.size     = vp_size
	vignette.position = Vector2.ZERO
	vignette.color    = Color(0.0, 0.0, 0.0, 0.0)
	add_child(vignette)

	## ── Ship: use the scene node, scale it up and snap it to the mission point ─
	_ship_dive_in.global_position = target
	_ship_dive_in.scale           = Vector2(9.0, 9.0)
	_ship_dive_in.modulate        = Color(3.0, 3.0, 3.0, 1.0)
	_ship_dive_in.visible         = true

	## ── Engine flames at the marker positions ─────────────────────────────────
	## Markers are children of _ship_dive_in; local_coords=false so particles
	## trail in world space and are not squeezed by the ship's scale animation.
	for marker_name: String in ["LeftEngine", "RightEngine"]:
		var marker := _ship_dive_in.get_node_or_null(marker_name) as Marker2D
		if marker:
			_ship_dive_in.add_child(_make_dive_flame(marker.position))

	## ── White flash (top layer) ───────────────────────────────────────────────
	var flash := ColorRect.new()
	flash.size     = vp_size
	flash.position = Vector2.ZERO
	flash.color    = Color(1.0, 1.0, 1.0, 0.9)
	add_child(flash)

	var flash_tw := create_tween()
	flash_tw.tween_property(flash, "color", Color(1.0, 1.0, 1.0, 0.0), 0.30) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	flash_tw.tween_callback(flash.queue_free)

	## Scale collapses to 0.2× over 2 s.
	var scale_tw := create_tween()
	scale_tw.tween_property(_ship_dive_in, "scale", Vector2(0.2, 0.2), 2.0) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	## Modulate: de-bloom (0-0.25 s), hold bright (0.25-0.70 s), darken with vignette.
	var mod_tw := create_tween()
	mod_tw.tween_property(_ship_dive_in, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	mod_tw.tween_interval(0.45)
	mod_tw.tween_property(_ship_dive_in, "modulate", Color(0.0, 0.0, 0.0, 1.0), 1.30) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	## Vignette darkens from 0.7 s onward.
	var vig_tw := create_tween()
	vig_tw.tween_interval(0.70)
	vig_tw.tween_property(vignette, "color", Color(0.0, 0.0, 0.0, 1.0), 1.30) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	await get_tree().create_timer(2.0).timeout
	_ship_dive_in.visible = false
	visible = false
	mission_confirmed.emit(scene_path)

## Creates a CPUParticles2D engine-flame emitter at a local position on the
## dive ship. Mirrors the POWER state from ThrusterEffect: large warm flame.
## local_coords=false so particles trail in world space, unaffected by ship scale.
func _make_dive_flame(local_pos: Vector2) -> CPUParticles2D:
	var p                      := CPUParticles2D.new()
	p.position                 = local_pos
	p.emitting                 = true
	p.amount                   = 24
	p.lifetime                 = 0.42
	p.one_shot                 = false
	p.explosiveness            = 0.0
	p.randomness               = 0.2
	p.local_coords             = false
	p.direction                = Vector2(1.0, 0.0)  ## arbitrary — overridden by full spread
	p.spread                   = 180.0              ## full 360° radial emission
	p.gravity                  = Vector2.ZERO
	p.emission_shape           = CPUParticles2D.EMISSION_SHAPE_POINT
	p.initial_velocity_min     = 100.0
	p.initial_velocity_max     = 190.0
	p.scale_amount_min         = 3.5
	p.scale_amount_max         = 7.0
	var grad                   := Gradient.new()
	grad.set_color(0, Color(1.0, 0.75, 0.1, 1.0))  ## bright yellow-orange at birth
	grad.set_color(1, Color(1.0, 0.2,  0.0, 0.0))  ## fades to transparent red
	p.color_ramp               = grad
	return p

## Forceful screen shake to sell the sensation of the ship passing through
## the camera at the start of the dive cinematic.
func _dive_entry_shake() -> void:
	var t := create_tween()
	t.tween_property(self, "offset", Vector2(-8.0, -5.0), 0.04)
	t.tween_property(self, "offset", Vector2(10.0,  6.0), 0.05)
	t.tween_property(self, "offset", Vector2(-7.0, -5.0), 0.05)
	t.tween_property(self, "offset", Vector2( 5.0,  4.0), 0.05)
	t.tween_property(self, "offset", Vector2(-4.0, -2.0), 0.05)
	t.tween_property(self, "offset", Vector2( 2.0,  1.5), 0.06)
	t.tween_property(self, "offset", Vector2.ZERO,        0.08)

func _animate_open() -> void:
	if _open_tween and _open_tween.is_valid():
		_open_tween.kill()

	## ── Start states ────────────────────────────────────────────────────────
	## Planet is already snapped to cursor position by _refresh(true).
	## Push it far below the screen so it rises up into the cockpit view,
	## representing the ship completing its dive toward the planet.
	var planet_snap: Vector2 = _planet_container.position
	_planet_sprite.scale      = _orig_planet_scale
	_points_container.scale   = _orig_planet_scale
	_planet_container.position = planet_snap + Vector2(0.0, 900.0)
	## UI panels start slightly below their resting positions.
	_list_container.position  = _orig_list_pos    + Vector2(0.0, 14.0)
	_central_screen.position  = _orig_central_pos + Vector2(0.0, 14.0)
	offset                    = Vector2.ZERO

	_open_tween = create_tween().set_parallel(true)

	## Planet rises from below — the hero motion that sells the dive approach.
	_open_tween.tween_property(_planet_container, "position", planet_snap, 0.70) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	## UI elements slide up staggered slightly behind the planet.
	_open_tween.tween_property(_list_container, "position", _orig_list_pos, 0.32) \
			.set_delay(0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_open_tween.tween_property(_central_screen, "position", _orig_central_pos, 0.30) \
			.set_delay(0.20).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _is_locked(m: MissionConfigResource) -> bool:
	# Gate 1: previous-mission completion (existing behaviour).
	if m.required_mission != 0 \
			and not MissionState.is_complete(m.required_mission):
		return true
	# Gate 2: high-score threshold on another mission (composes via AND).
	if m.required_score_mission != 0 \
			and MissionState.get_high_score(m.required_score_mission) < m.required_score:
		return true
	return false
