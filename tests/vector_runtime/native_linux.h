#include <X11/Xlib.h>
#include <stdbool.h>

static bool ui2_vector_resize_linux(void *display_ptr, void *window_ptr, int width, int height) {
    Display *display = display_ptr;
    Window window = (Window)window_ptr;
    if (!display || !window) return false;
    XResizeWindow(display, window, width, height);
    XSync(display, False);
    return true;
}
