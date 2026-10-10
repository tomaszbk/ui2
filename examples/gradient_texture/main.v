module main

import math
import ui2

const gradient_texture_width = 700
const gradient_texture_height = 500
const gradient_columns = 20
const gradient_rows = 14

pub struct GradientCell {
pub:
	id     int
	column int
	row    int
	color  u32
}

pub struct GradientTextureDemo {
pub mut:
	cells     []GradientCell
	hue_index int
	hue_name  string
	hue_color u32
	status    string
}

fn gradient_hues() []int {
	return [0, 30, 60, 120, 180, 240, 300]
}

fn gradient_hue_names() []string {
	return ['Red', 'Orange', 'Yellow', 'Green', 'Cyan', 'Blue', 'Magenta']
}

fn hsv_gradient_color(hue int, saturation f64, value f64) u32 {
	sector := (hue / 60) % 6
	fraction := f64(hue % 60) / 60.0
	p := value * (1.0 - saturation)
	q := value * (1.0 - fraction * saturation)
	t := value * (1.0 - (1.0 - fraction) * saturation)
	mut red, mut green, mut blue := value, t, p
	match sector {
		1 {
			red, green, blue = q, value, p
		}
		2 {
			red, green, blue = p, value, t
		}
		3 {
			red, green, blue = p, q, value
		}
		4 {
			red, green, blue = t, p, value
		}
		5 {
			red, green, blue = value, p, q
		}
		else {}
	}
	return (u32(math.round(red * 255)) << 16) | (u32(math.round(green * 255)) << 8) | u32(math.round(blue * 255))
}

fn gradient_demo(index int) GradientTextureDemo {
	mut app := GradientTextureDemo{ hue_index: index }
	app.rebuild()
	return app
}

fn (mut app GradientTextureDemo) rebuild() {
	hues := gradient_hues()
	names := gradient_hue_names()
	app.hue_index = (app.hue_index + hues.len) % hues.len
	hue := hues[app.hue_index]
	mut cells := []GradientCell{cap: gradient_columns * gradient_rows}
	for row in 0 .. gradient_rows {
		saturation := f64(row) / f64(gradient_rows - 1)
		for column in 0 .. gradient_columns {
			value := 1.0 - f64(column) / f64(gradient_columns - 1)
			cells << GradientCell{
				id:     row * gradient_columns + column
				column: column
				row:    row
				color:  hsv_gradient_color(hue, saturation, value)
			}
		}
	}
	app.cells = cells
	app.hue_name = names[app.hue_index]
	app.hue_color = hsv_gradient_color(hue, 1, 1)
	app.status = '${app.hue_name} hue · ${gradient_columns * gradient_rows} generated color tiles'
}

pub fn (mut app GradientTextureDemo) previous_hue() {
	app.hue_index--
	app.rebuild()
}

pub fn (mut app GradientTextureDemo) next_hue() {
	app.hue_index++
	app.rebuild()
}

fn main() {
	mut app := gradient_demo(0)
	ui2.run_compiled_vml[GradientTextureDemo](
		build:  build_gradient_texture
		model:  &app
		title:  'Gradient Texture'
		width:  gradient_texture_width
		height: gradient_texture_height
	) or { panic(err) }
}

fn build_gradient_texture(mut app GradientTextureDemo) ui2.Element {
	return $vml('gradient_texture.vml')
}

fn gradient_texture_tree(mut app GradientTextureDemo, frame ui2.Rect) ui2.Element {
	return $vml('gradient_texture.vml', frame)
}
