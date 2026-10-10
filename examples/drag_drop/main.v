module main

import ui2
import os
import time

struct CardPayload {
	name string
}

fn (card CardPayload) drag_type() string {
	return 'card'
}

@[heap]
struct Demo {
mut:
	drops   int
	cancels int
	status  string = 'Drag the card onto the green destination. Escape cancels.'
	inside  bool
}

const demo = &Demo{}

fn accept_card(offer ui2.DragOffer) ui2.DragOperation {
	if offer.payload is CardPayload { return .move }
	return .none
}

fn reject_card(_ ui2.DragOffer) ui2.DragOperation {
	return .none
}

// Optional, read-only scheduler evidence. Worker reads a synchronized handle;
// it never posts a task or changes the model, so it does not request a frame.
fn audit_idle(dispatcher ui2.UiDispatcher) {
	time.sleep(time.second)
	before := dispatcher.stats()
	time.sleep(30 * time.second)
	after := dispatcher.stats()
	println('IDLE builds=${after.builds - before.builds} draws=${after.draws - before.draws} callbacks=${after.callbacks - before.callbacks} pending=${after.pending} deadline=${after.next_deadline} animation=${after.animation_active}')
}

fn handle_drag(event ui2.ElementEvent) {
	mut state := unsafe { demo }
	if data := event.drag {
		println('${event.kind} ${event.id} ${data.operation} ${data.reason} window=(${data.offer.window_x},${data.offer.window_y})')
		match event.kind {
			.drag_enter { state.inside = data.operation != .none }
			.drag_leave { state.inside = false }
			.drop {
				state.drops++
				if data.offer.payload is CardPayload {
					state.status = 'Moved ${data.offer.payload.name}'
				}
			}
			.drag_cancel {
				state.cancels++
				state.status = 'Cancelled: ${data.reason}'
			}
			else {}
		}
		if event.kind in [.drag_end, .drag_cancel] && os.getenv('UI2_DRAG_AUDIT') == '1' {
			$if android || linux || ((macos || windows) && ui2_custom_rendering ?) {
				spawn audit_idle(ui2.ui_dispatcher())
			}
		}
	}
}

fn surface(id string, title string, frame ui2.Rect, color u32) ui2.Element {
	return ui2.with_event(ui2.view(id, frame, ui2.BoxStyle{ bg: color, radius: 8 }, [
		ui2.label('', title, ui2.rect(8, 12, frame.width - 16, 28), ui2.TextStyle{ color: 0xffffff, size: 16 }),
	]), handle_drag)
}

fn build() ui2.Element {
	state := unsafe { demo }
	return ui2.screen(0xf1f5f9, [
		ui2.label('', 'Drag-drop · typed card payload', ui2.rect(24, 18, 650, 32), ui2.TextStyle{ size: 24, color: 0x0f172a }),
		ui2.label('', state.status, ui2.rect(24, 60, 650, 30), ui2.TextStyle{ size: 16, color: 0x334155 }),
		// 360x140 composition projected to a 720x280 viewport (2x). Preview
		// follows the pointer beyond this viewport and clips only to the window.
		ui2.scaled_content('composition', ui2.rect(24, 100, 720, 280), 360, 140, ui2.BoxStyle{ bg: 0xe2e8f0 }, [
			ui2.with_drag_source(surface('card', 'Niño / café', ui2.rect(10, 30, 90, 50), 0x3b82f6), ui2.DragSource{
				payload: CardPayload{'Niño / café'}
				allowed: [.move]
				preview: ui2.DragPreview{ text: 'Niño / café', width: 90, height: 38, offset_x: 6, offset_y: 6 }
			}),
			ui2.with_drop_target(surface('destination', 'Move here', ui2.rect(130, 30, 100, 70), if state.inside {
				u32(0x15803d)
			} else {
				u32(0x16a34a)
			}), ui2.DropTarget{ accept: accept_card }),
			ui2.with_drop_target(surface('rejected', 'Reject', ui2.rect(250, 30, 100, 70), 0xdc2626), ui2.DropTarget{ accept: reject_card }),
		]),
		ui2.label('', 'Drops: ${state.drops} · Cancels: ${state.cancels}', ui2.rect(24, 400, 600, 32), ui2.TextStyle{ size: 20, color: 0x0f172a }),
		ui2.text_input(
			id:         'editor'
			text:       'Local draft: ñ / café'
			frame:      ui2.rect(24, 450, 420, 40)
			box:        ui2.BoxStyle{ bg: 0xffffff, radius: 6 }
			text_style: ui2.TextStyle{ size: 18, color: 0x0f172a }
		) or { panic(err) },
		ui2.label('', 'Edit this field, then drag: local text and focus survive.', ui2.rect(24, 500, 650, 28), ui2.TextStyle{ size: 14, color: 0x475569 }),
	])
}

fn main() {
	$if android || linux || ((macos || windows) && ui2_custom_rendering ?) {
		ui2.run_window('UI2 Drag Drop', 768, 550, build)
	} $else {
		eprintln('Run this example with -d ui2_custom_rendering; native profiles diagnose drag declarations.')
	}
}
