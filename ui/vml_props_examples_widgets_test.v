// vtest vflags: -d vml_props
module ui2

// Golden equivalence of hand-written props with the composite widget examples
// used verbatim: tabbed panel, accordion, tree view, screen manager, carousel.

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

struct PropsPagesDemo {
pub mut:
	current int
	log     []string
}

pub fn (mut app PropsPagesDemo) show_overview() {
	app.current = 0
}

pub fn (mut app PropsPagesDemo) show_activity() {
	app.current = 1
}

pub fn (mut app PropsPagesDemo) show_security() {
	app.current = 2
}

pub fn (mut app PropsPagesDemo) show_profile() {
	app.current = 0
}

pub fn (mut app PropsPagesDemo) show_notifications() {
	app.current = 1
}

fn props_pages_action(mut app PropsPagesDemo, current int) ElementCallback {
	return fn [mut app, current] (e ElementEvent) {
		app.current = current
	}
}

fn props_tabbed_panel_compiled(mut app PropsPagesDemo, frame Rect) Element {
	return $vml('../examples/tabbed_panel/tabbed_panel.vml', frame)
}

fn props_tabbed_panel_tree(mut app PropsPagesDemo, frame Rect) PNode {
	return pn(ScreenProps{ style: style_list([style_background(0xF1F5F9)]) }, id: 'root', children: [
		pn(AbsoluteProps{ style: props_transparent() }, children: [
			props_title('Settings', frame),
			pn(TabbedPanelProps{
				x:                     20
				y:                     56
				width:                 frame.width - 40
				height:                220
				current:               app.current
				tab_width:             118
				tab_height:            40
				tab_background:        0xE2E8F0
				active_tab_background: 0xFFFFFF
				tab_color:             0x475569
				active_tab_color:      0x1D4ED8
				style:                 style_list([style_background(0xFFFFFF), style_radius(10)])
			}, id: 'settings', children: [
				pn(TabProps{ text: 'Overview', on_select: props_pages_action(mut app, 0) }, id: 'overview', children: [
					pn(AbsoluteProps{ style: props_transparent() }, children: [
						props_page_label('Account overview', 24, 30, 300, 32, props_heading(0x0F172A,
							22)),
						props_page_label('Reusable content for the active tab.', 24, 70, 330,
							24, style_list([style_foreground(0x64748B)])),
					]),
				]),
				pn(TabProps{ text: 'Activity', on_select: props_pages_action(mut app, 1) }, id: 'activity', children: [
					pn(AbsoluteProps{ style: props_transparent() }, children: [
						props_page_label('Recent activity', 24, 30, 300, 32, props_heading(0x14532D,
							22)),
					]),
				]),
				pn(TabProps{ text: 'Security', on_select: props_pages_action(mut app, 2) }, id: 'security', children: [
					pn(AbsoluteProps{ style: props_transparent() }, children: [
						props_page_label('Security options', 24, 30, 300, 32, props_heading(0x7C2D12,
							22)),
					]),
				]),
			]),
		]),
	])
}

fn test_props_tabbed_panel_example_matches_compiled_vml() {
	for current in [0, 2] {
		frame := rect(0, 0, 440, 300)
		mut compiled_app := PropsPagesDemo{
			current: current
		}
		mut props_app := PropsPagesDemo{
			current: current
		}
		compiled := props_tabbed_panel_compiled(mut compiled_app, frame)
		built := props_document(props_tabbed_panel_tree(mut props_app, frame), frame)!
		assert_props_equal('tabbed panel', compiled, built)
	}
}

fn props_accordion_compiled(mut app PropsPagesDemo, frame Rect) Element {
	return $vml('../examples/accordion_widget/accordion_widget.vml', frame)
}

fn props_accordion_item(mut app PropsPagesDemo, id string, title string, current int, text string, width f64) PNode {
	return pn(AccordionItemProps{ title: title, on_select: props_pages_action(mut app, current) }, id: id, children: [
		pn(AbsoluteProps{ style: props_transparent() }, children: [
			props_page_label(text, 20, 22, width, 28, props_heading(0x0F172A, 18)),
		]),
	])
}

