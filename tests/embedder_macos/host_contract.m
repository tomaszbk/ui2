/* Native host tests: clang -std=c11 -Wall -Wextra -Werror -fobjc-arc
 * tests/embedder_macos/host_contract.m -framework Cocoa -framework Metal
 * -framework QuartzCore -o /tmp/ui2-embedder-host-test */
#include "../../ui/embedder_macos.m"
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <time.h>

static int test_idle_ms = 200;

static void test_close_windows(void) {
    NSUInteger count = ui2_embedder_windows.count;
    for (UI2EmbedderWindow* host in [ui2_embedder_windows copy]) {
        ui2_embedder_close(host.handle);
    }
    fprintf(stderr, "UI2 host test cleanup: closed %lu window(s), %lu remaining\n",
        (unsigned long)count, (unsigned long)ui2_embedder_windows.count);
}

/* These checks belong to the harness only. Runtime assertions and exceptions
 * retain their normal failure behavior. AppKit cleanup always runs on main. */
_Noreturn static void test_fail(const char* condition, const char* file, int line) {
    fprintf(stderr, "UI2 host test failed: %s (%s:%d)\n", condition, file, line);
    if (ui2_embedder_is_main_thread()) {
        test_close_windows();
    } else {
        dispatch_semaphore_t cleanup = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_main_queue(), ^{
            test_close_windows();
            dispatch_semaphore_signal(cleanup);
        });
        @autoreleasepool {
            NSEvent* wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
                subtype:0x5549 data1:0 data2:0];
            [NSApp postEvent:wake atStart:YES];
        }
        if (dispatch_semaphore_wait(cleanup,
            dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC))) {
            fputs("UI2 host test cleanup: main thread did not respond within 500 ms\n", stderr);
        }
    }
    exit(EXIT_FAILURE);
}

#define TEST_CHECK(condition) do { \
    if (!(condition)) test_fail(#condition, __FILE__, __LINE__); \
} while (0)

static bool test_parse_options(int argc, char** argv) {
    for (int index = 1; index < argc; index++) {
        if (strcmp(argv[index], "--idle-ms") || index + 1 == argc) {
            fprintf(stderr, "Usage: %s [--idle-ms N] (N: 1..%d; default: 200)\n", argv[0], INT_MAX);
            return false;
        }
        const char* value = argv[++index];
        const char* digit = value;
        while (*digit >= '0' && *digit <= '9') digit++;
        errno = 0;
        long delay = strtol(value, NULL, 10);
        if (!*value || *digit || errno == ERANGE || delay < 1 || delay > INT_MAX) {
            fprintf(stderr, "UI2 host test: --idle-ms requires an integer from 1 to %d\n", INT_MAX);
            return false;
        }
        test_idle_ms = (int)delay;
    }
    return true;
}

typedef struct TestWindow {
    void* handle;
    atomic_int pumps;
    atomic_int closed;
    atomic_bool stop;
    struct TestWindow* peer;
    int text_kind, replacement_start, replacement_length, selected_start;
    char* text;
    int drop_events;
    int key_events, last_key_kind;
    bool consume_key, close_on_key, last_text_input, last_skip_dispatch;
} TestWindow;

@interface UI2TestDragging : NSObject
@property(nonatomic, strong) NSPasteboard* draggingPasteboard;
@property(nonatomic) NSPoint draggingLocation;
@end
@implementation UI2TestDragging
@end

static void test_pause_ms(int delay) {
    struct timespec duration = {.tv_sec=delay / 1000, .tv_nsec=(delay % 1000) * 1000000};
    while (nanosleep(&duration, &duration) && errno == EINTR) {}
}

static int64_t test_pump(void* data) {
    TestWindow* state = data;
    atomic_fetch_add(&state->pumps, 1);
    if (atomic_load(&state->stop)) {
        ui2_embedder_close(state->handle);
        if (state->peer) ui2_embedder_close(state->peer->handle);
    }
    return -1;
}

