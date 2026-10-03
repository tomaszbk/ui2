/*
 * Host-owned IME profile. vglyph is a text measurement/drawing dependency of
 * UI2; the host owns its view, first responder, event routing and IME callbacks.
 * Keep the public composition/overlay API linkable without Objective-C classes,
 * categories, constructors, callback storage, IBus connections or host access.
 */
#include <stddef.h>
#include "ime_bridge_macos.h"
#include "ime_overlay_darwin.h"

void vglyph_ime_register_callbacks(IMEMarkedTextCallback marked,
                                  IMEInsertTextCallback insert,
                                  IMEUnmarkTextCallback unmark,
                                  IMEBoundsCallback bounds,
                                  void* user_data) {
    (void)marked; (void)insert; (void)unmark; (void)bounds; (void)user_data;
}

bool vglyph_ime_did_handle_key(void) { return false; }
bool vglyph_ime_has_marked_text(void) { return false; }

void* vglyph_discover_mtkview_from_window(void* window) {
    (void)window;
    return NULL;
}

void* vglyph_create_ime_overlay_auto(void* window) {
    (void)window;
    return NULL;
}

void* vglyph_create_ime_overlay(void* view) {
    (void)view;
    return NULL;
}

void vglyph_set_focused_field(void* handle, const char* field_id) {
    (void)handle; (void)field_id;
}

void vglyph_overlay_free(void* handle) { (void)handle; }

void vglyph_overlay_register_callbacks(void* handle, VGlyphIMECallbacks callbacks) {
    (void)handle; (void)callbacks;
}
