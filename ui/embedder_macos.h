#ifndef UI2_EMBEDDER_MACOS_H
#define UI2_EMBEDDER_MACOS_H

#include <stdbool.h>
#include <stdint.h>

/* The host has no dependency on gg or sokol_app. All coordinates are logical,
 * top-left points. Only framebuffer dimensions are device pixels. */
typedef struct ui2_embedder_config {
    const char* title;
    int width, height, min_width, min_height;
    bool resizable, visible;
} ui2_embedder_config;

enum ui2_embedder_event_kind {
    UI2_EMBEDDER_MOUSE_DOWN = 1, UI2_EMBEDDER_MOUSE_UP,
    UI2_EMBEDDER_MOUSE_MOVE, UI2_EMBEDDER_MOUSE_ENTER,
    UI2_EMBEDDER_MOUSE_LEAVE, UI2_EMBEDDER_SCROLL,
    UI2_EMBEDDER_KEY_DOWN, UI2_EMBEDDER_KEY_UP, UI2_EMBEDDER_CHAR,
    UI2_EMBEDDER_RESIZED, UI2_EMBEDDER_FOCUSED, UI2_EMBEDDER_UNFOCUSED,
    UI2_EMBEDDER_ICONIFIED, UI2_EMBEDDER_RESTORED,
    UI2_EMBEDDER_SUSPENDED, UI2_EMBEDDER_RESUMED, UI2_EMBEDDER_DROP,
};

typedef struct ui2_embedder_event {
    int kind, key_code, mouse_button;
    uint32_t char_code, modifiers;
    bool repeat;
    bool text_input, skip_dispatch;
    float x, y, scroll_x, scroll_y, dpi_scale;
    int width, height, framebuffer_width, framebuffer_height;
    const char* path; /* Borrowed for the event callback only. */
    const char** paths;
    int path_count;
} ui2_embedder_event;

enum ui2_embedder_text_kind {
    UI2_EMBEDDER_TEXT_COMMIT = 1,
    UI2_EMBEDDER_TEXT_PREEDIT,
    UI2_EMBEDDER_TEXT_UNMARK,
};

/* All ranges below are UTF-16 offsets, as required by NSTextInputClient.
 * Replacement ranges refer to the previous text snapshot; -1 means use the
 * existing composition or selection. Selection is relative to the inserted text.
 * Copy text before returning from the callback. */
typedef struct ui2_embedder_text_event {
    int kind;
    const char* text;
    int replacement_start, replacement_length;
    int selection_start, selection_length;
} ui2_embedder_text_event;

typedef struct ui2_embedder_callbacks {
    /* Called only for this window's work/event/deadline. Return milliseconds
     * until its next callback, or -1 to sleep until an event or explicit wakeup. */
    int64_t (*pump)(void* user_data);
    bool (*event)(void* user_data, const ui2_embedder_event* event);
    void (*text)(void* user_data, const ui2_embedder_text_event* event);
    void (*closed)(void* user_data);
} ui2_embedder_callbacks;

typedef struct ui2_embedder_surface {
    int width, height, framebuffer_width, framebuffer_height;
    float dpi_scale;
    void* drawable;
    void* color_texture;
} ui2_embedder_surface;

/* Creation, run, close, surface and text operations belong to the main thread.
 * wakeup is the sole worker-safe operation. Closed handles remain safe tombstones
 * so a worker holding an old dispatcher cannot wake a replacement window. */
void* ui2_embedder_create(const ui2_embedder_config* config,
    const ui2_embedder_callbacks* callbacks, void* user_data);
void ui2_embedder_run(void);
bool ui2_embedder_is_main_thread(void);
void ui2_embedder_close(void* window);
void ui2_embedder_wakeup(void* window);
void* ui2_embedder_metal_device(void);
void* ui2_embedder_native_window(void* window);
int64_t ui2_embedder_frame_interval(void* window);
uint64_t ui2_embedder_pump_count(void* window);
/* Input/geometry/text deliveries, distinct from deadline/worker pump wakeups. */
uint64_t ui2_embedder_event_count(void* window);
bool ui2_embedder_acquire_frame(void* window, ui2_embedder_surface* out);
void ui2_embedder_frame_done(void* window);
void ui2_embedder_metrics(void* window, ui2_embedder_surface* out);
void ui2_embedder_sync_text(void* window, bool enabled, const char* text,
    int selection_start, int selection_length, int marked_start, int marked_length,
    double caret_x, double caret_y, double caret_width, double caret_height);
void ui2_embedder_set_title(void* window, const char* title);
void ui2_embedder_show(void* window);
void ui2_embedder_set_cursor(int cursor);
/* Returned clipboard text is malloc-owned and must be freed by the caller. */
char* ui2_embedder_clipboard_get(void);
void ui2_embedder_clipboard_set(const char* text);

#endif
