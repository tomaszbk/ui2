@[has_globals]
module ui2

__global ios_callback_test_events = []ElementEvent{}

fn capture_ios_callback_event(event ElementEvent) {
	ios_callback_test_events << event
}

fn test_ios_button_behavior_release_preserves_the_captured_callback() {
	captured := IosCallbackBinding{ id: 'original', on_event: capture_ios_callback_event }
	current := IosCallbackBinding{ id: 'replacement', on_event: capture_ios_callback_event }
	assert ios_button_behavior_release_available(captured, current, true, true, false, true)
	assert !ios_button_behavior_release_available(captured, IosCallbackBinding{}, true, true, false, true)
	assert !ios_button_behavior_release_available(captured, current, false, true, false, true)
	assert !ios_button_behavior_release_available(captured, current, true, false, false, true)
	assert !ios_button_behavior_release_available(captured, current, true, true, true, true)
	assert !ios_button_behavior_release_available(captured, current, true, true, false, false)
	assert !ios_button_behavior_release_available(IosCallbackBinding{}, current, true, true, false, true)
	ios_callback_test_events = []ElementEvent{}
	if ios_button_behavior_release_available(captured, current, true, true, false, true) {
		ios_emit_callback(captured, ElementEvent{ kind: .tap })
	}
	assert ios_callback_test_events.len == 1
	assert ios_callback_test_events[0].id == 'original'
	anonymous := IosCallbackBinding{ on_event: capture_ios_callback_event }
	assert ios_button_behavior_release_available(anonymous, anonymous, true, true, false, true)
}

fn test_ios_button_behavior_capture_ignores_additional_touches() {
	captured := IosCallbackBinding{ id: 'original', on_event: capture_ios_callback_event }
	current := IosCallbackBinding{ id: 'replacement', on_event: capture_ios_callback_event }
	assert ios_button_behavior_capture_binding(captured, current, 1, false).id == 'original'
	assert ios_button_behavior_capture_binding(captured, current, 1, true).id == 'original'
	assert ios_button_behavior_capture_binding(captured, current, 0, true).id == 'replacement'
	assert !ios_callback_present(ios_button_behavior_capture_binding(captured, current, 0, false))
}

fn test_ios_typed_payloads_preserve_text_values_and_identity() {
	ios_callback_test_events = []ElementEvent{}
	binding := IosCallbackBinding{ on_event: capture_ios_callback_event }
	assert ios_emit_callback(binding, ElementEvent{ kind: .change, text: 'café: ñ', value: 2.75, checked: true })
	assert ios_callback_test_events[0].id == ''
	assert ios_callback_test_events[0].text == 'café: ñ'
	assert ios_callback_test_events[0].value == 2.75
	assert ios_callback_test_events[0].checked
}

fn capture_ios_scan_result(result ScanResult) {
	ios_scan_test_results << result
}

__global ios_scan_test_results = []ScanResult{}

fn test_ios_scanner_forwards_typed_results_without_encoding_content() {
	ios_scan_test_results = []ScanResult{}
	for result in [
		ScanResult{ kind: .code, text: 'café:EAN-13:7790000000000' },
		ScanResult{ kind: .error, text: 'camera permission denied' },
		ScanResult{ kind: .cancelled },
	] {
		g_scan_callback = capture_ios_scan_result
		report_scan_result(result)
		assert g_scan_callback == unsafe { nil }
	}
	assert ios_scan_test_results.len == 3
	assert ios_scan_test_results[0].kind == .code
	assert ios_scan_test_results[0].text == 'café:EAN-13:7790000000000'
	assert ios_scan_test_results[1].kind == .error
	assert ios_scan_test_results[2].kind == .cancelled
}

__global ios_control_test_handlers = []string{}

fn capture_ios_control_a(event ElementEvent) {
	ios_control_test_handlers << 'a'
	ios_callback_test_events << event
}

fn capture_ios_control_b(event ElementEvent) {
	ios_control_test_handlers << 'b'
	ios_callback_test_events << event
}

