// vfmt off
// The macOS host's menu bar, status item and popup menus (platform.v). The
// window's content is drawn, but the menu bar is the system's global one:
// NSMenu and NSStatusItem are Objective-C runtime objects rather than views,
// so the bridge is all they need, whichever host variant owns the window. A
// popup menu opens over the content view of the window the renderer
// names, sokol's or the embedder's.
module ui2

import macos

#flag darwin -framework AppKit

// AppKit shows the menu bar outside the window and runs its key equivalents
// itself, before the key reaches the window.
const host_menu_bar = HostMenuBar.native
const host_menu_key_equivalents = true

// NSEventModifierFlags, the subset a menu accelerator can carry.
const ns_event_modifier_shift = u64(1) << 17
const ns_event_modifier_control = u64(1) << 18
const ns_event_modifier_option = u64(1) << 19
const ns_event_modifier_command = u64(1) << 20

// NSVariableStatusItemLength: the item is as wide as its title and image need.
const ns_variable_status_item_length = f64(-1)

const ns_control_state_on = i64(1)
const ns_control_state_off = i64(0)

// Status area images are drawn at the menu bar's own height.
const macos_status_image_size = f64(18)

// popUpMenuPositioningItem:atLocation:inView: takes an NSPoint by value, which
// no bridge function passes, so it goes through objc_msgSend cast to its type.
type ObjcPopUpMenuMsg = fn (voidptr, voidptr, voidptr, macos.Point, voidptr) bool

fn C.objc_msgSend()

struct MacosMenuCallback {
	id       string
	on_event ElementCallback = unsafe { nil }
}

// MacosPopupMenu is a popup menu from host_show_popup_menu until its answer.
struct MacosPopupMenu {
	cfg       PopupMenuConfig
	on_result PopupMenuCallback = unsafe { nil }
	window    macos.Id
}

// MacosMenuState holds the process's main menu and status item. NSApp has one
// of each, and their actions reach V through the exported functions below,
// which carry no context, so this host state is process-wide. bar_owner and
// tray_owner are the windows that installed them, which their rows answer.
@[heap]
struct MacosMenuState {
mut:
	handler     macos.Id
	status_item macos.Id
	bar_owner   HostMenuOwner
	tray_owner  HostMenuOwner
	// bar_ids and tray_ids map an NSMenuItem — or the status item's button — to
	// the typed callback it invokes. The menu owns the item, so the pointer
	// identifies it for as long as it can be chosen.
	bar_ids  map[u64]MacosMenuCallback
	tray_ids map[u64]MacosMenuCallback
	// The popup menu waiting for an answer, if popup_active. popup_rows maps
	// its NSMenuItems to their rows; popup_choice is the row chosen while it
	// tracks, when popup_chosen.
	popup          MacosPopupMenu
	popup_active   bool
	popup_tracking bool
	popup_menu     macos.Id
	popup_rows     map[u64]MenuItem
	popup_chosen   bool
	popup_choice   MenuItem
}

const macos_menu_state_singleton = &MacosMenuState{
	bar_ids: map[u64]MacosMenuCallback{}
	tray_ids: map[u64]MacosMenuCallback{}
	popup_rows: map[u64]MenuItem{}
}

fn macos_menu_state() &MacosMenuState {
	return unsafe { macos_menu_state_singleton }
}

fn host_set_menu_bar(owner HostMenuOwner, menus []Menu) {
	macos_install_menu_bar(owner.app_name, menus)
	mut st := macos_menu_state()
	st.bar_owner = owner
}

fn host_tray_supported() bool { return true }

fn host_set_tray(owner HostMenuOwner, cfg TrayConfig) {
	macos_install_status_item(cfg)
	mut st := macos_menu_state()
	st.tray_owner = owner
}

fn host_remove_tray() { macos_remove_status_item() }

// A popup menu opens over the content view of the native window.
fn host_popup_menu_supported(native voidptr) bool { return native != unsafe { nil } }

// The menu tracks in a modal loop of its own. It opens from the run loop once
// the input callback that asked for it has returned, so that loop never runs
// inside the renderer's callbacks, and the answer comes from there too.
fn host_show_popup_menu(native voidptr, cfg PopupMenuConfig, on_result PopupMenuCallback) {
	mut st := macos_menu_state()
	window := macos.Id(native)
	if st.popup_active || window == unsafe { nil } || cfg.items.len == 0 {
		on_result(PopupMenuResult{})
		return
	}
	st.popup = MacosPopupMenu{
		cfg: cfg
		on_result: on_result
		window: window
	}
	st.popup_active = true
	macos.msg_void_sel_id_bool(macos_menu_handler(), 'performSelectorOnMainThread:withObject:waitUntilDone:',
		macos.sel('showPopupMenu:'), macos.Id(unsafe { nil }), false)
}

