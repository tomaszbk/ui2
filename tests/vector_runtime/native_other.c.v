module main

$if !macos && !linux {
	fn resize_vector_window(_width int, _height int) bool { return false }
}
