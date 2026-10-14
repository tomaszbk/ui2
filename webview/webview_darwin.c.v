module webview

#flag darwin -framework Cocoa
#flag darwin -framework WebKit
#flag darwin -fno-objc-arc
#include "@VMODROOT/webview/webview_darwin.h"
#include "@VMODROOT/webview/webview_darwin.m"

fn C.ui2_webview_new(&char, &char, &char, int, int, int) voidptr
fn C.ui2_webview_object(voidptr) voidptr
fn C.ui2_webview_load(voidptr, &char)
fn C.ui2_webview_eval(voidptr, &char)
fn C.ui2_webview_js_value(voidptr) &char
fn C.ui2_webview_cookie(voidptr, &char, &char) &char
fn C.ui2_webview_clear_data(voidptr)
fn C.ui2_webview_close(voidptr)
fn C.ui2_webview_is_open(voidptr) int

fn new_native_window(cfg Config) &WebView {
	native := C.ui2_webview_new(cfg.url.str, cfg.title.str, cfg.js_on_init.str, if cfg.width > 0 {
		cfg.width
	} else {
		1000
	}, if cfg.height > 0 { cfg.height } else { 800 }, if cfg.persistent { 1 } else { 0 })
	return &WebView{
		obj:    C.ui2_webview_object(native)
		native: native
	}
}

fn take_native_string(value &char) string {
	if value == unsafe { nil } {
		return ''
	}
	result := unsafe { value.vstring().clone() }
	unsafe { C.free(value) }
	return result
}
