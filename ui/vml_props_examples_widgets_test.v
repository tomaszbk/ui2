// vtest vflags: -d vml_props
module ui2

// Golden equivalence of hand-written props with the composite widget examples
// used verbatim: screen manager, carousel.

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

struct PropsCarouselDemo {
pub mut:
	index int
}

pub fn (mut app PropsCarouselDemo) previous() {
	app.index = carousel_previous(app.index, 3, true)
}

pub fn (mut app PropsCarouselDemo) next() {
	app.index = carousel_next(app.index, 3, true)
}

fn props_carousel_compiled(mut app PropsCarouselDemo, frame Rect) Element {
	return $vml('../examples/carousel/carousel.vml', frame)
}

fn props_carousel_slide(id string, background u32, text string, color u32, width f64) PNode {
	return pn(CarouselSlideProps{ style: style_list([style_background(background)]) }, id: id, children: [
		pn(AbsoluteProps{ style: props_transparent() }, children: [
			props_page_label(text, 24, 56, width - 48, 44, style_list([
				style_text_align(.center),
				style_foreground(color),
				style_font_size(30),
				style_weight(700),
			])),
		]),
	])
}

fn props_carousel_tree(mut app PropsCarouselDemo, frame Rect) PNode {
	slide_width := frame.width - 40
	return pn(ScreenProps{ style: style_list([style_background(0xF1F5F9)]) }, id: 'root', children: [
		pn(AbsoluteProps{ style: props_transparent() }, children: [
			props_page_label('Carousel', 20, 14, 180, 30, props_heading(0x0F172A, 20)),
			props_page_label('${app.index + 1} / 3', frame.width - 120, 18, 100, 22, style_list([
				style_text_align(.right),
				style_foreground(0x64748B),
			])),
			pn(CarouselProps{
				x:         20
				y:         56
				width:     slide_width
				height:    220
				index:     app.index
				direction: .right
				loop:      true
				style:     style_list([style_background(0xFFFFFF), style_radius(10)])
			}, id: 'gallery', children: [
				props_carousel_slide('ocean', 0xDBEAFE, 'Ocean', 0x1E3A8A, slide_width),
				props_carousel_slide('forest', 0xDCFCE7, 'Forest', 0x14532D, slide_width),
				props_carousel_slide('sunset', 0xFFEDD5, 'Sunset', 0x7C2D12, slide_width),
			]),
			pn(ButtonProps{
				text:     'Previous'
				on_click: fn [mut app] (e ElementEvent) {
					app.previous()
				}
				x:        20
				y:        290
				width:    110
				height:   36
				style:    style_list([style_background(0xFFFFFF), style_foreground(0x1D4ED8),
					style_radius(8)])
			}),
			pn(ButtonProps{
				text:     'Next'
				on_click: fn [mut app] (e ElementEvent) {
					app.next()
				}
				x:        frame.width - 130
				y:        290
				width:    110
				height:   36
				style:    style_list([style_background(0x2563EB), style_foreground(0xFFFFFF),
					style_radius(8)])
			}),
		]),
	])
}

fn test_props_carousel_example_matches_compiled_vml() {
	for index in [0, 2] {
		frame := rect(0, 0, 460, 340)
		mut compiled_app := PropsCarouselDemo{
			index: index
		}
		mut props_app := PropsCarouselDemo{
			index: index
		}
		compiled := props_carousel_compiled(mut compiled_app, frame)
		built := props_document(props_carousel_tree(mut props_app, frame), frame)!
		assert_props_equal('carousel', compiled, built)
	}
}
