module ui2

// with_hover makes an element report a `.pointer_enter` event to its callback
// when the pointer comes over it and `.pointer_leave` when it goes, so a hover
// card can open or a row can highlight. The event carries the element's id and
// the pointer position in window coordinates.
//
// Hover follows the CSS :hover rule on every backend: an element is hovered
// while the topmost element under the pointer is it or one of its descendants,
// so moving onto a child keeps its hoverable ancestors hovered, and an element
// covered by another one (an open popover, say) is not hovered.
pub fn with_hover(el Element) Element {
	return Element{
		...el
		hoverable: true
	}
}

// HoverTarget is one hoverable element under the pointer. identity tells the
// same element apart across rebuilds (its mounted path or key); on_event is the
// callback its enter and leave events go to.
struct HoverTarget {
	identity string
	id       string
	on_event ElementCallback = unsafe { nil }
}

fn hover_target(identity string, el Element) ?HoverTarget {
	if !el.hoverable || el.hidden || voidptr(el.on_event) == unsafe { nil } {
		return none
	}
	return HoverTarget{
		identity: identity
		id:       el.id
		on_event: el.on_event
	}
}

fn hover_chain_has(chain []HoverTarget, identity string) bool {
	for target in chain {
		if target.identity == identity {
			return true
		}
	}
	return false
}

// hover_transitions compares the hovered chains before and after a pointer
// move, each listed from the outermost element in. It returns the elements to
// report as left — innermost first — and as entered — outermost first, the
// order the DOM fires mouseleave and mouseenter in.
fn hover_transitions(previous []HoverTarget, current []HoverTarget) ([]HoverTarget, []HoverTarget) {
	mut left := []HoverTarget{}
	for i := previous.len - 1; i >= 0; i-- {
		if !hover_chain_has(current, previous[i].identity) {
			left << previous[i]
		}
	}
	mut entered := []HoverTarget{}
	for target in current {
		if !hover_chain_has(previous, target.identity) {
			entered << target
		}
	}
	return left, entered
}

// PendingHoverEvent is one hover change ready for its element's callback.
struct PendingHoverEvent {
	on_event ElementCallback = unsafe { nil }
	event    ElementEvent
}

// hover_events turns hover transitions into the events every backend delivers,
// leaves before enters, at a pointer position in window coordinates.
fn hover_events(left []HoverTarget, entered []HoverTarget, x f64, y f64) []PendingHoverEvent {
	mut events := []PendingHoverEvent{cap: left.len + entered.len}
	for target in left {
		events << PendingHoverEvent{
			on_event: target.on_event
			event:    ElementEvent{
				kind: .pointer_leave
				id:   target.id
				x:    x
				y:    y
			}
		}
	}
	for target in entered {
		events << PendingHoverEvent{
			on_event: target.on_event
			event:    ElementEvent{
				kind: .pointer_enter
				id:   target.id
				x:    x
				y:    y
			}
		}
	}
	return events
}

fn (pending PendingHoverEvent) fire(w &Window) {
	if voidptr(pending.on_event) != unsafe { nil } {
		pending.on_event(ElementEvent{ ...pending.event, window: w })
	}
}
