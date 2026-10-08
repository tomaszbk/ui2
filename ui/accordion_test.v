@[has_globals]
module ui2

__global accordion_test_events = []ElementEvent{}
__global accordion_test_indices = []int{}

fn capture_accordion_test_event(event ElementEvent) {
	accordion_test_events << event
}

fn accordion_test_items(count int) []AccordionItem {
	mut items := []AccordionItem{cap: count}
	for index in 0 .. count {
		items << AccordionItem{
			id:       'item_${index}'
			title:    'Item ${index}'
			on_event: fn [index] (event ElementEvent) {
				accordion_test_indices << index
				accordion_test_events << event
			}
			content:  view('content_${index}', rect(0, 0, 1, 1), BoxStyle{}, [])
		}
	}
	return items
}

fn test_vertical_accordion_assigns_remaining_height_to_active_item() {
	geometry := accordion_geometry(
		frame:       rect(0, 0, 300, 240)
		orientation: .vertical
		current:     1
		min_space:   40
		items:       accordion_test_items(3)
	) or { panic(err) }
	assert geometry.items == [rect(0, 0, 300, 40), rect(0, 40, 300, 160), rect(0, 200, 300, 40)]
	assert geometry.headers[1] == rect(0, 40, 300, 40)
	assert geometry.content == rect(0, 80, 300, 120)
}

fn test_horizontal_accordion_assigns_remaining_width_to_active_item() {
	geometry := accordion_geometry(
		frame:     rect(0, 0, 360, 180)
		current:   0
		min_space: 40
		items:     accordion_test_items(3)
	) or { panic(err) }
	assert geometry.items == [rect(0, 0, 280, 180), rect(280, 0, 40, 180), rect(320, 0, 40, 180)]
	assert geometry.content == rect(40, 0, 240, 180)
}

fn test_accordion_rejects_insufficient_title_space() {
	if _ := accordion_geometry(
		frame:       rect(0, 0, 200, 100)
		orientation: .vertical
		min_space:   40
		items:       accordion_test_items(3)
	) {
		assert false, 'insufficient title space must fail'
	} else {
		assert err.msg().contains('enough space')
	}
}

fn test_accordion_constructor_selects_content_and_header_style() {
	panel := accordion(
		id:                'sections'
		frame:             rect(0, 0, 300, 240)
		orientation:       .vertical
		current:           1
		min_space:         40
		header_box:        BoxStyle{ bg: 0xeeeeee }
		active_header_box: BoxStyle{ bg: 0x2563eb }
		items:             accordion_test_items(3)
	) or { panic(err) }
	assert panel.children[0].id == 'content_1'
	assert panel.children[2].box.bg == u32(0x2563eb)
	assert panel.children[2].accessibility_value == 'expanded'
	accordion_test_indices = []int{}
	accordion_test_events = []ElementEvent{}
	header := panel.children[2]
	header.on_event(ElementEvent{ kind: .tap, id: header.id })
	assert accordion_test_indices == [1]
	assert accordion_test_events[0].id == header.id
	assert accordion_test_events[0].kind == .tap
}
