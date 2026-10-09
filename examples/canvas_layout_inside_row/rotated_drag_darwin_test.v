// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
module main

import math
import ui2

$if !gcboehm ? {
	$compile_error('Logo drag fixtures require normal Boehm GC')
}

$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
	#include "@VMODROOT/examples/canvas_layout_inside_row/drag_fixture_darwin.h"
	fn C.ui2_inside_row_present(voidptr) bool
	fn C.ui2_inside_row_pointer(voidptr, int, f64, f64)
	fn C.ui2_inside_row_resize(voidptr, int, int)

	struct LogoPointerRecord {
		kind   ui2.ElementEventKind
		window ui2.Point
	}

	@[heap]
	struct LogoDragFixture {
	mut:
		translated   bool
		scaled       bool
		hide_logo    bool
		omit_card_id bool
		logo         ui2.VisualGeometry
		card         ui2.VisualGeometry
		events       []LogoPointerRecord
	}

	const logo_drag_fixture = &LogoDragFixture{}

	fn logo_drag_scene_element(el ui2.Element) ui2.Element {
		mut fixture := unsafe { logo_drag_fixture }
		mut children := []ui2.Element{cap: el.children.len}
		for child in el.children {
			children << logo_drag_scene_element(child)
		}
		mut result := ui2.Element{ ...el, children: children }
		if el.id == 'card' {
			result = ui2.Element{ ...result, id: if fixture.omit_card_id { '' } else { el.id } }
			if fixture.translated {
				result = ui2.with_transform(ui2.Element{
					...result
					frame: ui2.rect(16.25, 16.5, el.frame.width, el.frame.height)
				}, ui2.VisualTransform{ translate_x: 40.25, translate_y: 22.5 })
			}
		}
		if el.id == 'logo' {
			original := el.on_event
			result = ui2.Element{
				...result
				hidden:   fixture.hide_logo
				on_event: fn [original] (event ui2.ElementEvent) {
					if event.kind in [.pointer_down, .pointer_drag, .pointer_up] {
						geometry := ui2.visual_geometry('logo') or { panic(err) }
						mut fixture := unsafe { logo_drag_fixture }
						fixture.events << LogoPointerRecord{
							kind:   event.kind
							window: geometry.transform.point(event.x, event.y)
						}
					}
					original(event)
				}
			}
		}
		return result
	}

	fn build_logo_drag_fixture() ui2.Element {
		fixture := unsafe { logo_drag_fixture }
		frame := if fixture.scaled {
			ui2.rect(0, 0, inside_row_width, inside_row_height)
		} else {
			ui2.bounds()
		}
		root := ui2.element_from_vml_model_with_callbacks(inside_row_vml_source,
			*unsafe { inside_row_state }, frame, canvas_layout_inside_row_callbacks()) or { panic(err) }
		adjusted := logo_drag_scene_element(root)
		if fixture.scaled {
			// Real fixed composition at 3/4 scale with fractional viewport origin.
			return ui2.screen(0xf1f5f9, [ui2.scaled_content('fixture-content',
				ui2.rect(30.25, 20.5, inside_row_width * 0.75, inside_row_height * 0.75),
				inside_row_width, inside_row_height, ui2.BoxStyle{ transparent: true }, adjusted.children)])
		}
		return adjusted
	}

	fn present_logo_drag_fixture(window ui2.CustomWindow) {
		assert C.ui2_inside_row_present(window.native_handle()), 'retained presentation did not settle'
	}

	fn read_logo_drag_geometry(window ui2.CustomWindow) {
		assert window.update(fn () {
			mut fixture := unsafe { logo_drag_fixture }
			fixture.logo = ui2.visual_geometry('logo') or { panic(err) }
			fixture.card = ui2.visual_geometry('card') or { panic(err) }
		})
	}

	fn assert_logo_drag_near(actual f64, expected f64) {
		assert math.abs(actual - expected) < 0.0001, '${actual} != ${expected}'
	}

	fn logo_drag_anchor() ui2.Point {
		geometry := unsafe { logo_drag_fixture }.logo
		return geometry.transform.point(geometry.frame.x + 36, geometry.frame.y + 36)
	}

	fn send_logo_drag_pointer(window ui2.CustomWindow, kind int, point ui2.Point) {
		C.ui2_inside_row_pointer(window.native_handle(), kind, point.x, point.y)
		present_logo_drag_fixture(window)
		read_logo_drag_geometry(window)
	}
}

