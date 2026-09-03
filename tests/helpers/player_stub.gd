## A minimal PlayerBase stand-in for tests.
##
## PlayerBase._setup_components() looks its components up by node name
## (`$HealthComponent`, `$ShieldComponent`, `$OverheatComponent`, and the
## optional `TempHealthComponent`), so a test player only needs those children —
## no mission scene, no sprites, no input.
##
## Deliberately has no `class_name`: test-only types should not appear in the
## game's global class list. Preload it instead:
##     const PlayerStub := preload("res://tests/helpers/player_stub.gd")
##     var p: PlayerBase = PlayerStub.spawn(100, 1)
##     add_child_autofree(p)
##
## The file name avoids the `test_` prefix so GUT does not try to collect it as
## a test script.
extends PlayerBase


## Children are attached before the player enters the tree, because
## PlayerBase._ready() assumes its components have already run theirs.
static func spawn(max_hp: int = 100, permanent_shields: int = 1) -> PlayerBase:
	var p: PlayerBase = (load("res://tests/helpers/player_stub.gd") as GDScript).new()

	var health := Health.new()
	health.name = "HealthComponent"
	health.max_health = max_hp
	health.current_health = max_hp
	p.add_child(health)

	var shield := Shield.new()
	shield.name = "ShieldComponent"
	shield.bind_progression = false
	shield.permanent_charges = permanent_shields
	p.add_child(shield)

	var overheat := Overheat.new()
	overheat.name = "OverheatComponent"
	p.add_child(overheat)

	var temp := TempHealth.new()
	temp.name = "TempHealthComponent"
	p.add_child(temp)

	return p
