#include "embedder_macos.h"
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>


@class UI2EmbedderWindow;
typedef struct UI2EmbedderHandle {
    atomic_bool closed;
    atomic_bool pending;
    atomic_uint_fast64_t pumps;
    atomic_uint_fast64_t events;
    /* Accessed on the UI thread only. The handle itself is a stable tombstone. */
    __strong UI2EmbedderWindow* native;
} UI2EmbedderHandle;

static NSMutableArray<UI2EmbedderWindow*>* ui2_embedder_windows;
static id<MTLDevice> ui2_embedder_device;
static atomic_bool ui2_embedder_wake_posted;
static BOOL ui2_embedder_running;

static int64_t ui2_embedder_now_ms(void) {
    static mach_timebase_info_data_t scale;
    if (!scale.denom) mach_timebase_info(&scale);
    /* Split before multiplying to avoid overflowing after a long uptime. */
    uint64_t ticks = mach_absolute_time();
    return (int64_t)((ticks / scale.denom * scale.numer) / 1000000);
}

static uint32_t ui2_embedder_modifiers(NSEventModifierFlags flags) {
    return ((flags & NSEventModifierFlagShift) ? 1 : 0)
        | ((flags & NSEventModifierFlagControl) ? 2 : 0)
        | ((flags & NSEventModifierFlagOption) ? 4 : 0)
        | ((flags & NSEventModifierFlagCommand) ? 8 : 0);
}

/* Portable key values follow the existing Sokol/GLFW key contract, without
 * importing or calling sokol_app. Text always comes from NSTextInputClient. */
static int ui2_embedder_key(unsigned short key) {
    static const int table[128] = {
        [0]=65,[1]=83,[2]=68,[3]=70,[4]=72,[5]=71,[6]=90,[7]=88,[8]=67,[9]=86,
        [11]=66,[12]=81,[13]=87,[14]=69,[15]=82,[16]=89,[17]=84,[18]=49,[19]=50,
        [20]=51,[21]=52,[22]=54,[23]=53,[24]=61,[25]=57,[26]=55,[27]=45,[28]=56,
        [29]=48,[30]=93,[31]=79,[32]=85,[33]=91,[34]=73,[35]=80,[36]=257,[37]=76,
        [38]=74,[39]=39,[40]=75,[41]=59,[42]=92,[43]=44,[44]=47,[45]=78,[46]=77,
        [47]=46,[48]=258,[49]=32,[50]=96,[51]=259,[53]=256,[54]=347,[55]=343,
        [56]=340,[57]=280,[58]=342,[59]=341,[60]=344,[61]=346,[62]=345,
        [65]=330,[67]=332,[69]=334,[71]=282,[75]=331,[76]=335,[78]=333,[81]=336,
        [82]=320,[83]=321,[84]=322,[85]=323,[86]=324,[87]=325,[88]=326,[89]=327,
        [91]=328,[92]=329,[96]=294,[97]=295,[98]=296,[99]=292,[100]=297,[101]=298,
        [103]=300,[105]=302,[106]=305,[107]=303,[109]=299,[111]=301,[113]=304,
        [114]=260,[115]=268,[116]=266,[117]=261,[118]=293,[119]=269,[120]=291,
        [121]=267,[122]=290,[123]=263,[124]=262,[125]=264,[126]=265,
    };
    return key < 128 ? table[key] : 0;
}

static NSString* ui2_embedder_string(const char* text) {
    return text ? ([NSString stringWithUTF8String:text] ?: @"") : @"";
}

@interface UI2EmbedderView : NSView <NSTextInputClient, NSDraggingDestination>
@property(nonatomic, weak) UI2EmbedderWindow* host;
@property(nonatomic, strong) NSTrackingArea* tracking;
@property(nonatomic, copy) NSString* textSnapshot;
@property(nonatomic) NSRange textSelection;
@property(nonatomic) NSRange textMarked;
@property(nonatomic) NSRect textCaret;
@property(nonatomic) BOOL textEnabled;
@property(nonatomic) BOOL suppressTextCallbacks;
@property(nonatomic, strong) NSEvent* interpretingEvent;
@end

