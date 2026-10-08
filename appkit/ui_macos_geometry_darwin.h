#include <objc/message.h>
#include <objc/runtime.h>

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
