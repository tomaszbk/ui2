// Copyright 2024 - 2026 Longbridge <https://longbridge.com>
// SPDX-License-Identifier: Apache-2.0
// The hover-card timing rules are adapted from gpui-kit
// crates/base/src/hover_card.rs: open and close delays (600 ms and 300 ms),
// trigger and content hover flags, and stale timers ignored by generation. They
// are recast here as a pure state machine the application drives; the popover
// and hover-card builders are new UI2 code. See third_party/gpui-kit.
module ui2

import math

// Popovers, hover cards and dropdown menus are floating surfaces built from
// ordinary elements, so they work on every renderer. Build them last, as the
// final children of the screen, and give them the window rectangle
// (ui2.bounds()) and their anchor in window coordinates; they place themselves
// from those. On the desktop custom renderer, with_overlay can present
// application content in the window's overlay layer instead.

fn popover_default_padding(padding f64, metrics ComponentMetrics) !f64 {
	if padding < 0 && padding != -1 {
		return error('popover padding must be non-negative, or -1 for the default')
	}
	if !component_finite(padding) {
		return error('popover padding must be finite')
	}
	return if padding < 0 { metrics.padding * 1.5 } else { padding }
}

fn popover_arrow_depth(size ComponentSize) f64 {
	return match size {
		.small { 5 }
		.medium { 6 }
		.large { 8 }
	}
}

// popover_closed is what a closed overlay builds to: nothing is mounted, so an
// application can keep the call in its tree whether the overlay shows or not.
fn popover_closed(id string) Element {
	return Element{
		...view(id, rect(0, 0, 0, 0), BoxStyle{ transparent: true }, []Element{})
		hidden: true
	}
}

fn popover_translate(frame Rect, dx f64, dy f64) Rect {
	return rect(frame.x + dx, frame.y + dy, frame.width, frame.height)
}

// popover_chrome puts a surface (framed in window coordinates) and its arrow in
// a transparent container framed in window coordinates as well. The arrow is a
// border-colored triangle under a background-colored one; the second is drawn
// after the surface so that it opens the surface's border where they join.
fn popover_chrome(placement PopoverPlacement, surface Element, depth f64, theme ComponentTheme) Element {
	frame := placement.frame
	mut outline := []Rect{}
	mut fill := []Rect{}
	if depth > 0 {
		edge := match placement.side {
			.bottom { frame.y }
			.top { frame.y + frame.height }
			.right { frame.x }
			.left { frame.x + frame.width }
		}
		outline = popover_arrow_strips(placement.side, edge, placement.arrow, depth, 0, 0.5)
		fill = popover_arrow_strips(placement.side, edge, placement.arrow, depth, 1, 0.5)
	}
	mut outer := frame
	for strip in outline {
		outer = popover_union(outer, strip)
	}
	mut children := []Element{cap: outline.len + fill.len + 1}
	for strip in outline {
		children << view('', popover_translate(strip, -outer.x, -outer.y), BoxStyle{
			bg: theme.border
		}, []Element{})
	}
	children << Element{
		...surface
		frame: popover_translate(frame, -outer.x, -outer.y)
	}
	for strip in fill {
		children << view('', popover_translate(strip, -outer.x, -outer.y), BoxStyle{
			bg: theme.background
		}, []Element{})
	}
	return view('', outer, BoxStyle{ transparent: true }, children)
}

// popover_backdrop is a transparent button over the whole window that takes a
// press outside the surfaces drawn above it and reports it to on_dismiss.
fn popover_backdrop(id string, window Rect, on_dismiss ElementCallback) Element {
	return Element{
		...button(id, '', rect(0, 0, window.width, window.height), BoxStyle{
			transparent: true
		}, TextStyle{})
		on_event:           component_forward_click(on_dismiss)
		accessibility_role: 'presentation'
	}
}

// popover_layer is the root a floating surface returns. With a backdrop it
// covers the window, backdrop first; without one it is just the surfaces'
// container, so it neither hides the hover of nor swallows clicks on what lies
// around it.
fn popover_layer(id string, window Rect, backdrop_id string, backdrop bool, on_dismiss ElementCallback, layers []Element) Element {
	if backdrop {
		mut children := [popover_backdrop(backdrop_id, window, on_dismiss)]
		for layer in layers {
			children << Element{
				...layer
				frame: popover_translate(layer.frame, -window.x, -window.y)
			}
		}
		return view(id, window, BoxStyle{ transparent: true }, children)
	}
	if layers.len == 1 {
		return Element{
			...layers[0]
			id: id
		}
	}
	mut outer := if layers.len > 0 { layers[0].frame } else { rect(0, 0, 0, 0) }
	for layer in layers {
		outer = popover_union(outer, layer.frame)
	}
	mut children := []Element{cap: layers.len}
	for layer in layers {
		children << Element{
			...layer
			frame: popover_translate(layer.frame, -outer.x, -outer.y)
		}
	}
	return view(id, outer, BoxStyle{ transparent: true }, children)
}

