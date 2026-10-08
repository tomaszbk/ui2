module main

import sokol.sapp

#flag -lX11
#include "@VMODROOT/tests/vector_runtime/native_linux.h"

fn C.ui2_vector_resize_linux(display voidptr, window voidptr, width int, height int) bool

fn resize_vector_window(width int, height int) bool {
	return C.ui2_vector_resize_linux(sapp.x11_get_display(), sapp.x11_get_window(), width, height)
}
