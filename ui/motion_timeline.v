module ui2

import math

// motion_forever as a timeline's repeat loops it until the element leaves.
pub const motion_forever = -1

pub enum MotionTimelineKind {
	keyframes // keyframes over duration
	sequence  // children one after another
	parallel  // children together; the longest sets the length
}

// MotionKeyframe sets the channels of style at `at`, a fraction 0...1 of its
// timeline's duration. easing shapes the segment that ends at this keyframe.
// Keyframes may share an `at`: the later one wins from that instant, so a
// value can jump. A channel with no keyframe at 0 starts from the value
// beneath it: the previous step of a sequence, or the element's presentation.
pub struct MotionKeyframe {
pub:
	at        f64
	style     MotionStyle
	easing    MotionEasing
	easing_fn MotionEasingFn = unsafe { nil }
}

// MotionTimeline plays keyframes over an element's presentation while it is
// mounted, starting when it mounts or is shown and again whenever the
// timeline changes. It composes like Kivy's animations: a sequence plays its
// children in turn, each continuing from where the previous one left every
// channel; a parallel plays them together and its children must animate
// different channels.
//
// repeat plays the timeline that many more times; motion_forever loops it.
// alternate plays every other cycle backwards. step samples the timeline only
// every step seconds, holding values in between. Only the outermost timeline
// may alternate, step, hold or loop forever; nested timelines may delay and
// repeat a finite number of times. When the last cycle ends the channels
// return to the element's presentation, or keep the timeline's final values
// with hold.
pub struct MotionTimeline {
pub:
	kind      MotionTimelineKind
	duration  f64 // seconds; keyframe timelines only
	keyframes []MotionKeyframe
	children  []MotionTimeline
	delay     f64
	repeat    int
	alternate bool
	step      f64
	hold      bool
}

// motion_keyframes plays keyframes over duration seconds.
pub fn motion_keyframes(duration f64, keyframes ...MotionKeyframe) MotionTimeline {
	return MotionTimeline{
		duration:  duration
		keyframes: keyframes
	}
}

// motion_tween animates from the current values to target, like one Kivy
// Animation step.
pub fn motion_tween(target MotionStyle, transition MotionTransition) MotionTimeline {
	return MotionTimeline{
		duration:  transition.duration
		keyframes: [
			MotionKeyframe{
				at:        1
				style:     target
				easing:    transition.easing
				easing_fn: transition.easing_fn
			},
		]
	}
}

// motion_sequence plays timelines one after another.
pub fn motion_sequence(timelines ...MotionTimeline) MotionTimeline {
	return MotionTimeline{
		kind:     .sequence
		children: timelines
	}
}

// motion_parallel plays timelines together.
pub fn motion_parallel(timelines ...MotionTimeline) MotionTimeline {
	return MotionTimeline{
		kind:     .parallel
		children: timelines
	}
}

// is_empty reports a timeline without keyframes or children: no timeline.
pub fn (timeline MotionTimeline) is_empty() bool {
	return timeline.keyframes.len == 0 && timeline.children.len == 0
}

// looped returns the timeline repeating until the element leaves.
pub fn (timeline MotionTimeline) looped() MotionTimeline {
	return MotionTimeline{
		...timeline
		repeat: motion_forever
	}
}

// repeated returns the timeline played count more times.
pub fn (timeline MotionTimeline) repeated(count int) MotionTimeline {
	return MotionTimeline{
		...timeline
		repeat: count
	}
}

// validate rejects nonfinite or negative times, keyframes outside 0...1,
// invalid keyframe values, forever loops of zero length and parallel children
// that animate the same channel.
pub fn (timeline MotionTimeline) validate() ! {
	timeline.validate_level(true)!
	if timeline.repeat == motion_forever && timeline.length(true) <= 0 {
		return error('a looping motion timeline must have a positive duration')
	}
}

