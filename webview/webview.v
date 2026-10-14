// Standalone native browser windows. They share their host application's run loop.
module webview

pub struct Config {
pub:
	url        string
	title      string
	js_on_init string
	width      int = 1000
	height     int = 800
	// Use false for an isolated login session with no saved cookies or storage.
	persistent bool = true
}

@[heap]
pub struct WebView {
	native voidptr
pub:
	// Native WKWebView on macOS, for callers that need additional WebKit APIs.
	obj voidptr
}

// supported reports whether this platform has a native webview implementation.
pub fn supported() bool {
	$if macos {
		return true
	}
	return false
}

// new_window creates a window on the AppKit main thread. It does not start a
// second application or event loop. Callers from a worker need a running host UI.
pub fn new_window(cfg Config) &WebView {
	$if macos {
		return new_native_window(cfg)
	} $else {
		panic('ui2.webview is currently available only on macOS')
	}
}

pub fn (view &WebView) load(url string) {
	$if macos {
		C.ui2_webview_load(view.native, url.str)
	}
}

// eval_js evaluates JavaScript asynchronously. js_value reads the last result,
// or the last string posted to window.webkit.messageHandlers.vui.
pub fn (view &WebView) eval_js(script string) {
	$if macos {
		C.ui2_webview_eval(view.native, script.str)
	}
}

pub fn (view &WebView) js_value() string {
	$if macos {
		return take_native_string(C.ui2_webview_js_value(view.native))
	}
	return ''
}

// cookie uses the WebKit cookie store, including HttpOnly cookies. Workers wait
// up to three seconds; the main thread returns a cached value and starts a fresh
// asynchronous read. A domain must match exactly (a leading dot is optional).
pub fn (view &WebView) cookie(name string, domain string) string {
	$if macos {
		return take_native_string(C.ui2_webview_cookie(view.native, name.str, domain.str))
	}
	return ''
}

// delete_all_cookies asynchronously clears this browser's website data.
pub fn (view &WebView) delete_all_cookies() {
	$if macos {
		C.ui2_webview_clear_data(view.native)
	}
}

pub fn (view &WebView) is_open() bool {
	$if macos {
		return C.ui2_webview_is_open(view.native) != 0
	}
	return false
}

pub fn (view &WebView) close() {
	$if macos {
		C.ui2_webview_close(view.native)
	}
}
