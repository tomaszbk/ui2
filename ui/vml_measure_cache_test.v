module ui2

pub struct MeasureCacheItem {
pub:
	id   int
	text string
}

pub struct MeasureCacheApp {
pub:
	items []MeasureCacheItem
}

// The compiled trees retain authored layout so the runtime cache can measure
// them with an independent, window-free callback.
fn measure_cache_fixture_text(text string, style TextStyle, max_width f64) !LayoutSize {
	width := f64(text.len) * style.size * 0.5
	line_width := if max_width > 0 { max_width } else { width }
	lines := if style.lines > 1 && line_width > 0 { int(width / line_width) + 1 } else { 1 }
	return LayoutSize{ width: if width > line_width { line_width } else { width }, height: style.size * lines }
}

fn measure_cache_computations(depth int) u64 {
	frame := rect(0, 0, 800, 600)
	root := if depth == 6 {
		$vml('fixtures/measure_nested_6.vml', frame)
	} else {
		$vml('fixtures/measure_nested_12.vml', frame)
	}
	mut tree := LayoutTree{}
	tree.replace(root) or { panic(err) }
	_ = tree.resolve(LayoutConstraints{ max_width: 800, max_height: 600 }, measure_cache_fixture_text, LayoutEnvironment{}) or { panic(err) }
	first := tree.stats()
	assert first.measure_visits > 0
	tree.reset_stats()
	_ = tree.resolve(LayoutConstraints{ max_width: 800, max_height: 600 }, measure_cache_fixture_text, LayoutEnvironment{}) or { panic(err) }
	assert tree.stats().text_measurements == 0
	assert tree.stats().layout_visits == 0
	return first.measure_visits
}

fn test_nested_flex_measurement_grows_polynomially_with_depth() {
	shallow := measure_cache_computations(6)
	deep := measure_cache_computations(12)
	assert deep > shallow
	assert deep < shallow * 8, '${shallow} -> ${deep}'
}

// Repeated items share a source node and path but resolve to different text.
// Each must be measured as its own content inside an outer measurement.
fn test_nested_measurement_keeps_repeated_items_distinct() {
	long_text := 'A description long enough to wrap onto several lines in a narrow column'
	mut app := MeasureCacheApp{
		items: [MeasureCacheItem{1, 'Short'}, MeasureCacheItem{2, long_text},
			MeasureCacheItem{3, 'Short'}]
	}
	root := $vml('fixtures/measure_repeated_items.vml', rect(0, 0, 600, 400))
	row := root.children[0]
	items := row.children
	assert items.len == 3
	label := items[1].children[0]
	expected := measure_layout_text(long_text, label.text_style, items[1].frame.width) or {
		panic(err)
	}
	assert items[0].frame.height < items[1].frame.height
	assert items[0].frame.height == items[2].frame.height
	assert items[1].frame.height == expected.height
	assert row.frame.height == expected.height
}
