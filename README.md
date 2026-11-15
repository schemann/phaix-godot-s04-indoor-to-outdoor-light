# Indoor to Outdoor Light in Godot 4

Project files for tutorial s04 of the Godot 4 series by Phaix on YouTube (https://www.youtube.com/@Phaix).

Light a dark room and a sunny garden in the same game, like Roblox DOORS, in Godot 4.
A garden is a room without a ceiling, with a sun that casts shadows, drawn from a seed stream of its own so that no other room moves. A script blends six numbers by where the camera stands: five of one live Environment between an inside mood and an outside mood (the ambient light, the sky's share of it, the fog colour, the fog density and the volumetric fog density) and the Indirect Energy of the sun. Auto exposure lets the eyes adapt, so the sun can be as bright as the docs say (3.0 to 6.0) and the dark rooms stay dark.

Every step is its own project folder, and the start is the final project of tutorial 08.

## Steps

Every step of the video is its own folder in `steps/`, the exact state at the end of that
part. Open the project in Godot 4.7, then open `steps/<step>/main.tscn` and press F6 to run
that step. The project's main scene is the final step.

| Folder | Part of the video |
|---|---|
| `steps/step_00_start` | Starting point (the final state of tutorial 08) |
| `steps/step_01_garden` | Step 1 - A garden room |
| `steps/step_02_two_moods` | Step 2 - Two moods of light |
| `steps/step_03_eyes_adapt` | Step 3 - Eyes that adapt |

## Controls

WASD or arrow keys or the left stick to walk, mouse or right stick to look, Space to jump,
Esc gives the mouse back, a click captures it again. Further keys per tutorial are shown
in the video and in the HUD.

## Tests

```sh
godot --headless --path . -s res://tests/run_tests.gd
```

## Support

Support the channel: https://ko-fi.com/phaix or https://github.com/sponsors/schemann

## License

Code and scenes: MIT (see LICENSE).
The figure and its animations: Animated Characters Protagonists by Kenney (www.kenney.nl), CC0, see character/License.txt.
