class_name MovementController
extends Node

signal action_single_press
signal action_double_press

var SINGLE_PRESS_ACTIONS: Array = [
	"move_left",
	"move_right",
	"move_up",
	"move_down",
	"shoot",
	"special_weapon"
]

var DOUBLE_PRESS_ACTIONS: Array = [
	"move_left",
	"move_right",
]

func _ready() -> void:
	movement_lock.connect(lock_movement)


# --- Movement Lock Functionality ---
# Used to ignore input commands during specific actions, like dashing
#
signal movement_lock

@onready var movement_lock_timer: Timer = $MovementLockTimer

func lock_movement(time_sec: float) -> void:
	print("Movement controller will be locked for " + str(time_sec) + " sec.")
	movement_lock_timer.start(time_sec)

func _on_movement_lock_timer_timeout() -> void:
	print("Movement controller lock is ended.")


# --- Main Controller logic ---
# This method is used to store movement logic in one place, and provide notification for all player states via signals
func _process(delta: float) -> void:
	if !Input.is_anything_pressed():
		return

	if !movement_lock_timer.is_stopped():
		return

	var is_double_press: bool = handle_double_press()
	if is_double_press:
		return

	handle_single_press()


# --- Handle double press tracking logic ---
# If a key listed in the 'DOUBLE_PRESS_ACTIONS' array is pressed, the corresponding signal will be emitted.
@onready var double_press_threshold: Timer = $DoubleClickThreshold

var last_press_key: String

func handle_double_press() -> bool:
	for double_press_key in DOUBLE_PRESS_ACTIONS:
		if Input.is_action_just_pressed(double_press_key):
			var is_double_pressed: bool = double_press_key == last_press_key

			if is_double_pressed and !double_press_threshold.is_stopped():
				last_press_key = ""
				double_press_threshold.stop()
				action_double_press.emit(double_press_key)
				print("second time pressed " + str(double_press_key))
				return true
			else:
				double_press_threshold.start()
				last_press_key = double_press_key
				print("first time pressed " + str(double_press_key))
				return false
	return false

func _on_double_click_threshold_timeout() -> void:
	last_press_key = ""


# --- Handle single press tracking logic ---
func handle_single_press() -> void:
	for single_press_key in SINGLE_PRESS_ACTIONS:
		if Input.is_action_just_pressed(single_press_key):
			action_single_press.emit(single_press_key)
