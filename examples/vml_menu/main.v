module main

import ui2

const menus_source = $embed_file('menus.vml').to_string()

fn build() ui2.Element {
	return ui2.screen(0xffffff, [
		ui2.label('hint', 'Choose a menu item; its declared action is printed to the terminal.',
			ui2.rect(20, 20, 460, 80), ui2.TextStyle{
				size: 15
			}),
	])
}

fn main() {
	menus := ui2.menu_bar_from_vml_with_callbacks(menus_source, menu_callbacks()) or { panic(err) }
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
