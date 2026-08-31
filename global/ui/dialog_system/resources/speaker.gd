## SpeakerResource — character identity for dialog lines.
## A line references a speaker; one .tres per character means a single edit
## propagates to every line they speak.
class_name SpeakerResource
extends Resource

## Display name in the speaker label. Empty = no label (used for narration).
@export var display_name: String = ""

## Portrait shown next to the line. null = no portrait.
@export var portrait: Texture2D

## Color of the speaker label. Default matches the dialog box accent.
@export var name_color: Color = Color(0.55, 0.82, 1.0, 1.0)