// popover_panel returns the box and the first child of a rounded panel with a
// one-point border that looks the same on every renderer: the box is a
// border-colored shape and the child its fill, inset over it. A BoxStyle border
// would be square-cornered in the custom renderer. Lay the panel's content out
// after that child, in the panel's own coordinates.
fn popover_panel(size Rect, fill u32, border u32, radius f64, floating bool) (BoxStyle, []Element) {
	shadow := if floating { component_popup_shadow() } else { BoxShadow{} }
	if fill == border {
		return BoxStyle{
			bg:     fill
			radius: radius
			shadow: shadow
		}, []Element{}
	}
	return BoxStyle{
		bg:     border
		radius: radius
		shadow: shadow
	}, [
		Element{
			...view('', rect(1, 1, math.max(size.width - 2, 0), math.max(size.height - 2, 0)),
				BoxStyle{
					bg:     fill
					radius: math.max(radius - 1, 0)
				}, []Element{})
			key: 'fill'
		},
	]
}

// popover_surface is the bordered panel holding application content. It reports
// pointer presses as a clickable surface does, so a press on its blank space
// stays with it instead of falling through to the dismiss backdrop below.
fn popover_surface(id string, size Rect, padding f64, content []Element, role string, accessibility_label string, metrics ComponentMetrics, theme ComponentTheme) !Element {
	body := component_inset(rect(0, 0, size.width, size.height), padding)!
	box, mut children := popover_panel(size, theme.background, theme.border, metrics.radius,
		true)
	children << view('', body, BoxStyle{ transparent: true }, content)
	return Element{
		...view(id, size, box, children)
		on_event:            component_absorb
		clickable:           true
		accessibility_role:  role
		accessibility_label: accessibility_label
	}
}

// popover_dismiss_key reports whether a key press closes an open popover:
// Escape without modifiers. Call it from on_key_event, then consume the key.
pub fn popover_dismiss_key(open bool, event KeyEvent) bool {
	return open && event.code == .escape && !event.cmd && !event.ctrl && !event.alt
		&& !event.shift
}

pub struct PopoverConfig {
pub:
	id     string
	open   bool
	anchor Rect // The trigger, in window coordinates.
	window Rect // Pass ui2.bounds().
	width  f64          = 240 // Surface size, padding included.
	height f64          = 120
	side   PopoverSide  = .bottom
	align  PopoverAlign = .start
	offset f64          = 4
	margin f64          = 8
	arrow  bool
	flip   bool = true
	shift  bool = true
	// padding insets children from the surface edge; -1 picks one for the size.
	padding f64 = -1
	// close_on_outside_click lays a transparent backdrop over the window that
	// takes presses outside the surface and reports them to on_dismiss.
	close_on_outside_click bool            = true
	on_dismiss             ElementCallback = unsafe { nil }
	label                  string    // Accessibility label of the surface.
	children               []Element // Positioned relative to the padded body.
	size                   ComponentSize = .medium
	theme                  ComponentTheme
}

// popover_placement_config is the geometry part of a popover's configuration.
fn popover_placement_config(config PopoverConfig) PopoverPlacementConfig {
	return PopoverPlacementConfig{
		anchor: config.anchor
		window: config.window
		width:  config.width
		height: config.height
		side:   config.side
		align:  config.align
		offset: config.offset
		margin: config.margin
		arrow:  if config.arrow { popover_arrow_depth(config.size) } else { 0 }
		radius: component_metrics(config.size).radius
		flip:   config.flip
		shift:  config.shift
	}
}

// popover draws application content in a bordered surface next to an anchor,
// flipped and shifted to stay in the window. It is controlled: the application
// owns `open`, toggles it from its trigger's own callback and closes it from
// on_dismiss and on Escape (popover_dismiss_key). Build it after everything it
// may cover.
pub fn popover(config PopoverConfig) !Element {
	component_validate_id(config.id)!
	metrics := component_metrics(config.size)
	padding := popover_default_padding(config.padding, metrics)!
	placement := popover_place(popover_placement_config(config))!
	if !config.open {
		return component_finish(popover_closed(config.id))
	}
	surface := popover_surface(component_part_id(config.id, 'surface'), placement.frame,
		padding, config.children, 'dialog', config.label, metrics, config.theme)!
	chrome := popover_chrome(placement, surface, if config.arrow {
		popover_arrow_depth(config.size)
	} else {
		0
	}, config.theme)
	return component_finish(popover_layer(config.id, config.window, component_part_id(config.id,
		'backdrop'), config.close_on_outside_click, config.on_dismiss, [chrome]))
}