fn test_rotated_logo_callbacks_follow_window_pointer_using_retained_geometry() {
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
		mut state := unsafe { inside_row_state }
		previous_state := *state
		mut fixture := unsafe { logo_drag_fixture }
		defer { unsafe { *state = previous_state } }
		window := ui2.open_window('Rotated logo drag regression', inside_row_width,
			inside_row_height, build_logo_drag_fixture) or { panic(err) }
		defer { window.close() }
		for scenario in 0 .. 3 {
			for rotation in [0.0, 90.0, 180.0, 270.0] {
				unsafe {
					*state = inside_row_demo()
					*fixture = LogoDragFixture{ translated: scenario > 0, scaled: scenario == 2 }
				}
				state.rotation = rotation
				assert window.update(ui2.refresh)
				present_logo_drag_fixture(window)
				read_logo_drag_geometry(window)
				assert_logo_drag_near(fixture.logo.frame.x - fixture.card.frame.x, state.logo_x)
				assert_logo_drag_near(fixture.logo.frame.y - fixture.card.frame.y, state.logo_y)
				scale := if fixture.scaled { 0.75 } else { 1.0 }
				anchor := logo_drag_anchor()
				// Non-centre grab: no jump on down, including rotated corners.
				down := fixture.logo.transform.point(fixture.logo.frame.x + 20,
					fixture.logo.frame.y + 26)
				send_logo_drag_pointer(window, 0, down)
				assert_logo_drag_near(state.logo_x, 92)
				assert_logo_drag_near(state.logo_y, 150)
				grab_x, grab_y := state.grab_x, state.grab_y
				// Independent window movements: right20 must never become up20.
				for step in 1 .. 4 {
					point := ui2.Point{down.x + 20 * step, down.y + 12 * (step - 1)}
					send_logo_drag_pointer(window, if step == 3 { 2 } else { 1 }, point)
					assert_logo_drag_near(state.logo_x, 92 + 20 * step / scale)
					assert_logo_drag_near(state.logo_y, 150 + 12 * (step - 1) / scale)
					assert_logo_drag_near(state.grab_x, grab_x)
					assert_logo_drag_near(state.grab_y, grab_y)
					moved := logo_drag_anchor()
					assert_logo_drag_near(moved.x, anchor.x + 20 * step)
					assert_logo_drag_near(moved.y, anchor.y + 12 * (step - 1))
				}
				assert fixture.events.map(it.kind) == [.pointer_down, .pointer_drag, .pointer_drag,
					.pointer_up]
				for index, record in fixture.events {
					assert_logo_drag_near(record.window.x, down.x + 20 * index)
					assert_logo_drag_near(record.window.y, down.y + 12 * math.max(0, index - 1))
				}
				// Release ends capture: moving again must not change placement.
				C.ui2_inside_row_pointer(window.native_handle(), 1, down.x + 200, down.y + 200)
				assert fixture.events.len == 4
				assert_logo_drag_near(state.logo_x, 92 + 60 / scale)
				assert_logo_drag_near(state.logo_y, 150 + 24 / scale)
			}
		}
	}
}

fn test_logo_callback_clamps_to_presented_card_after_resize_and_missing_geometry_is_ignored() {
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
		mut state := unsafe { inside_row_state }
		previous_state := *state
		mut fixture := unsafe { logo_drag_fixture }
		defer { unsafe { *state = previous_state } }
		unsafe {
			*state = inside_row_demo()
			*fixture = LogoDragFixture{ translated: true }
		}
		state.rotation = 90
		window := ui2.open_window('Logo clamp and resize regression', inside_row_width,
			inside_row_height, build_logo_drag_fixture) or { panic(err) }
		defer { window.close() }
		present_logo_drag_fixture(window)
		read_logo_drag_geometry(window)
		down := fixture.logo.transform.point(fixture.logo.frame.x + 20, fixture.logo.frame.y + 26)
		send_logo_drag_pointer(window, 0, down)
		send_logo_drag_pointer(window, 1, ui2.Point{5000, 5000})
		assert_logo_drag_near(state.logo_x, fixture.card.frame.width - logo_size - 18)
		assert_logo_drag_near(state.logo_y, fixture.card.frame.height - logo_size - 60)
		C.ui2_inside_row_resize(window.native_handle(), 700, 480)
		present_logo_drag_fixture(window)
		read_logo_drag_geometry(window)
		assert fixture.card.frame.width == 668 && fixture.card.frame.height == 448
		send_logo_drag_pointer(window, 1, ui2.Point{5000, 5000})
		assert_logo_drag_near(state.logo_x, 578)
		assert_logo_drag_near(state.logo_y, 316)
		send_logo_drag_pointer(window, 2, ui2.Point{-1000, -1000})
		assert_logo_drag_near(state.logo_x, tray_x)
		assert_logo_drag_near(state.logo_y, pane_y)
		assert fixture.events.map(it.kind) == [.pointer_down, .pointer_drag, .pointer_drag,
			.pointer_up]
		for hide_logo in [true, false] {
			fixture.hide_logo = hide_logo
			fixture.omit_card_id = !hide_logo
			assert window.update(ui2.refresh)
			present_logo_drag_fixture(window)
			before := *state
			assert window.update(fn () {
				fixture := unsafe { logo_drag_fixture }
				if fixture.hide_logo {
					if _ := ui2.visual_geometry('logo') {
						assert false
					}
					ui2.visual_geometry('card') or { panic(err) }
				} else {
					ui2.visual_geometry('logo') or { panic(err) }
					if _ := ui2.visual_geometry('card') {
						assert false
					}
				}
				callback := canvas_layout_inside_row_callbacks()['logo'] or { panic('missing callback') }
				for kind in [ui2.ElementEventKind.pointer_down, .pointer_drag, .pointer_up] {
					callback(ui2.ElementEvent{ kind: kind, id: 'logo', x: 200, y: 200 })
				}
			})
			assert *state == before
		}
	}
}