static void test_closed(void* data) { atomic_fetch_add(&((TestWindow*)data)->closed, 1); }

static void test_text(void* data, const ui2_embedder_text_event* event) {
    TestWindow* state = data;
    state->text_kind = event->kind;
    state->replacement_start = event->replacement_start;
    state->replacement_length = event->replacement_length;
    state->selected_start = event->selection_start;
    free(state->text);
    state->text = strdup(event->text);
}

static bool test_event(void* data, const ui2_embedder_event* event) {
    TestWindow* state = data;
    if (event->kind == UI2_EMBEDDER_KEY_DOWN || event->kind == UI2_EMBEDDER_KEY_UP) {
        state->key_events++;
        state->last_key_kind = event->kind;
        state->last_text_input = event->text_input;
        state->last_skip_dispatch = event->skip_dispatch;
        if (state->close_on_key) ui2_embedder_close(state->handle);
        return state->consume_key;
    }
    if (event->kind == UI2_EMBEDDER_DROP) {
        state->drop_events++;
        TEST_CHECK(event->path_count == 2);
        TEST_CHECK(!strcmp(event->paths[0], "/tmp/ui2-first.txt"));
        TEST_CHECK(!strcmp(event->paths[1], "/tmp/ui2-second.txt"));
    }
    return false;
}

static void test_keyboard(TestWindow* state) {
    UI2EmbedderView* view = ((UI2EmbedderHandle*)state->handle)->native.view;
    ui2_embedder_sync_text(state->handle, true, "", 0, 0, -1, 0, 10, 20, 2, 18);
    NSEvent* key = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:0 timestamp:0 windowNumber:view.window.windowNumber context:nil
        characters:@"a" charactersIgnoringModifiers:@"a" isARepeat:NO keyCode:0];
    state->consume_key = true;
    int previous_text_kind = state->text_kind;
    [view keyDown:key];
    TEST_CHECK(state->key_events == 1 && state->last_text_input && !state->last_skip_dispatch);
    TEST_CHECK(state->text_kind == previous_text_kind && view.textSnapshot.length == 0);
    state->consume_key = false;
    view.interpretingEvent = key;
    [view doCommandBySelector:@selector(moveLeft:)];
    TEST_CHECK(state->key_events == 2 && !state->last_text_input && state->last_skip_dispatch);
    [view setMarkedText:@"かな" selectedRange:NSMakeRange(2, 0)
        replacementRange:NSMakeRange(NSNotFound, 0)];
    [view doCommandBySelector:@selector(moveLeft:)];
    TEST_CHECK(state->key_events == 2); /* Commands are owned by the IME while marked. */
    view.interpretingEvent = nil;
    NSEvent* release = [NSEvent keyEventWithType:NSEventTypeFlagsChanged location:NSZeroPoint
        modifierFlags:0 timestamp:0 windowNumber:view.window.windowNumber context:nil
        characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:56];
    [view flagsChanged:release];
    TEST_CHECK(state->key_events == 3 && state->last_key_kind == UI2_EMBEDDER_KEY_UP);
    ui2_embedder_sync_text(state->handle, false, "", 0, 0, -1, 0, 0, 0, 1, 18);
}

static void test_drop(TestWindow* state) {
    UI2EmbedderView* view = ((UI2EmbedderHandle*)state->handle)->native.view;
    UI2TestDragging* drag = [UI2TestDragging new];
    drag.draggingPasteboard = [NSPasteboard pasteboardWithUniqueName];
    [drag.draggingPasteboard writeObjects:@[
        [NSURL fileURLWithPath:@"/tmp/ui2-first.txt"],
        [NSURL fileURLWithPath:@"/tmp/ui2-second.txt"]]];
    TEST_CHECK([view performDragOperation:(id<NSDraggingInfo>)drag]);
    TEST_CHECK(state->drop_events == 1);
    [drag.draggingPasteboard releaseGlobally];
}

