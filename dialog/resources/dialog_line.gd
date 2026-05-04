## DialogLineResource — one line of dialog.
## A DialogScriptResource is an ordered array of these.
class_name DialogLineResource
extends Resource

## Where the line appears.
##   OTHER_TOP      — top bar, portrait left, used for non-protagonist speakers
##   PLAYER_BOTTOM  — bottom bar, portrait right (mirrored), used for protagonist
##   INNER_THOUGHT  — bottom bar, italicised, no portrait, used for monologue
enum Side { OTHER_TOP, PLAYER_BOTTOM, INNER_THOUGHT }

## How the text appears.
##   TYPEWRITER  — char-by-char reveal via visible_ratio (default)
##   FADE_IN     — modulate.a 0→1, all chars at once
##   INSTANT     — no animation
enum Reveal { TYPEWRITER, FADE_IN, INSTANT }

@export var speaker: SpeakerResource

@export_multiline var text: String = ""

@export var side: DialogLineResource.Side = DialogLineResource.Side.PLAYER_BOTTOM

@export var reveal: DialogLineResource.Reveal = DialogLineResource.Reveal.TYPEWRITER

## Characters per second for TYPEWRITER. Ignored for other reveals.
@export_range(5.0, 200.0, 1.0) var typing_speed: float = 35.0

## Extra pause after the line completes (used in autoplay timing).
@export_range(0.0, 5.0, 0.05) var post_delay: float = 0.0

## Optional voice/blip stream played when the line starts.
@export var sfx: AudioStream
