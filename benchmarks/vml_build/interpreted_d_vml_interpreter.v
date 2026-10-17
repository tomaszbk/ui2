module main

import time
import ui2

// The interpreted lowering of form.vml (`-d vml_interpreter`): every build
// parses and checks the source, then declares the same generic nodes as the
// generic lowering.
const form_source = $embed_file('form.vml').to_string()

fn build_interpreted(mut app Calculator, frame ui2.Rect) ui2.Element {
	return ui2.vml_interpret(form_source, app, frame: frame) or { panic(err) }
}

fn measure_interpreted(mut app Calculator, frame ui2.Rect, iterations int) {
	measure('interpreted', build_interpreted, mut app, frame, iterations)
	// Loading alone: parsing and checking against the model's type.
	model := ui2.vml_model(app)
	mut watch := time.new_stopwatch()
	before := ui2.gc_allocation_snapshot() or { panic(err) }
	for _ in 0 .. iterations {
		ui2.vml_interpreter(form_source, model, frame: frame) or { panic(err) }
	}
	after := ui2.gc_allocation_snapshot() or { panic(err) }
	elapsed := watch.elapsed()
	delta := after.delta_since(before)
	println('interpreted load (parse and check): ${f64(elapsed) / f64(time.microsecond) / iterations:.3f} us, ${f64(delta.allocated_bytes) / iterations:.1f} bytes per load')
}
