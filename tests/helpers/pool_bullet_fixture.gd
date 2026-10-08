## A minimal pooled projectile for tests/unit/test_bullet_pool.gd: a Node2D with the `expired`
## signal and `reset()` that BulletPool duck-types. Deliberately not an EnemyBullet, so the tests
## exercise only the pool's ownership contract. No `class_name`: test-only.
extends Node2D

signal expired

var reset_count: int = 0


func reset() -> void:
	reset_count += 1