@[export: 'ui2_popup_menu_show']
fn ui2_popup_menu_show(_self voidptr, _cmd voidptr, _arg voidptr) {
	mut st := macos_menu_state()
	if !st.popup_active || st.popup_menu != unsafe { nil } {
		return
	}
	cfg := st.popup.cfg
	view := macos.msg_id(st.popup.window, 'contentView')
	if view == unsafe { nil } {
		macos_finish_popup_menu(PopupMenuResult{})
		return
	}
	mut rows := map[u64]MenuItem{}
	menu := macos_build_popup_menu(cfg.items, mut rows)
	macos.msg_void_f64(menu, 'setMinimumWidth:', cfg.anchor.width)
	st.popup_menu = menu
	st.popup_rows = rows.move()
	// A select lays its current value over itself, as NSPopUpButton does. A
	// menu with no row to line up opens below its anchor.
	positioning := if cfg.selected >= 0 && cfg.selected < cfg.items.len {
		macos.msg_id_u64(menu, 'itemAtIndex:', u64(cfg.selected))
	} else {
		macos.Id(unsafe { nil })
	}
	y := if positioning != unsafe { nil } { cfg.anchor.y } else { cfg.anchor.y + cfg.anchor.height }
	// The renderer's coordinates run down from the top of the content view.
	location := if macos.msg_bool(view, 'isFlipped') {
		macos.point(cfg.anchor.x, y)
	} else {
		macos.point(cfg.anchor.x, macos.msg_rect(view, 'bounds').height - y)
	}
	pop_up := unsafe { ObjcPopUpMenuMsg(C.objc_msgSend) }
	st.popup_tracking = true
	answered := pop_up(menu, macos.sel('popUpMenuPositioningItem:atLocation:inView:'), positioning,
		location, view)
	st.popup_tracking = false
	if st.popup_chosen {
		macos_finish_popup_menu(PopupMenuResult{ chosen: true, item: st.popup_choice })
	} else if !answered {
		macos_finish_popup_menu(PopupMenuResult{})
	}
	// Otherwise AppKit sends the chosen row's action once tracking has
	// unwound, and ui2_popup_menu_item_chosen answers then.
}

@[export: 'ui2_popup_menu_item_chosen']
fn ui2_popup_menu_item_chosen(_self voidptr, _cmd voidptr, sender voidptr) {
	mut st := macos_menu_state()
	item := st.popup_rows[u64(sender)] or { return }
	if st.popup_tracking {
		st.popup_choice = item
		st.popup_chosen = true
		return
	}
	macos_finish_popup_menu(PopupMenuResult{ chosen: true, item: item })
}

fn macos_finish_popup_menu(result PopupMenuResult) {
	mut st := macos_menu_state()
	on_result := st.popup.on_result
	if st.popup_menu != unsafe { nil } {
		macos.release(st.popup_menu)
	}
	st.popup = MacosPopupMenu{}
	st.popup_menu = macos.Id(unsafe { nil })
	st.popup_rows = map[u64]MenuItem{}
	st.popup_chosen = false
	st.popup_choice = MenuItem{}
	st.popup_active = false
	if on_result != unsafe { nil } {
		on_result(result)
	}
}

// macos_build_popup_menu builds a popup menu the way macos_build_menu builds a
// menu bar menu, but its rows answer the waiting popup instead of invoking
// their callbacks.
fn macos_build_popup_menu(items []MenuItem, mut rows map[u64]MenuItem) macos.Id {
	menu := macos.msg_id1(macos.alloc('NSMenu'), 'initWithTitle:', macos.nsstring(''))
	macos.msg_void_bool(menu, 'setAutoenablesItems:', false)
	for item in items {
		if item.separator {
			macos.msg_void1(menu, 'addItem:', macos.msg_id(macos.get_class('NSMenuItem'), 'separatorItem'))
			continue
		}
		row := if item.items.len > 0 {
			macos_submenu_row(item, macos_build_popup_menu(item.items, mut rows))
		} else {
			macos_menu_row(item, 'handlePopupItem:')
		}
		if item.items.len == 0 {
			rows[u64(voidptr(row))] = item
		}
		macos.msg_void1(menu, 'addItem:', row)
		macos.release(row)
	}
	return menu
}

