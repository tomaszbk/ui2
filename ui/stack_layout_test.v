module ui2

import math

fn test_stack_aligns_independent_layers_with_asymmetric_fractional_padding() {
	config := StackConfig{
		frame:    rect(80, 90, 140.5, 100.5)
		padding:  LayoutPadding{ left: 10.25, top: 5.5, right: 20.25, bottom: 15.5 }
		align_x:  .center
		align_y:  .end
		children: [
			StackChild{ element: Element{ id: 'first', frame: rect(900, 800, 30, 20) } },
			StackChild{ element: Element{ id: 'second', frame: rect(0, 0, 40, 25) }, align_x: .end, align_y: .center },
			StackChild{ element: Element{ id: 'cover', frame: rect(0, 0, 1, 1) }, align_x: .stretch, align_y: .stretch },
		]
	}
	assert stack_frames(config)! == [rect(50.25, 65, 30, 20), rect(80.25, 32.75, 40, 25),
		rect(10.25, 5.5, 110, 79.5)]
	layers := stack(config)!
	assert layers.frame == config.frame
	assert layers.children.map(it.id) == ['first', 'second', 'cover']
	assert stack_preferred_size(config)! == rect(0, 0, 70.5, 46)
}

fn test_stack_preserves_overflow_and_clamps_empty_stretch_area() {
	frames := stack_frames(StackConfig{
		frame:    rect(0, 0, 20, 10)
		padding:  LayoutPadding{ left: 8, top: 7, right: 15, bottom: 7 }
		children: [
			StackChild{ element: Element{ frame: rect(0, 0, 30, 20) }, align_x: .end, align_y: .center },
			StackChild{ element: Element{ frame: rect(0, 0, 30, 20) }, align_x: .stretch, align_y: .stretch },
		]
	})!
	assert frames == [rect(-22, -3, 30, 20), rect(8, 7, 0, 0)]
}

fn test_stack_rejects_invalid_geometry_and_container_auto_alignment() {
	for config in [StackConfig{ frame: rect(0, 0, -1, 10) },
		StackConfig{ frame: rect(0, 0, 10, 10), align_x: .auto },
		StackConfig{ frame: rect(0, 0, 10, 10), padding: LayoutPadding{ left: -1 } },
		StackConfig{ frame: rect(0, 0, 10, 10), padding: LayoutPadding{ top: math.nan() } },
		StackConfig{ frame: rect(0, 0, 10, 10), children: [StackChild{ element: Element{ frame: rect(0, 0, math.inf(1), 10) } }] }] {
		if _ := stack_frames(config) {
			assert false, 'invalid stack must fail'
		}
	}
}

struct StackFixtureModel {
	unused int
}

fn test_vml_stack_has_matching_direct_and_model_geometry() {
	source := 'Stack { padding_left: 10 padding_top: 5 padding_right: 20 padding_bottom: 15
		align_x: center align_y: center
		View { id: back width: 40 height: 20 }
		View { id: badge width: 10 height: 10 align_self_x: end align_self_y: start }
		View { id: front align_self_x: stretch align_self_y: stretch }
	}'
	for width in [120.0, 200.0] {
		direct := element_from_vml(source, rect(75, 80, width, 100))!
		modeled := element_from_vml_model(source, StackFixtureModel{}, rect(75, 80, width, 100))!
		assert direct.children.map(it.frame) == modeled.children.map(it.frame)
		assert direct.children[0].frame == rect((width - 50) / 2, 35, 40, 20)
		assert direct.children[1].frame == rect(width - 30, 5, 10, 10)
		assert direct.children[2].frame == rect(10, 5, width - 30, 80)
	}
}

fn test_row_and_column_use_flex_geometry_in_both_vml_paths() {
	for tag in ['Row', 'Column'] {
		source := '${tag} { gap: 10 View { width: 30 height: 20 flex_grow: 1 } View { width: 50 height: 20 } }'
		direct := element_from_vml(source, rect(0, 0, 100, 80))!
		modeled := element_from_vml_model(source, StackFixtureModel{}, rect(0, 0, 100, 80))!
		assert direct.children.map(it.frame) == modeled.children.map(it.frame)
		assert direct.children.map(it.frame) == if tag == 'Row' {
			[rect(0, 0, 40, 80), rect(50, 0, 50, 80)]
		} else {
			[rect(0, 0, 100, 50), rect(0, 60, 100, 20)]
		}
	}
}