fn props_accordion_tree(mut app PropsPagesDemo, frame Rect) PNode {
	return pn(ScreenProps{ style: style_list([style_background(0xF1F5F9)]) }, id: 'root', children: [
		pn(AbsoluteProps{ style: props_transparent() }, children: [
			props_title('Preferences', frame),
			pn(AccordionProps{
				x:                       20
				y:                       56
				width:                   frame.width - 40
				height:                  244
				current:                 app.current
				orientation:             .vertical
				min_space:               44
				title_background:        0xE2E8F0
				active_title_background: 0x2563EB
				title_color:             0x475569
				active_title_color:      0xFFFFFF
				style:                   style_list([style_background(0xFFFFFF), style_radius(10)])
			}, id: 'preferences', children: [
				props_accordion_item(mut app, 'profile', 'Profile', 0, 'Update your public profile.',
					320),
				props_accordion_item(mut app, 'notifications', 'Notifications', 1, 'Choose which alerts you receive.',
					340),
				props_accordion_item(mut app, 'security', 'Security', 2, 'Review passwords and active sessions.',
					350),
			]),
		]),
	])
}

fn test_props_accordion_example_matches_compiled_vml() {
	for current in [0, 1] {
		frame := rect(0, 0, 440, 320)
		mut compiled_app := PropsPagesDemo{
			current: current
		}
		mut props_app := PropsPagesDemo{
			current: current
		}
		compiled := props_accordion_compiled(mut compiled_app, frame)
		built := props_document(props_accordion_tree(mut props_app, frame), frame)!
		assert_props_equal('accordion', compiled, built)
	}
}

struct PropsTreeDemo {
pub mut:
	docs_open bool
	selected  string = 'welcome'
}

pub fn (mut app PropsTreeDemo) toggle_docs() {
	app.docs_open = !app.docs_open
}

pub fn (mut app PropsTreeDemo) select_welcome() {
	app.selected = 'welcome'
}

pub fn (mut app PropsTreeDemo) select_installation() {
	app.selected = 'installation'
}

pub fn (mut app PropsTreeDemo) select_license() {
	app.selected = 'license'
}

fn props_tree_compiled(mut app PropsTreeDemo, frame Rect) Element {
	return $vml('../examples/tree_view_widget/tree_view_widget.vml', frame)
}

fn props_tree_select(mut app PropsTreeDemo, selected string) ElementCallback {
	return fn [mut app, selected] (e ElementEvent) {
		app.selected = selected
	}
}

fn props_tree_tree(mut app PropsTreeDemo, frame Rect) PNode {
	return pn(ScreenProps{ style: style_list([style_background(0xF1F5F9)]) }, id: 'root', children: [
		pn(AbsoluteProps{ style: props_transparent() }, children: [
			props_title('Project', frame),
			pn(ScrollProps{
				x:      20
				y:      56
				width:  frame.width - 40
				height: 240
				style:  style_list([style_background(0xFFFFFF)])
			}, id: 'navigation_scroll', children: [
				pn(AbsoluteProps{ style: props_transparent() }, children: [
					pn(TreeViewProps{
						width:               frame.width - 40
						height:              240
						row_height:          38
						spacing:             3
						indent:              24
						disclosure_width:    30
						row_background:      0xFFFFFF
						selected_background: 0xDBEAFE
						selected_color:      0x1D4ED8
						style:               style_list([style_foreground(0x334155)])
					}, id: 'navigation', children: [
						pn(TreeNodeProps{
							text:      DisplayText('Documentation')
							expanded:  app.docs_open
							on_toggle: fn [mut app] (e ElementEvent) {
								app.toggle_docs()
							}
						}, id: 'docs', children: [
							pn(TreeNodeProps{
								text:      DisplayText('Welcome')
								selected:  app.selected == 'welcome'
								on_select: props_tree_select(mut app, 'welcome')
							}, id: 'welcome'),
							pn(TreeNodeProps{
								text:      DisplayText('Installation')
								selected:  app.selected == 'installation'
								on_select: props_tree_select(mut app, 'installation')
							}, id: 'installation'),
						]),
						pn(TreeNodeProps{
							text:      DisplayText('License')
							selected:  app.selected == 'license'
							on_select: props_tree_select(mut app, 'license')
						}, id: 'license'),
					]),
				]),
			]),
			pn(LabelProps{
				text:   'Selected: ${app.selected}'
				x:      20
				y:      310
				width:  frame.width - 40
				height: 24
				style:  style_list([style_text_align(.center), style_foreground(0x166534)])
			}),
		]),
	])
}

fn test_props_tree_view_example_matches_compiled_vml() {
	for docs_open in [false, true] {
		frame := rect(0, 0, 460, 360)
		mut compiled_app := PropsTreeDemo{
			docs_open: docs_open
			selected:  'installation'
		}
		mut props_app := PropsTreeDemo{
			docs_open: docs_open
			selected:  'installation'
		}
		compiled := props_tree_compiled(mut compiled_app, frame)
		built := props_document(props_tree_tree(mut props_app, frame), frame)!
		assert_props_equal('tree view', compiled, built)
	}
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
