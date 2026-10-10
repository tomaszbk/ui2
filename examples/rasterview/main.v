module main

import os
import ui2

const rasterview_width = 560
const rasterview_height = 500

pub struct RasterviewDemo {
pub:
	image_path string
pub mut:
	show_details bool   = true
	status       string = 'Bundled repository logo loaded.'
}

fn raster_logo_path() string {
	$if windows {
		return os.real_path(os.join_path(os.dir(@FILE), '..', 'users', 'logo.bmp'))
	} $else {
		return os.real_path(os.join_path(os.dir(@FILE), '..', 'users', 'logo.png'))
	}
}

fn initial_rasterview() RasterviewDemo {
	return RasterviewDemo{ image_path: raster_logo_path() }
}

pub fn (mut app RasterviewDemo) toggle_details() {
	app.show_details = !app.show_details
	app.status = if app.show_details { 'Image details shown.' } else { 'Image details hidden.' }
}

fn main() {
	$if windows && !ui2_custom_rendering ? {
		eprintln('Raster View requires -d ui2_custom_rendering on Windows for proportional image fitting.')
		return
	}
	mut app := initial_rasterview()
	ui2.run_compiled_vml[RasterviewDemo](
		build:  build_rasterview
		model:  &app
		title:  'Raster View'
		width:  rasterview_width
		height: rasterview_height
	) or { panic(err) }
}

fn build_rasterview(mut app RasterviewDemo) ui2.Element {
	return $vml('rasterview.vml')
}

fn rasterview_tree(mut app RasterviewDemo, frame ui2.Rect) ui2.Element {
	return $vml('rasterview.vml', frame)
}
