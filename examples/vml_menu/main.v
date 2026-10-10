module main

import ui2

fn build() ui2.Element {
	return ui2.screen(0xffffff, [
		ui2.label('hint', 'Choose a menu item; its declared action is printed to the terminal.',
			ui2.rect(20, 20, 460, 80), ui2.TextStyle{
				size: 15
			}),
	])
}

fn main() {
	menus := build_menus()
	ui2.set_menu_bar(menus)
	ui2.run_window('VML menus', 500, 180, build)
}

fn menu_action(action string) ui2.ElementCallback {
	return fn [action] (event ui2.ElementEvent) {
		println('Menu action: ${action} (element ${event.id})')
	}
}

fn menu_callbacks() map[string]ui2.ElementCallback {
	return {
		'file_new':    menu_action('file_new')
		'file_open':   menu_action('file_open')
		'file_revert': menu_action('file_revert')
		'export_pdf':  menu_action('export_pdf')
		'export_png':  menu_action('export_png')
		'word_wrap':   menu_action('word_wrap')
	}
}

fn build_menus() []ui2.Menu {
	callbacks := menu_callbacks()
	callback_file_new := callbacks['file_new'] or { panic('missing file_new callback') }
	callback_file_open := callbacks['file_open'] or { panic('missing file_open callback') }
	callback_file_revert := callbacks['file_revert'] or { panic('missing file_revert callback') }
	callback_export_pdf := callbacks['export_pdf'] or { panic('missing export_pdf callback') }
	callback_export_png := callbacks['export_png'] or { panic('missing export_png callback') }
	callback_word_wrap := callbacks['word_wrap'] or { panic('missing word_wrap callback') }
	return $vml('menus.vml')
}
