// Module timeline is a widget module outside ui2: a Timeline element and its
// Keyframe parts, which VML authors as `timeline.Timeline { timeline.Keyframe() }`
// with no compiler support for either tag.
module timeline

import ui2

// Keyframe is the record a Keyframe tag gives its Timeline.
pub struct Keyframe {
pub:
	at      f64
	opacity f64
}

// KeyframeProps is a part: it becomes a record of its parent, not an element.
pub struct KeyframeProps {
pub mut:
	at      f64
	opacity f64 = 1
}

pub fn (p KeyframeProps) part(ctx ui2.VmlBuildContext) !ui2.VmlPart {
	if p.at < 0 || p.at > 1 {
		return error('keyframe `at` must be between 0 and 1')
	}
	return ui2.VmlRecordPart{
		record: Keyframe{
			at:      p.at
			opacity: p.opacity
		}
	}
}

// TimelineProps shows its keyframes, in declaration order, as a label.
pub struct TimelineProps {
	ui2.CommonProps
pub mut:
	duration f64 = 1
}

pub fn (p TimelineProps) build(ctx ui2.VmlBuildContext) !ui2.Element {
	frames := ctx.records[Keyframe]()
	text := frames.map('${it.at}:${it.opacity}').join(' ')
	return ui2.label(ctx.id, '${p.duration}s ${text}', ctx.frame, ui2.TextStyle{})
}
