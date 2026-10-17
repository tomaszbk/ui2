// Linux and Android draw with the custom renderer, which records the modifiers
// of every event sokol delivers.
module ui2

fn host_key_modifiers() KeyModifiers {
	return g_key_modifiers
}