// macos_install_menu_bar rebuilds the whole main menu. The application menu
// with its "Quit <app>" item always comes first — macOS reads the first
// submenu as the application one, and without it AppKit has nothing to handle
// the Cmd+Q key equivalent, so a ui2 window could not be quit from the
// keyboard. The Quit item has no explicit target, so its terminate: action
// travels the responder chain to NSApp, honoring any applicationShouldTerminate:
// the app's delegate installs.
fn macos_install_menu_bar(app_name string, menus []Menu) {
	mut ids := map[u64]MacosMenuCallback{}
	main_menu := macos.msg_id(macos.alloc('NSMenu'), 'init')
	macos.msg_void_bool(main_menu, 'setAutoenablesItems:', false)

	app_menu_item := macos.msg_id(macos.alloc('NSMenuItem'), 'init')
	macos.msg_void1(main_menu, 'addItem:', app_menu_item)
	app_menu := macos.msg_id(macos.alloc('NSMenu'), 'init')
	macos.msg_void1(app_menu, 'setTitle:', macos.nsstring(app_name))
	quit_item := macos.msg_id3(macos.alloc('NSMenuItem'), 'initWithTitle:action:keyEquivalent:', macos.nsstring('Quit ${app_name}'), macos.Id(voidptr(macos.sel('terminate:'))), macos.nsstring('q'))
	macos.msg_void1(app_menu, 'addItem:', quit_item)
	macos.release(quit_item)
	macos.msg_void1(app_menu_item, 'setSubmenu:', app_menu)
	macos.release(app_menu)
	macos.release(app_menu_item)
	if backend_embedder {
		macos_add_edit_menu(main_menu)
	}

	for m in menus {
		title := macos.msg_id3(macos.alloc('NSMenuItem'), 'initWithTitle:action:keyEquivalent:', macos.nsstring(m.title), macos.Id(unsafe { nil }), macos.nsstring(''))
		rows := macos_build_menu(m.title, m.items, mut ids)
		macos.msg_void1(title, 'setSubmenu:', rows)
		macos.release(rows)
		macos.msg_void1(main_menu, 'addItem:', title)
		macos.release(title)
	}

	macos.msg_void1(macos_shared_application(), 'setMainMenu:', main_menu)
	macos.release(main_menu)
	mut st := macos_menu_state()
	st.bar_ids = ids.move()
}

// macos_add_edit_menu adds the standard Edit menu. The embedder's view takes
// copy:, cut:, paste: and selectAll: from it, the way AppKit text views do;
// a sokol window handles those keys itself and must not lose them to a menu.
fn macos_add_edit_menu(main_menu macos.Id) {
	edit_item := macos.msg_id3(macos.alloc('NSMenuItem'), 'initWithTitle:action:keyEquivalent:', macos.nsstring('Edit'), macos.Id(unsafe { nil }), macos.nsstring(''))
	edit_menu := macos.msg_id1(macos.alloc('NSMenu'), 'initWithTitle:', macos.nsstring('Edit'))
	for row in [['Cut', 'cut:', 'x'], ['Copy', 'copy:', 'c'], ['Paste', 'paste:', 'v'], ['Select All', 'selectAll:', 'a']] {
		item := macos.msg_id3(macos.alloc('NSMenuItem'), 'initWithTitle:action:keyEquivalent:', macos.nsstring(row[0]), macos.Id(voidptr(macos.sel(row[1]))), macos.nsstring(row[2]))
		macos.msg_void1(edit_menu, 'addItem:', item)
		macos.release(item)
	}
	macos.msg_void1(edit_item, 'setSubmenu:', edit_menu)
	macos.release(edit_menu)
	macos.msg_void1(main_menu, 'addItem:', edit_item)
	macos.release(edit_item)
}

