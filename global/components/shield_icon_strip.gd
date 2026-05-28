# global/components/shield_icon_strip.gd
## A horizontal row of ShieldIcon nodes, one per shield slot.
## Permanent icons are leftmost (always present, switch to "empty" visual when
## destroyed). Temporary icons are appended to the right and queue_free on destroy.
##
## Uses manual positioning because ShieldIcon extends AnimatedSprite2D (Node2D),
## which is invisible to HBoxContainer's layout engine.
##
## Usage:
##   var strip := preload(".../shield_icon_strip.tscn").instantiate()
##   add_child(strip)
##   strip.setup(player.shield_component)
class_name ShieldIconStrip
extends Control

const _ICON_SCENE: PackedScene = preload("res://global/components/shield_icon.tscn")

const ICON_SIZE: int = 32   ## matches the 32×32 sprite art
const ICON_GAP:  int = 4    ## pixels between icons

var _shield: Shield = null
var _perm_icons: Array[ShieldIcon] = []
var _temp_icons: Array[ShieldIcon] = []
var _last: Dictionary = {
	"perm_active": 0, "perm_max": 0, "temp_count": 0, "hacked": false,
}

func setup(shield: Shield) -> void:
	_shield = shield
	_rebuild_permanent(shield.permanent_max)
	shield.shield_state_changed.connect(_on_shield_state_changed)
	## Apply the initial state (the Shield emits its snapshot in _ready before
	## we connect — push the current state through manually).
	_on_shield_state_changed({
		"perm_active": shield.permanent_active,
		"perm_max": shield.permanent_max,
		"temp_count": shield.temporary_count,
		"hacked": shield.is_hacked,
	})

func _rebuild_permanent(count: int) -> void:
	for icon in _perm_icons:
		icon.queue_free()
	_perm_icons.clear()
	for _i in count:
		var icon: ShieldIcon = _ICON_SCENE.instantiate()
		add_child(icon)
		icon.setup(ShieldIcon.Tier.PERMANENT)
		_perm_icons.append(icon)
	_reposition_all()

## Recalculates every icon's position left-to-right: permanent first, then temporary.
## AnimatedSprite2D is centered by default, so offset each icon by half ICON_SIZE.
func _reposition_all() -> void:
	var x: float = 0.0
	for icon in _perm_icons:
		icon.position = Vector2(x + ICON_SIZE * 0.5, ICON_SIZE * 0.5)
		x += ICON_SIZE + ICON_GAP
	for icon in _temp_icons:
		icon.position = Vector2(x + ICON_SIZE * 0.5, ICON_SIZE * 0.5)
		x += ICON_SIZE + ICON_GAP

func _on_shield_state_changed(snap: Dictionary) -> void:
	## --- Permanent max changed (e.g. shield-up pickup) ---
	if snap.perm_max != _last.perm_max:
		_rebuild_permanent(int(snap.perm_max))

	## --- Permanent active changed ---
	var perm_delta: int = int(snap.perm_active) - int(_last.perm_active)
	if perm_delta < 0:
		## Destroy the rightmost (perm_delta) active permanent icons.
		var to_destroy: int = -perm_delta
		var idx: int = int(_last.perm_active) - 1
		while to_destroy > 0 and idx >= 0:
			_perm_icons[idx].play_destroy()
			idx -= 1
			to_destroy -= 1
	elif perm_delta > 0:
		## Recharge the leftmost (perm_delta) empty permanent icons.
		var to_recharge: int = perm_delta
		var idx: int = int(_last.perm_active)
		while to_recharge > 0 and idx < _perm_icons.size():
			_perm_icons[idx].play_recharge()
			idx += 1
			to_recharge -= 1

	## --- Temporary count changed ---
	var temp_delta: int = int(snap.temp_count) - int(_last.temp_count)
	if temp_delta > 0:
		for _i in temp_delta:
			var icon: ShieldIcon = _ICON_SCENE.instantiate()
			add_child(icon)
			icon.setup(ShieldIcon.Tier.TEMPORARY)
			icon.play_recharge()
			_temp_icons.append(icon)
		_reposition_all()
	elif temp_delta < 0:
		var to_remove: int = -temp_delta
		while to_remove > 0 and _temp_icons.size() > 0:
			var icon: ShieldIcon = _temp_icons.pop_back()
			icon.play_destroy()  ## icon queue_frees itself on animation_finished
			to_remove -= 1

	## --- Hacked toggle ---
	if bool(snap.hacked) != bool(_last.hacked):
		if snap.hacked:
			for icon in _perm_icons:
				icon.play_hacked()
			for icon in _temp_icons:
				icon.play_hacked()
		else:
			for icon in _perm_icons:
				icon.play_restore()
			for icon in _temp_icons:
				icon.play_restore()

	_last = snap.duplicate()
