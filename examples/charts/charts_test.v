module main

import ui2

fn test_charts_demo_builds_all_types_at_multiple_window_sizes() {
	for width in [360, 720, 1080] {
		root := charts_screen(ui2.rect(0, 0, width, 720))
		ui2.validate_element_tree(root) or { panic(err) }
		scroll := root.children[0]
		assert scroll.kind == .scroll
		assert scroll.children.len == 5
		for chart in scroll.children {
			assert chart.frame.x >= 0
			assert chart.frame.x + chart.frame.width <= width
			assert chart.accessibility_role == 'img'
			assert chart.children.len > 0
		}
	}
}
