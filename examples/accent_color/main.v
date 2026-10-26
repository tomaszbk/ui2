module main

// vml: accent_color.vml

import ui2

const accent_color_width = 800
const accent_color_height = 600
// The three tracks share one geometry, so a pointer position converts with the
// card inset plus the label gutter in front of them.
const track_root_x = 92.0
const track_gutter = 200.0

pub struct AccentSwatch {
pub:
	key   string
	index int
	role  string
	color u32
	label string
}

@[heap]
pub struct AccentColorDemo {
pub mut:
	red         int = 100
	green       int = 40
	blue        int = 150
	red_ratio   f64
	green_ratio f64
	blue_ratio  f64
	accent      u32
	shade       u32
	tint        u32
	font_color  u32
	on_dark     bool
	swatches    []AccentSwatch
	subscribed  bool   = true
	sample      string = 'Accent colors'
	status      string
}

const accent_color_state = &AccentColorDemo{}

fn accent_hex(red int, green int, blue int) u32 {
	return (u32(clamp_channel(red)) << 16) | (u32(clamp_channel(green)) << 8) | u32(clamp_channel(blue))
}

// derive builds the four-color scheme the original example asks the window for:
// a shade at a third of the accent, the accent itself, a tint at five thirds of
// it, and the font color that stays readable on all three.
fn (mut app AccentColorDemo) derive() {
	app.shade = accent_hex(app.red / 3, app.green / 3, app.blue / 3)
	app.accent = accent_hex(app.red, app.green, app.blue)
	app.tint = accent_hex(app.red * 5 / 3, app.green * 5 / 3, app.blue * 5 / 3)
	// The original divides only the blue channel before comparing, which reads
	// as a slip; averaging all three is what keeps the caption legible.
	app.on_dark = (app.red + app.green + app.blue) / 3 < 128
	app.font_color = if app.on_dark { u32(0xffffff) } else { u32(0x111111) }
	app.red_ratio = f64(app.red) / 255.0
	app.green_ratio = f64(app.green) / 255.0
	app.blue_ratio = f64(app.blue) / 255.0
	app.swatches = [
		AccentSwatch{
			key:   'swatch-0'
			index: 0
			role:  'shade'
			color: app.shade
			label: '0 · shade'
		},
		AccentSwatch{
			key:   'swatch-1'
			index: 1
			role:  'accent'
			color: app.accent
			label: '1 · accent'
		},
		AccentSwatch{
			key:   'swatch-2'
			index: 2
			role:  'tint'
			color: app.tint
			label: '2 · tint'
		},
		AccentSwatch{
			key:   'swatch-3'
			index: 3
			role:  'font'
			color: app.font_color
			label: '3 · font'
		},
	]
	app.status = 'Accent #${app.accent:06X} · shade #${app.shade:06X} · tint #${app.tint:06X} · font #${app.font_color:06X}'
}

fn accent_color_demo() AccentColorDemo {
	mut app := AccentColorDemo{}
	app.derive()
	return app
}

fn clamp_channel(value int) int {
	if value < 0 {
		return 0
	}
	return if value > 255 { 255 } else { value }
}

pub fn (mut app AccentColorDemo) set_channel(name string, value int) {
	channel := clamp_channel(value)
	match name {
		'red' {
			app.red = channel
		}
		'green' {
			app.green = channel
		}
		else {
			app.blue = channel
		}
	}
	app.derive()
}

pub fn (mut app AccentColorDemo) set_fraction(name string, fraction f64) {
	clamped := if fraction < 0 {
		0.0
	} else if fraction > 1 {
		1.0
	} else {
		fraction
	}
	app.set_channel(name, int(clamped * 255.0 + 0.5))
}

pub fn (mut app AccentColorDemo) reset() {
	app.red = 100
	app.green = 40
	app.blue = 150
	app.derive()
	app.status = 'Accent reset to #${app.accent:06X}.'
}

pub fn (mut app AccentColorDemo) toggle_subscribed() {
	app.subscribed = !app.subscribed
}

fn accent_track_width(frame ui2.Rect) f64 {
	return frame.width - 32.0 - track_gutter
}

fn accent_color_callbacks() map[string]ui2.ElementCallback {
	return {
		'reset':        callback_reset
		'subscribe':    callback_subscribe
		'sample_input': callback_sample_input
		'track_red':    callback_track_red
		'track_green':  callback_track_green
		'track_blue':   callback_track_blue
	}
}

fn callback_reset(event ui2.ElementEvent) {
	mut state := unsafe { accent_color_state }
	state.reset()
	event.window.request_refresh()
}

fn callback_subscribe(event ui2.ElementEvent) {
	mut state := unsafe { accent_color_state }
	state.subscribed = event.checked
	event.window.request_refresh()
}

fn callback_sample_input(event ui2.ElementEvent) {
	mut state := unsafe { accent_color_state }
	state.sample = event.text
	event.window.request_refresh()
}

fn callback_track_red(event ui2.ElementEvent) {
	mut state := unsafe { accent_color_state }
	state.track_channel('red', event, accent_track_width(event.window.bounds()))
	event.window.request_refresh()
}

fn callback_track_green(event ui2.ElementEvent) {
	mut state := unsafe { accent_color_state }
	state.track_channel('green', event, accent_track_width(event.window.bounds()))
	event.window.request_refresh()
}

fn callback_track_blue(event ui2.ElementEvent) {
	mut state := unsafe { accent_color_state }
	state.track_channel('blue', event, accent_track_width(event.window.bounds()))
	event.window.request_refresh()
}

fn main() {
	mut state := unsafe { accent_color_state }
	unsafe {
		*state = accent_color_demo()
	}
	ui2.run_compiled_vml[AccentColorDemo](
		build:  build_accent_color
		model:  accent_color_state
		title:  'Accent Color'
		width:  accent_color_width
		height: accent_color_height
	) or { panic(err) }
}

fn (mut app AccentColorDemo) track_channel(channel string, event ui2.ElementEvent, track_width f64) {
	if event.kind in [.pointer_down, .pointer_drag, .pointer_up] && track_width > 0 {
		app.set_fraction(channel, (event.x - track_root_x) / track_width)
	}
}

fn build_accent_color(mut app AccentColorDemo) ui2.Element {
	return accent_color_vml(mut app)
}

fn accent_color_tree(mut app AccentColorDemo, frame ui2.Rect) ui2.Element {
	return accent_color_vml_framed(mut app, frame)
}

pub fn (app &AccentColorDemo) display_color() string {
	return '#${app.accent:06X}'
}