static void* test_worker(void* data) {
    TEST_CHECK(!ui2_embedder_is_main_thread());
    TestWindow* first = data;
    TestWindow* second = first->peer;
    test_pause_ms(test_idle_ms);
    /* With neither a visual deadline nor an event, there are no periodic host
     * callbacks. Waking one window must not execute its peer's callback. */
    TEST_CHECK(atomic_load(&first->pumps) == 1);
    TEST_CHECK(atomic_load(&second->pumps) == 1);
    ui2_embedder_wakeup(first->handle);
    test_pause_ms(100);
    TEST_CHECK(atomic_load(&first->pumps) == 2);
    TEST_CHECK(atomic_load(&second->pumps) == 1);
    atomic_store(&first->stop, true);
    ui2_embedder_wakeup(first->handle);
    return NULL;
}

static int64_t test_deadline_pump(void* data) {
    TestWindow* state = data;
    int count = atomic_fetch_add(&state->pumps, 1) + 1;
    if (count == 1) return 40;
    ui2_embedder_close(state->handle);
    return -1;
}

static int64_t test_close_pump(void* data) {
    TestWindow* state = data;
    atomic_fetch_add(&state->pumps, 1);
    ui2_embedder_close(state->handle);
    return -1;
}

static int64_t test_late_create_pump(void* data) {
    TestWindow* state = data;
    atomic_fetch_add(&state->pumps, 1);
    ui2_embedder_config config = {.title="Late hidden window", .width=320, .height=240};
    ui2_embedder_callbacks callbacks = {.pump=test_close_pump, .closed=test_closed};
    state->peer->handle = ui2_embedder_create(&config, &callbacks, state->peer);
    TEST_CHECK(state->peer->handle);
    ui2_embedder_close(state->handle);
    return -1;
}

static void* test_late_watchdog(void* data) {
    test_pause_ms(500);
    TEST_CHECK(atomic_load(&((TestWindow*)data)->closed) == 1);
    return NULL;
}

static int64_t test_async_text_pump(void* data) {
    TestWindow* state = data;
    int count = atomic_fetch_add(&state->pumps, 1) + 1;
    if (count == 1) {
        UI2EmbedderView* view = ((UI2EmbedderHandle*)state->handle)->native.view;
        ui2_embedder_sync_text(state->handle, true, "", 0, 0, -1, 0, 10, 20, 2, 18);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [view setMarkedText:@"非同期" selectedRange:NSMakeRange(3, 0)
                replacementRange:NSMakeRange(NSNotFound, 0)];
        });
    } else {
        TEST_CHECK(state->text_kind == UI2_EMBEDDER_TEXT_PREEDIT);
        TEST_CHECK(!strcmp(state->text, "非同期"));
        ui2_embedder_close(state->handle);
    }
    return -1;
}

