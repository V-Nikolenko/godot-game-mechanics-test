## BackgroundPhase — a state snapshot describing what the background should look like
## once a section's transition_in completes.
##
## Level1Background.transition_to(phase, duration) Tweens all properties from
## their current values to these targets over [duration] seconds.
##
## Cloud peel schedules run concurrently as section-relative timers; they are
## independent from the main alpha/scale tween.
class_name BackgroundPhase
extends Resource

@export var phase_name: StringName = &""

# ── Target layer alphas ───────────────────────────────────────────────────────
## Stars and nebula share one group; all tween together toward these values.
@export_group("Space Layers")
@export_range(0.0, 1.0, 0.01) var stars_base_alpha:    float = 1.0
@export_range(0.0, 1.0, 0.01) var stars_overlay_alpha: float = 1.0
@export_range(0.0, 1.0, 0.01) var nebula_alpha:         float = 0.08
## Fraction [0-1] of transition_in_duration before stars/nebula begin fading.
## 0 = fade immediately (default). Use 0.7 for planet_approach so stars hold
## until the planet is large and close before the sky brightens.
@export_range(0.0, 1.0, 0.01) var space_fade_start_fraction: float = 0.0

## Cloud layers tween from current alpha to these values during transition_in.
## During planet approach they tween FROM 0 but start delayed by clouds_appear_fraction.
@export_group("Cloud Layers")
@export_range(0.0, 1.0, 0.01) var cloud_1_alpha: float = 0.0
@export_range(0.0, 1.0, 0.01) var cloud_2_alpha: float = 0.0
@export_range(0.0, 1.0, 0.01) var cloud_3_alpha: float = 0.0
@export_range(0.0, 1.0, 0.01) var cloud_4_alpha: float = 0.0

## Fraction [0-1] of transition_in_duration before clouds begin tweening.
## Set to 0.6 for planet approach (clouds appear only in the last 40 %).
@export_range(0.0, 1.0, 0.01) var clouds_appear_fraction: float = 0.0

## Target alpha for the surface (planet ground) layer.
@export_range(0.0, 1.0, 0.01) var surface_alpha: float = 0.0

# ── Planet ────────────────────────────────────────────────────────────────────
@export_group("Planet")
@export_range(0.0, 1.0, 0.01) var planet_alpha: float = 0.0
## Target scale at end of transition.  Uses EASE_IN CUBIC to mimic ease(t,3).
@export var planet_scale: float = 0.1
## Seconds after section start for the planet to reach planet_alpha.
## Independent from the main transition duration (usually 2 s).
@export var planet_fade_in: float = 2.0
## Seconds into the transition before the planet begins fading out to 0.
## -1.0 = no delayed fade-out (planet alpha is driven by planet_alpha instead).
## Use during planet_approach so the planet disappears behind clouds rather than
## lingering at full opacity until the next section starts.
@export var planet_fade_out_start:    float = -1.0
@export var planet_fade_out_duration: float = 20.0

# ── Asteroid entry ────────────────────────────────────────────────────────────
## If true the asteroid layer resets to the top of screen when this phase starts.
## The layer then scrolls downward at its export speed until it exits.
## Alpha tracks _alpha_stars_base (fades with the space layers automatically).
@export_group("Asteroids")
@export var asteroids_back_enter:  bool = false
@export var asteroids_front_enter: bool = false

# ── Cloud peel schedule (section-relative) ────────────────────────────────────
## Peel = fade alpha to 0 + scale up to cloud_peel_scale using EASE_IN QUAD.
## -1.0 = this layer does not peel during this section.
@export_group("Cloud Peel")
@export var cloud_4_peel_start:    float = -1.0
@export var cloud_4_peel_duration: float =  3.0
@export var cloud_3_peel_start:    float = -1.0
@export var cloud_3_peel_duration: float =  5.0
@export var cloud_2_peel_start:    float = -1.0
@export var cloud_2_peel_duration: float =  5.0
@export var cloud_1_peel_start:    float = -1.0
@export var cloud_1_peel_duration: float =  5.0
## Scale reached by the end of the peel animation.
@export var cloud_peel_scale: float = 4.0

## Seconds after section start before surface begins fading in.
## -1.0 = surface does not appear during this section.
@export var surface_appear_start:    float = -1.0
@export var surface_appear_duration: float = 10.0