fn (timeline MotionTimeline) validate_level(outermost bool) ! {
	if !finite_number(timeline.delay) || timeline.delay < 0 {
		return error('motion timeline delay must be finite and nonnegative')
	}
	if timeline.repeat < motion_forever {
		return error('motion timeline repeat must be nonnegative or motion_forever')
	}
	if !finite_number(timeline.step) || timeline.step < 0 {
		return error('motion timeline step must be finite and nonnegative')
	}
	if !outermost && (timeline.repeat == motion_forever || timeline.alternate
		|| timeline.step > 0 || timeline.hold) {
		return error('only the outermost motion timeline can loop forever, alternate, step or hold')
	}
	match timeline.kind {
		.keyframes {
			if !finite_number(timeline.duration) || timeline.duration < 0 {
				return error('motion timeline duration must be finite and nonnegative')
			}
			if timeline.children.len > 0 {
				return error('a keyframe motion timeline has no children')
			}
			for keyframe in timeline.keyframes {
				if !finite_number(keyframe.at) || keyframe.at < 0 || keyframe.at > 1 {
					return error('motion keyframes must be at a fraction between 0 and 1')
				}
				keyframe.style.validate()!
			}
		}
		.sequence, .parallel {
			if timeline.keyframes.len > 0 {
				return error('a ${timeline.kind} motion timeline takes children, not keyframes')
			}
			mut seen := u32(0)
			for child in timeline.children {
				child.validate_level(false)!
				mask := child.channel_mask()
				if timeline.kind == .parallel && seen & mask != 0 {
					return error('parallel motion timelines must animate different channels')
				}
				seen |= mask
			}
		}
	}
}

// length is the seconds one play of the timeline spans. The outermost
// timeline's delay and repeats belong to its schedule rather than its length.
fn (timeline MotionTimeline) length(outermost bool) f64 {
	body := match timeline.kind {
		.keyframes {
			timeline.duration
		}
		.sequence {
			mut total := 0.0
			for child in timeline.children {
				total += child.length(false)
			}
			total
		}
		.parallel {
			mut longest := 0.0
			for child in timeline.children {
				longest = math.max(longest, child.length(false))
			}
			longest
		}
	}
	if outermost {
		return body
	}
	return timeline.delay + body * f64(timeline.repeat + 1)
}

fn (timeline MotionTimeline) channel_mask() u32 {
	mut mask := u32(0)
	for keyframe in timeline.keyframes {
		mask |= motion_style_mask(keyframe.style)
	}
	for child in timeline.children {
		mask |= child.channel_mask()
	}
	return mask
}

// MotionChannel indexes one animatable number. Colors are stored as numbers;
// a shadow is six channels.
enum MotionChannel {
	opacity
	translate_x
	translate_y
	scale_x
	scale_y
	rotation
	origin_x
	origin_y
	background
	border_color
	text_color
	radius
	shadow_color
	shadow_opacity
	shadow_blur
	shadow_x
	shadow_y
	shadow_spread
	box_scale_x
	box_scale_y
}

const motion_channel_count = 20

fn motion_bit(channel MotionChannel) u32 {
	return u32(1) << u32(int(channel))
}

const motion_shadow_mask = motion_bit(.shadow_color) | motion_bit(.shadow_opacity) | motion_bit(.shadow_blur) | motion_bit(.shadow_x) | motion_bit(.shadow_y) | motion_bit(.shadow_spread)

fn motion_style_mask(style MotionStyle) u32 {
	mut mask := u32(0)
	if _ := style.opacity { mask |= motion_bit(.opacity) }
	if _ := style.translate_x { mask |= motion_bit(.translate_x) }
	if _ := style.translate_y { mask |= motion_bit(.translate_y) }
	if _ := style.scale_x { mask |= motion_bit(.scale_x) }
	if _ := style.scale_y { mask |= motion_bit(.scale_y) }
	if _ := style.rotation { mask |= motion_bit(.rotation) }
	if _ := style.origin_x { mask |= motion_bit(.origin_x) }
	if _ := style.origin_y { mask |= motion_bit(.origin_y) }
	if _ := style.background { mask |= motion_bit(.background) }
	if _ := style.border_color { mask |= motion_bit(.border_color) }
	if _ := style.text_color { mask |= motion_bit(.text_color) }
	if _ := style.radius { mask |= motion_bit(.radius) }
	if _ := style.shadow { mask |= motion_shadow_mask }
	if _ := style.box_scale_x { mask |= motion_bit(.box_scale_x) }
	if _ := style.box_scale_y { mask |= motion_bit(.box_scale_y) }
	return mask
}

// MotionChannels is MotionValues as an indexable array, so a timeline writes
// any channel without allocating.
struct MotionChannels {
mut:
	v [motion_channel_count]f64
}

fn motion_channels(values MotionValues) MotionChannels {
	t := values.transform
	p := values.paint
	return MotionChannels{
		v: [values.opacity, t.translate_x, t.translate_y, t.scale_x, t.scale_y, t.rotation, t.origin_x,
			t.origin_y, f64(p.background), f64(p.border_color), f64(p.text_color), p.radius,
			f64(p.shadow.color), p.shadow.opacity, p.shadow.blur, p.shadow.x, p.shadow.y,
			p.shadow.spread, values.box_scale_x, values.box_scale_y]!
	}
}

