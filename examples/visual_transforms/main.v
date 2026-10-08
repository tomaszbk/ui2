@[has_globals]
module main

import math
import os
import ui2

__global camera = ui2.PanZoom{ x: 18, y: 12, zoom: 1 }
__global pointer_window = ui2.Point{}
__global has_pointer = false
__global dragging = false

fn main() {
	$if macos || windows {
		$if !ui2_custom_rendering ? {
			eprintln('Run with -d ui2_custom_rendering')
			return
		}
	}
	ui2.run_window('Visual transforms · drag the blue canvas, zoom at pointer', 920, 680, build)
}

fn camera_event(event ui2.ElementEvent) {
	if event.kind !in [.pointer_down, .pointer_drag, .pointer_up] { return }
	if event.kind == .pointer_up { dragging = false }
	geometry := ui2.visual_geometry('camera') or { return }
	window := geometry.transform.point(event.x, event.y)
	if event.kind == .pointer_down { dragging = true }
	if event.kind == .pointer_drag && dragging {
		delta := geometry.parent_transform.inverse_vector(window.x - pointer_window.x, window.y - pointer_window.y)
		camera = camera.pan(delta.x, delta.y) or { return }
	}
	pointer_window = window
	has_pointer = true
	// Even pointer-down/up are presentation-only callbacks.
	ui2.set_visual_transform('camera', camera.transform()) or { eprintln(err) }
}

fn zoom(factor f64) {
	mut anchor := ui2.Point{200, 140}
	if has_pointer {
		geometry := ui2.visual_geometry('camera') or { return }
		x, y := geometry.parent_transform.inverse(pointer_window.x, pointer_window.y)
		anchor = ui2.Point{x - geometry.frame.x, y - geometry.frame.y}
	}
	camera = camera.zoom_at(math.clamp(camera.zoom * factor, 0.4, 3.0), anchor) or { return }
	ui2.set_visual_transform('camera', camera.transform()) or { eprintln(err) }
}

fn build() ui2.Element {
	style := ui2.TextStyle{ size: 17, color: 0x17233c }
	mut rows := []ui2.Element{}
	for i in 0 .. 12 {
		rows << ui2.label('row-${i}', 'Rotated scroll · fila ${i + 1} · ñ á é', ui2.rect(12, i * 30, 276, 28), style)
	}
	editor := ui2.text_input(
		id:         'draft'
		text:       'Selección: año, café, pingüino'
		frame:      ui2.rect(10, 38, 276, 82)
		box:        ui2.BoxStyle{ bg: 0xffffff, radius: 5 }
		text_style: style
		keyboard:   0
		multiline:  true
	) or { panic(err) }
	field := ui2.text_input(
		id:         'field'
		text:       'Caret e IME · España'
		frame:      ui2.rect(10, 132, 276, 36)
		box:        ui2.BoxStyle{ bg: 0xffffff, radius: 5 }
		text_style: style
		keyboard:   0
		multiline:  false
	) or { panic(err) }
	plane := ui2.with_event(ui2.draggable_view('camera', ui2.rect(0, 0, 450, 240), ui2.BoxStyle{ bg: 0xdbeafe, border_color: 0x2563eb, border_left: 2, border_top: 2, border_right: 2, border_bottom: 2 }, [
		ui2.label('canvas-title', 'Pan / zoom at the last pointer', ui2.rect(20, 20, 400, 30), ui2.TextStyle{ ...style, size: 22, weight: 700 }),
		ui2.with_transform(ui2.view('tile', ui2.rect(60, 72, 160, 90), ui2.BoxStyle{ bg: 0x2563eb, radius: 12 }, [
			ui2.label('tile-text', 'Full affine\nglyphs + border', ui2.rect(10, 10, 140, 70), ui2.TextStyle{ size: 19, color: 0xffffff, lines: 2 }),
		]), ui2.VisualTransform{ rotation: -12, scale_x: 1.1, scale_y: 0.8, origin_x: 80, origin_y: 45 }),
		ui2.with_transform(ui2.image('image', os.join_path(os.dir(@FILE), '..', 'users', 'logo.png'), ui2.rect(286, 64, 90, 110)), ui2.VisualTransform{ rotation: 28, origin_x: 45, origin_y: 55 }),
	]), camera_event)
	// A Scroll with content fitting its viewport still supplies a rectangular clip.
	camera_view := ui2.scroll('camera-viewport', ui2.rect(90, 294, 450, 260), 0xf1f5f9, [ui2.with_transform(plane, camera.transform())])
	panel := ui2.view('editor-panel', ui2.rect(600, 70, 300, 186), ui2.BoxStyle{ bg: 0xe2e8f0, radius: 6 }, [
		ui2.label('editor-title', 'Edit / select under rotation', ui2.rect(10, 5, 278, 30), style),
		editor,
		field,
	])
	slide := ui2.scaled_content('composition', ui2.rect(20, 72, 880, 520), 1000, 600, ui2.BoxStyle{ bg: 0xf8fafc }, [
		ui2.with_transform(ui2.scroll('rotated-scroll', ui2.rect(65, 38, 310, 200), 0xe2e8f0, rows), ui2.VisualTransform{ rotation: 14, origin_x: 155, origin_y: 100 }),
		ui2.with_transform(panel, ui2.VisualTransform{ rotation: -9, scale_x: 0.95, scale_y: 1.05, origin_x: 150, origin_y: 93 }),
		ui2.with_transform(camera_view, ui2.VisualTransform{ rotation: 5, origin_x: 225, origin_y: 130 }),
	])
	return ui2.screen(0xffffff, [
		ui2.label('heading', 'Affine presentation · exact clips · logical layout', ui2.rect(24, 16, 840, 34), ui2.TextStyle{ ...style, size: 25, weight: 700 }),
		slide,
		ui2.with_event(ui2.button('zoom-in', 'Zoom +', ui2.rect(24, 610, 110, 38), ui2.BoxStyle{ bg: 0xdbeafe, radius: 6 }, style), fn (event ui2.ElementEvent) {
			if event.kind == .tap { zoom(1.2) }
		}),
		ui2.with_event(ui2.button('zoom-out', 'Zoom −', ui2.rect(148, 610, 110, 38), ui2.BoxStyle{ bg: 0xdbeafe, radius: 6 }, style), fn (event ui2.ElementEvent) {
			if event.kind == .tap { zoom(1 / 1.2) }
		}),
		ui2.label('hint', 'Drag blue canvas. Wheel follows the rotated scroll axis. Type / select in both editors.', ui2.rect(282, 608, 612, 52), ui2.TextStyle{ ...style, size: 14, lines: 2 }),
	])
}
