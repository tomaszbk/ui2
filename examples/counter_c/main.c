#include "ui2.h"
#include <stdio.h>
#include <string.h>

typedef struct { int count; } Counter;

static ui2_node *build(void *user_data) {
    Counter *app = (Counter *)user_data;
    char text[64];
    snprintf(text, sizeof text, "Count: %d", app->count);

    ui2_node *screen = ui2_screen(0xf4f6f8);
    ui2_add(screen, ui2_label("count", text, 20, 16, 240, 30));
    ui2_add(screen, ui2_button("increment", "Increment", 20, 56, 240, 40));
    return screen;
}

static void event(void *user_data, const char *id) {
    Counter *app = (Counter *)user_data;
    if (strcmp(id, "increment") == 0) app->count++;
    /* ui2 rebuilds automatically after events. */
}

int main(void) {
    Counter app = {0};
    ui2_config config = {0};
    config.title = "Counter from C";
    config.width = 280;
    config.height = 120;
    config.build = build;
    config.event = event;
    config.user_data = &app;
    if (ui2_run(&config) != 0) {
        fprintf(stderr, "%s\n", ui2_last_error());
        return 1;
    }
    return 0;
}
