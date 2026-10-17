// Linux, Android and iOS have no modifier state to ask for, so the renderer
// records the modifiers of every event sokol delivers.
module ui2

fn host_key_modifiers() KeyModifiers {
	return g_key_modifiers
}
