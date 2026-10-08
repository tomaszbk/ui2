#ifndef UI2_VISUAL_TRANSFORM_FIXTURE_DARWIN_H
#define UI2_VISUAL_TRANSFORM_FIXTURE_DARWIN_H
#import <Cocoa/Cocoa.h>
#include <math.h>

/* Exercise NSTextInputClient's real screen/window/view projection. The runtime
 * supplies window-logical affine caret bounds, never device-pixel coordinates. */
static bool ui2_transform_ime_matches(void *native_window, double x, double y,
                                     double width, double height, bool marked) {
    NSWindow *window = (__bridge NSWindow *)native_window;
    NSView<NSTextInputClient> *view = (id)window.contentView;
    if (!view || ![view respondsToSelector:@selector(firstRectForCharacterRange:actualRange:)])
        return false;
    NSRect screen = [view firstRectForCharacterRange:NSMakeRange(0, 0) actualRange:NULL];
    NSRect local = [view convertRect:[window convertRectFromScreen:screen] fromView:nil];
    return fabs(local.origin.x - x) < 1e-7 && fabs(local.origin.y - y) < 1e-7 &&
           fabs(local.size.width - width) < 1e-7 && fabs(local.size.height - height) < 1e-7 &&
           [view hasMarkedText] == marked;
}
#endif
