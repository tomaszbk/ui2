module main

import math
import ui2

const circle_drawer_width = 680
const circle_drawer_height = 520
const circle_canvas_root_x = 34.0
const circle_canvas_root_y = 92.0

pub struct DrawCircle {
pub:
	id    int
	x     f64
	y     f64
	color u32
pub mut:
	radius f64
}

@[heap]
pub struct CircleDrawerDemo {
pub mut:
	circles         []DrawCircle
	selected_id     int = -1
	selected_radius f64
	radius_label    string = 'No selection'
	can_undo        bool
	can_redo        bool
	status          string = 'Click the canvas to add a circle; click a circle to select it.'
mut:
	next_id    int = 1
	undo_stack [][]DrawCircle
	redo_stack [][]DrawCircle
}

const circle_drawer_state = &CircleDrawerDemo{}

fn (mut app CircleDrawerDemo) update_history_flags() {
	app.can_undo = app.undo_stack.len > 0
	app.can_redo = app.redo_stack.len > 0
}

fn (mut app CircleDrawerDemo) checkpoint() {
	app.undo_stack << app.circles.clone()
	app.redo_stack = [][]DrawCircle{}
	app.update_history_flags()
}

fn (app &CircleDrawerDemo) circle_at(x f64, y f64) int {
	for index := app.circles.len - 1; index >= 0; index-- {
		circle := app.circles[index]
		if math.pow(circle.x - x, 2) + math.pow(circle.y - y, 2) <= math.pow(circle.radius, 2) {
			return index
		}
	}
	return -1
}

fn circle_color(id int) u32 {
	colors := [u32(0xbfdbfe), u32(0xbbf7d0), u32(0xfde68a), u32(0xfbcfe8), u32(0xddd6fe)]
	return colors[(id - 1) % colors.len]
}

fn (mut app CircleDrawerDemo) add_or_select(x f64, y f64) {
	index := app.circle_at(x, y)
	if index >= 0 {
		circle := app.circles[index]
		app.selected_id = circle.id
		app.selected_radius = circle.radius
		app.radius_label = 'r = ${int(circle.radius)}'
		app.status = 'Circle ${circle.id} selected.'
		return
	}
	app.checkpoint()
	circle := DrawCircle{
		id:     app.next_id
		x:      x
		y:      y
		radius: 24
		color:  circle_color(app.next_id)
	}
	app.circles << circle
	app.selected_id = circle.id
	app.selected_radius = circle.radius
	app.radius_label = 'r = ${int(circle.radius)}'
	app.next_id++
	app.status = 'Circle ${circle.id} added.'
	app.update_history_flags()
}

fn (mut app CircleDrawerDemo) adjust_radius(delta f64) {
	for index, circle in app.circles {
		if circle.id != app.selected_id {
			continue
		}
		app.checkpoint()
		next_radius := if circle.radius + delta < 12 {
			12.0
		} else if circle.radius + delta > 64 {
			64.0
		} else {
			circle.radius + delta
		}
		app.circles[index].radius = next_radius
		app.selected_radius = next_radius
		app.radius_label = 'r = ${int(next_radius)}'
		app.status = 'Circle ${circle.id} radius: ${int(next_radius)}.'
		app.update_history_flags()
		return
	}
}

fn (mut app CircleDrawerDemo) reconcile_selection() {
	for circle in app.circles {
		if circle.id == app.selected_id {
			app.selected_radius = circle.radius
			app.radius_label = 'r = ${int(circle.radius)}'
			return
		}
	}
	app.selected_id = -1
	app.selected_radius = 0
	app.radius_label = 'No selection'
}

fn (mut app CircleDrawerDemo) undo() {
	if app.undo_stack.len == 0 {
		return
	}
	app.redo_stack << app.circles.clone()
	app.circles = app.undo_stack.last().clone()
	app.undo_stack.delete_last()
	app.reconcile_selection()
	app.update_history_flags()
	app.status = 'Undid the last change.'
}

fn (mut app CircleDrawerDemo) redo() {
	if app.redo_stack.len == 0 {
		return
	}
	app.undo_stack << app.circles.clone()
	app.circles = app.redo_stack.last().clone()
	app.redo_stack.delete_last()
	app.reconcile_selection()
	app.update_history_flags()
	app.status = 'Redid the last change.'
}

fn circle_drawer_callbacks() map[string]ui2.ElementCallback {
	return {
		'undo':          fn (_event ui2.ElementEvent) {
			mut state := unsafe { circle_drawer_state }
			state.undo()
			ui2.refresh()
		}
		'redo':          fn (_event ui2.ElementEvent) {
			mut state := unsafe { circle_drawer_state }
			state.redo()
			ui2.refresh()
		}
		'radius_less':   fn (_event ui2.ElementEvent) {
			mut state := unsafe { circle_drawer_state }
			state.adjust_radius(-4)
			ui2.refresh()
		}
		'radius_more':   fn (_event ui2.ElementEvent) {
			mut state := unsafe { circle_drawer_state }
			state.adjust_radius(4)
			ui2.refresh()
		}
		'circle_canvas': fn (event ui2.ElementEvent) {
			mut state := unsafe { circle_drawer_state }
			if event.kind == .pointer_up {
				state.add_or_select(event.x - circle_canvas_root_x, event.y - circle_canvas_root_y)
			}
			ui2.refresh()
		}
	}
}

fn main() {
	ui2.run_compiled_vml[CircleDrawerDemo](
		build:  build_circle_drawer
		model:  circle_drawer_state
		title:  'Circle Drawer'
		width:  circle_drawer_width
		height: circle_drawer_height
	) or { panic(err) }
}

fn build_circle_drawer(mut app CircleDrawerDemo) ui2.Element {
	callbacks := circle_drawer_callbacks()
	callback_undo := callbacks['undo'] or { panic('missing undo callback') }
	callback_redo := callbacks['redo'] or { panic('missing redo callback') }
	callback_radius_less := callbacks['radius_less'] or { panic('missing radius_less callback') }
	callback_radius_more := callbacks['radius_more'] or { panic('missing radius_more callback') }
	callback_circle_canvas := callbacks['circle_canvas'] or { panic('missing circle_canvas callback') }
	return $vml('circle_drawer.vml')
}

fn circle_drawer_tree(mut app CircleDrawerDemo, frame ui2.Rect) ui2.Element {
	callbacks := circle_drawer_callbacks()
	callback_undo := callbacks['undo'] or { panic('missing undo callback') }
	callback_redo := callbacks['redo'] or { panic('missing redo callback') }
	callback_radius_less := callbacks['radius_less'] or { panic('missing radius_less callback') }
	callback_radius_more := callbacks['radius_more'] or { panic('missing radius_more callback') }
	callback_circle_canvas := callbacks['circle_canvas'] or { panic('missing circle_canvas callback') }
	return $vml('circle_drawer.vml', frame)
}