@interface UI2EmbedderWindow : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSWindow* window;
@property(nonatomic, strong) UI2EmbedderView* view;
@property(nonatomic, strong) CAMetalLayer* metalLayer;
@property(nonatomic, strong) id<CAMetalDrawable> drawable;
@property(nonatomic) UI2EmbedderHandle* handle;
@property(nonatomic) ui2_embedder_callbacks callbacks;
@property(nonatomic) void* userData;
@property(nonatomic) int64_t deadline;
@property(nonatomic) BOOL suspended;
- (BOOL)sendEvent:(ui2_embedder_event)event;
- (void)closeHost;
- (void)updateMetrics;
@end

@interface UI2EmbedderDelegate : NSObject <NSApplicationDelegate>
@end

@implementation UI2EmbedderDelegate
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
    (void)sender;
    for (UI2EmbedderWindow* host in [ui2_embedder_windows copy]) [host closeHost];
    return NSTerminateCancel;
}
@end

@implementation UI2EmbedderWindow
- (BOOL)sendEvent:(ui2_embedder_event)event {
    if (atomic_load(&_handle->closed)) return NO;
    atomic_fetch_add(&_handle->events, 1);
    ui2_embedder_surface metrics = {0};
    ui2_embedder_metrics(_handle, &metrics);
    event.width = metrics.width;
    event.height = metrics.height;
    event.framebuffer_width = metrics.framebuffer_width;
    event.framebuffer_height = metrics.framebuffer_height;
    event.dpi_scale = metrics.dpi_scale;
    ui2_embedder_wakeup(_handle);
    return _callbacks.event ? _callbacks.event(_userData, &event) : NO;
}
- (void)updateMetrics {
    CGFloat scale = _window.backingScaleFactor;
    NSSize size = _view.bounds.size;
    _metalLayer.contentsScale = scale;
    _metalLayer.drawableSize = CGSizeMake(MAX(1, size.width * scale), MAX(1, size.height * scale));
}
- (void)closeHost {
    __attribute__((objc_precise_lifetime)) UI2EmbedderWindow* keepAlive = self;
    if (atomic_exchange(&_handle->closed, true)) return;
    _deadline = -1;
    _window.delegate = nil;
    [_view.inputContext discardMarkedText];
    [_window orderOut:nil];
    [_window close];
    /* An event handler may close during an acquired frame. Keep its drawable
     * alive until frame_done, after the renderer has finished that frame. */
    if (_callbacks.closed) _callbacks.closed(_userData);
    _callbacks = (ui2_embedder_callbacks){0};
    _userData = NULL;
    _view.host = nil;
    if (!_drawable) _handle->native = nil;
    [ui2_embedder_windows removeObject:self];
    (void)keepAlive;
}
- (BOOL)windowShouldClose:(NSWindow*)sender {
    (void)sender;
    [self closeHost];
    return NO;
}
- (void)windowDidResize:(NSNotification*)note {
    (void)note;
    [self updateMetrics];
    [self sendEvent:(ui2_embedder_event){.kind=UI2_EMBEDDER_RESIZED}];
}
- (void)windowDidChangeBackingProperties:(NSNotification*)note {
    [self windowDidResize:note];
}
- (void)windowDidBecomeKey:(NSNotification*)note {
    (void)note;
    [self sendEvent:(ui2_embedder_event){.kind=UI2_EMBEDDER_FOCUSED}];
}
- (void)windowDidResignKey:(NSNotification*)note {
    (void)note;
    [self sendEvent:(ui2_embedder_event){.kind=UI2_EMBEDDER_UNFOCUSED}];
}
- (void)windowDidMiniaturize:(NSNotification*)note {
    (void)note;
    [self sendEvent:(ui2_embedder_event){.kind=UI2_EMBEDDER_ICONIFIED}];
}
- (void)windowDidDeminiaturize:(NSNotification*)note {
    (void)note;
    [self sendEvent:(ui2_embedder_event){.kind=UI2_EMBEDDER_RESTORED}];
}
- (void)windowDidChangeOcclusionState:(NSNotification*)note {
    (void)note;
    BOOL hidden = !(_window.occlusionState & NSWindowOcclusionStateVisible);
    if (hidden == _suspended) return;
    _suspended = hidden;
    [self sendEvent:(ui2_embedder_event){.kind=hidden ? UI2_EMBEDDER_SUSPENDED : UI2_EMBEDDER_RESUMED}];
}
@end

