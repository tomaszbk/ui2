#include <objc/message.h>
#include <objc/runtime.h>
#include <CoreGraphics/CGGeometry.h>
#include <stdio.h>
#include <string.h>

#if __has_feature(objc_arc)
#define UI2_TRACKING_OBJECT(pointer) ((__bridge id)(pointer))
#define UI2_TRACKING_POINTER(object) ((__bridge void *)(object))
#else
#define UI2_TRACKING_OBJECT(pointer) ((id)(pointer))
#define UI2_TRACKING_POINTER(object) ((void *)(object))
#endif

// Keep CGRect and BOOL in the UIKit message signature; neither a pointer-sized
// argument nor AppKit's one-argument selector has the UIScrollView ABI.
static inline void ui2_ios_scroll_rect_visible(void *pointer, double x, double y,
        double width, double height, BOOL animated) {
    ((void (*)(id, SEL, CGRect, BOOL))objc_msgSend)(UI2_TRACKING_OBJECT(pointer),
        sel_registerName("scrollRectToVisible:animated:"),
        CGRectMake(x, y, width, height), animated);
}

extern void vui_control_tracking_begin(void *control);
extern void vui_control_tracking_end(void *control);
extern void vui_control_tracking_cancel(void *control);

// touchesEnded: wraps the full event delivery, including touchUpInside actions
// that UIControl can send after endTrackingWithTouch: returns.
// Subclass the actual UIKit control class so UIButton/UISwitch private behavior
// stays intact. UIKit retains ownership of native tracking and action delivery.
static BOOL ui2_ios_begin_tracking(id control, SEL selector, id touch, id event) {
    vui_control_tracking_begin(UI2_TRACKING_POINTER(control));
    struct objc_super parent = {control, class_getSuperclass(object_getClass(control))};
    BOOL accepted = ((BOOL (*)(struct objc_super *, SEL, id, id))objc_msgSendSuper)(
        &parent, selector, touch, event);
    if (!accepted) vui_control_tracking_cancel(UI2_TRACKING_POINTER(control));
    return accepted;
}
static void ui2_ios_touches_ended(id control, SEL selector, id touch, id event) {
    struct objc_super parent = {control, class_getSuperclass(object_getClass(control))};
    ((void (*)(struct objc_super *, SEL, id, id))objc_msgSendSuper)(&parent, selector, touch, event);
    vui_control_tracking_end(UI2_TRACKING_POINTER(control));
}
static void ui2_ios_cancel_tracking(id control, SEL selector, id event) {
    vui_control_tracking_cancel(UI2_TRACKING_POINTER(control));
    struct objc_super parent = {control, class_getSuperclass(object_getClass(control))};
    ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, selector, event);
}
static inline void ui2_ios_install_control_tracking(void *pointer) {
    if (pointer == NULL) return;
    id control = UI2_TRACKING_OBJECT(pointer);
    Class original = object_getClass(control);
    const char *name = class_getName(original);
    if (strncmp(name, "UI2Tracking_", 12) == 0) return;
    char tracking_name[256];
    if (snprintf(tracking_name, sizeof(tracking_name), "UI2Tracking_%s", name)
            >= (int)sizeof(tracking_name)) return;
    Class tracking = objc_getClass(tracking_name);
    if (tracking == Nil) {
        tracking = objc_allocateClassPair(original, tracking_name, 0);
        class_addMethod(tracking, sel_registerName("beginTrackingWithTouch:withEvent:"),
            (IMP)ui2_ios_begin_tracking, "B@:@@");
        class_addMethod(tracking, sel_registerName("touchesEnded:withEvent:"),
            (IMP)ui2_ios_touches_ended, "v@:@@");
        class_addMethod(tracking, sel_registerName("cancelTrackingWithEvent:"),
            (IMP)ui2_ios_cancel_tracking, "v@:@");
        objc_registerClassPair(tracking);
    }
    object_setClass(control, tracking);
}
