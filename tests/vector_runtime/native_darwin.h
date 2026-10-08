#include <objc/message.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <stdbool.h>
#include <CoreGraphics/CoreGraphics.h>

static bool ui2_vector_resize(void *window, int width, int height) {
    if (!window || !pthread_main_np()) return false;
    ((void (*)(void *, SEL, CGSize))objc_msgSend)(window,
        sel_registerName("setContentSize:"), CGSizeMake(width, height));
    return true;
}
