#include <objc/message.h>
#include <objc/runtime.h>
#include <dlfcn.h>
#include <CoreFoundation/CoreFoundation.h>

// A message that takes a rectangle and answers one, which vlib's macos bridge has no
// entry for: -[NSCell titleRectForBounds:] is how a control says where its title is
// drawn once its image, bezel and arrows have had their share of the frame.
typedef struct ui2_macos_rect {
	double x;
	double y;
	double width;
	double height;
} ui2_macos_rect;

static inline ui2_macos_rect ui2_macos_msg_rect_rect(void* obj, void* sel, ui2_macos_rect rect) {
#if defined(__x86_64__)
	// Intel returns a structure this large through memory, which plain objc_msgSend
	// does not do.
	ui2_macos_rect result;
	((void (*)(ui2_macos_rect*, void*, void*, ui2_macos_rect))objc_msgSend_stret)(&result, obj, sel, rect);
	return result;
#else
	return ((ui2_macos_rect (*)(void*, void*, ui2_macos_rect))objc_msgSend)(obj, sel, rect);
#endif
}

// NSControl owns its native tracking loop. Wrap that loop without changing its
// focus, keyboard or text-editing behavior; target actions use the press snapshot.
extern void ui2_appkit_control_tracking_begin(void *control);
extern void ui2_appkit_control_tracking_end(void *control);
static inline void ui2_macos_control_mouse_down(void *control, void *event) {
    ui2_appkit_control_tracking_begin(control);
    struct objc_super parent = { (id)control, class_getSuperclass(object_getClass((id)control)) };
    ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent,
        sel_registerName("mouseDown:"), (id)event);
    ui2_appkit_control_tracking_end(control);
}

// Focus navigation runs once at the window's event boundary, before AppKit's
// field editor/control handling. Unhandled events keep the native IME path.
static inline void ui2_macos_window_send_event(void *window, void *event) {
    // AppKit can dynamically subclass a window. Start above our implementation,
    // rather than above that dynamic subclass (which would re-enter our override).
    struct objc_super parent = { (id)window, class_getSuperclass(objc_getClass("UI2Window")) };
    ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent,
        sel_registerName("sendEvent:"), (id)event);
}

static inline void ui2_macos_window_lifecycle(void *window, void *selector) {
    struct objc_super parent = { (id)window, class_getSuperclass(objc_getClass("UI2Window")) };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&parent, (SEL)selector);
}

// A class built at runtime has no `super` to send to, so reaching the method it
// overrides means naming the class the lookup should start from. objc_super is a
// receiver followed by that class; plain pointers keep this free of ownership casts.
static inline void ui2_macos_msg_super_void_id(void* obj, void* superclass, void* sel, void* arg) {
	struct {
		void* receiver;
		void* super_class;
	} target = { obj, superclass };
	((void (*)(void*, void*, void*))objc_msgSendSuper)(&target, sel, arg);
}

// -[NSView hitTest:] takes a point and answers an object, which the bridge has no
// entry for either. A point is two doubles on both architectures.
static inline void* ui2_macos_msg_id_point(void* obj, void* sel, double x, double y) {
	struct { double x; double y; } point = { x, y };
	return ((void* (*)(void*, void*, __typeof__(point)))objc_msgSend)(obj, sel, point);
}

// Gives `view` a tracking area that follows its visible rectangle and reports the
// pointer entering, moving over and leaving it while the app is active. The
// initializer takes a rectangle, an option set and two objects: a shape the bridge
// has no entry for.
static inline void ui2_macos_add_tracking_area(void* view) {
	const unsigned long entered_and_exited = 0x01, moved = 0x02, active_in_app = 0x40,
		in_visible_rect = 0x200;
	void* area = ((void* (*)(void*, void*))objc_msgSend)((void*)objc_getClass("NSTrackingArea"),
		sel_registerName("alloc"));
	ui2_macos_rect zero = { 0, 0, 0, 0 };
	area = ((void* (*)(void*, void*, ui2_macos_rect, unsigned long, void*, void*))objc_msgSend)(area,
		sel_registerName("initWithRect:options:owner:userInfo:"), zero,
		entered_and_exited | moved | active_in_app | in_visible_rect, view, (void*)0);
	if (area == (void*)0) return;
	((void (*)(void*, void*, void*))objc_msgSend)(view, sel_registerName("addTrackingArea:"), area);
	((void (*)(void*, void*))objc_msgSend)(area, sel_registerName("release"));
}

// CALayer's shadowOpacity is a float, which the bridge's double setters would
// pass in the wrong register width.
static inline void ui2_macos_msg_void_float(void* obj, void* sel, float value) {
	((void (*)(void*, void*, float))objc_msgSend)(obj, sel, value);
}

// CoreGraphics' path functions are looked up at run time: tcc cannot read the
// CoreGraphics headers, and declaring the functions here would clash with those
// headers wherever an application includes them. CGRect is four CGFloats, laid
// out like ui2_macos_rect.
typedef void* (*ui2_macos_rounded_path_fn)(ui2_macos_rect rect, double corner_width,
	double corner_height, const void* transform);
typedef void (*ui2_macos_release_path_fn)(void* path);

