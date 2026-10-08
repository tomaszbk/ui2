// Public API runtime fixture: normal GC, real resize, retained redraw, removal,
// local UTF-8 edits/selection/focus and a normal quit with renderer teardown.
@[has_globals]
module main

import time
import ui2
import sokol.gfx
import sokol.sapp

fn C.atexit(callback fn ()) int

__global vector_runtime_started = false
__global vector_runtime_phase = 0
__global vector_runtime_done = false
__global vector_runtime_shapes = []ui2.VectorShape{}

fn build() ui2.Element {
	if !vector_runtime_started {
		vector_runtime_started = true
		spawn verify(ui2.ui_dispatcher())
	}
	mut children := [ui2.text_input(
		id:         'edit'
		text:       'declarado: ñ, á'
		multiline:  true
		frame:      ui2.rect(15, 15, 300, 70)
		box:        ui2.BoxStyle{ bg: 0xffffff }
		text_style: ui2.TextStyle{ size: 15 }
	) or { panic(err) }]
	if vector_runtime_phase != 2 {
		frame := if vector_runtime_phase == 0 {
			ui2.rect(15, 100, 200, 150)
		} else {
			ui2.rect(35, 120, 260, 170)
		}
		children << ui2.vector_canvas(id: 'retained', frame: frame, shapes: vector_runtime_shapes) or { panic(err) }
	}
	children << ui2.scroll('scroll', ui2.rect(240, 100, 160, 150), 0xe2e8f0, [
		ui2.vector_canvas(
			id:     'scroll-shape'
			frame:  ui2.rect(0, -25, 150, 300)
			shapes: vector_runtime_shapes
		) or { panic(err) },
		ui2.label('', 'bottom', ui2.rect(10, 260, 100, 20), ui2.TextStyle{}),
	])
	return ui2.screen(0xf1f5f9, children)
}

fn verify(dispatcher ui2.UiDispatcher) {
	time.sleep(1200 * time.millisecond)
	before := dispatcher.stats()
	time.sleep(500 * time.millisecond)
	after := dispatcher.stats()
	assert after.builds == before.builds
	if !before.presentation_required {
		assert after.draws == before.draws
	}
	println('VECTOR_IDLE builds=${after.builds - before.builds} draws=${after.draws - before.draws} callbacks=${after.callbacks - before.callbacks} presentation_required=${before.presentation_required}')
	assert dispatcher.post(fn () {
		ui2.set_text('edit', 'edición local: ñ, á, é')
		ui2.focus('edit')
		ui2.text_area_set_selection('edit', 2, 5)
		vector_runtime_phase = 1
		assert resize_vector_window(540, 380)
	})
	time.sleep(600 * time.millisecond)
	assert dispatcher.post(fn () {
		assert int(f32(sapp.width()) / sapp.dpi_scale() + 0.5) == 540
		assert int(f32(sapp.height()) / sapp.dpi_scale() + 0.5) == 380
		assert ui2.text('edit') == 'edición local: ñ, á, é'
		assert ui2.focused_id() == 'edit'
		assert ui2.text_area_caret('edit') == 7
		assert ui2.text_area_selection_length('edit') == 5
		vector_runtime_phase = 2
	})
	time.sleep(600 * time.millisecond)
	assert dispatcher.post(fn () {
		assert ui2.text('edit') == 'edición local: ñ, á, é'
		assert ui2.focused_id() == 'edit'
		assert ui2.text_area_caret('edit') == 7
		assert ui2.text_area_selection_length('edit') == 5
		vector_runtime_phase = 3
		assert resize_vector_window(460, 320)
	})
	time.sleep(600 * time.millisecond)
	assert dispatcher.post(fn () {
		assert int(f32(sapp.width()) / sapp.dpi_scale() + 0.5) == 460
		assert int(f32(sapp.height()) / sapp.dpi_scale() + 0.5) == 320
		assert ui2.text('edit') == 'edición local: ñ, á, é'
		assert ui2.text_area_selection_length('edit') == 5
		vector_runtime_done = true
		ui2.quit()
		assert ui2.render_stats().closed
		assert !ui2.ui_dispatcher().post(fn () {})
		println('VECTOR_RUNTIME_OK resize/edit/selection/focus/remove/recreate')
	})
}

fn verify_exit() {
	assert vector_runtime_done
	assert ui2.render_stats().closed
	assert !gfx.is_valid()
	println('VECTOR_TEARDOWN_OK scheduler closed / GPU device released / normal exit')
}

fn main() {
	assert C.atexit(verify_exit) == 0
	mut path := ui2.VectorPath{}
	path.move_to(0, 0)
	path.line_to(180, 0)
	path.quadratic_to(220, 80, 90, 120)
	path.cubic_to(-20, 80, 30, 20, 0, 0)
	path.close()
	vector_runtime_shapes = [ui2.prepare_vector_shape(path, ui2.VectorStyle{ fill: 0x38bdf8, stroke: 0x0369a1, stroke_width: 6, cap: .round, join: .round }) or { panic(err) }]
	ui2.run_window('UI2 Vector Runtime', 420, 300, build)
}
