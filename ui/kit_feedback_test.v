// vtest vflags: -d vml_props
module ui2

// The kit's feedback components built through the generic node runtime:
// progress fills, the looping parts of the indeterminate and placeholder
// components, and the Clipboard's copied state.

fn kit_timeline(el Element) MotionTimeline {
	config := el.motion or { return MotionTimeline{} }
	return config.timeline
}

fn test_progress_fills_its_track_to_the_value() ! {
	tree := props_document(pn(ColumnProps{ gap: 8 },
		children: [
			pn(ProgressProps{ value: 40 }, id: 'upload'),
			pn(ProgressProps{ value: 3, max: 4, size: .large, tone: .success }, id: 'steps'),
			pn(ProgressProps{ value: 140 }, id: 'over'),
		]
	), rect(0, 0, 300, 200))!
	t := kit_tokens(default_theme())
	upload := tree.children[0]
	assert upload.frame.width == 300 && upload.frame.height == 8
	assert upload.box.bg == t.track && upload.box.radius == 4
	assert upload.accessibility_role == 'progressbar' && upload.accessibility_value == '40%'
	fill := upload.children[0]
	assert fill.id.ends_with('upload__fill') && fill.box.bg == t.accent
	assert fill.frame.width == 120 && fill.frame.height == 8
	assert upload.children[1].frame.width == 180
	// A new value slides the fill's box to its new width.
	assert (fill.motion or { MotionConfig{} }).layout == .box
	steps := tree.children[1]
	assert steps.frame.height == 10 && steps.children[0].frame.width == 225
	assert steps.children[0].box.bg == t.success
	over := tree.children[2]
	assert over.children[0].frame.width == 300 && over.accessibility_value == '100%'
}

fn test_loading_progress_sweeps_a_segment() ! {
	tree := props_document(pn(ColumnProps{},
		children: [
			pn(ProgressProps{ loading: true }, id: 'busy'),
		]
	), rect(0, 0, 300, 100))!
	t := kit_tokens(default_theme())
	busy := tree.children[0]
	assert busy.layout.kind == .stack && busy.accessibility_label == 'Loading'
	fill := busy.children[0]
	mask := busy.children[1]
	assert fill.frame.width == 300 && mask.frame.width == 300
	// Without motion the bar is full: the mask is transparent until its loop
	// shows it in the track color.
	assert fill.opacity == 1 && mask.opacity == 0 && mask.box.bg == t.track
	assert kit_timeline(fill).repeat == motion_forever
	assert kit_timeline(mask).repeat == motion_forever
	left, right := linear_progress_loading_keys()
	assert kit_timeline(fill).keyframes.len == right.len
	assert kit_timeline(mask).keyframes.len == left.len
}

fn test_progress_circle_draws_its_ring_as_vector_arcs() ! {
	tree := props_document(pn(RowProps{ align_items: .start },
		children: [
			pn(ProgressCircleProps{ value: 25 }, id: 'quarter'),
			pn(ProgressCircleProps{}, id: 'empty'),
			pn(ProgressCircleProps{ loading: true, size: .large }, id: 'busy'),
			pn(ProgressCircleProps{ value: 50, width: 40 }, id: 'big'),
		]
	), rect(0, 0, 300, 100))!
	quarter := tree.children[0]
	assert quarter.is_vector_canvas && quarter.frame.width == 16 && quarter.frame.height == 16
	assert quarter.vector_shapes.len == 2 && quarter.accessibility_value == '25%'
	assert tree.children[1].vector_shapes.len == 1
	busy := tree.children[2]
	assert busy.frame.width == 20 && busy.origin_x == 10
	assert kit_timeline(busy).repeat == motion_forever && busy.accessibility_label == 'Loading'
	assert tree.children[3].frame.width == 40
}

fn test_spinner_skeleton_and_shimmer() ! {
	tree := props_document(pn(ColumnProps{ align_items: .start, gap: 8 },
		children: [
			pn(SpinnerProps{ size: .small }, id: 'spin'),
			pn(SpinnerProps{ color: 0x112233 }, id: 'tinted'),
			pn(SkeletonProps{ width: 200 }, id: 'line'),
			pn(SkeletonProps{ circle: true }, id: 'face'),
			pn(ShimmerProps{ width: 200 }, id: 'text'),
			pn(ShimmerProps{ lines: 1, width: 100 }, id: 'one'),
		]
	), rect(0, 0, 300, 400))!
	t := kit_tokens(default_theme())
	spin := tree.children[0]
	assert spin.is_vector_canvas && spin.frame.width == 14 && spin.accessibility_role == 'progressbar'
	stroke := spin.vector_shapes[0].style.stroke or { 0 }
	assert stroke == t.muted
	assert kit_timeline(spin).repeat == motion_forever
	tinted := tree.children[1].vector_shapes[0].style.stroke or { 0 }
	assert tinted == 0x112233
	line := tree.children[2]
	assert line.frame.width == 200 && line.frame.height == 16 && line.box.bg == t.track
	assert kit_timeline(line).repeat == motion_forever
	face := tree.children[3]
	assert face.frame.width == 40 && face.box.radius == 20
	text := tree.children[4]
	assert text.children.len == 3
	first := text.children[0]
	assert first.frame.width == 200 && first.frame.height == t.font_caption
	assert first.children.map(it.key) == ['band', 'cover']
	assert first.children.all(it.opacity == 0)
	assert kit_timeline(first.children[0]).repeat == motion_forever
	// The last line is three fifths of the width, up to the flex rounding.
	last := text.children[2].children[0].frame.width
	assert last > 119.999 && last < 120.001
	assert tree.children[5].children.len == 1 && tree.children[5].children[0].frame.width == 100
}

fn test_clipboard_shows_a_check_while_copied() ! {
	tree := props_document(pn(ColumnProps{ align_items: .start },
		children: [
			pn(ClipboardProps{ value: 'npm i ui2' }, id: 'copy'),
			pn(ClipboardProps{ value: 'x', text: 'Copy link', copied: true }, id: 'done'),
		]
	), rect(0, 0, 300, 100))!
	mut root := tree.compiled_node
	root.mount()!
	copy := root.element().children[0]
	assert copy.button_behavior && copy.frame.height == 24
	assert copy.children[0].image_path == 'symbol:' + IconName.copy.symbol()
	assert copy.accessibility_label == 'Copy'
	done := root.element().children[1]
	assert done.children[0].image_path == 'symbol:' + IconName.check.symbol()
	assert done.children[1].text == 'Copy link' && done.accessibility_value == 'Copied'
	// The change a copy emits sets `copied`; the one two seconds later clears it.
	copy.on_event(ElementEvent{ kind: .change, id: copy.id, checked: true })
	assert root.element().children[0].children[0].image_path == 'symbol:' + IconName.check.symbol()
	copy.on_event(ElementEvent{ kind: .change, id: copy.id, checked: false })
	assert root.element().children[0].children[0].image_path == 'symbol:' + IconName.copy.symbol()
	root.dispose_document()!
}

fn test_progress_rejects_a_bad_maximum() {
	ProgressProps{
		max: 0
	}.validate() or {
		assert err.msg().contains('`max`')
		return
	}
	assert false
}
