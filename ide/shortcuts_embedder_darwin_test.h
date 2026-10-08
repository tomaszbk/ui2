#ifndef UI2_IDE_SHORTCUT_FIXTURE_H
#define UI2_IDE_SHORTCUT_FIXTURE_H

#include <stdbool.h>
#include <stddef.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include "../ui/embedder_macos.h"

typedef struct { double x, y; } UI2IdeShortcutPoint;

/* Borrowed Objective-C values keep this fixture usable with the embedder's
 * ARC build. NSEvent injection verifies host routing, not physical OS input. */
static inline void *ui2_ide_shortcut_key_event(void *window, unsigned long type,
        unsigned short code, void *characters, unsigned long modifiers,
        double timestamp) {
    long number = ((long (*)(void *, SEL))objc_msgSend)(window,
        sel_registerName("windowNumber"));
    return ((void *(*)(void *, SEL, unsigned long, UI2IdeShortcutPoint,
        unsigned long, double, long, void *, void *, void *, bool,
        unsigned short))objc_msgSend)(
        (__bridge void *)objc_getClass("NSEvent"), sel_registerName(
        "keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:"),
        type, (UI2IdeShortcutPoint){0, 0}, modifiers, timestamp, number, NULL,
        characters, characters, false, code);
}

static inline void ui2_ide_shortcut_character(void *window, uint32_t character) {
    void *view = ((void *(*)(void *, SEL))objc_msgSend)(window,
        sel_registerName("contentView"));
    void *host = ((void *(*)(void *, SEL))objc_msgSend)(view,
        sel_registerName("host"));
    ((bool (*)(void *, SEL, ui2_embedder_event))objc_msgSend)(host,
        sel_registerName("sendEvent:"),
        (ui2_embedder_event){.kind=UI2_EMBEDDER_CHAR, .char_code=character});
}

#endif
