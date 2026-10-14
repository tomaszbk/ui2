// Offline test support, compiled only by webview_darwin_test.v.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include "webview_darwin.h"

static void ui2_webview_test_pump(int milliseconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:(double)milliseconds / 1000.0];
    while ([deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:deadline];
        NSEvent *event;
        while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantPast]
            inMode:NSDefaultRunLoopMode dequeue:YES])) {
            [NSApp sendEvent:event];
        }
    }
}

static void ui2_webview_test_cookie(void *handle, const char *name, const char *domain, const char *value) {
    WKWebView *view = (WKWebView *)ui2_webview_object(handle);
    NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:@{
        NSHTTPCookieName: [NSString stringWithUTF8String:name],
        NSHTTPCookieDomain: [NSString stringWithUTF8String:domain],
        NSHTTPCookieValue: [NSString stringWithUTF8String:value],
        NSHTTPCookiePath: @"/",
        @"HttpOnly": @"TRUE"
    }];
    [view.configuration.websiteDataStore.httpCookieStore setCookie:cookie completionHandler:^{}];
}

static void ui2_webview_test_user_close(void *handle) {
    [[(WKWebView *)ui2_webview_object(handle) window] performClose:nil];
}

static int ui2_webview_test_width(void *handle) {
    return (int)((WKWebView *)ui2_webview_object(handle)).frame.size.width;
}

static void *ui2_webview_test_delegate(void) {
    return [NSApplication sharedApplication].delegate;
}

static void *ui2_webview_test_new_delegate(void) {
    return [[NSObject alloc] init];
}

static void ui2_webview_test_set_delegate(void *delegate) {
    [NSApplication sharedApplication].delegate = (id)delegate;
}

static void ui2_webview_test_release_delegate(void *delegate) {
    [(id)delegate release];
}

static int ui2_webview_test_late_native_read(void *object) {
    // This reproduces a worker handing the public obj to an asynchronous native
    // helper after the main thread has already closed the browser.
    WKWebView *view = (WKWebView *)object;
    __block int detached = 0;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_retain(finished);
    dispatch_async(dispatch_get_main_queue(), ^{
        detached = view.window == nil && view.configuration != nil;
        dispatch_semaphore_signal(finished);
        dispatch_release(finished);
    });
    long timedOut = dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    dispatch_release(finished);
    return timedOut ? -1 : detached;
}