@implementation UI2EmbedderView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { (void)event; return YES; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved
            | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
    /* Metal owns the layer contents. An AppKit backing refresh does not lose its
     * presented image and may touch peer windows during another presentation.
     * Geometry, DPI and restoration invalidate through NSWindowDelegate. */
}
- (void)sendMouse:(NSEvent*)event kind:(int)kind {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    ui2_embedder_event converted = {.kind=kind, .x=point.x, .y=point.y,
        .mouse_button=(int)event.buttonNumber, .modifiers=ui2_embedder_modifiers(event.modifierFlags)};
    if (kind == UI2_EMBEDDER_SCROLL) {
        converted.scroll_x = event.scrollingDeltaX;
        converted.scroll_y = event.scrollingDeltaY;
        if (event.hasPreciseScrollingDeltas) {
            converted.scroll_x /= 10.0;
            converted.scroll_y /= 10.0;
        }
    }
    [_host sendEvent:converted];
}
- (void)mouseDown:(NSEvent*)event { [self.window makeFirstResponder:self]; [self sendMouse:event kind:UI2_EMBEDDER_MOUSE_DOWN]; }
- (void)mouseUp:(NSEvent*)event { [self sendMouse:event kind:UI2_EMBEDDER_MOUSE_UP]; }
- (void)rightMouseDown:(NSEvent*)event { [self sendMouse:event kind:UI2_EMBEDDER_MOUSE_DOWN]; }
- (void)rightMouseUp:(NSEvent*)event { [self sendMouse:event kind:UI2_EMBEDDER_MOUSE_UP]; }
- (void)otherMouseDown:(NSEvent*)event { [self sendMouse:event kind:UI2_EMBEDDER_MOUSE_DOWN]; }
- (void)otherMouseUp:(NSEvent*)event { [self sendMouse:event kind:UI2_EMBEDDER_MOUSE_UP]; }
- (void)mouseMoved:(NSEvent*)event { [self sendMouse:event kind:UI2_EMBEDDER_MOUSE_MOVE]; }
- (void)mouseDragged:(NSEvent*)event { [self sendMouse:event kind:UI2_EMBEDDER_MOUSE_MOVE]; }
- (void)rightMouseDragged:(NSEvent*)event { [self sendMouse:event kind:UI2_EMBEDDER_MOUSE_MOVE]; }
- (void)otherMouseDragged:(NSEvent*)event { [self sendMouse:event kind:UI2_EMBEDDER_MOUSE_MOVE]; }
- (void)mouseEntered:(NSEvent*)event { [self sendMouse:event kind:UI2_EMBEDDER_MOUSE_ENTER]; }
- (void)mouseExited:(NSEvent*)event { [self sendMouse:event kind:UI2_EMBEDDER_MOUSE_LEAVE]; }
- (void)scrollWheel:(NSEvent*)event { [self sendMouse:event kind:UI2_EMBEDDER_SCROLL]; }
- (void)sendKey:(NSEvent*)event kind:(int)kind {
    [_host sendEvent:(ui2_embedder_event){.kind=kind, .key_code=ui2_embedder_key(event.keyCode),
        .repeat=event.type == NSEventTypeKeyDown && event.isARepeat,
        .modifiers=ui2_embedder_modifiers(event.modifierFlags)}];
}
- (void)keyDown:(NSEvent*)event {
    _interpretingEvent = event;
    BOOL command = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    BOOL consumed = [_host sendEvent:(ui2_embedder_event){.kind=UI2_EMBEDDER_KEY_DOWN,
        .key_code=ui2_embedder_key(event.keyCode), .repeat=event.isARepeat,
        .modifiers=ui2_embedder_modifiers(event.modifierFlags), .text_input=_textEnabled && !command}];
    if (!consumed && !command && _host && !atomic_load(&_host.handle->closed)) {
        [self interpretKeyEvents:@[event]];
    }
    _interpretingEvent = nil;
}
- (void)keyUp:(NSEvent*)event { [self sendKey:event kind:UI2_EMBEDDER_KEY_UP]; }
- (void)flagsChanged:(NSEvent*)event {
    NSEventModifierFlags flag = 0;
    switch (event.keyCode) {
        case 54: case 55: flag = NSEventModifierFlagCommand; break;
        case 56: case 60: flag = NSEventModifierFlagShift; break;
        case 58: case 61: flag = NSEventModifierFlagOption; break;
        case 59: case 62: flag = NSEventModifierFlagControl; break;
        case 57: flag = NSEventModifierFlagCapsLock; break;
        default: return;
    }
    [self sendKey:event kind:(event.modifierFlags & flag) ? UI2_EMBEDDER_KEY_DOWN : UI2_EMBEDDER_KEY_UP];
}
- (void)shortcut:(int)key {
    [_host sendEvent:(ui2_embedder_event){.kind=UI2_EMBEDDER_KEY_DOWN, .key_code=key, .modifiers=8}];
}
- (void)copy:(id)sender { (void)sender; [self shortcut:67]; }
- (void)cut:(id)sender { (void)sender; [self shortcut:88]; }
- (void)paste:(id)sender { (void)sender; [self shortcut:86]; }
- (void)selectAll:(id)sender { (void)sender; [self shortcut:65]; }
- (void)doCommandBySelector:(SEL)selector {
    (void)selector;
    /* IME consumes navigation while composing; ordinary editing commands retain
     * the renderer's existing keyboard semantics. */
    if (_textEnabled && ![self hasMarkedText] && _interpretingEvent) {
        [_host sendEvent:(ui2_embedder_event){.kind=UI2_EMBEDDER_KEY_DOWN,
            .key_code=ui2_embedder_key(_interpretingEvent.keyCode), .repeat=_interpretingEvent.isARepeat,
            .modifiers=ui2_embedder_modifiers(_interpretingEvent.modifierFlags), .skip_dispatch=true}];
    }
}
- (NSRange)replacementRange:(NSRange)range {
    if (range.location == NSNotFound) range = [self hasMarkedText] ? _textMarked : _textSelection;
    range.location = MIN(range.location, _textSnapshot.length);
    range.length = MIN(range.length, _textSnapshot.length - range.location);
    return range;
}
- (void)sendText:(int)kind value:(NSString*)value replacement:(NSRange)replacement selection:(NSRange)selection {
    UI2EmbedderWindow* host = _host;
    if (_suppressTextCallbacks || !host || atomic_load(&host.handle->closed)) return;
    atomic_fetch_add(&host.handle->events, 1);
    ui2_embedder_wakeup(host.handle);
    ui2_embedder_text_event event = {.kind=kind, .text=value.UTF8String,
        .replacement_start=replacement.location == NSNotFound ? -1 : (int)replacement.location,
        .replacement_length=replacement.location == NSNotFound ? 0 : (int)replacement.length,
        .selection_start=(int)selection.location, .selection_length=(int)selection.length};
    if (host.callbacks.text) host.callbacks.text(host.userData, &event);
}
- (void)insertText:(id)value replacementRange:(NSRange)replacementRange {
    NSString* text = [value isKindOfClass:NSAttributedString.class] ? [value string] : value;
    if (!_textEnabled) {
        NSData* bytes = [text dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
        const uint32_t* runes = bytes.bytes;
        for (NSUInteger i = 0; i < bytes.length / 4; i++) {
            [_host sendEvent:(ui2_embedder_event){.kind=UI2_EMBEDDER_CHAR, .char_code=runes[i],
                .modifiers=_interpretingEvent ? ui2_embedder_modifiers(_interpretingEvent.modifierFlags) : 0}];
        }
        return;
    }
    NSRange replacement = [self replacementRange:replacementRange];
    _textSnapshot = [_textSnapshot stringByReplacingCharactersInRange:replacement withString:text];
    _textSelection = NSMakeRange(replacement.location + text.length, 0);
    _textMarked = NSMakeRange(NSNotFound, 0);
    [self sendText:UI2_EMBEDDER_TEXT_COMMIT value:text replacement:replacementRange selection:NSMakeRange(text.length, 0)];
}
- (void)setMarkedText:(id)value selectedRange:(NSRange)selection replacementRange:(NSRange)replacementRange {
    if (!_textEnabled) return;
    NSString* text = [value isKindOfClass:NSAttributedString.class] ? [value string] : value;
    NSRange replacement = [self replacementRange:replacementRange];
    selection.location = MIN(selection.location, text.length);
    selection.length = MIN(selection.length, text.length - selection.location);
    _textSnapshot = [_textSnapshot stringByReplacingCharactersInRange:replacement withString:text];
    _textMarked = NSMakeRange(replacement.location, text.length);
    _textSelection = NSMakeRange(replacement.location + selection.location, selection.length);
    [self sendText:UI2_EMBEDDER_TEXT_PREEDIT value:text replacement:replacementRange selection:selection];
}
- (void)unmarkText {
    if (![self hasMarkedText]) return;
    NSRange previous = _textMarked;
    _textMarked = NSMakeRange(NSNotFound, 0);
    [self sendText:UI2_EMBEDDER_TEXT_UNMARK value:@"" replacement:previous selection:NSMakeRange(0, 0)];
}
- (BOOL)hasMarkedText { return _textMarked.location != NSNotFound && _textMarked.length > 0; }
- (NSRange)markedRange { return _textMarked; }
- (NSRange)selectedRange { return _textSelection; }
- (NSArray<NSAttributedStringKey>*)validAttributesForMarkedText { return @[]; }
- (NSAttributedString*)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actual {
    if (range.location > _textSnapshot.length || range.location == NSNotFound) return nil;
    range.length = MIN(range.length, _textSnapshot.length - range.location);
    if (actual) *actual = range;
    return [[NSAttributedString alloc] initWithString:[_textSnapshot substringWithRange:range]];
}
- (NSUInteger)characterIndexForPoint:(NSPoint)point { (void)point; return _textSelection.location; }
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actual {
    if (actual) *actual = range;
    NSRect inWindow = [self convertRect:_textCaret toView:nil];
    return [self.window convertRectToScreen:inWindow];
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return [sender.draggingPasteboard canReadObjectForClasses:@[NSURL.class]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}] ? NSDragOperationCopy : NSDragOperationNone;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL*>* files = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
    NSPoint point = [self convertPoint:sender.draggingLocation fromView:nil];
    NSMutableArray<NSString*>* paths = [NSMutableArray arrayWithCapacity:files.count];
    for (NSURL* file in files) [paths addObject:file.path];
    const char** pointers = calloc(paths.count, sizeof(*pointers));
    if (!pointers && paths.count) return NO;
    for (NSUInteger index = 0; index < paths.count; index++) pointers[index] = paths[index].UTF8String;
    if (paths.count) {
        [_host sendEvent:(ui2_embedder_event){.kind=UI2_EMBEDDER_DROP,
            .x=point.x, .y=point.y, .path=pointers[0], .paths=pointers, .path_count=(int)paths.count}];
    }
    free(pointers);
    return files.count > 0;
}
@end

