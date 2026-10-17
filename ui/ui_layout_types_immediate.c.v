// vfmt off
// The scrollbar and text area geometry a custom renderer window keeps.
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
	struct ScrollbarGeometry {
		track Rect
		thumb Rect
	}

	struct TextAreaLineRange {
		start int
		end   int
	}

	struct TextAreaLayout {
		text          string
		width         f64
		style         TextStyle
		rendered_size int
		lines         []string
		ranges        []TextAreaLineRange
	}
}
