# Project Structure

The project is divided into **three main modules**, each representing a separate game entry:

- **Sector Operations** — open-zone space hub  
- **Assault Mission** — fast-paced autoscroller stage  
- **Infiltration Mission** — isometric ground combat gameplay  

The codebase is organized **by game entry**, with each module containing only **stage-specific logic and assets**, such as local scripts, sprites, UI, and configuration files. This approach keeps gameplay systems isolated and easy to maintain.

All **shared systems and reusable logic** (utilities, global managers, common data structures, base components) are placed in a **dedicated global module**, which is used across all stages.

## Structure
```
/sector_operations
  /assets
	/tilesets        # TileSets and TileMap textures used only in this mode
	/sprites         # Mode-specific sprites (props, decorations)
	/ui              # UI images unique to this mode
	/vfx             # Particle sprites, effects used only in this mode

  /scenes
	/entities
	  /player        # Player scene variants used in this mode (if any)
	  /enemies
		/patrol_drone# Enemy scenes unique or overridden for this mode
		  /sprites
		  /scripts
		  /ai
			/states
		  /data
	  /npcs          # Non-hostile characters, mission actors
	  /props         # Doors, terminals, alarms, breakables, traps
	/levels
	/ui
	  /screens       # Mode screens (briefing, mission complete/fail)
	  /widgets       # Small reusable UI pieces for this mode
	/systems
	  /spawners      # Enemy and object spawn scenes
	  /triggers      # Area triggers, mission logic triggers
	  /cameras       # Camera rigs or constraints for this mode

  /scripts
	/mode            # Mode controller, rules, objectives, win/lose logic
	/systems         # Alarm systems, stealth logic, wave logic
	/ui              # UI logic for mode screens/widgets

  /data
	/configs
	  /items         # Items usable only in this mode
	  /weapons       # Mode-specific weapon configs or overrides
	/objectives      # Mission objectives and conditions
	/waves           # Enemy wave definitions (if applicable)
	/dialogue        # Dialogue scripts used in this mode

  /tools             # Debug tools, import helpers, test scenes
  /tests             # Automated or manual test scenes/scripts


/assault_mission
  (same structure as /sector_operations)


/infiltration_mission
  (same structure as /sector_operations)


/global
  /assets
	/audio
	  /music         # Shared music tracks
	  /sfx           # Shared sound effects
	/fonts           # Global fonts
	/ui              # Shared UI graphics
	/vfx             # Shared visual effects sprites

  /shaders            # Global shaders (lighting, pixel effects, distortions)

  /scenes
	/systems
	  /spawners       # Generic spawners reused by modes
	  /fx             # Shared effect scenes

  /scripts
	/core             # Game state, save/load, scene management
	/components       # Reusable components (Health, Hurtbox, Hover, etc.)
	/entities         # Base entity logic and shared behaviors
	/systems          # Audio manager, input handling, event bus
	/ui               # Shared UI logic
	/util             # Helpers, math, timers, utilities

  /data
	/configs
	/localization     # Localization files

```