static void ui2_embedder_setup(void) {
    if (ui2_embedder_windows) return;
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    ui2_embedder_windows = [NSMutableArray array];
    if (!ui2_embedder_device) ui2_embedder_device = MTLCreateSystemDefaultDevice();
    static UI2EmbedderDelegate* delegate;
    delegate = [UI2EmbedderDelegate new];
    NSApp.delegate = delegate;
    NSMenu* menu = [NSMenu new];
    NSMenuItem* appItem = [NSMenuItem new];
    [menu addItem:appItem];
    NSMenu* appMenu = [NSMenu new];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    NSMenuItem* editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu* editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    [menu addItem:editItem];
    NSApp.mainMenu = menu;
    [NSApp finishLaunching];
}

void* ui2_embedder_create(const ui2_embedder_config* config,
    const ui2_embedder_callbacks* callbacks, void* user_data) {
    if (![NSThread isMainThread] || !config || !callbacks) return NULL;
    ui2_embedder_setup();
    if (!ui2_embedder_device) return NULL;
    UI2EmbedderHandle* handle = calloc(1, sizeof(*handle));
    if (!handle) return NULL;
    atomic_init(&handle->closed, false);
    atomic_init(&handle->pending, true);
    atomic_init(&handle->pumps, 0);
    atomic_init(&handle->events, 0);
    UI2EmbedderWindow* host = [UI2EmbedderWindow new];
    host.handle = handle;
    handle->native = host;
    host.callbacks = *callbacks;
    host.userData = user_data;
    host.deadline = -1;
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
    if (config->resizable) style |= NSWindowStyleMaskResizable;
    NSRect rect = NSMakeRect(0, 0, MAX(1, config->width), MAX(1, config->height));
    host.window = [[NSWindow alloc] initWithContentRect:rect styleMask:style backing:NSBackingStoreBuffered defer:NO];
    host.window.releasedWhenClosed = NO;
    host.window.title = ui2_embedder_string(config->title);
    host.window.contentMinSize = NSMakeSize(MAX(1, config->min_width), MAX(1, config->min_height));
    host.window.acceptsMouseMovedEvents = YES;
    host.view = [[UI2EmbedderView alloc] initWithFrame:rect];
    host.view.host = host;
    host.view.textSnapshot = @"";
    host.view.textMarked = NSMakeRange(NSNotFound, 0);
    host.view.wantsLayer = YES;
    host.metalLayer = [CAMetalLayer layer];
    host.metalLayer.device = ui2_embedder_device;
    host.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    host.metalLayer.framebufferOnly = YES;
    host.metalLayer.opaque = YES;
    host.metalLayer.displaySyncEnabled = YES;
    host.view.layer = host.metalLayer;
    host.window.contentView = host.view;
    host.window.delegate = host;
    [host.view registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    [host updateMetrics];
    [ui2_embedder_windows addObject:host];
    [host.window center];
    [host.window makeFirstResponder:host.view];
    if (config->visible) {
        [host.window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
    }
    /* Creation during a callback adds a window outside the loop's current
     * snapshot. Wake the loop so that hidden late windows get their first pump. */
    ui2_embedder_wakeup(handle);
    return handle;
}

void ui2_embedder_run(void) {
    if (![NSThread isMainThread] || ui2_embedder_running) return;
    ui2_embedder_running = YES;
    while (ui2_embedder_windows.count > 0) {
        @autoreleasepool {
            int64_t now = ui2_embedder_now_ms();
            int64_t earliest = -1;
            for (UI2EmbedderWindow* host in [ui2_embedder_windows copy]) {
                UI2EmbedderHandle* handle = host.handle;
                if (atomic_load(&handle->closed)) continue;
                BOOL due = host.deadline >= 0 && now >= host.deadline;
                if (atomic_exchange(&handle->pending, false) || due) {
                    host.deadline = -1;
                    atomic_fetch_add(&handle->pumps, 1);
                    int64_t delay = host.callbacks.pump ? host.callbacks.pump(host.userData) : -1;
                    if (!atomic_load(&handle->closed) && delay >= 0) {
                        host.deadline = ui2_embedder_now_ms() + delay;
                    }
                }
                if (!atomic_load(&handle->closed)) {
                    if (atomic_load(&handle->pending)) earliest = now;
                    else if (host.deadline >= 0 && (earliest < 0 || host.deadline < earliest)) earliest = host.deadline;
                }
            }
            if (!ui2_embedder_windows.count) break;
            NSDate* until = earliest < 0 ? NSDate.distantFuture
                : [NSDate dateWithTimeIntervalSinceNow:MAX(0, earliest - ui2_embedder_now_ms()) / 1000.0];
            NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:until
                inMode:NSDefaultRunLoopMode dequeue:YES];
            if (event.type == NSEventTypeApplicationDefined && event.subtype == 0x5549) {
                atomic_store(&ui2_embedder_wake_posted, false);
            } else if (event) {
                [NSApp sendEvent:event];
            }
            [NSApp updateWindows];
        }
    }
    ui2_embedder_running = NO;
}

bool ui2_embedder_is_main_thread(void) { return NSThread.isMainThread; }

void ui2_embedder_close(void* window) {
    if (![NSThread isMainThread] || !window) return;
    UI2EmbedderHandle* handle = window;
    [handle->native closeHost];
}

void ui2_embedder_wakeup(void* window) {
    if (!window) return;
    UI2EmbedderHandle* handle = window;
    if (atomic_load(&handle->closed)) return;
    atomic_store(&handle->pending, true);
    if (atomic_exchange(&ui2_embedder_wake_posted, true)) return;
    @autoreleasepool {
        NSEvent* event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
            location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
            subtype:0x5549 data1:0 data2:0];
        [NSApp postEvent:event atStart:NO];
    }
}

