// vtest build: macos && !ui2_custom_rendering?
@[has_globals]
module ui2

$if !ui2_custom_rendering ? {
	import macos

	__global appkit_callback_test_events = []ElementEvent{}
	__global appkit_callback_test_handlers = []string{}

	fn capture_appkit_callback_a(event ElementEvent) {
		appkit_callback_test_handlers << 'a'
		appkit_callback_test_events << event
	}

	fn capture_appkit_callback_b(event ElementEvent) {
		appkit_callback_test_handlers << 'b'
		appkit_callback_test_events << event
	}

	fn test_appkit_callbacks_are_attached_to_elements_and_allow_anonymous_sources() {
		appkit_callback_test_events = []ElementEvent{}
		appkit_callback_test_handlers = []string{}
		first := AppkitCallbackBinding{ id: 'same', on_event: capture_appkit_callback_a }
		second := AppkitCallbackBinding{ id: 'same', on_event: capture_appkit_callback_b }
		assert appkit_emit_callback(first, ElementEvent{ kind: .tap })
		assert appkit_emit_callback(second, ElementEvent{ kind: .tap })
		assert appkit_emit_callback(AppkitCallbackBinding{ on_event: capture_appkit_callback_a }, ElementEvent{ kind: .link, target: 'https://example.test/café?q=a:b' })
		assert appkit_callback_test_handlers == ['a', 'b', 'a']
		assert appkit_callback_test_events[2].id == ''
		assert appkit_callback_test_events[2].target == 'https://example.test/café?q=a:b'
		assert !appkit_emit_callback(AppkitCallbackBinding{ id: 'same' }, ElementEvent{ kind: .tap })
	}

	fn test_appkit_text_callbacks_receive_change_and_submit_with_native_committed_text() {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		field := macos.msg_id(macos.alloc('NSTextField'), 'init')
		defer { macos.release(field) }
		macos.msg_void1(field, 'setStringValue:', macos.nsstring('café: ñ'))
		appkit_callback_test_events = []ElementEvent{}
		binding := AppkitCallbackBinding{ id: 'editor', on_event: capture_appkit_callback_a, kind: .text_field, event: .change }
		assert appkit_emit_callback(binding, appkit_control_event(field, binding))
		submit := AppkitCallbackBinding{ ...binding, event: .submit }
		assert appkit_emit_callback(submit, appkit_control_event(field, submit))
		assert appkit_callback_test_events.len == 2
		assert appkit_callback_test_events[0].kind == .change
		assert appkit_callback_test_events[1].kind == .submit
		assert appkit_callback_test_events[0].text == 'café: ñ'
		assert appkit_callback_test_events[1].text == 'café: ñ'
	}
	fn test_appkit_pointer_release_keeps_callback_capture_across_handler_replacement() {
		captured := AppkitCallbackBinding{ id: 'same', on_event: capture_appkit_callback_a }
		current := AppkitCallbackBinding{ id: 'same', on_event: capture_appkit_callback_b }
		selected := appkit_pointer_release_binding(captured, current) or { panic('registered surface must release') }
		appkit_callback_test_handlers = []string{}
		appkit_callback_test_events = []ElementEvent{}
		assert appkit_emit_callback(selected, ElementEvent{ kind: .tap })
		assert appkit_callback_test_handlers == ['a']
		assert appkit_callback_test_events[0].id == 'same'
		if _ := appkit_pointer_release_binding(captured, AppkitCallbackBinding{}) {
			assert false, 'unregistered surface must cancel capture'
		}
	}

	fn test_appkit_native_control_tracking_keeps_press_callback_and_cancels_ineligible_controls() {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		ensure_runtime_classes()
		control := macos.msg_id(macos.alloc('UI2TrackingNSButton'), 'init')
		defer { macos.release(control) }
		pointer := u64(control)
		mut st := state()
		old_callbacks := st.control_callbacks.clone()
		old_captures := st.control_captures.clone()
		defer {
			st.control_callbacks = old_callbacks
			st.control_captures = old_captures
		}
		first := AppkitCallbackBinding{ id: 'same', on_event: capture_appkit_callback_a, kind: .button, event: .tap }
		second := AppkitCallbackBinding{ ...first, on_event: capture_appkit_callback_b }
		st.control_callbacks[pointer] = first
		ui2_appkit_control_tracking_begin(control)
		st.control_callbacks[pointer] = second
		appkit_callback_test_handlers = []string{}
		appkit_callback_test_events = []ElementEvent{}
		ui2_button_tap(unsafe { nil }, unsafe { nil }, control)
		assert appkit_callback_test_handlers == ['a']
		assert appkit_callback_test_events[0].id == 'same'
		ui2_appkit_control_tracking_end(control)
		// Keyboard/accessibility activation after pointer tracking uses the current callback.
		ui2_button_tap(unsafe { nil }, unsafe { nil }, control)
		assert appkit_callback_test_handlers == ['a', 'b']
		ui2_appkit_control_tracking_begin(control)
		macos.msg_void_bool(control, 'setEnabled:', false)
		ui2_button_tap(unsafe { nil }, unsafe { nil }, control)
		assert appkit_callback_test_handlers == ['a', 'b']
		macos.msg_void_bool(control, 'setEnabled:', true)
		st.control_callbacks.delete(pointer)
		ui2_button_tap(unsafe { nil }, unsafe { nil }, control)
		assert appkit_callback_test_handlers == ['a', 'b']
		ui2_appkit_control_tracking_end(control)
		// A callback installed during a press with no callback cannot take it over.
		ui2_appkit_control_tracking_begin(control)
		st.control_callbacks[pointer] = second
		ui2_button_tap(unsafe { nil }, unsafe { nil }, control)
		assert appkit_callback_test_handlers == ['a', 'b']
		ui2_appkit_control_tracking_end(control)
	}

	fn test_appkit_native_slider_capture_reads_the_committed_value() {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		ensure_runtime_classes()
		control := macos.msg_id(macos.alloc('UI2TrackingNSSlider'), 'init')
		defer { macos.release(control) }
		macos.msg_void_f64(control, 'setMaxValue:', 100)
		macos.msg_void_f64(control, 'setDoubleValue:', 27.75)
		pointer := u64(control)
		mut st := state()
		old_callbacks := st.control_callbacks.clone()
		old_captures := st.control_captures.clone()
		defer {
			st.control_callbacks = old_callbacks
			st.control_captures = old_captures
		}
		first := AppkitCallbackBinding{ id: 'same', on_event: capture_appkit_callback_a, kind: .slider, event: .change }
		st.control_callbacks[pointer] = first
		ui2_appkit_control_tracking_begin(control)
		st.control_callbacks[pointer] = AppkitCallbackBinding{ ...first, on_event: capture_appkit_callback_b }
		appkit_callback_test_handlers = []string{}
		appkit_callback_test_events = []ElementEvent{}
		ui2_button_tap(unsafe { nil }, unsafe { nil }, control)
		ui2_appkit_control_tracking_end(control)
		assert appkit_callback_test_handlers == ['a']
		assert appkit_callback_test_events[0].kind == .change
		assert appkit_callback_test_events[0].value == 27.75
	}
	fn test_appkit_scroll_notification_uses_element_callback_and_fractional_logical_offset() {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		clip := macos.msg_id_rect(macos.alloc('NSClipView'), 'initWithFrame:', macos.rect(0, 0, 80, 40))
		document := macos.msg_id_rect(macos.alloc('NSView'), 'initWithFrame:', macos.rect(0, 0, 80, 300))
		defer {
			macos.release(clip)
			macos.release(document)
		}
		macos.msg_void1(clip, 'setDocumentView:', document)
		macos.msg_void_rect(clip, 'setBounds:', macos.rect(0, 64.25, 80, 40))
		assert native_bounds(clip).y == 64.25
		mut st := state()
		old_callbacks := st.scroll_callbacks.clone()
		defer { st.scroll_callbacks = old_callbacks }
		st.scroll_callbacks[u64(clip)] = AppkitCallbackBinding{ id: 'list', on_event: capture_appkit_callback_a, kind: .scroll, event: .scroll }
		notification := macos.msg_id2(macos.get_class('NSNotification'), 'notificationWithName:object:', macos.nsstring('UI2ScrollTest'), clip)
		appkit_callback_test_handlers = []string{}
		appkit_callback_test_events = []ElementEvent{}
		ui2_bounds_changed(unsafe { nil }, unsafe { nil }, notification)
		assert appkit_callback_test_events.len == 1
		assert appkit_callback_test_events[0].kind == .scroll
		assert appkit_callback_test_events[0].id == 'list'
		assert appkit_callback_test_events[0].value == 64.25
		// Callback registration works for anonymous scroll containers too.
		st.scroll_callbacks[u64(clip)] = AppkitCallbackBinding{ on_event: capture_appkit_callback_b, kind: .scroll, event: .scroll }
		ui2_bounds_changed(unsafe { nil }, unsafe { nil }, notification)
		assert appkit_callback_test_handlers == ['a', 'b']
		assert appkit_callback_test_events[1].id == ''
		st.scroll_callbacks.delete(u64(clip))
		ui2_bounds_changed(unsafe { nil }, unsafe { nil }, notification)
		assert appkit_callback_test_events.len == 2
	}
}
