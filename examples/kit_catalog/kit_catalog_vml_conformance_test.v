// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

fn kit_catalog_conformance_tree(mut app CatalogApp, _ ui2.Rect) ui2.Element {
	return build_catalog(mut app)
}

// The interpreted app.vml (and the page components it imports) equals the
// compiled one: the same tree, events and model state (ui2.vml_conformance).
fn test_kit_catalog_interpreted_vml_matches_compiled() {
	mut app := CatalogApp{}
	report := ui2.vml_conformance[CatalogApp](
		path:            @DIR + '/app.vml'
		frame:           ui2.rect(0, 0, 960, 640)
		model:           &app
		reset:           fn (mut app CatalogApp) {
			app = CatalogApp{}
		}
		compiled:        kit_catalog_conformance_tree
		follow_viewport: true
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
