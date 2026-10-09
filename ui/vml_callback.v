module ui2

@[params]
pub struct VmlCallbackConfig {
pub:
	refresh bool = true
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
	} $else $if F is fn(ElementEvent) {
		return fn [callback, config] [F](event ElementEvent) {
			if callback == unsafe { nil } { return }
			callback(event)
			if config.refresh { request_refresh() }
		}
	} $else {
		$compile_error('VML callback requires fn() or fn(ui2.ElementEvent), returning void')
	}
}
