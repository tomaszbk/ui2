module main

// vml: form.vml

import os
import time
import ui2

const default_iterations = 1_000
const default_rows = 5

struct Key {
pub:
	text   string
	role   string
	row    int
	column int
}

pub struct Calculator {
pub mut:
	display string
	keys    []Key
}

fn benchmark_model(rows int) Calculator {
	mut keys := []Key{cap: rows * 4}
	for row in 0 .. rows {
		for column in 0 .. 4 {
			keys << Key{
				text:   '${row * 4 + column}'
				role:   if column == 3 { 'operator' } else { 'digit' }
				row:    row
				column: column
			}
		}
	}
	return Calculator{
		display: '12345'
		keys:    keys
	}
}

fn build_compiled(mut app Calculator, frame ui2.Rect) ui2.Element {
	return form_vml_framed(mut app, frame)
}

fn consume_and_dispose(root ui2.Element) int {
	checksum := root.children[0].children.len
	if root.compiled_node != unsafe { nil } {
		root.compiled_node.dispose_document() or { panic(err) }
	}
	return checksum
}

fn main() {
	iterations := if os.args.len > 1 { os.args[1].int() } else { default_iterations }
	rows := if os.args.len > 2 { os.args[2].int() } else { default_rows }
	mode := if os.args.len > 3 { os.args[3] } else { 'compiled' }
	if iterations <= 0 || rows <= 0 || mode !in ['compiled', 'generic', 'both', 'interpreted',
		'all'] {
		eprintln('usage: ${os.args[0]} [positive iteration count] [positive row count] [compiled|generic|both|interpreted|all]')
		exit(1)
	}
	mut app := benchmark_model(rows)
	frame := ui2.rect(0, 0, 800, 600)
	println('iterations: ${iterations}')
	println('keys:       ${app.keys.len}')
	if mode in ['compiled', 'both', 'all'] {
		measure('compiled', build_compiled, mut app, frame, iterations)
	}
	if mode in ['generic', 'both', 'all'] {
		measure('generic', build_generic, mut app, frame, iterations)
	}
	if mode in ['interpreted', 'all'] {
		measure_interpreted(mut app, frame, iterations)
	}
}

fn measure(name string, build fn (mut Calculator, ui2.Rect) ui2.Element, mut app Calculator, frame ui2.Rect, iterations int) {
	first_before := ui2.gc_allocation_snapshot() or { panic(err) }
	_ = consume_and_dispose(build(mut app, frame))
	first := ui2.gc_allocation_snapshot() or { panic(err) }
	first_delta := first.delta_since(first_before)
	mut checksum := 0
	mut watch := time.new_stopwatch()
	before := ui2.gc_allocation_snapshot() or { panic(err) }
	for _ in 0 .. iterations {
		checksum += consume_and_dispose(build(mut app, frame))
	}
	after := ui2.gc_allocation_snapshot() or { panic(err) }
	elapsed := watch.elapsed()
	delta := after.delta_since(before)
	println('${name} first build/dispose: ${first_delta.allocated_bytes} bytes; ${first_delta.collections} GC collections')
	println('${name} build/dispose: ${f64(elapsed) / f64(time.millisecond):.3f} ms')
	println('per build:    ${f64(elapsed) / f64(time.microsecond) / iterations:.3f} us')
	println('bytes:        ${delta.allocated_bytes}')
	println('bytes/build:  ${f64(delta.allocated_bytes) / iterations:.1f}')
	println('GC collections: ${delta.collections}')
	println('checksum:     ${checksum}')
}
