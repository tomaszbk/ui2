// vfmt off
// The renderer's popup menus: an element's context menu (Element.menu) and a
// select's options. The host shows them natively where it can
// (host_show_popup_menu, platform.v). Elsewhere the renderer draws a context
// menu as a context-menu overlay laid out like a dropdown menu
// (component_popovers_menu.v), and a select keeps its drawn list
// (ui_immediate.c.v).
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
	// The id of the drawn popup menu's overlay. Its rows and levels are parts of
	// it (dropdown_menu_item_id).
	const drawn_popup_menu_id = 'ui2:popup-menu'

	// DrawnPopupMenu is a popup menu the renderer draws: one context-menu
	// overlay holding the menu and every submenu its highlight opens. `anchor`
	// is in the overlay layer's coordinates, below a drawn menu bar.
	@[heap]
	struct DrawnPopupMenu {
	mut:
		serial    u64
		items     []MenuItem
		rows      []DropdownMenuItem
		state     DropdownMenuState
		anchor    Rect
		on_result PopupMenuCallback = unsafe { nil }
		// The overlay laid out for state and viewport, while laid_out holds.
		layer    Element
		viewport Rect
		laid_out bool
	}

	// show_popup_menu opens a popup menu over the window. on_result runs once,
	// on the UI thread: a native menu's result in the window's next task
	// drain, a drawn menu's in the input event that closed it.
	fn (mut w Window) show_popup_menu(cfg PopupMenuConfig, on_result PopupMenuCallback) {
		if host_popup_menu_supported(w.os_window) {
			window := UiDispatcher{
				coordinator: w.scheduler
			}
			host_show_popup_menu(w.os_window, cfg, fn [window, on_result] (result PopupMenuResult) {
				window.post(fn [on_result, result] () {
					on_result(result)
				})
			})
			return
		}
		w.open_drawn_popup_menu(cfg, on_result)
	}

	fn (mut w Window) popup_menu_scale() f64 {
		return if w.ctx != unsafe { nil } && w.ctx.scale > 0 {
			f64(w.ctx.scale)
		} else {
			1.0
		}
	}

	// open_drawn_popup_menu replaces any drawn popup menu, which reports a
	// dismissal first. A renderer without overlays has nowhere to draw one.
	fn (mut w Window) open_drawn_popup_menu(cfg PopupMenuConfig, on_result PopupMenuCallback) {
		w.dismiss_drawn_popup_menu()
		if !backend_supports_overlays || cfg.items.len == 0 {
			on_result(PopupMenuResult{})
			return
		}
		w.popup_menu_serial++
		rows := dropdown_menu_items_from_menu(cfg.items)
		mut path := []int{}
		if cfg.selected >= 0 && cfg.selected < rows.len && dropdown_menu_navigable(rows[cfg.selected]) {
			path << cfg.selected
		}
		w.popup_menu = &DrawnPopupMenu{
			serial:    w.popup_menu_serial
			items:     cfg.items
			rows:      rows
			state:     DropdownMenuState{
				open: true
				path: path
			}
			anchor:    rect(cfg.anchor.x, cfg.anchor.y - w.menu_bar_height(), cfg.anchor.width,
				cfg.anchor.height)
			on_result: on_result
		}
		w.scheduler.invalidate(.layout)
	}

	fn (mut w Window) drawn_popup_menu_open() bool {
		return w != unsafe { nil } && w.popup_menu != unsafe { nil }
	}

	fn (mut w Window) finish_drawn_popup_menu(serial u64, result PopupMenuResult) {
		menu := w.popup_menu
		if menu == unsafe { nil } || menu.serial != serial {
			return
		}
		w.popup_menu = unsafe { nil }
		w.scheduler.invalidate(.layout)
		menu.on_result(result)
	}

	fn (mut w Window) dismiss_drawn_popup_menu() {
		if w.drawn_popup_menu_open() {
			w.finish_drawn_popup_menu(w.popup_menu.serial, PopupMenuResult{})
		}
	}

	// drawn_popup_menu_step applies a step its rows or keys asked for: a row
	// chosen, the menu closed, or the highlight moved, which can open or close
	// a submenu.
	fn (mut w Window) drawn_popup_menu_step(serial u64, step DropdownMenuStep) {
		mut menu := w.popup_menu
		if menu == unsafe { nil } || menu.serial != serial {
			return
		}
		if step.chosen {
			item := popup_menu_item_at(menu.items, step.path) or { MenuItem{} }
			w.finish_drawn_popup_menu(serial, PopupMenuResult{
				chosen: true
				item:   item
			})
			return
		}
		if !step.state.open {
			w.finish_drawn_popup_menu(serial, PopupMenuResult{})
			return
		}
		if step.state == menu.state {
			return
		}
		menu.state = step.state
		menu.laid_out = false
		w.scheduler.invalidate(.layout)
	}

	// popup_menu_item_at follows path through submenus, as
	// dropdown_menu_items_from_menu keeps one row for every item.
	fn popup_menu_item_at(items []MenuItem, path []int) ?MenuItem {
		mut level := unsafe { items }
		for depth, index in path {
			if index < 0 || index >= level.len {
				return none
			}
			if depth == path.len - 1 {
				return level[index]
			}
			level = unsafe { level[index].items }
		}
		return none
	}

	// drawn_popup_menu_key moves the highlight of an open drawn popup menu. Like
	// a native menu it takes every key while it is open.
	fn (mut w Window) drawn_popup_menu_key(event KeyEvent) bool {
		menu := w.popup_menu
		if menu == unsafe { nil } {
			return false
		}
		if step := dropdown_menu_key(menu.rows, menu.state, event) {
			w.drawn_popup_menu_step(menu.serial, step)
		}
		return true
	}

	// drawn_popup_menu_blocks reports whether a wheel at a window point must not
	// scroll: it would move the content out from under an open drawn popup menu.
	fn (mut w Window) drawn_popup_menu_blocks(x f64, y f64) bool {
		if !w.drawn_popup_menu_open() {
			return false
		}
		node := w.navigation.node(drawn_popup_menu_id) or { return true }
		return !hit_target_contains(w.custom_focus_target(node), x, y)
	}

	// with_drawn_popup_menu presents an open drawn popup menu as the root's last
	// overlay, above every declared one. A viewport too small to lay it out in
	// shows nothing until the next frame tries again.
	fn (mut w Window) with_drawn_popup_menu(root Element, viewport Rect) Element {
		mut menu := w.popup_menu
		if menu == unsafe { nil } {
			return root
		}
		if !menu.laid_out || menu.viewport != viewport {
			menu.layer = w.drawn_popup_menu_layer(menu, viewport) or { return root }
			menu.viewport = viewport
			menu.laid_out = true
		}
		mut children := []Element{cap: root.children.len + 1}
		children << root.children
		children << menu.layer
		return Element{
			...root
			children: children
		}
	}

	// drawn_popup_menu_layer lays the open levels out as a dropdown menu does,
	// at the anchor and inside the viewport, and puts them in one overlay that
	// spans them. A press anywhere outside the menus, even between them,
	// dismisses the whole menu. The highlight is the only cursor, as in the
	// drawn menu bar: nothing in the overlay takes keyboard focus, which comes
	// back to its owner when the menu closes.
	fn (mut w Window) drawn_popup_menu_layer(menu &DrawnPopupMenu, viewport Rect) !Element {
		serial := menu.serial
		config := DropdownMenuConfig{
			id:        drawn_popup_menu_id
			state:     menu.state
			items:     menu.rows
			anchor:    menu.anchor
			window:    viewport
			offset:    if menu.anchor.width > 0 || menu.anchor.height > 0 { 4.0 } else { 0.0 }
			min_width: if menu.anchor.width > 128 { menu.anchor.width } else { 128.0 }
			on_step:   fn [mut w, serial] (step DropdownMenuStep) {
				w.drawn_popup_menu_step(serial, step)
			}
		}
		levels := dropdown_menu_levels(config)!
		mut extent := levels[0].frame
		for level in levels[1..] {
			extent = popover_union(extent, level.frame)
		}
		mut surfaces := []Element{cap: levels.len}
		for depth, level in levels {
			surfaces << drawn_popup_menu_unfocusable(dropdown_menu_surface(config, DropdownMenuLevel{
				...level
				frame: popover_translate(level.frame, -extent.x, -extent.y)
			}, depth))
		}
		layer := with_overlay(Element{
			...view(drawn_popup_menu_id, rect(0, 0, extent.width, extent.height), BoxStyle{
				transparent: true
			}, surfaces)
			on_event:  fn [mut w, serial] (event ElementEvent) {
				if event.kind == .pointer_down {
					w.finish_drawn_popup_menu(serial, PopupMenuResult{})
				}
			}
			clickable: true
		}, OverlayConfig{
			kind:       .context_menu
			open:       true
			point:      OverlayPoint{
				x: extent.x
				y: extent.y
			}
			gap:        0
			margin:     0
			on_dismiss: fn [mut w, serial] (event ElementEvent) {
				// A chosen row has already answered, and a submenu row stays open.
				if event.dismiss_reason != .selection {
					w.finish_drawn_popup_menu(serial, PopupMenuResult{})
				}
			}
		})!
		return Element{
			...layer
			focus_policy: .unfocusable
		}
	}

	fn drawn_popup_menu_unfocusable(element Element) Element {
		return Element{
			...element
			focus_policy: .unfocusable
			children:     element.children.map(drawn_popup_menu_unfocusable(it))
		}
	}

	// custom_context_press answers a secondary press. It closes the drawn menu
	// bar or select list it lands on, or goes to the overlays (overlay.v), or
	// opens the context menu of the element under it.
	fn (mut w Window) custom_context_press(x f64, y f64) {
		dispatch := w.begin_custom_input_dispatch()
		if !dispatch.valid() {
			return
		}
		mut scheduler := w.scheduler
		scheduler.invalidate(.paint)
		w.tooltip.dismiss()
		if !w.sync_custom_input_geometry(dispatch) {
			return
		}
		if w.menu_bar_open() {
			w.close_menu_bar()
			return
		}
		if w.dropdown_id.len > 0 {
			w.close_dropdown()
			return
		}
		if w.overlay_context_press(x, y) || !dispatch.valid() {
			return
		}
		w.open_context_menu(x, y)
	}

	// open_context_menu shows the menu of the element a secondary press at a
	// window point belongs to, and reports whether there was one.
	fn (mut w Window) open_context_menu(x f64, y f64) bool {
		owner := w.context_menu_owner(x, y) or { return false }
		items := owner.el.menu.map(MenuItem{
			on_select: it.on_select
			id:        it.id
			title:     it.title
		})
		w.show_popup_menu(PopupMenuConfig{
			items:  items
			anchor: rect(x, y, 0, 0)
			scale:  w.popup_menu_scale()
		}, fn [mut w] (result PopupMenuResult) {
			w.context_menu_result(result)
		})
		return true
	}

	fn (mut w Window) context_menu_result(result PopupMenuResult) {
		if result.chosen {
			w.emit_menu_callback(result.item.on_select, result.item.id)
		}
	}

	fn context_menu_node(node FocusNode) bool {
		return node.el.menu.len > 0 && node.el.kind != .dropdown && !node.hidden && node.enabled
	}

	// context_menu_owner finds the element a secondary press belongs to: the
	// topmost one with a menu under the point, unless a control painted over it
	// takes the press, which then belongs to that control's own menu or the
	// nearest one around it. A select's options are not a context menu.
	fn (mut w Window) context_menu_owner(x f64, y f64) ?FocusNode {
		nodes := w.navigation.nodes
		mut found := -1
		for i := nodes.len - 1; i >= 0; i-- {
			if context_menu_node(nodes[i]) && hit_target_contains(w.custom_focus_target(nodes[i]), x, y) {
				found = i
				break
			}
		}
		target := w.hit_test(x, y)
		if target.identity.len > 0 {
			mut index := w.navigation.path_indices[target.identity] or { -1 }
			if index > found {
				for index >= 0 {
					node := nodes[index]
					if context_menu_node(node) {
						return node
					}
					index = w.navigation.path_indices[node.parent] or { -1 }
				}
				return none
			}
		}
		if found < 0 {
			return none
		}
		return nodes[found]
	}

	// open_host_dropdown shows a select's options in a native popup menu, its
	// value checked and, where the host does that, laid over the select. The
	// select reads as expanded until the result arrives.
	fn (mut w Window) open_host_dropdown(target HitTarget) {
		id := target.id
		if w.popup_menu_owner.len > 0 {
			return
		}
		w.focus(id)
		node := w.navigation.node(id) or { return }
		selected := w.text_values[id] or { node.el.text }
		w.popup_menu_owner = id
		w.invalidate_custom_paint()
		w.show_popup_menu(PopupMenuConfig{
			items:    target.options.map(MenuItem{
				id:      it
				title:   it
				checked: it == selected
			})
			anchor:   node.frame
			selected: target.options.index(selected)
			scale:    w.popup_menu_scale()
		}, fn [mut w, id] (result PopupMenuResult) {
			w.dropdown_popup_menu_result(id, result)
		})
	}

	// dropdown_popup_menu_result commits a choice to the select, if it is still
	// mounted and enabled.
	fn (mut w Window) dropdown_popup_menu_result(id string, result PopupMenuResult) {
		if w.popup_menu_owner == id {
			w.popup_menu_owner = ''
		}
		w.invalidate_custom_paint()
		if !result.chosen {
			return
		}
		node := w.navigation.node(id) or { return }
		if node.hidden || !node.enabled || node.el.kind != .dropdown {
			return
		}
		w.commit_dropdown(id, node.el.on_event, result.item.title)
	}
}
