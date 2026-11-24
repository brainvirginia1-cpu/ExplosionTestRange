# Testing

Open the project in Godot 4.7.2 or import it with its command-line runner before testing.

```powershell
godot_console --headless --path . --import
godot_console --path . --audio-driver Dummy --script res://scripts/tests/menu_preview.gd
```

The preview test requires a graphics device. It checks the isolated viewport, the frozen age, updates when render settings change, English translations and entry into the range. It changes settings in memory for the current process.

For a manual pass, switch between English and Russian under Settings → Language, compare the preview with and without smoke shadows, then start a trial. Test pause/resume, reset, replay, the editor and a launch in each of the three modes.

`scripts/tests/first_trial.gd` also includes a broader physics test. Some of its older visual and physics assertions are sensitive to headless timing and renderer differences.
