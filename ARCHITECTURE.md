# Architecture

The main scene builds the amber terminal in `scripts/ui/menu.gd`. Its preview owns a separate 3D viewport and uses the same `Burst` and volume renderer as the range. A frozen burst has a fixed age, no audio, and no simulation processing. The viewport redraws when its size or graphics settings change.

`scripts/core/range.gd` owns the simulation, terrain, layout/editor, replay and observer. It selects the visual profile and instantiates a surface, thermobaric or underground effect. The art curves in `yield_catalog.gd` define fictional gameplay presets.

Weather and view settings feed conventional geometry, procedural volume shaders and a depth-based smoke shadow pass. The volume has a procedural density atlas sampled by raymarch shaders. Graphics settings are saved in `user://range_settings.cfg`. English and Russian strings live in `locale/interface.csv` and are imported by Godot.

Range layouts are saved as versioned JSON in the Godot user data directory. The repository contains the initial layout and sample scenes. Local settings, saves, screenshots and captures are excluded from version control.
