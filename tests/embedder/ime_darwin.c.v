module main

#include "@VMODROOT/tests/embedder_macos/ime_session.h"

fn C.ui2_test_ime_begin(native_window voidptr) voidptr
fn C.ui2_test_ime_selected(session voidptr) bool
fn C.ui2_test_ime_end(session voidptr)
