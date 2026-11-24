# Assets and credits

The GLB props in `assets/models/` are generated from the included Blender project and generator in `tools/blender/`. The terrain, sky, smoke, fire and dust use the included Godot shaders. The terminal UI uses an available system monospace font. Font files are not bundled.

The game uses original synthesized explosion, debris and echo layers. The two thunder variants are adapted from field recordings under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/):

- [Long Rumbling Thunder, billgrip](https://freesound.org/people/billgrip/sounds/151447/)
- [Distant Thunder 1, Fission9](https://freesound.org/people/Fission9/sounds/581122/)

The clips were trimmed, filtered and faded. Mixing adds a short silence so the roll follows the initial hit. Reproducible source previews are under `tools/audio_generation/sources/`.

To regenerate assets from the project root, install Blender and Python with NumPy and SciPy. The thunder renderer also uses FFmpeg.

```powershell
blender -b --factory-startup --python-exit-code 1 --python tools/blender/generate_models.py
python -c "import sys; sys.path.insert(0, 'tools/audio_generation'); from generate_burst import impact, flyby; impact(); flyby()"
python tools/audio_generation/render_mix.py
python tools/audio_generation/render_layers.py
godot_console --headless --editor --path . --import
```

Visual reference footage is linked in the historical VFX notes. No reference videos or frames are included in the game distribution.
