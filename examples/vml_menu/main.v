module main

// vml: menus.vml

import ui2

fn build(mut w ui2.Window) ui2.Element {
	return ui2.screen(0xffffff, [
		ui2.label('hint', 'Choose a menu item; its declared action is printed to the terminal.',
			ui2.rect(20, 20, 460, 80), ui2.TextStyle{
				size: 15
			}),
	])
}

fn main() {
	menus := build_menus()
	mut app := ui2.new_app()
	mut window := app.new_window(
		title:  'VML menus'
		width:  500
		height: 180
		build:  build
	) or { panic(err) }
	window.set_menu_bar(menus)
	app.run()
}

fn menu_action(action string) ui2.ElementCallback {
	return fn [action] (event ui2.ElementEvent) {
		println('Menu action: ${action} (element ${event.id})')
	}
}

fn menu_callbacks() map[string]ui2.ElementCallback {
	return {
		'file_new':    callback_file_new
		'file_open':   callback_file_open
		'file_revert': callback_file_revert
		'export_pdf':  callback_export_pdf
		'export_png':  callback_export_png
		'word_wrap':   callback_word_wrap
	}
}

fn callback_file_new(event ui2.ElementEvent) {
	menu_action('file_new')(event)
}

fn callback_file_open(event ui2.ElementEvent) {
	menu_action('file_open')(event)
}

fn callback_file_revert(event ui2.ElementEvent) {
	menu_action('file_revert')(event)
}

fn callback_export_pdf(event ui2.ElementEvent) {
	menu_action('export_pdf')(event)
}

fn callback_export_png(event ui2.ElementEvent) {
	menu_action('export_png')(event)
}

fn callback_word_wrap(event ui2.ElementEvent) {
	menu_action('word_wrap')(event)
}

// MenuActions is the model of the menus document: the action of each item.
@[heap]
struct MenuActions {
pub:
	callback_file_new    ui2.ElementCallback = callback_file_new
	callback_file_open   ui2.ElementCallback = callback_file_open
	callback_file_revert ui2.ElementCallback = callback_file_revert
	callback_export_pdf  ui2.ElementCallback = callback_export_pdf
	callback_export_png  ui2.ElementCallback = callback_export_png
	callback_word_wrap   ui2.ElementCallback = callback_word_wrap
}

fn build_menus() []ui2.Menu {
	mut actions := &MenuActions{}
	return ui2.menus(menus_vml(mut actions)) or { panic(err) }
}
