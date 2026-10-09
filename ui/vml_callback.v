module ui2

@[params]
pub struct VmlCallbackConfig {
pub:
	refresh bool = true
}

// Numeric controls emit f64; a typed writable numeric source defines the
// destination representation. Strings and booleans require their own payloads.
pub fn vml_binding_number[T](current T, value f64) T {
	_ = current
	$if T is $int || T is $float {
		return T(value)
	} $else {
		$compile_error('VML numeric binding requires a numeric writable source')
	}
}

// VML callbacks either ignore a control's event or receive its exact typed
// ElementEvent. Function return values and mismatched payloads are errors.
pub fn vml_callback[F](callback F, config VmlCallbackConfig) ElementCallback {
	$if F is fn() {
		return fn [callback, config] [F](event ElementEvent) {
			if callback == unsafe { nil } { return }
			callback()
			if config.refresh { request_refresh() }
		}
	} $else $if F is fn(ElementEvent) || F is ElementCallback {
		return fn [callback, config] [F](event ElementEvent) {
			if callback == unsafe { nil } { return }
			callback(event)
			if config.refresh { request_refresh() }
		}
	} $else {
		$compile_error('VML callback requires fn() or fn(ui2.ElementEvent), returning void')
	}
}
