module ui2

fn compiled_vml_publish(id string, element Element) {
	$if ui2_document_library ? {
		panic('compiled VML document library updates require an attached host publisher')
	} $else {
		if id.len > 0 {
			refresh_element(id, element)
			return
		}
		$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
			refresh_compiled_element(element.compiled_node, element)
		} $else {
			// Native runners reconcile the cached document snapshot; its component
			// builder and state initializers remain untouched.
			request_refresh()
		}
	}
}