fn macos_install_status_item(cfg TrayConfig) {
	mut st := macos_menu_state()
	if st.status_item == unsafe { nil } {
		bar := macos.msg_id(macos.get_class('NSStatusBar'), 'systemStatusBar')
		if bar == unsafe { nil } {
			return
		}
		item := macos.msg_id_f64(bar, 'statusItemWithLength:', ns_variable_status_item_length)
		if item == unsafe { nil } {
			return
		}
		// The status bar hands the item back without transferring ownership;
		// hold it, or it leaves the menu bar as soon as the pool drains.
		st.status_item = macos.retain(item)
	}
	mut ids := map[u64]MacosMenuCallback{}
	if cfg.menu.len > 0 {
		menu := macos_build_menu(cfg.title, cfg.menu, mut ids)
		macos.msg_void1(st.status_item, 'setMenu:', menu)
		macos.release(menu)
	} else {
		macos.msg_void1(st.status_item, 'setMenu:', macos.Id(unsafe { nil }))
	}
	status_button := macos.msg_id(st.status_item, 'button')
	if status_button != unsafe { nil } {
		macos.msg_void1(status_button, 'setTitle:', macos.nsstring(cfg.title))
		macos.msg_void1(status_button, 'setToolTip:', macos.nsstring(cfg.tooltip))
		macos.msg_void1(status_button, 'setImage:', macos_status_image(cfg.icon))
		// A status item with a menu opens it on either mouse button, so the
		// button's own action is only wired up for the menu-less case.
		if cfg.menu.len == 0 && cfg.on_event != unsafe { nil } {
			macos.msg_void1(status_button, 'setTarget:', macos_menu_handler())
			macos.msg_void1(status_button, 'setAction:', macos.sel('handleMenuItem:'))
			ids[u64(voidptr(status_button))] = MacosMenuCallback{ id: cfg.id, on_event: cfg.on_event }
		} else {
			macos.msg_void1(status_button, 'setTarget:', macos.Id(unsafe { nil }))
			macos.msg_void1(status_button, 'setAction:', macos.Id(unsafe { nil }))
		}
	}
	st.tray_ids = ids.move()
}

fn macos_remove_status_item() {
	mut st := macos_menu_state()
	if st.status_item == unsafe { nil } {
		return
	}
	bar := macos.msg_id(macos.get_class('NSStatusBar'), 'systemStatusBar')
	if bar != unsafe { nil } {
		macos.msg_void1(bar, 'removeStatusItem:', st.status_item)
	}
	macos.release(st.status_item)
	st.status_item = macos.Id(unsafe { nil })
	st.tray_ids = map[u64]MacosMenuCallback{}
	st.tray_owner = HostMenuOwner{}
}

// macos_status_image resolves an SF Symbol name or an image file into an icon
// the status bar can draw, sized to the menu bar's height.
fn macos_status_image(icon string) macos.Id {
	if icon.len == 0 {
		return macos.Id(unsafe { nil })
	}
	mut source := macos.Id(unsafe { nil })
	if icon.starts_with('symbol:') {
		image_class := macos.get_class('NSImage')
		if macos.responds_to(image_class, 'imageWithSystemSymbolName:accessibilityDescription:') {
			source = macos.msg_id2(image_class, 'imageWithSystemSymbolName:accessibilityDescription:', macos.nsstring(icon['symbol:'.len..]), macos.Id(unsafe { nil }))
		}
	} else {
		from_file := macos.msg_id1(macos.alloc('NSImage'), 'initWithContentsOfFile:', macos.nsstring(icon))
		if from_file != unsafe { nil } {
			source = macos.msg_id(from_file, 'autorelease')
		} else {
			source = macos.msg_id1(macos.get_class('NSImage'), 'imageNamed:', macos.nsstring(icon))
		}
	}
	if source == unsafe { nil } {
		return source
	}
	sized := macos.msg_id(macos.msg_id(source, 'copy'), 'autorelease')
	macos.msg_void_point(sized, 'setSize:', macos.point(macos_status_image_size, macos_status_image_size))
	// Carry the source's own template flag rather than forcing one: a template
	// image is recolored by the system, which is what keeps an SF Symbol
	// legible in both the light and the dark menu bar, while an icon the app
	// drew in color stays the color it drew.
	macos.msg_void_bool(sized, 'setTemplate:', macos.msg_bool(source, 'isTemplate'))
	return sized
}

fn macos_build_menu(title string, items []MenuItem, mut ids map[u64]MacosMenuCallback) macos.Id {
	menu := macos.msg_id1(macos.alloc('NSMenu'), 'initWithTitle:', macos.nsstring(title))
	// ui2 declares whether a row is enabled, so AppKit must not decide for
	// itself by asking the responder chain about each action.
	macos.msg_void_bool(menu, 'setAutoenablesItems:', false)
	for item in items {
		macos_add_menu_item(menu, item, mut ids)
	}
	return menu
}

fn macos_add_menu_item(menu macos.Id, item MenuItem, mut ids map[u64]MacosMenuCallback) {
	if item.separator {
		macos.msg_void1(menu, 'addItem:', macos.msg_id(macos.get_class('NSMenuItem'), 'separatorItem'))
		return
	}
	if item.items.len > 0 {
		parent := macos_submenu_row(item, macos_build_menu(item.title, item.items, mut ids))
		macos.msg_void1(menu, 'addItem:', parent)
		macos.release(parent)
		return
	}
	row := macos_menu_row(item, 'handleMenuItem:')
	// Bind by sender pointer rather than by a positional tag, so a retained
	// item from an earlier declaration can never dispatch through this one.
	ids[u64(voidptr(row))] = MacosMenuCallback{ id: item.id, on_event: item.on_select }
	macos.msg_void1(menu, 'addItem:', row)
	macos.release(row)
}

