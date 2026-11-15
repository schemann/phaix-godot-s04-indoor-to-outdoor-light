extends OmniLight3D
## A ceiling lamp: the light and the block it hangs from. A room puts one at every one of its lamp spots.

## The colour of the light. The fixture keeps its own look.
func set_tint(color: Color) -> void:
	light_color = color
