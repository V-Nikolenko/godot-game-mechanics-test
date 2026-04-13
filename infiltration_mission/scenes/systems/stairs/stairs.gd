@tool
extends Area2D
class_name StairAssist

@onready var col_poly: CollisionPolygon2D = $CollisionPolygon2D

func _on_body_entered(body: Node2D) -> void:
	print(body)
	pass # Replace with function body.
