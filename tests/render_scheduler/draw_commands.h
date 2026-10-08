#ifndef UI2_TEST_DRAW_COMMANDS_H
#define UI2_TEST_DRAW_COMMANDS_H

/* Test observations of the real SGL queue and Cocoa drawable ownership. */
#ifndef SOKOL_GL_IMPL_INCLUDED
#error "draw command fixture requires the SGL owner"
#endif

static int ui2_test_command_count(sgl_context context) {
    _sgl_context_t* ctx = _sgl_lookup_context(context.id);
    return ctx ? ctx->commands.next : -1;
}

static int ui2_test_vertex_count(sgl_context context) {
    _sgl_context_t* ctx = _sgl_lookup_context(context.id);
    return ctx ? ctx->vertices.next : -1;
}

static sg_sampler ui2_test_shared_sampler(void) { return _sgl.def_smp; }

#include "../../ui/embedder_macos.h"
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdint.h>

extern void* objc_autoreleasePoolPush(void);
extern void objc_autoreleasePoolPop(void* pool);
static void* ui2_test_pool_begin(void) { return objc_autoreleasePoolPush(); }
static void ui2_test_pool_end(void* pool) { objc_autoreleasePoolPop(pool); }

static int64_t ui2_test_pump(void* data, int64_t (*pump)(void*)) {
    @autoreleasepool { return pump(data); }
}

static id ui2_test_host(void* window) {
    void* native = ui2_embedder_native_window(window);
    if (!native) return nil;
    id view = ((id (*)(void*, SEL))objc_msgSend)(native, sel_registerName("contentView"));
    return ((id (*)(id, SEL))objc_msgSend)(view, sel_registerName("host"));
}

static __weak id ui2_test_drawable_host;
static void* ui2_test_drawable_window;
static IMP ui2_test_original_drawable_setter;
static int ui2_test_drawable_releases;

static void ui2_test_set_drawable(id host, SEL selector, id drawable) {
    if (host == ui2_test_drawable_host && !drawable) ui2_test_drawable_releases++;
    ((void (*)(id, SEL, id))ui2_test_original_drawable_setter)(host, selector, drawable);
}

static void ui2_test_watch_drawable(void* window) {
    if (!ui2_test_original_drawable_setter) {
        Method setter = class_getInstanceMethod(objc_getClass("UI2EmbedderWindow"), sel_registerName("setDrawable:"));
        ui2_test_original_drawable_setter = method_setImplementation(setter, (IMP)ui2_test_set_drawable);
    }
    ui2_test_drawable_host = ui2_test_host(window);
    ui2_test_drawable_window = window;
    ui2_test_drawable_releases = 0;
}

static int ui2_test_drawable_release_count(void) { return ui2_test_drawable_releases; }

static bool ui2_test_has_drawable(void* window) {
    id host = window == ui2_test_drawable_window ? ui2_test_drawable_host : ui2_test_host(window);
    id drawable = host ? ((id (*)(id, SEL))objc_msgSend)(host, sel_registerName("drawable")) : nil;
    return drawable != nil;
}

#endif