// HoverCardTimer names the delay a hover card is waiting out.
pub enum HoverCardTimer {
	none
	open
	close
}

// HoverCardState is a hover card's pure state machine. The application keeps
// one per card, receives each step from pointer events on the trigger and the
// card (HoverCardConfig.on_step, built with hover_card_step), feeds it timer
// firings (timer_fired), and runs the timers each step asks for with `after`
// and `cancel_timer`. The zero value is a closed card with the default delays;
// set `open: true` to start with it showing.
pub struct HoverCardState {
pub:
	open_delay      f64 = 0.6 // Seconds the pointer rests on the trigger before the card opens.
	close_delay     f64 = 0.3 // Seconds after leaving trigger and card before it closes.
	open            bool
	trigger_hovered bool
	card_hovered    bool
	pending         HoverCardTimer
	// generation names the pending timer. A firing carrying any other value is
	// stale and changes nothing, so a timer that could not be cancelled in time
	// is harmless.
	generation u64
}

// HoverCardStep is a state transition and the timer work it needs: when
// `cancel` is set, cancel the timer started for an earlier step; when
// `schedule` is set, start `after(delay)` and pass `state.generation` to
// timer_fired when it runs.
pub struct HoverCardStep {
pub:
	state    HoverCardState
	cancel   bool
	schedule bool
	delay    f64
}

fn hover_card_delay(seconds f64) f64 {
	return if component_finite(seconds) && seconds > 0 { seconds } else { 0 }
}

fn (state HoverCardState) schedule(next HoverCardState, timer HoverCardTimer) HoverCardStep {
	delay := if timer == .open { state.open_delay } else { state.close_delay }
	return HoverCardStep{
		state:    HoverCardState{
			...next
			pending:    timer
			generation: state.generation + 1
		}
		cancel:   state.pending != .none
		schedule: true
		delay:    hover_card_delay(delay)
	}
}

// settled clears any pending timer.
fn (state HoverCardState) settled(next HoverCardState) HoverCardStep {
	if state.pending == .none {
		return HoverCardStep{
			state: next
		}
	}
	return HoverCardStep{
		state:  HoverCardState{
			...next
			pending:    .none
			generation: state.generation + 1
		}
		cancel: true
	}
}

// trigger_entered starts the open delay, or, when the card already shows,
// calls off a pending close.
pub fn (state HoverCardState) trigger_entered() HoverCardStep {
	next := HoverCardState{
		...state
		trigger_hovered: true
	}
	if state.open {
		return state.settled(next)
	}
	return state.schedule(next, .open)
}

// trigger_left starts the close delay unless the pointer went onto the card. A
// pointer that only swept across the trigger never opens it.
pub fn (state HoverCardState) trigger_left() HoverCardStep {
	next := HoverCardState{
		...state
		trigger_hovered: false
	}
	if state.card_hovered {
		return HoverCardStep{
			state: next
		}
	}
	if state.open {
		return state.schedule(next, .close)
	}
	return state.settled(next)
}

// card_entered keeps the card open while the pointer is over it.
pub fn (state HoverCardState) card_entered() HoverCardStep {
	next := HoverCardState{
		...state
		card_hovered: true
	}
	if state.pending == .close {
		return state.settled(next)
	}
	return HoverCardStep{
		state: next
	}
}

// card_left starts the close delay unless the pointer went back to the trigger.
pub fn (state HoverCardState) card_left() HoverCardStep {
	next := HoverCardState{
		...state
		card_hovered: false
	}
	if state.open && !state.trigger_hovered {
		return state.schedule(next, .close)
	}
	return HoverCardStep{
		state: next
	}
}

// timer_fired applies the delay named by generation, or changes nothing when
// that timer has since been replaced or called off.
pub fn (state HoverCardState) timer_fired(generation u64) HoverCardStep {
	if generation != state.generation || state.pending == .none {
		return HoverCardStep{
			state: state
		}
	}
	hovered := state.trigger_hovered || state.card_hovered
	return HoverCardStep{
		state: HoverCardState{
			...state
			open:    if state.pending == .open {
				hovered || state.open
			} else {
				hovered && state.open
			}
			pending: .none
		}
	}
}

// dismissed closes the card at once, for Escape or a click inside it. It
// stays closed until the pointer enters the trigger again.
pub fn (state HoverCardState) dismissed() HoverCardStep {
	return state.settled(HoverCardState{
		...state
		open: false
	})
}

