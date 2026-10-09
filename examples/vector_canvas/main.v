module main

import os
import ui2

// Geometry is prepared once, outside the retained frame/build hot path.
const gallery = &Gallery{}

@[heap]
struct Gallery {
mut:
	cards  []ui2.Element
	status string = 'Click the painted shapes. Holes and empty bounds let the pointer through.'
}

fn shape(path ui2.VectorPath, style ui2.VectorStyle) ui2.VectorShape {
	return ui2.prepare_vector_shape(path, style) or { panic(err) }
}

fn polygon(points []ui2.VectorPoint, style ui2.VectorStyle) ui2.VectorShape {
	return shape(ui2.vector_polygon(points), style)
}

fn on_shape(event ui2.ElementEvent) {
	if event.kind == .tap {
		mut state := unsafe { gallery }
		state.status = 'Paint hit: ${event.id}'
	}
}

fn canvas(id string, shapes []ui2.VectorShape) ui2.Element {
	return ui2.vector_canvas(
		id:              id
		frame:           ui2.rect(12, 38, 280, 112)
		shapes:          shapes
		on_event:        on_shape
		button_behavior: true
		tooltip:         'Only painted geometry responds'
	) or { panic(err) }
}

fn card(index int, title string, subtitle string, content ui2.Element) ui2.Element {
	return ui2.view('card-${index}', ui2.rect(24 + (index % 3) * 320, 86 + (index / 3) * 182, 304, 166),
		ui2.BoxStyle{ bg: 0xffffff, radius: 8 }, [
			ui2.label('', title, ui2.rect(12, 8, 280, 24), ui2.TextStyle{ size: 15, weight: 600, color: 0x172554 }),
			content,
			ui2.label('', subtitle, ui2.rect(12, 145, 280, 18), ui2.TextStyle{ size: 10, color: 0x64748b }),
		])
}

