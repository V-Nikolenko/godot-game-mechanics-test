## global/resources/planet_config_resource.gd
## All inspector-configurable data for one mission trigger (planet, space station, ship...).
## Create one .tres file per trigger object. Assign it to a MissionTrigger node.
## Change anything here and the in-game menu reflects it with zero code changes.
class_name PlanetConfigResource
extends Resource

## ── Identity (shown in the menu header) ───────────────────────────────────
@export var display_name: String = "UNKNOWN"
## Subtitle line, e.g. "TERRESTRIAL", "ORBITAL STATION", "DREADNOUGHT"
@export var planet_class: String = "TERRESTRIAL"
## e.g. "LOW", "MEDIUM", "HIGH", "EXTREME"
@export var threat_level: String = "MEDIUM"

## ── Visuals ───────────────────────────────────────────────────────────────
## Background rendered behind the overlay in the mission select menu.
@export var background_texture: Texture2D = null
## Texture used for two things:
##   1. The Sprite2D shown on the MissionTrigger node in the open-space world.
##   2. The "planet map" image rendered in the right panel of the menu.
## Swap this to turn a planet into a space station or ship.
@export var sprite_texture: Texture2D = null

## ── Missions ──────────────────────────────────────────────────────────────
## The ordered list of missions shown in the menu. Drag MissionConfigResource
## .tres files here. The first entry is always index 0 in the list.
@export var missions: Array[MissionConfigResource] = []

## ── Point positions ───────────────────────────────────────────────────────
## Pixel offsets from the planet map image centre for the mission point icons.
## Index 0 maps to missions[0], index 1 maps to missions[1], etc.
## Edit these in the Inspector to drag points around the planet map visually.
@export var point_positions: Array[Vector2] = [
	Vector2(-60.0, -30.0),
	Vector2(40.0, 50.0),
]