static void test_ime(TestWindow* state) {
    UI2EmbedderView* view = ((UI2EmbedderHandle*)state->handle)->native.view;
    ui2_embedder_sync_text(state->handle, true, "A🙂B", 3, 0, -1, 0, 10, 20, 2, 18);
    [view setMarkedText:@"に" selectedRange:NSMakeRange(1, 0)
        replacementRange:NSMakeRange(NSNotFound, 0)];
    TEST_CHECK(state->text_kind == UI2_EMBEDDER_TEXT_PREEDIT);
    TEST_CHECK(state->replacement_start == -1);
    TEST_CHECK(!strcmp(state->text, "に"));
    TEST_CHECK(NSEqualRanges(view.markedRange, NSMakeRange(3, 1)));
    TEST_CHECK(NSEqualRanges(view.selectedRange, NSMakeRange(4, 0)));
    TEST_CHECK([view.textSnapshot isEqualToString:@"A🙂にB"]);
    [view setMarkedText:@"日本" selectedRange:NSMakeRange(2, 0)
        replacementRange:NSMakeRange(NSNotFound, 0)];
    TEST_CHECK([view.textSnapshot isEqualToString:@"A🙂日本B"]);
    TEST_CHECK(NSEqualRanges(view.markedRange, NSMakeRange(3, 2)));
    [view insertText:@"日本語" replacementRange:NSMakeRange(NSNotFound, 0)];
    TEST_CHECK(state->text_kind == UI2_EMBEDDER_TEXT_COMMIT);
    TEST_CHECK(!strcmp(state->text, "日本語"));
    TEST_CHECK(state->replacement_start == -1);
    TEST_CHECK(!view.hasMarkedText);
    TEST_CHECK([view.textSnapshot isEqualToString:@"A🙂日本語B"]);
    TEST_CHECK(NSEqualRanges(view.selectedRange, NSMakeRange(6, 0)));
    NSRange actual;
    NSAttributedString* substring = [view attributedSubstringForProposedRange:NSMakeRange(1, 2)
        actualRange:&actual];
    TEST_CHECK([substring.string isEqualToString:@"🙂"]);
    TEST_CHECK(NSEqualRanges(actual, NSMakeRange(1, 2)));
    NSRect candidate = [view firstRectForCharacterRange:view.selectedRange actualRange:&actual];
    TEST_CHECK(candidate.size.width == 2 && candidate.size.height == 18);
    /* Candidate rectangles use screen coordinates and preserve the caret size.
     * An explicit window origin makes this independent of monitor arrangement. */
    [view.window setFrameOrigin:NSMakePoint(100, 200)];
    candidate = [view firstRectForCharacterRange:view.selectedRange actualRange:&actual];
    TEST_CHECK(candidate.origin.x == 110);
    [view setMarkedText:@"かな" selectedRange:NSMakeRange(2, 0)
        replacementRange:NSMakeRange(NSNotFound, 0)];
    [view unmarkText];
    TEST_CHECK(state->text_kind == UI2_EMBEDDER_TEXT_UNMARK);
    TEST_CHECK(!view.hasMarkedText);
    TEST_CHECK([view.textSnapshot isEqualToString:@"A🙂日本語かなB"]);
    [view setMarkedText:@"未確定" selectedRange:NSMakeRange(3, 0)
        replacementRange:NSMakeRange(NSNotFound, 0)];
    TEST_CHECK(state->text_kind == UI2_EMBEDDER_TEXT_PREEDIT);
    ui2_embedder_sync_text(state->handle, false, "", 0, 0, -1, 0, 0, 0, 1, 18);
    TEST_CHECK(!view.hasMarkedText);
    TEST_CHECK(state->text_kind == UI2_EMBEDDER_TEXT_PREEDIT); /* Reset did not commit. */
    free(state->text);
    state->text = NULL;
}

