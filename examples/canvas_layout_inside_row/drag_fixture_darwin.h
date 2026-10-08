#ifndef UI2_INSIDE_ROW_DRAG_FIXTURE_DARWIN_H
#define UI2_INSIDE_ROW_DRAG_FIXTURE_DARWIN_H
#import <Cocoa/Cocoa.h>
#include "../../ui/embedder_macos.h"
#include <unistd.h>

/* Use the real host pump and NSView pointer bridge without entering the
 * application event loop. The protocol describes existing host accessors. */
@protocol UI2InsideRowFixtureHost
- (ui2_embedder_callbacks)callbacks;
- (void *)userData;
@end

static bool ui2_inside_row_present(void *native_window) {
    NSWindow *window = (__bridge NSWindow *)native_window;
    id<UI2InsideRowFixtureHost> host = (id)window.delegate;
    if (!host) return false;
    ui2_embedder_callbacks callbacks = [host callbacks];
    if (!callbacks.pump) return false;
    for (int i = 0; i < 120; ++i) {
        int64_t delay = callbacks.pump([host userData]);
        if (delay < 0) return true;
        usleep((useconds_t)(MAX(1, MIN(delay, 20)) * 1000));
    }
    return false;
}

static void ui2_inside_row_pointer(void *native_window, int kind, double x, double y) {
    NSWindow *window = (__bridge NSWindow *)native_window;
    NSView *view = window.contentView;
    NSPoint location = [view convertPoint:NSMakePoint(x, y) toView:nil];
    NSEventType type = kind == 0 ? NSEventTypeLeftMouseDown :
                       kind == 1 ? NSEventTypeLeftMouseDragged : NSEventTypeLeftMouseUp;
    NSEvent *event = [NSEvent mouseEventWithType:type location:location modifierFlags:0
                                      timestamp:NSProcessInfo.processInfo.systemUptime
                                   windowNumber:window.windowNumber context:nil
                                    eventNumber:0 clickCount:1 pressure:1];
    if (kind == 0) [view mouseDown:event];
    else if (kind == 1) [view mouseDragged:event];
    else [view mouseUp:event];
}

static void ui2_inside_row_resize(void *native_window, int width, int height) {
    NSWindow *window = (__bridge NSWindow *)native_window;
    [window setContentSize:NSMakeSize(width, height)];
}
#endif
