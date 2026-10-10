module main

import ui2

const dynamic_layout_width = 640
const dynamic_layout_height = 420

pub struct DynamicItem {
pub:
	id    int
	label string
}

pub struct DynamicLayoutDemo {
pub mut:
	items        []DynamicItem
	next_id      int
	items_hidden bool
	status       string
}

fn initial_dynamic_layout() DynamicLayoutDemo {
	return DynamicLayoutDemo{
		items:   [DynamicItem{ id: 1, label: 'Button 1' }]
		next_id: 2
		status:  '1 button'
	}
}

fn (mut app DynamicLayoutDemo) update_status() {
	app.status = if app.items.len == 1 { '1 button' } else { '${app.items.len} buttons' }
}

pub fn (mut app DynamicLayoutDemo) add_last() {
	app.items << DynamicItem{
		id:    app.next_id
		label: 'Button ${app.next_id}'
	}
	app.next_id++
	app.update_status()
}

pub fn (mut app DynamicLayoutDemo) add_two() {
	app.add_last()
	app.add_last()
}

pub fn (mut app DynamicLayoutDemo) remove_last() {
	if app.items.len > 0 {
		app.items.delete_last()
	}
	app.update_status()
}

pub fn (mut app DynamicLayoutDemo) remove_second() {
	if app.items.len > 1 {
		app.items.delete(1)
	}
	app.update_status()
}

pub fn (mut app DynamicLayoutDemo) move_first() {
	if app.items.len < 2 {
		return
	}
	first := app.items[0]
	app.items.delete(0)
	app.items << first
}

pub fn (mut app DynamicLayoutDemo) toggle_items() {
	app.items_hidden = !app.items_hidden
}

pub fn (mut app DynamicLayoutDemo) rename(id int) {
	for index, item in app.items {
		if item.id == id {
			app.items[index] = DynamicItem{
				...item
				label: '${item.label} ✓'
			}
			return
		}
	}
}

fn main() {
	mut app := initial_dynamic_layout()
	ui2.run_compiled_vml[DynamicLayoutDemo](
		build:  build_dynamic_layout
		model:  &app
		title:  'Dynamic Layout'
		width:  dynamic_layout_width
		height: dynamic_layout_height
	) or { panic(err) }
}

fn build_dynamic_layout(mut app DynamicLayoutDemo) ui2.Element {
	return $vml('dynamic_layout.vml')
}

fn dynamic_layout_tree(mut app DynamicLayoutDemo, frame ui2.Rect) ui2.Element {
	return $vml('dynamic_layout.vml', frame)
}