fn test_ios_ordinary_control_press_keeps_callback_and_cancels_without_current_registration() {
	first := IosCallbackBinding{ id: 'same', on_event: capture_ios_control_a, kind: .button, event: .tap }
	second := IosCallbackBinding{ ...first, on_event: capture_ios_control_b }
	ios_control_test_handlers = []string{}
	ios_callback_test_events = []ElementEvent{}
	selected := ios_control_release_binding(first, second, true) or { panic('eligible native control must activate') }
	assert ios_emit_callback(selected, ElementEvent{ kind: .tap })
	assert ios_control_test_handlers == ['a']
	assert ios_callback_test_events[0].id == 'same'
	if _ := ios_control_release_binding(first, second, false) {
		assert false, 'disabled/hidden native control must cancel'
	}
	if _ := ios_control_release_binding(first, IosCallbackBinding{}, true) {
		assert false, 'removed native control must cancel'
	}
	if _ := ios_control_release_binding(IosCallbackBinding{}, second, true) {
		assert false, 'callback installed after press cannot take over'
	}
}

fn test_ios_long_press_and_swipe_keep_the_initial_gesture_callback() {
	old_captures := g_gesture_captures.clone()
	old_owners := g_gesture_capture_owners.clone()
	defer {
		g_gesture_captures = old_captures.clone()
		g_gesture_capture_owners = old_owners.clone()
	}
	first := IosCallbackBinding{ id: 'same', on_event: capture_ios_control_a, kind: .view }
	current := IosCallbackBinding{ ...first, on_event: capture_ios_control_b }
	ios_control_test_handlers = []string{}
	ios_callback_test_events = []ElementEvent{}
	for index, kind in [ElementEventKind.long_press, .swipe_left] {
		gesture := u64(index + 101)
		assert ios_capture_gesture_callback(gesture, 100, first, 0, true)
		// A second touch and a callback replacement cannot redirect recognition.
		assert ios_capture_gesture_callback(gesture, 100, current, 1, true)
		captured := g_gesture_captures[gesture]
		selected := ios_control_release_binding(captured, current, true) or { panic('available gesture must recognize') }
		assert ios_emit_callback(selected, ElementEvent{ kind: kind })
		if _ := ios_control_release_binding(captured, current, false) {
			assert false, 'disabled/hidden gesture must cancel'
		}
		if _ := ios_control_release_binding(captured, IosCallbackBinding{}, true) {
			assert false, 'removed gesture must cancel'
		}
	}
	assert ios_control_test_handlers == ['a', 'a']
	assert ios_callback_test_events[0].kind == .long_press
	assert ios_callback_test_events[1].kind == .swipe_left
	assert ios_callback_test_events[0].id == 'same'
	clear_ios_gesture_captures(100)
	assert u64(101) !in g_gesture_captures
	assert u64(102) !in g_gesture_captures
}

fn test_ios_scroll_delegate_uses_current_element_callback_and_fractional_logical_offset() {
	old_callbacks := g_scroll_callbacks.clone()
	defer { g_scroll_callbacks = old_callbacks.clone() }
	native := View(usize(0x4567))
	g_scroll_callbacks[u64(native)] = IosCallbackBinding{ id: 'list', on_event: capture_ios_control_a, kind: .scroll, event: .scroll }
	ios_control_test_handlers = []string{}
	ios_callback_test_events = []ElementEvent{}
	assert ios_emit_scroll(native, 64.25)
	assert ios_callback_test_events[0].kind == .scroll
	assert ios_callback_test_events[0].id == 'list'
	assert ios_callback_test_events[0].value == 64.25
	g_scroll_callbacks[u64(native)] = IosCallbackBinding{ on_event: capture_ios_control_b, kind: .scroll, event: .scroll }
	assert ios_emit_scroll(native, 72.5)
	assert ios_control_test_handlers == ['a', 'b']
	assert ios_callback_test_events[1].id == ''
	g_scroll_callbacks.delete(u64(native))
	assert !ios_emit_scroll(native, 90)
}