fn make_gallery() []ui2.Element {
	mut cards := []ui2.Element{}
	concave := polygon([ui2.vector_point(15, 10), ui2.vector_point(255, 10), ui2.vector_point(255, 40),
		ui2.vector_point(135, 40), ui2.vector_point(135, 100), ui2.vector_point(15, 100)],
		ui2.VectorStyle{ fill: 0x38bdf8, stroke: 0x0369a1, stroke_width: 3 })
	cards << card(0, 'Concave polygon', 'Segments / shape hits / empty bounds', canvas('polygon', [concave]))
	mut holes := ui2.vector_polygon([ui2.vector_point(15, 10), ui2.vector_point(115, 10),
		ui2.vector_point(115, 100), ui2.vector_point(15, 100)])
	holes.move_to(40, 30)
	holes.line_to(90, 30)
	holes.line_to(90, 80)
	holes.line_to(40, 80)
	holes.close()
	mut holes2 := ui2.vector_polygon([ui2.vector_point(155, 10), ui2.vector_point(255, 10),
		ui2.vector_point(255, 100), ui2.vector_point(155, 100)])
	holes2.move_to(180, 30)
	holes2.line_to(230, 30)
	holes2.line_to(230, 80)
	holes2.line_to(180, 80)
	holes2.close()
	cards << card(1, 'Fill rules', 'even_odd hole (left) / nonzero (right)', canvas('fill-rules', [
		shape(holes, ui2.VectorStyle{ fill: 0xa78bfa, fill_rule: .even_odd }),
		shape(holes2, ui2.VectorStyle{ fill: 0xa78bfa }),
	]))
	mut quadratic := ui2.VectorPath{}
	quadratic.move_to(15, 95)
	quadratic.quadratic_to(135, -75, 255, 95)
	cards << card(2, 'Quadratic Bézier', 'Open contour / implicit fill closure', canvas('quadratic', [shape(quadratic,
		ui2.VectorStyle{ fill: 0x99f6e4, stroke: 0x0f766e, stroke_width: 5, cap: .round })]))
	mut cubic := ui2.VectorPath{}
	cubic.move_to(15, 90)
	cubic.cubic_to(85, -95, 185, 190, 255, 10)
	cards << card(3, 'Cubic Bézier', 'Two controls / stroke-only shape hits', canvas('cubic', [shape(cubic,
		ui2.VectorStyle{ stroke: 0x2563eb, stroke_width: 8, cap: .round, join: .round })]))
	mut caps := []ui2.VectorShape{}
	for i, cap in [ui2.VectorCap.butt, .round, .square] {
		mut line := ui2.VectorPath{}
		line.move_to(35, 20 + i * 35)
		line.line_to(235, 20 + i * 35)
		caps << shape(line, ui2.VectorStyle{ stroke: 0xf97316, stroke_width: 18, cap: cap })
	}
	cards << card(4, 'Stroke caps', 'butt / round / square, top to bottom', canvas('caps', caps))
	mut joins := []ui2.VectorShape{}
	for i, join in [ui2.VectorJoin.miter, .bevel, .round] {
		mut corner := ui2.VectorPath{}
		corner.move_to(15 + i * 90, 100)
		corner.line_to(45 + i * 90, 18)
		corner.line_to(75 + i * 90, 100)
		joins << shape(corner, ui2.VectorStyle{ stroke: 0xfb7185, stroke_width: 14, join: join })
	}
	cards << card(5, 'Stroke joins', 'miter / bevel / round, left to right', canvas('joins', joins))
	mut closed := ui2.VectorPath{}
	closed.move_to(30, 90)
	closed.cubic_to(-20, 10, 120, -25, 140, 65)
	closed.cubic_to(160, -25, 300, 10, 250, 90)
	closed.close()
	cards << card(6, 'Closed curved contour', 'Fill + stroke / closing segment / joins', canvas('closed', [shape(closed,
		ui2.VectorStyle{ fill: 0xfde68a, stroke: 0xb45309, stroke_width: 4, join: .round })]))
	mut clip_path := ui2.VectorPath{}
	clip_path.move_to(-40, 30)
	clip_path.cubic_to(100, -60, 160, 180, 330, 70)
	let_clip := ui2.vector_canvas(
		id:              'clipped'
		frame:           ui2.rect(40, 45, 224, 85)
		shapes:          [shape(clip_path,
			ui2.VectorStyle{ stroke: 0x0d9488, stroke_width: 22, cap: .round })]
		button_behavior: true
		on_event:        on_shape
	) or { panic(err) }
	cards << card(7, 'Frame clipping', 'Geometry outside the canvas cannot hit', let_clip)
	mini := polygon([ui2.vector_point(5, 5), ui2.vector_point(130, 5), ui2.vector_point(65, 48)], ui2.VectorStyle{ fill: 0x818cf8, stroke: 0x4338ca, stroke_width: 2 })
	small := ui2.vector_canvas(
		id:              'scaled'
		frame:           ui2.rect(0, 0, 140, 56)
		shapes:          [mini]
		on_event:        on_shape
		button_behavior: true
	) or { panic(err) }
	scaled := ui2.scaled_content('scale', ui2.rect(12, 38, 280, 112), 140, 56, ui2.BoxStyle{ transparent: true }, [small])
	cards << card(8, 'Shared coordinates', 'ScaledContent 2x / inverse shape hits', scaled)
	return cards
}

fn build() ui2.Element {
	$if android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) {
		state := unsafe { gallery }
		mut children := [
			ui2.label('', 'Vector canvas', ui2.rect(24, 14, 930, 35), ui2.TextStyle{ size: 27, weight: 600, color: 0x172554 }),
			ui2.label('status', state.status, ui2.rect(24, 52, 950, 24), ui2.TextStyle{ size: 13, color: 0x475569 }),
		]
		children << state.cards
		children << ui2.text_input(
			id:         'editor'
			text:       'Español: ñ, á, é — local edits survive vector updates'
			frame:      ui2.rect(24, 646, 944, 34)
			box:        ui2.BoxStyle{ bg: 0xffffff, radius: 6 }
			text_style: ui2.TextStyle{ size: 13 }
		) or { panic(err) }
		return ui2.screen(0xeef2f6, children)
	} $else {
		return ui2.screen(0xffffff, [ui2.label('', 'Vector canvas requires -d ui2_custom_rendering', ui2.rect(24, 24, 900, 40), ui2.TextStyle{ size: 20 })])
	}
}

fn main() {
	mut state := unsafe { gallery }
	state.cards = make_gallery()
	if '--check-geometry' in os.args {
		assert state.cards.len == 9
		println('VECTOR_GALLERY_GEOMETRY_OK')
		return
	}
	ui2.run_window('UI2 Vector Canvas', 992, 704, build)
}
