## The infiltration player is a plain CharacterBody2D, not a PlayerBase — see
## docs/architecture/modules/infiltration.md. PickupBase and InfoLogInteractable both gate
## `_on_body_entered` on `body.is_in_group("player")`, so without this the ground player is
## invisible to every pickup/interactable in the game.
extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://infiltration/scenes/entities/player/player.tscn")


func test_infiltration_player_is_in_the_player_group() -> void:
	var player := PLAYER_SCENE.instantiate()
	add_child_autofree(player)

	assert_true(player.is_in_group("player"),
		"the infiltration player must join \"player\" the same way PlayerBase._ready() does")
