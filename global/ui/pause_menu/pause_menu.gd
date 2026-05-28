## global/ui/pause_menu/pause_menu.gd
## ESC pause menu shown during missions and open space.
##
## mission_mode = true  (missions)   : Resume / Restart / Exit Mission / Exit Game
## mission_mode = false (open space) : Resume / Exit Game only
##
## Opens with ESC. Blocked while DialogPlayer is running or any other system
## has already paused the tree (e.g. PlayerMenu).
##
## Navigation: W / S  |  Space / F to confirm  |  ESC to close.
## On open: Camera2D zooms toward the player ship (ship sits in the right half).
## On close: zoom reverts.
class_name PauseMenu
extends CanvasLayer

const _HUB_PATH := "res://open_space/scenes/levels/sector_hub.tscn"

const _COLOR_NORMAL  := Color.WHITE
const _COLOR_HOVERED := Color(1.4, 1.4, 1.0)

## Camera zoom applied when the menu opens.
const _ZOOM_TARGET := Vector2(3.0, 3.0)
## World-space offset so the ship centres in the right half of the screen.
## Derived: offset.x = -(screen_half_width / zoom) = -(160 / 3.0) ~ -53
const _CAMERA_OFFSET := Vector2(-53.0, 0.0)

## false = open-space mode: only Resume and Exit Game are shown.
@export var mission_mode: bool = true

var _options:          Array[Node2D] = []
var _cursor:           int           = 0
var _was_paused_by_us: bool          = false
var _zoom_tween:       Tween         = null
var _orig_zoom:        Vector2
var _orig_cam_pos:     Vector2
## Visibility state of every HUD sibling captured on open, restored on close.
var _sibling_vis:      Dictionary    = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_options = [
		$MenuContainer/Option0,
		$MenuContainer/Option1,
		$MenuContainer/Option2,
		$MenuContainer/Option3,
	]
	_options[1].visible = mission_mode
	_options[2].visible = mission_mode
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if visible:
			_close()
		else:
			_try_open()
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	if event.is_action_pressed("menu_up"):
		_navigate(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		_navigate(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_confirm"):
		get_viewport().set_input_as_handled()
		_confirm()


## ── Open / Close ────────────────────────────────────────────────────────────

func _try_open() -> void:
	if get_tree().paused:
		return
	if DialogPlayer.is_active:
		return
	_cursor = 0
	_hide_hud()
	visible = true
	get_tree().paused = true
	_was_paused_by_us = true
	_refresh()
	_zoom_in()


func _close() -> void:
	visible = false
	_show_hud()
	if _was_paused_by_us:
		get_tree().paused = false
		_was_paused_by_us = false
	_zoom_out()


## ── Actions ─────────────────────────────────────────────────────────────────

func _confirm() -> void:
	match _cursor:
		0:
			_close()
		1:
			visible = false
			_show_hud()
			_reset_camera_instant()
			get_tree().paused = false
			## Safety: if a GameOver overlay survived at root (e.g. player somehow
			## opened the pause menu while the death screen was up), remove it now
			## so it doesn't bleed into the reloaded scene.
			var go := get_tree().root.get_node_or_null("GameOver")
			if is_instance_valid(go):
				go.queue_free()
			get_tree().reload_current_scene()
		2:
			visible = false
			_reset_camera_instant()
			get_tree().paused = false
			## If the HUD was dynamically injected at root level (assault director
			## pattern), free it now — change_scene_to_file won't touch it because
			## it isn't the current scene.  Scene-embedded menus (infiltration, open
			## space) are part of the current scene and get freed automatically, so
			## we must not queue_free them here.
			var hud := get_parent()
			if is_instance_valid(hud) and hud != get_tree().current_scene:
				hud.queue_free()
			get_tree().change_scene_to_file(_HUB_PATH)
		3:
			get_tree().quit()


## ── Navigation ──────────────────────────────────────────────────────────────

## Step the cursor by +1 or -1, skipping any hidden (inactive) options.
func _navigate(dir: int) -> void:
	var next := _cursor
	for _i: int in _options.size():
		next = wrapi(next + dir, 0, _options.size())
		if _options[next].visible:
			break
	_cursor = next
	_refresh()


func _refresh() -> void:
	for i: int in _options.size():
		_options[i].modulate = _COLOR_HOVERED if i == _cursor else _COLOR_NORMAL


## ── HUD visibility ──────────────────────────────────────────────────────────

## Hides all sibling nodes inside the parent HUD, saving their visibility so
## it can be restored exactly when the menu closes.
func _hide_hud() -> void:
	_sibling_vis.clear()
	var parent := get_parent()
	if parent == null:
		return
	for child: Node in parent.get_children():
		if child == self:
			continue
		## Skip world-space nodes (Sprite2D, CharacterBody2D, etc.) — only hide
		## canvas UI overlays (Control, CanvasLayer).  This keeps game objects
		## visible in scenes where PauseMenu is a direct scene child (infiltration),
		## while still hiding HUD panels in the assault CanvasLayer HUD.
		if child is Node2D:
			continue
		_sibling_vis[child] = child.visible
		child.visible = false


## Restores every sibling to the visibility it had before the menu opened.
func _show_hud() -> void:
	for child: Node in _sibling_vis:
		if is_instance_valid(child):
			child.visible = _sibling_vis[child]
	_sibling_vis.clear()


## ── Camera zoom ─────────────────────────────────────────────────────────────

func _get_camera() -> Camera2D:
	return get_viewport().get_camera_2d()


func _zoom_in() -> void:
	var camera: Camera2D = _get_camera()
	if camera == null:
		return

	_orig_zoom    = camera.zoom
	_orig_cam_pos = camera.global_position

	var players := get_tree().get_nodes_in_group("player")
	var target_pos: Vector2 = _orig_cam_pos
	if not players.is_empty():
		target_pos = (players[0] as Node2D).global_position

	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()

	_zoom_tween = create_tween().set_parallel(true)
	_zoom_tween.tween_property(camera, "zoom", _ZOOM_TARGET, 0.45) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_zoom_tween.tween_property(camera, "global_position",
			target_pos + _CAMERA_OFFSET, 0.45) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _zoom_out() -> void:
	var camera: Camera2D = _get_camera()
	if camera == null:
		return

	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()

	_zoom_tween = create_tween().set_parallel(true)
	_zoom_tween.tween_property(camera, "zoom", _orig_zoom, 0.30) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_zoom_tween.tween_property(camera, "global_position", _orig_cam_pos, 0.30) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _reset_camera_instant() -> void:
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	var camera: Camera2D = _get_camera()
	if camera == null:
		return
	camera.zoom            = _orig_zoom
	camera.global_position = _orig_cam_pos