// macos_menu_row builds a choosable row that sends `action` to the handler.
fn macos_menu_row(item MenuItem, action string) macos.Id {
	shortcut := parse_menu_shortcut(item.shortcut)
	row := macos.msg_id3(macos.alloc('NSMenuItem'), 'initWithTitle:action:keyEquivalent:', macos.nsstring(item.title), macos.Id(voidptr(macos.sel(action))), macos.nsstring(macos_key_equivalent(shortcut)))
	macos.msg_void_u64(row, 'setKeyEquivalentModifierMask:', macos_modifier_mask(shortcut))
	macos.msg_void1(row, 'setTarget:', macos_menu_handler())
	macos.msg_void_bool(row, 'setEnabled:', item.enabled)
	macos.msg_void_i64(row, 'setState:', if item.checked { ns_control_state_on } else { ns_control_state_off })
	return row
}

// macos_submenu_row builds the row a submenu hangs from, taking over `child`.
fn macos_submenu_row(item MenuItem, child macos.Id) macos.Id {
	parent := macos.msg_id3(macos.alloc('NSMenuItem'), 'initWithTitle:action:keyEquivalent:', macos.nsstring(item.title), macos.Id(unsafe { nil }), macos.nsstring(''))
	macos.msg_void1(parent, 'setSubmenu:', child)
	macos.release(child)
	macos.msg_void_bool(parent, 'setEnabled:', item.enabled)
	return parent
}

// macos_key_equivalent turns a parsed shortcut into the single-character
// string NSMenuItem wants. Shift lives in the modifier mask rather than in the
// case of the character, so the letter stays lowercase.
fn macos_key_equivalent(shortcut MenuShortcut) string {
	if shortcut.key.len == 0 {
		return ''
	}
	if shortcut.key.len > 1 && shortcut.key[0] == `f` {
		number := shortcut.key[1..].int()
		if number >= 1 && number <= 12 {
			// NSF1FunctionKey and its successors sit in the Unicode private
			// use area, one code point apart.
			return rune(0xf704 + number - 1).str()
		}
	}
	return match shortcut.key {
		'left' { rune(0xf702).str() }
		'right' { rune(0xf703).str() }
		'up' { rune(0xf700).str() }
		'down' { rune(0xf701).str() }
		'space' { ' ' }
		'tab' { '\t' }
		'enter', 'return' { '\r' }
		'escape', 'esc' { '\x1b' }
		'delete', 'backspace' { '\x08' }
		else { if shortcut.key.runes().len == 1 { shortcut.key } else { '' } }
	}
}

fn macos_modifier_mask(shortcut MenuShortcut) u64 {
	mut mask := u64(0)
	if shortcut.cmd {
		mask |= ns_event_modifier_command
	}
	if shortcut.ctrl {
		mask |= ns_event_modifier_control
	}
	if shortcut.alt {
		mask |= ns_event_modifier_option
	}
	if shortcut.shift {
		mask |= ns_event_modifier_shift
	}
	return mask
}

fn macos_shared_application() macos.Id {
	return macos.msg_id(macos.get_class('NSApplication'), 'sharedApplication')
}

fn macos_menu_handler() macos.Id {
	mut st := macos_menu_state()
	if st.handler != unsafe { nil } {
		return st.handler
	}
	if macos.get_class('UI2MenuHandler') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('NSObject'), 'UI2MenuHandler')
		macos.add_method(cls, 'handleMenuItem:', voidptr(ui2_menu_item_chosen), 'v@:@')
		macos.add_method(cls, 'handlePopupItem:', voidptr(ui2_popup_menu_item_chosen), 'v@:@')
		macos.add_method(cls, 'showPopupMenu:', voidptr(ui2_popup_menu_show), 'v@:@')
		macos.register_class_pair(cls)
	}
	st.handler = macos.msg_id(macos.alloc('UI2MenuHandler'), 'init')
	return st.handler
}

@[export: 'ui2_menu_item_chosen']
fn ui2_menu_item_chosen(_self voidptr, _cmd voidptr, sender voidptr) {
	st := macos_menu_state()
	pointer := u64(sender)
	mut owner := st.bar_owner.window
	binding := st.bar_ids[pointer] or {
		owner = st.tray_owner.window
		st.tray_ids[pointer] or { return }
	}
	if owner != unsafe { nil } {
		owner.emit_menu_callback(binding.on_event, binding.id)
	}
}