fn (c &MotionChannels) values() MotionValues {
	v := c.v
	return MotionValues{
		opacity:     v[0]
		transform:   VisualTransform{
			translate_x: v[1]
			translate_y: v[2]
			scale_x:     v[3]
			scale_y:     v[4]
			rotation:    v[5]
			origin_x:    v[6]
			origin_y:    v[7]
		}
		paint:       MotionPaint{
			background:   u32(v[8])
			border_color: u32(v[9])
			text_color:   u32(v[10])
			radius:       v[11]
			shadow:       BoxShadow{
				color:   u32(v[12])
				opacity: v[13]
				blur:    v[14]
				x:       v[15]
				y:       v[16]
				spread:  v[17]
			}
		}
		box_scale_x: v[18]
		box_scale_y: v[19]
	}
}

// motion_channel_mix interpolates one channel. Colors and bounded channels
// clamp the curve; scales never reach zero, so a reflection stays invertible.
fn motion_channel_mix(channel int, start f64, target f64, eased f64) f64 {
	return match channel {
		int(MotionChannel.background), int(MotionChannel.border_color),
		int(MotionChannel.text_color),
		int(MotionChannel.shadow_color) {
			f64(interpolate_color(u32(start), u32(target), motion_unit(eased)))
		}
		int(MotionChannel.opacity), int(MotionChannel.shadow_opacity) {
			motion_lerp(start, target, motion_unit(eased))
		}
		int(MotionChannel.scale_x), int(MotionChannel.scale_y) {
			value := motion_lerp(start, target, motion_unit(eased))
			if math.abs(value) < 1e-6 {
				if value < 0 || (value == 0 && target < 0) { -1e-6 } else { 1e-6 }
			} else {
				value
			}
		}
		int(MotionChannel.radius), int(MotionChannel.shadow_blur), int(MotionChannel.box_scale_x),
		int(MotionChannel.box_scale_y) {
			math.max(0.0, motion_lerp(start, target, eased))
		}
		else {
			motion_lerp(start, target, eased)
		}
	}
}

// A compiled key: its time within one cycle and its value. An inherit key
// takes the value beneath the timeline at the moment it is sampled.
struct MotionKey {
	at        f64
	value     f64
	inherit   bool
	easing    MotionEasing
	easing_fn MotionEasingFn = unsafe { nil }
}

struct MotionTrack {
	channel int
mut:
	keys []MotionKey
}

// MotionProgram is a timeline flattened to one track of keys per channel. It
// is compiled when an element's timeline changes; sampling it only reads.
struct MotionProgram {
mut:
	tracks    []MotionTrack
	duration  f64
	delay     f64
	repeat    int
	alternate bool
	step      f64
	hold      bool
	mask      u32
}

struct MotionProgramBuilder {
mut:
	tracks []MotionTrack
	index  [motion_channel_count]int
}

fn compile_motion_timeline(timeline MotionTimeline) !MotionProgram {
	timeline.validate()!
	mut builder := MotionProgramBuilder{
		index: [motion_channel_count]int{init: -1}
	}
	duration := builder.add_body(timeline, 0)
	return MotionProgram{
		tracks:    builder.tracks
		duration:  duration
		delay:     timeline.delay
		repeat:    timeline.repeat
		alternate: timeline.alternate
		step:      timeline.step
		hold:      timeline.hold
		mask:      timeline.channel_mask()
	}
}

// add places a nested timeline at offset, with its own delay and repeats, and
// returns the seconds it spans.
fn (mut builder MotionProgramBuilder) add(timeline MotionTimeline, offset f64) f64 {
	mut cursor := offset + timeline.delay
	for _ in 0 .. timeline.repeat + 1 {
		cursor += builder.add_body(timeline, cursor)
	}
	return cursor - offset
}

fn (mut builder MotionProgramBuilder) add_body(timeline MotionTimeline, offset f64) f64 {
	match timeline.kind {
		.keyframes {
			builder.add_keyframes(timeline.keyframes, timeline.duration, offset)
			return timeline.duration
		}
		.sequence {
			mut cursor := offset
			for child in timeline.children {
				cursor += builder.add(child, cursor)
			}
			return cursor - offset
		}
		.parallel {
			mut longest := 0.0
			for child in timeline.children {
				longest = math.max(longest, builder.add(child, offset))
			}
			return longest
		}
	}
}

fn (mut builder MotionProgramBuilder) track(channel int) int {
	if builder.index[channel] < 0 {
		builder.index[channel] = builder.tracks.len
		builder.tracks << MotionTrack{
			channel: channel
		}
	}
	return builder.index[channel]
}

