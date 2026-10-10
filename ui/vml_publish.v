module ui2

fn compiled_vml_publish(id string, element Element) {
	$if ui2_document_library ? {
		panic('compiled VML document library updates require an attached host publisher')
	} $else {
		$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
			refresh_compiled_element(id, element.compiled_node, element)
		} $else {
			if id.len > 0 {
				refresh_element(id, element)
				return
			}
			// Native runners reconcile the cached document snapshot; its component
			// builder and state initializers remain untouched.
			request_refresh()
		}
	}
}

// The compiled controller returns its retained document whole. Effects that
// run while it produces that declaration are already part of it.
fn compiled_vml_begin_snapshot() {
	$if !ui2_document_library ? {
		$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
			begin_compiled_snapshot()
		}
	}
}

fn compiled_vml_end_snapshot() {
	$if !ui2_document_library ? {
		$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
			end_compiled_snapshot()
		}
	}
}