// tapped toggles the card without delays: the behavior for touch screens, which
// have no hover. Call it from the trigger's own callback.
pub fn (state HoverCardState) tapped() HoverCardStep {
	return state.settled(HoverCardState{
		...state
		open: !state.open
	})
}

// HoverCardPart is the part of a hover card the pointer moved over.
pub enum HoverCardPart {
	trigger
	card
}

// hover_card_step turns a pointer enter or leave on the card's trigger
// (hover_card_trigger) or on the card itself into the transition with the
// timer work to do. Every other event gives none.
pub fn hover_card_step(state HoverCardState, part HoverCardPart, event ElementEvent) ?HoverCardStep {
	entered := match event.kind {
		.pointer_enter { true }
		.pointer_leave { false }
		else { return none }
	}
	return match part {
		.trigger {
			if entered { state.trigger_entered() } else { state.trigger_left() }
		}
		.card {
			if entered { state.card_entered() } else { state.card_left() }
		}
	}
}

// hover_card_hover_callback reports each step the pointer moving over part asks
// of the state the card was built with.
fn hover_card_hover_callback(config HoverCardConfig, part HoverCardPart) ElementCallback {
	if voidptr(config.on_step) == unsafe { nil } {
		return unsafe { nil }
	}
	on_step := config.on_step
	card_state := config.state
	return fn [on_step, card_state, part] (event ElementEvent) {
		if step := hover_card_step(card_state, part, event) {
			on_step(step)
		}
	}
}

// hover_card_trigger wraps any element in the hover area that opens the card
// config describes. The wrapper takes the element's frame; the element keeps
// its own callback, so a link stays a link. Hovering the element counts as
// hovering the wrapper.
pub fn hover_card_trigger(config HoverCardConfig, trigger Element) !Element {
	component_validate_id(config.id)!
	component_validate_frame(trigger.frame)!
	return component_finish(Element{
		...view(component_part_id(config.id, 'trigger'), trigger.frame, BoxStyle{
			transparent: true
		}, [
			Element{
				...trigger
				frame: rect(0, 0, trigger.frame.width, trigger.frame.height)
			},
		])
		on_event:  hover_card_hover_callback(config, .trigger)
		hoverable: true
	})
}

pub struct HoverCardConfig {
pub:
	id       string
	state    HoverCardState
	anchor   Rect // The trigger, in window coordinates.
	window   Rect // Pass ui2.bounds().
	width    f64          = 280
	height   f64          = 96
	side     PopoverSide  = .bottom
	align    PopoverAlign = .center
	offset   f64          = 4
	margin   f64          = 8
	arrow    bool
	padding  f64 = -1
	label    string
	children []Element // Positioned relative to the padded body.
	size     ComponentSize = .medium
	theme    ComponentTheme
	// on_step receives each transition the pointer entering or leaving the
	// trigger or the card asks for; store its state and run its timer work.
	on_step fn (HoverCardStep) = unsafe { nil }
}

// hover_card shows rich content while the pointer rests on a trigger wrapped by
// hover_card_trigger, and keeps it while the pointer moves onto the card. It has
// no backdrop and no outside-click dismissal; it opens and closes as the
// HoverCardState the application drives says.
pub fn hover_card(config HoverCardConfig) !Element {
	component_validate_id(config.id)!
	metrics := component_metrics(config.size)
	padding := popover_default_padding(config.padding, metrics)!
	depth := if config.arrow { popover_arrow_depth(config.size) } else { 0.0 }
	placement := popover_place(
		anchor: config.anchor
		window: config.window
		width:  config.width
		height: config.height
		side:   config.side
		align:  config.align
		offset: config.offset
		margin: config.margin
		arrow:  depth
		radius: metrics.radius
	)!
	if !config.state.open {
		return component_finish(popover_closed(config.id))
	}
	surface := popover_surface(component_part_id(config.id, 'surface'), placement.frame,
		padding, config.children, 'group', config.label, metrics, config.theme)!
	chrome := popover_chrome(placement, surface, depth, config.theme)
	return component_finish(Element{
		...chrome
		id:        config.id
		on_event:  hover_card_hover_callback(config, .card)
		hoverable: true
	})
}

// popover_blend mixes two 0xRRGGBB colors; amount 0 is a, 1 is b.
fn popover_blend(a u32, b u32, amount f64) u32 {
	t := math.min(math.max(amount, 0), 1)
	mut out := u32(0)
	for shift in [u32(16), 8, 0] {
		ca := f64((a >> shift) & 0xff)
		cb := f64((b >> shift) & 0xff)
		out |= u32(math.round(ca + (cb - ca) * t)) << shift
	}
	return out
}
