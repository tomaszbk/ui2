module main

import ui2

const counter_width = 540
const counter_height = 264

pub struct CounterApp {
pub mut:
	events     int
	last_value int
	mounted    int
	cleaned    int
	unmounted  int
}

pub fn (mut app CounterApp) observe(value int) {
	app.events++
	app.last_value = value
}

pub fn (mut app CounterApp) counter_mounted() { app.mounted++ }

pub fn (mut app CounterApp) counter_cleaned() { app.cleaned++ }

pub fn (mut app CounterApp) counter_unmounted() { app.unmounted++ }

fn main() {
	mut app := CounterApp{}
	ui2.run_compiled_vml[CounterApp](
		build:  build_counter
		model:  &app
		title:  'Independent counters'
		width:  counter_width
		height: counter_height
	) or { panic(err) }
}

fn build_counter(mut app CounterApp) ui2.Element {
	return $vml('app.vml')
}

fn counter_tree(mut app CounterApp, frame ui2.Rect) ui2.Element {
	return $vml('app.vml', frame)
}
