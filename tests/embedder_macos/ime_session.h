#ifndef UI2_TEST_IME_SESSION_H
#define UI2_TEST_IME_SESSION_H

#import <AppKit/AppKit.h>
#include <stdio.h>

/* Optional interactive acceptance helper. It selects an already available IME
 * in the fixture view's input context and restores the previous source on end.
 * It never enables/adds a source or edits system preferences. */
@interface UI2TestImeSession : NSObject
@property(nonatomic, strong) NSTextInputContext* context;
@property(nonatomic, strong) NSWindow* window;
@property(nonatomic, copy) NSString* previous;
@end
@implementation UI2TestImeSession
@end

static void* ui2_test_ime_begin(void* native_window) {
    if (!native_window || !NSThread.isMainThread) return NULL;
    NSWindow* window = (__bridge NSWindow*)native_window;
    NSTextInputContext* context = window.contentView.inputContext;
    NSString* japanese = @"com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese";
    if (![context.keyboardInputSources containsObject:japanese]) return NULL;
    UI2TestImeSession* session = [UI2TestImeSession new];
    session.context = context;
    session.window = window;
    session.previous = context.selectedKeyboardInputSource;
    if (!session.previous) return NULL;
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:window.contentView];
    [NSApp activateIgnoringOtherApps:YES];
    [context activate];
    context.selectedKeyboardInputSource = japanese;
    if (![context.selectedKeyboardInputSource isEqualToString:japanese]) {
        context.selectedKeyboardInputSource = session.previous;
        return NULL;
    }
    return (__bridge_retained void*)session;
}

static bool ui2_test_ime_selected(void* session_handle) {
    if (!session_handle) return false;
    UI2TestImeSession* session = (__bridge UI2TestImeSession*)session_handle;
    return [session.context.selectedKeyboardInputSource isEqualToString:
        @"com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"];
}

static void ui2_test_ime_end(void* session_handle) {
    if (!session_handle || !NSThread.isMainThread) return;
    UI2TestImeSession* session = (__bridge_transfer UI2TestImeSession*)session_handle;
    id<NSTextInputClient> client = (id<NSTextInputClient>)session.window.contentView;
    NSAttributedString* displayed = [client attributedSubstringForProposedRange:
        NSMakeRange(0, NSUIntegerMax) actualRange:NULL];
    printf("Japanese session final display='%s', preedit=%d\n",
        displayed.string.UTF8String ?: "", [client hasMarkedText]);
    [session.context discardMarkedText];
    [session.context activate];
    session.context.selectedKeyboardInputSource = session.previous;
    printf("Restored keyboard source: %s\n", session.context.selectedKeyboardInputSource.UTF8String);
}

#endif
