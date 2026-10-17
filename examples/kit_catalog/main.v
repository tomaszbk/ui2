module main

import os
import ui2

// The GPUI Kit catalog: a page for each group of kit components, picked from
// the sidebar. Run it with `--dark` for the dark theme.

pub struct CatalogApp {
pub mut:
	page    string = 'buttons'
	clicks  int
	loading bool
}

pub fn (mut app CatalogApp) show(page string) {
	app.page = page
}

pub fn (mut app CatalogApp) click() {
	app.clicks++
}

pub fn (mut app CatalogApp) toggle_loading() {
	app.loading = !app.loading
}

fn build_catalog(mut app CatalogApp) ui2.Element {
	return $vml('app.vml')
}

fn main() {
	mut app := CatalogApp{}
	ui2.run_compiled_vml[CatalogApp](
		build:  build_catalog
		model:  &app
		title:  'Kit catalog'
		width:  960
		height: 640
		theme:  if '--dark' in os.args { ui2.dark_theme() } else { ui2.default_theme() }
	) or { panic(err) }
}