int main(int argc, char** argv) {
    if (!test_parse_options(argc, argv)) return EXIT_FAILURE;
    @autoreleasepool {
        TEST_CHECK(ui2_embedder_is_main_thread());
        ui2_embedder_run(); /* An empty host returns without starting AppKit. */
        TestWindow first = {0}, second = {0};
        first.peer = &second;
        second.peer = &first;
        ui2_embedder_config config = {.title="UI2 embedder contract", .width=320, .height=240,
            .resizable=true, .visible=false};
        ui2_embedder_callbacks callbacks = {.pump=test_pump, .closed=test_closed,
            .text=test_text, .event=test_event};
        first.handle = ui2_embedder_create(&config, &callbacks, &first);
        second.handle = ui2_embedder_create(&config, &callbacks, &second);
        TEST_CHECK(first.handle && second.handle && first.handle != second.handle);
        TEST_CHECK(ui2_embedder_native_window(first.handle) != ui2_embedder_native_window(second.handle));
        TEST_CHECK(ui2_embedder_frame_interval(first.handle) > 0);
        TEST_CHECK(ui2_embedder_metal_device());
        test_ime(&first);
        test_keyboard(&first);
        test_drop(&first);
        pthread_t worker;
        int64_t started = ui2_embedder_now_ms();
        TEST_CHECK(!pthread_create(&worker, NULL, test_worker, &first));
        ui2_embedder_run();
        pthread_join(worker, NULL);
        TEST_CHECK(ui2_embedder_now_ms() - started >= (int64_t)test_idle_ms + 80);
        TEST_CHECK(atomic_load(&first.closed) == 1 && atomic_load(&second.closed) == 1);
        TEST_CHECK(atomic_load(&first.pumps) == 3 && atomic_load(&second.pumps) == 1);
        TEST_CHECK(ui2_embedder_pump_count(first.handle) == 3);
        TEST_CHECK(ui2_embedder_pump_count(second.handle) == 1);
        ui2_embedder_close(first.handle);
        ui2_embedder_wakeup(first.handle); /* Late worker/close cannot reach a new window. */
        TEST_CHECK(atomic_load(&first.closed) == 1);
        TEST_CHECK(!ui2_embedder_native_window(first.handle));

        TestWindow timer = {0};
        callbacks.pump = test_deadline_pump;
        timer.handle = ui2_embedder_create(&config, &callbacks, &timer);
        started = ui2_embedder_now_ms();
        ui2_embedder_run();
        TEST_CHECK(atomic_load(&timer.pumps) == 2 && atomic_load(&timer.closed) == 1);
        TEST_CHECK(ui2_embedder_now_ms() - started >= 35);

        TestWindow early = {0};
        early.handle = ui2_embedder_create(&config, &callbacks, &early);
        ui2_embedder_close(early.handle);
        ui2_embedder_run();
        TEST_CHECK(atomic_load(&early.pumps) == 0 && atomic_load(&early.closed) == 1);

        TestWindow parent = {0}, late = {0};
        parent.peer = &late;
        callbacks.pump = test_late_create_pump;
        parent.handle = ui2_embedder_create(&config, &callbacks, &parent);
        pthread_t watchdog;
        TEST_CHECK(!pthread_create(&watchdog, NULL, test_late_watchdog, &late));
        ui2_embedder_run();
        pthread_join(watchdog, NULL);
        TEST_CHECK(atomic_load(&parent.pumps) == 1 && atomic_load(&late.pumps) == 1);
        TEST_CHECK(atomic_load(&parent.closed) == 1 && atomic_load(&late.closed) == 1);

        TestWindow async_text = {0};
        callbacks.pump = test_async_text_pump;
        async_text.handle = ui2_embedder_create(&config, &callbacks, &async_text);
        TEST_CHECK(!pthread_create(&watchdog, NULL, test_late_watchdog, &async_text));
        ui2_embedder_run();
        pthread_join(watchdog, NULL);
        TEST_CHECK(atomic_load(&async_text.pumps) == 2 && atomic_load(&async_text.closed) == 1);
        free(async_text.text);

        TestWindow key_close = {.close_on_key=true};
        callbacks.pump = test_pump;
        key_close.handle = ui2_embedder_create(&config, &callbacks, &key_close);
        UI2EmbedderView* closing_view = ((UI2EmbedderHandle*)key_close.handle)->native.view;
        ui2_embedder_sync_text(key_close.handle, true, "", 0, 0, -1, 0, 0, 0, 1, 18);
        [closing_view keyDown:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
            modifierFlags:0 timestamp:0 windowNumber:closing_view.window.windowNumber context:nil
            characters:@"a" charactersIgnoringModifiers:@"a" isARepeat:NO keyCode:0]];
        TEST_CHECK(atomic_load(&key_close.closed) == 1 && key_close.key_events == 1);
        TEST_CHECK(closing_view.textSnapshot.length == 0);
        printf("UI2 native embedder: %d ms idle sleep, worker wake, window isolation, deadlines, closure, file-drop batches and IME bridge passed\n", test_idle_ms);
    }
    return 0;
}
