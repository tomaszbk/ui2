module main

import sokol.sapp

#include "@VMODROOT/tests/vector_runtime/native_darwin.h"

fn C.ui2_vector_resize(window voidptr, width int, height int) bool

fn resize_vector_window(width int, height int) bool {
	return C.ui2_vector_resize(sapp.macos_get_window(), width, height)
}
