class_name WeaponSelector
extends Node2D

@export var default_icon: Texture2D

@export var left_icon: Texture2D
@export var center_icon: Texture2D
@export var right_icon: Texture2D

@onready var left_icon_sprite: Sprite2D = $SelectorLeft/IconLeft
@onready var center_icon_sprite: Sprite2D = $SelectorCenter/IconCenter
@onready var right_icon_sprite: Sprite2D = $SelectorRight/IconRight

func _ready() -> void:
	_set_icon(left_icon_sprite, left_icon)
	_set_icon(center_icon_sprite, center_icon)
	_set_icon(right_icon_sprite, right_icon)

func _set_icon(sprite: Sprite2D, icon: Texture2D) -> void:
	sprite.texture = icon if icon else default_icon