// Gives a layer the rounded-rectangle shadow path of a box, so CoreAnimation draws
// the shadow from that shape instead of from the layer's rendered content, which a
// transparent box does not have. CGPathCreateWithRoundedRect rejects corners
// larger than half a side, so the radius is clamped.
static inline void ui2_macos_set_shadow_path(void* layer, double x, double y, double width,
		double height, double radius) {
	void* set = sel_registerName("setShadowPath:");
	if (width <= 0 || height <= 0) {
		((void (*)(void*, void*, void*))objc_msgSend)(layer, set, (void*)0);
		return;
	}
	double limit = (width < height ? width : height) / 2;
	double r = radius < 0 ? 0 : (radius > limit ? limit : radius);
	static ui2_macos_rounded_path_fn create = (void*)0;
	static ui2_macos_release_path_fn release = (void*)0;
	if (create == (void*)0) {
		create = (ui2_macos_rounded_path_fn)dlsym(RTLD_DEFAULT, "CGPathCreateWithRoundedRect");
		release = (ui2_macos_release_path_fn)dlsym(RTLD_DEFAULT, "CGPathRelease");
	}
	if (create == (void*)0 || release == (void*)0) return;
	ui2_macos_rect rect = { x, y, width, height };
	void* path = create(rect, r, r, (void*)0);
	((void (*)(void*, void*, void*))objc_msgSend)(layer, set, path);
	release(path);
}

// The window server's picture of a view: what the window shows over the view's
// bounds, in pixels. Controls such as NSButton are drawn by hosted layers that
// -cacheDisplayInRect: leaves out, so a screenshot asks the window server. A
// process may read its own windows without screen recording permission. The
// function is looked up at run time because newer SDKs mark it unavailable.
// Returns a CGImageRef the caller releases with CFRelease, or NULL.
typedef void *(*ui2_macos_window_list_image_fn)(ui2_macos_rect, uint32_t, uint32_t, uint32_t);
static inline void *ui2_macos_view_window_image(void *view) {
	ui2_macos_window_list_image_fn create = (ui2_macos_window_list_image_fn)dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");
	if (create == NULL || view == NULL) return NULL;
	id window = ((id (*)(id, SEL))objc_msgSend)((id)view, sel_registerName("window"));
	if (window == nil) return NULL;
	ui2_macos_rect bounds = ((ui2_macos_rect (*)(id, SEL))objc_msgSend)((id)view, sel_registerName("bounds"));
	ui2_macos_rect in_window = ((ui2_macos_rect (*)(id, SEL, ui2_macos_rect, id))objc_msgSend)((id)view, sel_registerName("convertRect:toView:"), bounds, nil);
	ui2_macos_rect on_screen = ((ui2_macos_rect (*)(id, SEL, ui2_macos_rect))objc_msgSend)(window, sel_registerName("convertRectToScreen:"), in_window);
	id screens = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSScreen"), sel_registerName("screens"));
	if (((unsigned long (*)(id, SEL))objc_msgSend)(screens, sel_registerName("count")) == 0) return NULL;
	id primary = ((id (*)(id, SEL, unsigned long))objc_msgSend)(screens, sel_registerName("objectAtIndex:"), 0);
	ui2_macos_rect primary_frame = ((ui2_macos_rect (*)(id, SEL))objc_msgSend)(primary, sel_registerName("frame"));
	ui2_macos_rect global = { on_screen.x, primary_frame.height - on_screen.y - on_screen.height, on_screen.width, on_screen.height };
	uint32_t number = (uint32_t)((long (*)(id, SEL))objc_msgSend)(window, sel_registerName("windowNumber"));
	// kCGWindowListOptionIncludingWindow; kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution.
	return create(global, 8, number, 1 | 8);
}

// -[NSObject performSelector:withObject:afterDelay:], which takes a double the
// bridge has no message shape for.
static inline void ui2_macos_perform_after_delay(void *obj, void *sel, void *arg, double delay) {
	((void (*)(id, SEL, SEL, id, double))objc_msgSend)((id)obj,
		sel_registerName("performSelector:withObject:afterDelay:"), (SEL)sel, (id)arg, delay);
}

// Ends -[NSApp run] once the current event is handled. -stop: only takes
// effect after the run loop dispatches another event, so an empty
// application-defined event follows it.
static inline void ui2_macos_stop_app(void) {
	typedef struct { double x; double y; } ui2_macos_point;
	id app = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
	((void (*)(id, SEL, id))objc_msgSend)(app, sel_registerName("stop:"), nil);
	ui2_macos_point origin = {0, 0};
	// NSEventTypeApplicationDefined.
	id event = ((id (*)(id, SEL, unsigned long, ui2_macos_point, unsigned long, double, long, id, short, long, long))objc_msgSend)(
		(id)objc_getClass("NSEvent"),
		sel_registerName("otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:"),
		15, origin, 0, 0, 0, nil, 0, 0, 0);
	((void (*)(id, SEL, id, BOOL))objc_msgSend)(app, sel_registerName("postEvent:atStart:"), event, YES);
}

// +[NSFont systemFontOfSize:weight:], which takes two CGFloats.
static inline void *ui2_macos_system_font(double size, double weight) {
	return ((id (*)(id, SEL, double, double))objc_msgSend)((id)objc_getClass("NSFont"),
		sel_registerName("systemFontOfSize:weight:"), size, weight);
}
