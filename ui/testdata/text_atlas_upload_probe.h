#ifndef UI2_TEXT_ATLAS_UPLOAD_PROBE_H
#define UI2_TEXT_ATLAS_UPLOAD_PROBE_H

#import <Metal/Metal.h>
#include <stdlib.h>
#include <string.h>

/* Test-only observation of the real Metal textures at pass submission. No
 * uploads, commits or resource mutations are performed by this probe. */
typedef struct {
    sg_image image;
    uint32_t frame;
    unsigned char* pixels;
    size_t size;
    bool drawn;
} ui2_test_atlas_image;

static ui2_test_atlas_image ui2_test_atlas_images[128];
static int ui2_test_atlas_count;
static uint32_t ui2_test_atlas_bound;
static bool ui2_test_atlas_active, ui2_test_atlas_seen, ui2_test_atlas_ok;
static sg_trace_hooks ui2_test_atlas_previous;

static bool ui2_test_atlas_pixels_match(const ui2_test_atlas_image* image) {
    sg_mtl_image_info info = sg_mtl_query_image_info(image->image);
    id<MTLTexture> texture = (__bridge id<MTLTexture>)info.tex[info.active_slot];
    if (!texture || texture.pixelFormat != MTLPixelFormatRGBA8Unorm ||
        texture.storageMode == MTLStorageModePrivate ||
        image->size != texture.width * texture.height * 4) return false;
    unsigned char* actual = malloc(image->size);
    if (!actual) return false;
    [texture getBytes:actual bytesPerRow:texture.width * 4
        fromRegion:MTLRegionMake2D(0, 0, texture.width, texture.height) mipmapLevel:0];
    bool matches = memcmp(actual, image->pixels, image->size) == 0;
    free(actual);
    return matches;
}

static void ui2_test_atlas_begin_pass(const sg_pass* pass, void* user_data) {
    ui2_test_atlas_seen = true;
    for (int i = 0; i < ui2_test_atlas_count; i++) {
        const ui2_test_atlas_image* image = &ui2_test_atlas_images[i];
        bool valid = sg_query_image_state(image->image) == SG_RESOURCESTATE_VALID;
        ui2_test_atlas_ok &= valid &&
            sg_query_image_info(image->image).upd_frame_index == image->frame;
        if (valid && image->pixels) ui2_test_atlas_ok &= ui2_test_atlas_pixels_match(image);
    }
    if (ui2_test_atlas_previous.begin_pass)
        ui2_test_atlas_previous.begin_pass(pass, user_data);
}

static void ui2_test_atlas_apply_bindings(const sg_bindings* bindings, void* user_data) {
    ui2_test_atlas_bound = bindings->fs.images[0].id;
    if (ui2_test_atlas_previous.apply_bindings)
        ui2_test_atlas_previous.apply_bindings(bindings, user_data);
}

static void ui2_test_atlas_draw(int base, int count, int instances, void* user_data) {
    if (count > 0 && instances > 0) {
        for (int i = 0; i < ui2_test_atlas_count; i++)
            if (ui2_test_atlas_images[i].image.id == ui2_test_atlas_bound)
                ui2_test_atlas_images[i].drawn = true;
    }
    if (ui2_test_atlas_previous.draw)
        ui2_test_atlas_previous.draw(base, count, instances, user_data);
}

static void ui2_test_atlas_stop(void) {
    if (!ui2_test_atlas_active) return;
    sg_install_trace_hooks(&ui2_test_atlas_previous);
    for (int i = 0; i < ui2_test_atlas_count; i++) free(ui2_test_atlas_images[i].pixels);
    ui2_test_atlas_active = false;
}

static void ui2_test_atlas_start(void) {
    ui2_test_atlas_stop();
    memset(ui2_test_atlas_images, 0, sizeof(ui2_test_atlas_images));
    ui2_test_atlas_count = 0;
    ui2_test_atlas_bound = 0;
    ui2_test_atlas_seen = false;
    ui2_test_atlas_ok = true;
    sg_trace_hooks hooks = {0};
    ui2_test_atlas_previous = sg_install_trace_hooks(&hooks);
    hooks = ui2_test_atlas_previous;
    hooks.begin_pass = ui2_test_atlas_begin_pass;
    hooks.apply_bindings = ui2_test_atlas_apply_bindings;
    hooks.draw = ui2_test_atlas_draw;
    sg_install_trace_hooks(&hooks);
    ui2_test_atlas_active = true;
}

static bool ui2_test_atlas_watch(uint32_t id, uint32_t frame,
        const unsigned char* pixels, size_t size) {
    if (ui2_test_atlas_count == 128) return false;
    ui2_test_atlas_image* image = &ui2_test_atlas_images[ui2_test_atlas_count++];
    image->image.id = id;
    image->frame = frame;
    image->size = size;
    if (pixels) {
        image->pixels = malloc(size);
        if (!image->pixels) return false;
        memcpy(image->pixels, pixels, size);
    }
    return true;
}

static bool ui2_test_atlas_passed(void) {
    return ui2_test_atlas_seen && ui2_test_atlas_count > 0 && ui2_test_atlas_ok;
}

static bool ui2_test_atlas_drawn(uint32_t id) {
    for (int i = 0; i < ui2_test_atlas_count; i++)
        if (ui2_test_atlas_images[i].image.id == id) return ui2_test_atlas_images[i].drawn;
    return false;
}
#endif
