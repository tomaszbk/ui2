// vtest vflags: -d vml_props
module ui2

// Timeline and Keyframe parts built through the props table, as the VML
// runtime builds them: keyframes without a target animate the element holding
// the Timeline, and keyframes naming a descendant become the element's targets.

fn props_motion_find(el Element, id string) ?Element {
	if el.id == id {
		return el
	}
	for child in el.children {
		if found := props_motion_find(child, id) {
			return found
		}
	}
	return none
}

fn props_motion_card(timeline PNode) PNode {
	return pn(ScreenProps{},
		id:       'root'
		children: [
			pn(ViewProps{
				width:  200
				height: 100
			},
				id:       'card'
				children: [
					pn(ViewProps{
						width:  20
						height: 20
					}, id: 'logo'),
					timeline,
				]
			),
		]
	)
}

fn test_timeline_parts_animate_their_element_and_its_descendants() ! {
	built := props_document(props_motion_card(pn(TimelineProps{
		duration: 1.2
		repeat:   true
	},
		children: [
			pn(KeyframeProps{
				target:  'logo'
				at:      0.5
				opacity: 0.4
				scale:   1.1
				easing:  .in_out_sine
			}),
			pn(KeyframeProps{
				target:  'logo'
				at:      1
				opacity: 1
				scale:   1
			}),
			pn(KeyframeProps{
				at:         1
				background: 0xff0000
			}),
		]
	)), rect(0, 0, 400, 300))!
	card := props_motion_find(built, 'card') or { panic('no card') }
	logo := props_motion_find(built, 'logo') or { panic('no logo') }
	assert logo.motion == none
	config := card.motion or { panic('the card has no motion') }
	// The card plays its own keyframes and targets the logo.
	assert config.timeline == MotionTimeline{
		duration:  1.2
		keyframes: [
			MotionKeyframe{
				at:    1
				style: MotionStyle{
					background: 0xff0000
				}
			},
		]
		repeat:    motion_forever
	}
	assert config.targets.len == 1
	target := config.targets[0]
	assert target.id == logo.id
	assert target.timeline.repeat == motion_forever && target.timeline.duration == 1.2
	assert target.timeline.keyframes == [
		MotionKeyframe{
			at:     0.5
			style:  MotionStyle{
				opacity: 0.4
				scale_x: 1.1
				scale_y: 1.1
			}
			easing: .in_out_sine
		},
		MotionKeyframe{
			at:    1
			style: MotionStyle{
				opacity: 1
				scale_x: 1
				scale_y: 1
			}
		},
	]
	// A Timeline added to an element starts with no enter or exit effect.
	assert config.enter == MotionStyle{} && config.exit == MotionStyle{}
	config.validate()!
}

fn test_timeline_part_options_map_to_the_timeline() ! {
	built := props_document(props_motion_card(pn(TimelineProps{
		duration:  0.5
		delay:     0.25
		times:     3
		alternate: true
		step:      0.1
		hold:      true
	},
		children: [
			pn(KeyframeProps{
				at:          1
				translate_x: 40
				scale_x:     2
				scale:       3
				rotation:    90
				radius:      6
				box_scale_x: 0.5
			}),
		]
	)), rect(0, 0, 400, 300))!
	card := props_motion_find(built, 'card') or { panic('no card') }
	timeline := (card.motion or { panic('no motion') }).timeline
	assert timeline.duration == 0.5 && timeline.delay == 0.25
	assert timeline.repeat == 2 && timeline.alternate && timeline.step == 0.1 && timeline.hold
	// scale_x wins over scale for its axis.
	assert timeline.keyframes[0].style == MotionStyle{
		translate_x: 40
		scale_x:     2
		scale_y:     3
		rotation:    90
		radius:      6
		box_scale_x: 0.5
	}
}

fn test_timeline_parts_reject_invalid_keyframes() {
	for keyframe in [KeyframeProps{
		at:      1.5
		opacity: 1
	}, KeyframeProps{
		at:      0.5
		opacity: 2
	}, KeyframeProps{
		at:    0.5
		scale: 0
	}] {
		if _ := keyframe.part(VmlBuildContext{}) {
			assert false, 'invalid keyframe ${keyframe.at} accepted'
		}
	}
	if _ := (TimelineProps{
		times: 0
	}).part(VmlBuildContext{}) {
		assert false, 'a timeline that never plays accepted'
	}
	if _ := (TimelineProps{
		duration: -1
	}).part(VmlBuildContext{
		parts: [VmlPart(VmlKeyframe{
			keyframe: MotionKeyframe{
				at:    1
				style: MotionStyle{
					opacity: 1
				}
			}
		})]
	}) {
		assert false, 'negative duration accepted'
	}
}

fn test_timeline_parts_join_an_authored_motion() {
	pulse := motion_keyframes(1, MotionKeyframe{
		at:    1
		style: MotionStyle{
			rotation: 90
		}
	})
	authored := compose_motion([motion_fade(0.2), motion_timeline(pulse),
		motion_target('badge', pulse)])
	parts := [
		VmlPart(VmlTimeline{
			targets: [
				MotionTarget{
					timeline: motion_keyframes(1, MotionKeyframe{
						at:    1
						style: MotionStyle{
							opacity: 0.5
						}
					})
				},
				MotionTarget{
					id:       'logo'
					timeline: pulse
				},
			]
		}),
	]
	el := view('card', rect(0, 0, 10, 10), BoxStyle{}, []Element{})
	projected := vml_project_motion(authored, el, VmlBuildContext{ parts: parts }) or {
		panic('no motion')
	}
	// The authored timeline and the part's play together; targets add up.
	assert projected.timeline.kind == .parallel && projected.timeline.children.len == 2
	assert projected.timeline.children[0] == pulse
	assert projected.targets.map(it.id) == ['badge', 'logo']
	assert projected.enter == authored.enter
	projected.validate() or { panic(err) }
	// Without parts the authored motion is kept as it is.
	assert vml_project_motion(authored, el, VmlBuildContext{}) or { panic('no motion') } == authored
	assert vml_project_motion(none, el, VmlBuildContext{}) == none
}
