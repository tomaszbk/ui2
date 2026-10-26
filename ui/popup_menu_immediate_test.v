@[has_globals]
module ui2

import gg

// No host shows a popup menu before the renderer publishes a window to it
// (platform.v), so here a context menu is the renderer's drawn overlay and a
// select keeps its drawn list, as on Linux.
$if (linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	__global popup_menu_choices = []string{}
	__global popup_menu_results = []PopupMenuResult{}

	fn popup_menu_record(event ElementEvent) {
		popup_menu_choices << event.id
	}

	fn popup_menu_record_result(result PopupMenuResult) {
		popup_menu_results << result
	}

	fn popup_menu_resolve(mut w Window) !Element {
		projected := w.resolve_custom_layout_snapshot(FrameWork{}, measure_layout_text,
			[], true)!
		w.reconcile_mounted_focus_controls(projected)
		w.update_custom_focus_tree(projected)
		return projected
	}

	fn popup_menu_mount(mut w Window, children []Element) !Element {
		w.declared_root = Element{
			kind:     .screen
			id:       'root'
			frame:    rect(0, 0, 400, 300)
			children: children
		}
		w.has_root = true
		w.declaration_pending = true
		return popup_menu_resolve(mut w)!
	}

	fn popup_menu_row(mut w Window, path []int) FocusNode {
		return w.navigation.node(dropdown_menu_item_id(drawn_popup_menu_id, path)) or {
			panic('popup menu row ${path} is not mounted')
		}
	}

	fn popup_menu_press(mut w Window, button gg.MouseButton, x f64, y f64) {
		on_event(&gg.Event{
			typ:          .mouse_down
			mouse_button: button
			mouse_x:      f32(x)
			mouse_y:      f32(y)
		}, mut w)
		on_event(&gg.Event{
			typ:          .mouse_up
			mouse_button: button
			mouse_x:      f32(x)
			mouse_y:      f32(y)
		}, mut w)
	}

	fn popup_menu_key(mut w Window, code KeyCode) {
		assert w.drawn_popup_menu_key(KeyEvent{ code: code })
	}

	fn test_right_press_opens_the_element_menu_as_a_drawn_overlay() ! {
		mut w := &Window{
			ctx: &DrawContext{
				width:  400
				height: 300
			}
		}
		popup_menu_choices.clear()
		area := Element{
			...view('area', rect(20, 20, 200, 120), BoxStyle{}, [
				Element{
					kind:  .button
					id:    'inner'
					frame: rect(10, 10, 80, 28)
				},
			])
			menu: [
				MenuEntry{
					id:        'copy'
					title:     'Copy'
					on_select: popup_menu_record
				},
				MenuEntry{
					id:        'paste'
					title:     'Paste'
					on_select: popup_menu_record
				},
			]
		}
		plain := Element{
			kind:  .button
			id:    'plain'
			frame: rect(250, 20, 100, 28)
		}
		popup_menu_mount(mut w, [area, plain])!
		w.focus('plain')
		popup_menu_press(mut w, .right, 260, 30)
		assert w.popup_menu == unsafe { nil }
		// The press lands on a control inside the element, and bubbles up to it.
		popup_menu_press(mut w, .right, 40, 35)
		assert w.popup_menu != unsafe { nil }
		popup_menu_resolve(mut w)!
		layer := w.overlay_tree.top_active() or { return error('the popup menu is not presented') }
		assert layer.element.id == drawn_popup_menu_id && layer.config.kind == .context_menu
		surface := w.navigation.node(drawn_popup_menu_id) or {
			return error('the popup menu is not mounted')
		}
		assert surface.frame.x == 40 && surface.frame.y == 35
		// The highlight is the menu's cursor; keyboard focus waits for it to close.
		assert w.focused_field == ''
		row := popup_menu_row(mut w, [1])
		popup_menu_press(mut w, .left, row.frame.x + row.frame.width / 2, row.frame.y +
			row.frame.height / 2)
		assert popup_menu_choices == ['paste']
		assert w.popup_menu == unsafe { nil }
		popup_menu_resolve(mut w)!
		if _ := w.overlay_tree.top_active() {
			return error('the closed popup menu is still presented')
		}
		assert w.focused_field == 'plain'
		// A press outside the menu closes it without reaching the control under it.
		popup_menu_press(mut w, .right, 40, 35)
		popup_menu_resolve(mut w)!
		popup_menu_press(mut w, .left, 300, 34)
		assert w.popup_menu == unsafe { nil } && popup_menu_choices == ['paste']
	}

	fn test_drawn_popup_menu_keys_skip_separators_and_disabled_rows_into_submenus() ! {
		mut w := &Window{
			ctx: &DrawContext{
				width:  400
				height: 300
			}
		}
		popup_menu_results.clear()
		popup_menu_mount(mut w, [])!
		items := [
			MenuItem{
				id:    'new'
				title: 'New'
			},
			MenuItem{
				separator: true
			},
			MenuItem{
				id:      'gone'
				title:   'Gone'
				enabled: false
			},
			MenuItem{
				title: 'Export'
				items: [
					MenuItem{
						id:    'pdf'
						title: 'PDF'
					},
					MenuItem{
						id:    'png'
						title: 'PNG'
					},
				]
			},
		]
		w.show_popup_menu(PopupMenuConfig{
			items:  items
			anchor: rect(30, 40, 0, 0)
		}, popup_menu_record_result)
		popup_menu_resolve(mut w)!
		assert !popup_menu_row(mut w, [2]).enabled
		popup_menu_key(mut w, .down)
		assert w.popup_menu.state.path == [0]
		popup_menu_key(mut w, .down)
		assert w.popup_menu.state.path == [3]
		// Highlighting a submenu row opens its submenu beside it.
		popup_menu_resolve(mut w)!
		submenu := popup_menu_row(mut w, [3, 0])
		assert submenu.frame.x >= popup_menu_row(mut w, [3]).frame.x + popup_menu_row(mut w, [3]).frame.width
		popup_menu_key(mut w, .right)
		popup_menu_key(mut w, .down)
		assert w.popup_menu.state.path == [3, 1]
		popup_menu_key(mut w, .left)
		assert w.popup_menu.state.path == [3]
		popup_menu_key(mut w, .enter)
		popup_menu_key(mut w, .enter)
		assert popup_menu_results.len == 1 && popup_menu_results[0].chosen
		assert popup_menu_results[0].item.id == 'pdf'
		assert w.popup_menu == unsafe { nil }
		w.show_popup_menu(PopupMenuConfig{
			items:  items
			anchor: rect(30, 40, 0, 0)
		}, popup_menu_record_result)
		// Every key belongs to the open menu, and Escape dismisses it.
		popup_menu_key(mut w, .a)
		popup_menu_key(mut w, .escape)
		assert popup_menu_results.len == 2 && !popup_menu_results[1].chosen
		assert !w.drawn_popup_menu_key(KeyEvent{ code: .escape })
	}

	fn test_select_keeps_its_drawn_list_without_host_popup_menus() ! {
		mut w := &Window{
			ctx: &DrawContext{
				width:  400
				height: 300
			}
		}
		assert !host_popup_menu_supported(w.backend_native_window())
		popup_menu_mount(mut w, [
			dropdown('size', 'M', ['S', 'M', 'L'], rect(20, 200, 120, 30), BoxStyle{},
				TextStyle{}),
		])!
		// A select's options are not a context menu.
		popup_menu_press(mut w, .right, 40, 215)
		assert w.popup_menu == unsafe { nil }
		popup_menu_press(mut w, .left, 40, 215)
		assert w.dropdown_id == 'size' && w.popup_menu_owner == ''
		// A secondary press closes the open list.
		popup_menu_press(mut w, .right, 300, 100)
		assert w.dropdown_id == '' && w.popup_menu == unsafe { nil }
	}
}
