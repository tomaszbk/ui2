#ifndef UI2_EMBEDDER_FIXTURE_NATIVE_DARWIN_H
#define UI2_EMBEDDER_FIXTURE_NATIVE_DARWIN_H

#include <dispatch/dispatch.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct { double x, y; } UI2FixturePoint;
typedef struct { double width, height; } UI2FixtureSize;
typedef struct { UI2FixturePoint origin; UI2FixtureSize size; } UI2FixtureRect;
typedef struct { unsigned long location, length; } UI2FixtureRange;

static void *ui2_fixture_class(const char *name) {
#if defined(__OBJC__)
    return (__bridge void *)objc_getClass(name);
#else
    return (void *)objc_getClass(name);
#endif
}

static void *ui2_fixture_view(void *window) {
    if (!window || !pthread_main_np()) return NULL;
    return ((void *(*)(void *, SEL))objc_msgSend)(window, sel_registerName("contentView"));
}

/* The host handle is an immutable tombstone. Reading its native atomic pump
 * counter from the worker measures host callbacks, including calls which find
 * no scheduler work. Cocoa selectors are only used on the main thread here. */
static void *ui2_fixture_host_handle(void *window) {
    void *view = ui2_fixture_view(window);
    if (!view) return NULL;
    void *host = ((void *(*)(void *, SEL))objc_msgSend)(view, sel_registerName("host"));
    return host ? ((void *(*)(void *, SEL))objc_msgSend)(host, sel_registerName("handle")) : NULL;
}

static bool ui2_fixture_place(void *window, double x, double y) {
    if (!ui2_fixture_view(window)) return false;
    ((void (*)(void *, SEL, UI2FixturePoint))objc_msgSend)(
        window, sel_registerName("setFrameOrigin:"), (UI2FixturePoint){x, y});
    return true;
}

static void ui2_fixture_restore(void *window) {
    ((void (*)(void *, SEL, void *))objc_msgSend)(
        window, sel_registerName("deminiaturize:"), NULL);
    ((void (*)(void *, SEL, void *))objc_msgSend)(
        window, sel_registerName("orderFront:"), NULL);
    ((void (*)(void *, SEL))objc_msgSend)(window, sel_registerName("release"));
}

static bool ui2_fixture_minimize_restore(void *window, int64_t delay_ms) {
    if (!ui2_fixture_view(window) || delay_ms <= 0) return false;
    ((void *(*)(void *, SEL))objc_msgSend)(window, sel_registerName("retain"));
    ((void (*)(void *, SEL, void *))objc_msgSend)(
        window, sel_registerName("miniaturize:"), NULL);
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, delay_ms * NSEC_PER_MSEC),
        dispatch_get_main_queue(), window, ui2_fixture_restore);
    return true;
}

static void *ui2_fixture_string(const char *value) {
    return ((void *(*)(void *, SEL, const char *))objc_msgSend)(
        ui2_fixture_class("NSString"), sel_registerName("stringWithUTF8String:"), value);
}

/* Inject through NSTextInputClient, rather than calling the V callback. This
 * checks UTF-16 protocol ranges and native composition snapshots end to end;
 * the interactive mode is used to check an actual configured input method. */
static bool ui2_fixture_preedit(void *window, const char *value) {
    void *view = ui2_fixture_view(window);
    if (!view) return false;
    ((void (*)(void *, SEL, void *, UI2FixtureRange, UI2FixtureRange))objc_msgSend)(view,
        sel_registerName("setMarkedText:selectedRange:replacementRange:"),
        ui2_fixture_string(value), (UI2FixtureRange){3, 0}, (UI2FixtureRange){1, 2});
    return true;
}

static bool ui2_fixture_has_preedit(void *window) {
    void *view = ui2_fixture_view(window);
    return view && ((bool (*)(void *, SEL))objc_msgSend)(view, sel_registerName("hasMarkedText"));
}

static bool ui2_fixture_commit(void *window, const char *value) {
    void *view = ui2_fixture_view(window);
    if (!view) return false;
    ((void (*)(void *, SEL, void *, UI2FixtureRange))objc_msgSend)(view,
        sel_registerName("insertText:replacementRange:"), ui2_fixture_string(value),
        (UI2FixtureRange){~0UL, 0});
    return true;
}

static UI2FixtureRect ui2_fixture_window_frame(void *window) {
    UI2FixtureRect result;
#if defined(__x86_64__)
    ((void (*)(UI2FixtureRect *, void *, SEL))objc_msgSend_stret)(
        &result, window, sel_registerName("frame"));
#else
    result = ((UI2FixtureRect (*)(void *, SEL))objc_msgSend)(window, sel_registerName("frame"));
#endif
    return result;
}

static bool ui2_fixture_candidate_inside_window(void *window) {
    void *view = ui2_fixture_view(window);
    if (!view) return false;
    UI2FixtureRect candidate;
    UI2FixtureRange range = {1, 0};
#if defined(__x86_64__)
    ((void (*)(UI2FixtureRect *, void *, SEL, UI2FixtureRange, void *))objc_msgSend_stret)(
        &candidate, view, sel_registerName("firstRectForCharacterRange:actualRange:"), range, NULL);
#else
    candidate = ((UI2FixtureRect (*)(void *, SEL, UI2FixtureRange, void *))objc_msgSend)(
        view, sel_registerName("firstRectForCharacterRange:actualRange:"), range, NULL);
#endif
    UI2FixtureRect frame = ui2_fixture_window_frame(window);
    return candidate.size.width > 0 && candidate.size.height > 0
        && candidate.origin.x >= frame.origin.x
        && candidate.origin.x <= frame.origin.x + frame.size.width
        && candidate.origin.y >= frame.origin.y
        && candidate.origin.y <= frame.origin.y + frame.size.height;
}

static bool ui2_fixture_move_pointer(void *window, double x, double y) {
    void *view = ui2_fixture_view(window);
    if (!view) return false;
    UI2FixturePoint position = ((UI2FixturePoint (*)(void *, SEL, UI2FixturePoint, void *))objc_msgSend)(
        view, sel_registerName("convertPoint:toView:"), (UI2FixturePoint){x, y}, NULL);
    long number = ((long (*)(void *, SEL))objc_msgSend)(window, sel_registerName("windowNumber"));
    void *event = ((void *(*)(void *, SEL, unsigned long, UI2FixturePoint, unsigned long,
        double, long, void *, long, long, float))objc_msgSend)(ui2_fixture_class("NSEvent"),
        sel_registerName("mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:"),
        5, position, 0, 0, number, NULL, 0, 0, 0);
    if (!event) return false;
    ((void (*)(void *, SEL, void *))objc_msgSend)(view, sel_registerName("mouseMoved:"), event);
    return true;
}

#endif
