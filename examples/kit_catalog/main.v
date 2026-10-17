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
	// The display page.
	progress     f64 = 40
	notes_open   bool
	faq          string = 'billing'
	section      string = 'overview'
	results_page int    = 3
	file         string = 'main.v'
	slide        int
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

// advance fills the display page's progress by a fifth, and starts over once
// it is full.
pub fn (mut app CatalogApp) advance() {
	app.progress = if app.progress >= 100 { 0 } else { app.progress + 20 }
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
