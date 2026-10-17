// Linux, Android and iOS have no modifier state to ask for, so the renderer
// records the modifiers of every event sokol delivers in its window.
module ui2

fn host_key_modifiers(last_event KeyModifiers) KeyModifiers {
	return last_event
}
