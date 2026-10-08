#include <objc/message.h>
#include <objc/runtime.h>

// Real NSEvents delivered through NSWindow sendEvent:, including its shared
// field editor. Injection covers library/native routing, not physical OS input.
typedef struct ui2_focus_test_point { double x, y; } ui2_focus_test_point;
static inline void *ui2_focus_test_key_event(void *window, unsigned long type,
        unsigned short code, void *characters, unsigned long modifiers,
        double timestamp, BOOL repeated) {
    long number = ((long (*)(id, SEL))objc_msgSend)((id)window,
        sel_registerName("windowNumber"));
    return ((id (*)(id, SEL, unsigned long, ui2_focus_test_point, unsigned long,
        double, long, id, id, id, BOOL, unsigned short))objc_msgSend)(
        (id)objc_getClass("NSEvent"), sel_registerName(
        "keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:"),
        type, (ui2_focus_test_point){0, 0}, modifiers, timestamp, number, nil,
        (id)characters, (id)characters, repeated, code);
}
