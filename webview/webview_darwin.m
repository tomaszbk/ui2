#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <dispatch/dispatch.h>
#include <stdlib.h>
#include <string.h>

// Sessions deliberately outlive their windows: a polling worker may still hold
// the V WebView after the user closes its window. The detached WKWebView remains
// owned as long as the handle, keeping the public native object pointer valid.
@interface UI2BrowserSession : NSObject <WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate> {
@public
    NSWindow *_ui2Window;
    WKWebView *_ui2View;
    NSLock *_ui2Lock;
    NSString *_ui2JsText;
    NSMutableDictionary *_ui2Cookies;
    NSUInteger _ui2Generation;
    BOOL _ui2Open;
}
- (void)resetPage;
- (void)closeWindow;
@end

@implementation UI2BrowserSession
- (instancetype)init {
    self = [super init];
    if (self) {
        _ui2Lock = [[NSLock alloc] init];
        _ui2JsText = [@"" copy];
        _ui2Cookies = [[NSMutableDictionary alloc] init];
    }
    return self;
}
- (void)dealloc {
    [_ui2View release];
    [_ui2Lock release];
    [_ui2JsText release];
    [_ui2Cookies release];
    [super dealloc];
}
- (void)resetPage {
    [_ui2Lock lock];
    _ui2Generation++;
    [_ui2JsText release];
    _ui2JsText = [@"" copy];
    [_ui2Cookies removeAllObjects];
    [_ui2Lock unlock];
}
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [self resetPage];
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (!message.frameInfo.mainFrame) return;
    NSString *text = [message.body isKindOfClass:[NSString class]] ? message.body : [message.body description];
    [_ui2Lock lock];
    if (_ui2Open) {
        [_ui2JsText release];
        _ui2JsText = [(text ?: @"") copy];
    }
    [_ui2Lock unlock];
}
- (void)windowWillClose:(NSNotification *)notification {
    [self closeWindow];
}
- (void)closeWindow {
    [_ui2Lock lock];
    BOOL wasOpen = _ui2Open;
    _ui2Open = NO;
    [_ui2Lock unlock];
    if (!wasOpen) return;
    [self resetPage];
    [_ui2View stopLoading];
    [_ui2View.configuration.userContentController removeScriptMessageHandlerForName:@"vui"];
    _ui2View.navigationDelegate = nil;
    _ui2Window.delegate = nil;
    [_ui2Window close];
    _ui2Window.contentView = nil;
    [_ui2Window release];
    _ui2Window = nil;
}
@end

// A read owns its condition and result independently of timeout/callback order.
@interface UI2BrowserCookieRead : NSObject {
    NSCondition *_ui2Condition;
    NSString *_ui2CookieText;
    BOOL _ui2Finished;
}
- (void)finish:(NSString *)text;
- (char *)wait;
@end

@implementation UI2BrowserCookieRead
- (instancetype)init {
    self = [super init];
    if (self) _ui2Condition = [[NSCondition alloc] init];
    return self;
}
- (void)dealloc {
    [_ui2Condition release];
    [_ui2CookieText release];
    [super dealloc];
}
- (void)finish:(NSString *)text {
    [_ui2Condition lock];
    if (!_ui2Finished) {
        _ui2CookieText = [(text ?: @"") copy];
        _ui2Finished = YES;
        [_ui2Condition signal];
    }
    [_ui2Condition unlock];
}
- (char *)wait {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
    [_ui2Condition lock];
    while (!_ui2Finished && [_ui2Condition waitUntilDate:deadline]) {}
    _ui2Finished = YES;
    char *text = strdup(_ui2CookieText ? [_ui2CookieText UTF8String] : "");
    [_ui2Condition unlock];
    return text;
}
@end

static NSString *ui2_browser_string(const char *text) {
    return [NSString stringWithUTF8String:text ?: ""] ?: @"";
}

static void ui2_browser_main(void (^operation)(void)) {
    if ([NSThread isMainThread]) operation();
    else dispatch_async(dispatch_get_main_queue(), operation);
}

static NSString *ui2_browser_domain(NSString *domain) {
    NSString *normalized = [domain lowercaseString];
    return [normalized hasPrefix:@"."] ? [normalized substringFromIndex:1] : normalized;
}

void *ui2_webview_new(const char *url, const char *title, const char *script, int width, int height, int persistent) {
    @autoreleasepool {
        __block UI2BrowserSession *session = nil;
        NSString *urlText = [ui2_browser_string(url) copy];
        NSString *titleText = [ui2_browser_string(title) copy];
        NSString *scriptText = [ui2_browser_string(script) copy];
        void (^create)(void) = ^{
            [NSApplication sharedApplication];
            session = [[UI2BrowserSession alloc] init];
            WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
            config.websiteDataStore = persistent ? [WKWebsiteDataStore defaultDataStore] : [WKWebsiteDataStore nonPersistentDataStore];
            [config.userContentController addScriptMessageHandler:session name:@"vui"];
            if (scriptText.length) {
                WKUserScript *injection = [[WKUserScript alloc] initWithSource:scriptText
                    injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
                [config.userContentController addUserScript:injection];
                [injection release];
            }
            session->_ui2View = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, width, height) configuration:config];
            [config release];
            session->_ui2View.navigationDelegate = session;
            session->_ui2View.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            session->_ui2View.customUserAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15";
            session->_ui2Window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                backing:NSBackingStoreBuffered defer:NO];
            session->_ui2Window.releasedWhenClosed = NO;
            session->_ui2Window.delegate = session;
            session->_ui2Window.title = titleText;
            session->_ui2Window.contentView = session->_ui2View;
            session->_ui2Open = YES;
            [session->_ui2Window center];
            [session->_ui2Window makeKeyAndOrderFront:nil];
            NSURL *target = [NSURL URLWithString:urlText];
            if (target) [session->_ui2View loadRequest:[NSURLRequest requestWithURL:target]];
        };
        if ([NSThread isMainThread]) create();
        else dispatch_sync(dispatch_get_main_queue(), create);
        [urlText release];
        [titleText release];
        [scriptText release];
        return session;
    }
}

