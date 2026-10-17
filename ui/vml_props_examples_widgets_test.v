// vtest vflags: -d vml_props
module ui2

// Golden equivalence of hand-written props with the screen manager example
// used verbatim.

fn props_title(text string, frame Rect) PNode {
	return pn(LabelProps{
		text:   text
		x:      20
		y:      14
		width:  frame.width - 40
		height: 30
		style:  style_list([style_foreground(0x0F172A), style_font_size(20), style_weight(700)])
	})
}

fn props_transparent() StylePatch {
	return style_list([style_transparent(true)])
}

fn props_page_label(text string, x f64, y f64, width f64, height f64, style StylePatch) PNode {
	return pn(LabelProps{
		text:   text
		x:      x
		y:      y
		width:  width
		height: height
		style:  style
	})
}

fn props_heading(color u32, size f64) StylePatch {
	return style_list([style_foreground(color), style_font_size(size), style_weight(700)])
}

struct PropsScreensDemo {
pub mut:
	current string
}

pub fn (mut app PropsScreensDemo) show_home() {
	app.current = 'home'
}

pub fn (mut app PropsScreensDemo) show_details() {
	app.current = 'details'
}

fn props_screens_compiled(mut app PropsScreensDemo, frame Rect) Element {
	return $vml('../examples/screen_manager/screen_manager.vml', frame)
}

fn props_screen_button(mut app PropsScreensDemo, text string, current string, width f64, style StylePatch) PNode {
	return pn(ButtonProps{
		text:     text
		on_click: fn [mut app, current] (e ElementEvent) {
			app.current = current
		}
		x:        24
		y:        116
		width:    width
		height:   38
		style:    style
	})
}

fn props_screens_tree(mut app PropsScreensDemo, frame Rect) PNode {
	return pn(ScreenProps{ style: style_list([style_background(0xF1F5F9)]) }, id: 'root', children: [
		pn(AbsoluteProps{ style: props_transparent() }, children: [
			props_title('Screen manager', frame),
			pn(ScreenManagerProps{
				x:       20
				y:       56
				width:   frame.width - 40
				height:  240
				current: app.current
				style:   style_list([style_background(0xFFFFFF), style_radius(10)])
			}, id: 'navigation', children: [
				pn(ScreenProps{}, id: 'home', children: [
					pn(AbsoluteProps{ style: props_transparent() }, children: [
						props_page_label('Home', 24, 26, 240, 34, props_heading(0x0F172A, 24)),
						props_page_label('Only this screen is mounted.', 24, 68, 300, 24, style_list([
							style_foreground(0x64748B),
						])),
						props_screen_button(mut app, 'Open details', 'details', 140, style_list([
							style_background(0x2563EB),
							style_foreground(0xFFFFFF),
							style_radius(8),
						])),
					]),
				]),
				pn(ScreenProps{ style: style_list([style_background(0xEFF6FF)]) }, id: 'details', children: [
					pn(AbsoluteProps{ style: props_transparent() }, children: [
						props_page_label('Details', 24, 26, 240, 34, props_heading(0x1E3A8A, 24)),
						props_page_label('State-driven navigation keeps content isolated.', 24, 68,
							340, 24, style_list([style_foreground(0x475569)])),
						props_screen_button(mut app, 'Back home', 'home', 120, style_list([
							style_background(0xFFFFFF),
							style_foreground(0x1D4ED8),
							style_radius(8),
						])),
					]),
				]),
			]),
		]),
	])
}

fn test_props_screen_manager_example_matches_compiled_vml() {
	for current in ['', 'details'] {
		frame := rect(0, 0, 440, 320)
		mut compiled_app := PropsScreensDemo{
			current: current
		}
		mut props_app := PropsScreensDemo{
			current: current
		}
		compiled := props_screens_compiled(mut compiled_app, frame)
		built := props_document(props_screens_tree(mut props_app, frame), frame)!
		assert_props_equal('screen manager', compiled, built)
	}
}