fn (mut builder MotionProgramBuilder) add_keyframes(keyframes []MotionKeyframe, duration f64, offset f64) {
	mut order := []int{len: keyframes.len, init: index}
	order.sort_with_compare(fn [keyframes] (a &int, b &int) int {
		left, right := keyframes[*a].at, keyframes[*b].at
		if left < right {
			return -1
		}
		if left > right {
			return 1
		}
		return if *a < *b {
			-1
		} else if *a > *b {
			1
		} else {
			0
		}
	})
	mut started := u32(0)
	for position in order {
		keyframe := keyframes[position]
		mask := motion_style_mask(keyframe.style)
		values := motion_channels(keyframe.style.over(MotionValues{}))
		at := offset + keyframe.at * duration
		for channel in 0 .. motion_channel_count {
			bit := u32(1) << u32(channel)
			if mask & bit == 0 {
				continue
			}
			index := builder.track(channel)
			if started & bit == 0 {
				started |= bit
				if keyframe.at > 0 {
					// The segment starts from whatever the channel holds.
					keys := builder.tracks[index].keys
					builder.tracks[index].keys << if keys.len == 0 {
						MotionKey{
							at:      offset
							inherit: true
						}
					} else {
						MotionKey{
							at:      offset
							value:   keys[keys.len - 1].value
							inherit: keys[keys.len - 1].inherit
						}
					}
				}
			}
			builder.tracks[index].keys << MotionKey{
				at:        at
				value:     values.v[channel]
				easing:    keyframe.easing
				easing_fn: keyframe.easing_fn
			}
		}
	}
}

// MotionTimelinePosition is where a program is at some seconds after it
// started: the time within its cycle and the cycle's forward progress.
struct MotionTimelinePosition {
	time     f64
	progress f64
	cycle    int
	started  bool
	done     bool
}

fn (program &MotionProgram) locate(elapsed_since_start f64) MotionTimelinePosition {
	elapsed := elapsed_since_start - program.delay
	if elapsed < 0 {
		return MotionTimelinePosition{}
	}
	duration := program.duration
	if duration <= 0 {
		return MotionTimelinePosition{
			progress: 1
			started:  true
			done:     true
		}
	}
	cycle_float := math.floor(elapsed / duration)
	if program.repeat != motion_forever && cycle_float >= f64(program.repeat + 1) {
		last := program.repeat
		reversed := program.alternate && last % 2 == 1
		return MotionTimelinePosition{
			time:     if reversed { 0.0 } else { duration }
			progress: 1
			cycle:    last
			started:  true
			done:     true
		}
	}
	cycle := int(math.min(cycle_float, f64(max_int)))
	mut within := elapsed - cycle_float * duration
	progress := within / duration
	if program.step > 0 {
		within = math.floor(within / program.step) * program.step
	}
	if program.alternate && cycle % 2 == 1 {
		within = duration - within
	}
	return MotionTimelinePosition{
		time:     within
		progress: progress
		cycle:    cycle
		started:  true
	}
}

// end is the seconds after its start when a finite program ends.
fn (program &MotionProgram) end() f64 {
	return program.delay + program.duration * f64(program.repeat + 1)
}

// apply overrides the channels the program animates at time t of a cycle.
// Channels whose first key is later than t keep the values beneath.
fn (program &MotionProgram) apply(mut channels MotionChannels, t f64) {
	for track in program.tracks {
		keys := track.keys
		if keys.len == 0 || t < keys[0].at {
			continue
		}
		mut index := 0
		for index + 1 < keys.len && keys[index + 1].at <= t {
			index++
		}
		underlying := channels.v[track.channel]
		first := keys[index]
		start := if first.inherit { underlying } else { first.value }
		if index + 1 >= keys.len {
			channels.v[track.channel] = start
			continue
		}
		next := keys[index + 1]
		target := if next.inherit { underlying } else { next.value }
		progress := (t - first.at) / (next.at - first.at)
		eased := motion_ease(next.easing, next.easing_fn, progress)
		if !finite_number(eased) {
			channels.v[track.channel] = start
			continue
		}
		channels.v[track.channel] = motion_channel_mix(track.channel, start, target, eased)
	}
}

// copy_channels writes the program's channels from frozen values.
fn (program &MotionProgram) copy_channels(mut channels MotionChannels, frozen MotionChannels) {
	for track in program.tracks {
		channels.v[track.channel] = frozen.v[track.channel]
	}
}