void *ui2_webview_object(void *handle) {
    return handle ? ((UI2BrowserSession *)handle)->_ui2View : NULL;
}

void ui2_webview_load(void *handle, const char *url) {
    if (!handle) return;
    @autoreleasepool {
        UI2BrowserSession *session = (UI2BrowserSession *)handle;
        NSString *urlText = [ui2_browser_string(url) copy];
        ui2_browser_main(^{
            if (!session->_ui2Window) return;
            [session resetPage];
            NSURL *target = [NSURL URLWithString:urlText];
            if (target) [session->_ui2View loadRequest:[NSURLRequest requestWithURL:target]];
        });
        [urlText release];
    }
}

void ui2_webview_eval(void *handle, const char *script) {
    if (!handle) return;
    @autoreleasepool {
        UI2BrowserSession *session = (UI2BrowserSession *)handle;
        NSString *scriptText = [ui2_browser_string(script) copy];
        ui2_browser_main(^{
            if (!session->_ui2Window) return;
            [session->_ui2Lock lock];
            NSUInteger generation = session->_ui2Generation;
            [session->_ui2Lock unlock];
            [session->_ui2View evaluateJavaScript:scriptText completionHandler:^(id value, NSError *error) {
                [session->_ui2Lock lock];
                if (session->_ui2Open && session->_ui2Generation == generation) {
                    [session->_ui2JsText release];
                    session->_ui2JsText = [(!error && value && value != [NSNull null] ? [value description] : @"") copy];
                }
                [session->_ui2Lock unlock];
            }];
        });
        [scriptText release];
    }
}

char *ui2_webview_js_value(void *handle) {
    if (!handle) return strdup("");
    UI2BrowserSession *session = (UI2BrowserSession *)handle;
    [session->_ui2Lock lock];
    char *text = strdup([session->_ui2JsText UTF8String]);
    [session->_ui2Lock unlock];
    return text;
}

char *ui2_webview_cookie(void *handle, const char *name, const char *domain) {
    if (!handle) return strdup("");
    @autoreleasepool {
        UI2BrowserSession *session = (UI2BrowserSession *)handle;
        NSString *cookieName = [ui2_browser_string(name) copy];
        NSString *cookieDomain = [ui2_browser_domain(ui2_browser_string(domain)) copy];
        NSString *cacheKey = [[NSString alloc] initWithFormat:@"%@\n%@", cookieName, cookieDomain];
        UI2BrowserCookieRead *read = [[UI2BrowserCookieRead alloc] init];
        BOOL isMain = [NSThread isMainThread];
        ui2_browser_main(^{
            if (!session->_ui2Window) { [read finish:@""]; return; }
            NSUInteger generation = session->_ui2Generation;
            [session->_ui2View.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
                NSString *text = @"";
                for (NSHTTPCookie *cookie in cookies) {
                    if ([cookie.name isEqualToString:cookieName] &&
                        (!cookieDomain.length || [ui2_browser_domain(cookie.domain) isEqualToString:cookieDomain])) {
                        text = cookie.value;
                        break;
                    }
                }
                [session->_ui2Lock lock];
                if (session->_ui2Open && session->_ui2Generation == generation) {
                    [session->_ui2Cookies setObject:text forKey:cacheKey];
                } else text = @"";
                [session->_ui2Lock unlock];
                [read finish:text];
            }];
        });
        char *text;
        if (isMain) {
            [session->_ui2Lock lock];
            NSString *cached = [session->_ui2Cookies objectForKey:cacheKey];
            text = strdup(cached ? cached.UTF8String : "");
            [session->_ui2Lock unlock];
        } else text = [read wait];
        [read release];
        [cacheKey release];
        [cookieName release];
        [cookieDomain release];
        return text;
    }
}

void ui2_webview_clear_data(void *handle) {
    if (!handle) return;
    UI2BrowserSession *session = (UI2BrowserSession *)handle;
    ui2_browser_main(^{
        if (!session->_ui2Window) return;
        [session resetPage];
        [session->_ui2View.configuration.websiteDataStore removeDataOfTypes:[WKWebsiteDataStore allWebsiteDataTypes]
            modifiedSince:[NSDate distantPast] completionHandler:^{}];
    });
}

void ui2_webview_close(void *handle) {
    if (!handle) return;
    UI2BrowserSession *session = (UI2BrowserSession *)handle;
    ui2_browser_main(^{ [session closeWindow]; });
}

int ui2_webview_is_open(void *handle) {
    if (!handle) return 0;
    UI2BrowserSession *session = (UI2BrowserSession *)handle;
    [session->_ui2Lock lock];
    BOOL open = session->_ui2Open;
    [session->_ui2Lock unlock];
    return open;
}
