module main

import ui2
import ui2.tests.compiled_vml.timeline

pub struct TimelineApp {
pub mut:
	peak f64
}

fn build_timeline(mut app TimelineApp) ui2.Element {
	return $vml('third_party_parts.vml')
}

// A tag pair defined outside ui2 needs no compiler support: the Timeline
// element receives its Keyframe parts as typed records, in declaration order.
fn test_third_party_part_tags_carry_typed_records_to_their_parent() {
	mut app := TimelineApp{
		peak: 0.8
	}
	element := build_timeline(mut app)
	assert element.id == 'fade'
	assert element.text == '2.0s 0.0:0.0 0.4:0.8 1.0:0.5'
}

// A part checks its own values when its parent builds.
fn test_third_party_part_rejects_values_out_of_range() {
	timeline.KeyframeProps{
		at: 2
	}.part(ui2.VmlBuildContext{}) or {
		assert err.msg().contains('between 0 and 1')
		return
	}
	assert false, 'a keyframe outside the timeline was accepted'
}
