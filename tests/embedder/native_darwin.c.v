module main

#include "@VMODROOT/tests/embedder/native_darwin.h"

fn C.ui2_fixture_host_handle(window voidptr) voidptr
fn C.ui2_fixture_place(window voidptr, x f64, y f64) bool
fn C.ui2_fixture_minimize_restore(window voidptr, delay_ms i64) bool
fn C.ui2_fixture_preedit(window voidptr, value &char) bool
fn C.ui2_fixture_has_preedit(window voidptr) bool
fn C.ui2_fixture_commit(window voidptr, value &char) bool
fn C.ui2_fixture_candidate_inside_window(window voidptr) bool
fn C.ui2_fixture_move_pointer(window voidptr, x f64, y f64) bool
fn C.ui2_embedder_pump_count(handle voidptr) u64
fn C.ui2_embedder_event_count(handle voidptr) u64