void* ui2_embedder_metal_device(void) {
    if (![NSThread isMainThread]) return NULL;
    if (!ui2_embedder_device) ui2_embedder_device = MTLCreateSystemDefaultDevice();
    return (__bridge void*)ui2_embedder_device;
}

void* ui2_embedder_native_window(void* window) {
    if (!window) return NULL;
    UI2EmbedderHandle* handle = window;
    return atomic_load(&handle->closed) ? NULL : (__bridge void*)handle->native.window;
}

int64_t ui2_embedder_frame_interval(void* window) {
    if (!window) return 16;
    UI2EmbedderHandle* handle = window;
    NSInteger fps = 60;
    if (!atomic_load(&handle->closed)) {
        NSScreen* screen = handle->native.window.screen;
        if ([screen respondsToSelector:@selector(maximumFramesPerSecond)]) fps = screen.maximumFramesPerSecond;
    }
    return MAX(1, 1000 / MAX(1, fps));
}

uint64_t ui2_embedder_pump_count(void* window) {
    return window ? atomic_load(&((UI2EmbedderHandle*)window)->pumps) : 0;
}

uint64_t ui2_embedder_event_count(void* window) {
    return window ? atomic_load(&((UI2EmbedderHandle*)window)->events) : 0;
}

void ui2_embedder_metrics(void* window, ui2_embedder_surface* out) {
    if (!window || !out) return;
    *out = (ui2_embedder_surface){0};
    UI2EmbedderHandle* handle = window;
    if (atomic_load(&handle->closed)) return;
    UI2EmbedderWindow* host = handle->native;
    NSSize size = host.view.bounds.size;
    out->width = (int)size.width;
    out->height = (int)size.height;
    out->framebuffer_width = (int)host.metalLayer.drawableSize.width;
    out->framebuffer_height = (int)host.metalLayer.drawableSize.height;
    out->dpi_scale = (float)host.window.backingScaleFactor;
}

