// The X11 RandR extension knows which mode each output runs. The query opens
// its own X connection and closes it, so a call may come before the window
// runs, when sokol's display is not up yet. Once the window runs, sokol has
// initialized Xlib for threads, so the extra connection is safe from any
// thread; before that, this is the process's only X connection.
module ui2

#flag -lXrandr
#include <X11/extensions/Xrandr.h>

fn C.XOpenDisplay(voidptr) voidptr

fn C.XCloseDisplay(voidptr) i32

fn C.DefaultRootWindow(voidptr) u64

fn C.XRRGetScreenInfo(voidptr, u64) voidptr

// XRRConfigCurrentRate returns a C `short`: RandR 1.0 rates are whole Hz.
fn C.XRRConfigCurrentRate(voidptr) i16

fn C.XRRFreeScreenConfigInfo(voidptr)

fn native_monitor_refresh_rate() f64 {
	dpy := C.XOpenDisplay(0)
	if dpy == unsafe { nil } {
		return 0
	}
	defer {
		C.XCloseDisplay(dpy)
	}
	root := C.DefaultRootWindow(dpy)
	config := C.XRRGetScreenInfo(dpy, root)
	if config == unsafe { nil } {
		return 0
	}
	rate := C.XRRConfigCurrentRate(config)
	C.XRRFreeScreenConfigInfo(config)
	hz := f64(rate)
	if hz < 20 || hz > 500 {
		return 0
	}
	return hz
}
