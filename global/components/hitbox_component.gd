class_name HitBox
extends Area2D

enum DamageType { LASER, ROCKET, CONTACT }

@export var damage: int
@export var damage_type: DamageType = DamageType.LASER