bool ui2_embedder_acquire_frame(void* window, ui2_embedder_surface* out) {
    if (!window || !out || ![NSThread isMainThread]) return false;
    UI2EmbedderHandle* handle = window;
    if (atomic_load(&handle->closed)) return false;
    UI2EmbedderWindow* host = handle->native;
    ui2_embedder_metrics(window, out);
    if (host.window.miniaturized || host.suspended || out->width <= 0 || out->height <= 0) return false;
    if (!host.drawable) host.drawable = [host.metalLayer nextDrawable];
    if (!host.drawable) return false;
    out->drawable = (__bridge void*)host.drawable;
    out->color_texture = (__bridge void*)host.drawable.texture;
    return true;
}

void ui2_embedder_frame_done(void* window) {
    if (!window) return;
    UI2EmbedderHandle* handle = window;
    handle->native.drawable = nil;
    if (atomic_load(&handle->closed)) handle->native = nil;
}

void ui2_embedder_sync_text(void* window, bool enabled, const char* text,
    int selection_start, int selection_length, int marked_start, int marked_length,
    double caret_x, double caret_y, double caret_width, double caret_height) {
    if (!window) return;
    UI2EmbedderHandle* handle = window;
    if (atomic_load(&handle->closed)) return;
    UI2EmbedderView* view = handle->native.view;
    if (view.textEnabled && (!enabled || (view.textMarked.location != NSNotFound && marked_start < 0))) {
        /* App-driven focus/reset cancels the input method's composition. Its
         * unmark callback must not commit the old field during that reset. */
        view.suppressTextCallbacks = YES;
        [view.inputContext discardMarkedText];
        view.suppressTextCallbacks = NO;
    }
    view.textSnapshot = ui2_embedder_string(text);
    NSUInteger length = view.textSnapshot.length;
    NSUInteger start = MIN((NSUInteger)MAX(0, selection_start), length);
    view.textSelection = NSMakeRange(start, MIN((NSUInteger)MAX(0, selection_length), length - start));
    NSUInteger marked = MIN((NSUInteger)MAX(0, marked_start), length);
    view.textMarked = marked_start < 0 ? NSMakeRange(NSNotFound, 0)
        : NSMakeRange(marked, MIN((NSUInteger)MAX(0, marked_length), length - marked));
    view.textCaret = NSMakeRect(caret_x, caret_y, MAX(1, caret_width), MAX(1, caret_height));
    view.textEnabled = enabled;
    [view.inputContext invalidateCharacterCoordinates];
}

void ui2_embedder_set_title(void* window, const char* title) {
    if (!window) return;
    UI2EmbedderHandle* handle = window;
    if (!atomic_load(&handle->closed)) handle->native.window.title = ui2_embedder_string(title);
}

void ui2_embedder_show(void* window) {
    if (!window) return;
    UI2EmbedderHandle* handle = window;
    if (!atomic_load(&handle->closed)) {
        [handle->native.window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
    }
}

void ui2_embedder_set_cursor(int cursor) {
    switch (cursor) {
        case 1: [[NSCursor IBeamCursor] set]; break;
        case 2: [[NSCursor pointingHandCursor] set]; break;
        case 3: [[NSCursor resizeLeftRightCursor] set]; break;
        case 4: [[NSCursor resizeUpDownCursor] set]; break;
        default: [[NSCursor arrowCursor] set]; break;
    }
}

char* ui2_embedder_clipboard_get(void) {
    return strdup(([NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString] ?: @"").UTF8String);
}

void ui2_embedder_clipboard_set(const char* text) {
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:ui2_embedder_string(text) forType:NSPasteboardTypeString];
}
