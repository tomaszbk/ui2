module ui2

// KeyModifiers are the modifier keys held at a moment. `cmd` is Command on Apple
// platforms and the Windows key elsewhere, as in KeyEvent.
pub struct KeyModifiers {
pub:
	shift bool
	ctrl  bool
	alt   bool
	cmd   bool
}

// key_modifiers reports the modifier keys held right now. Pointer events do not
// carry them, so a click handler asks here to tell a Shift- or Cmd-click apart.
// Where the platform has no way to ask, these are the modifiers of the last
// event the window received.
pub fn (w &Window) key_modifiers() KeyModifiers {
	return host_key_modifiers(w.event_modifiers)
}
