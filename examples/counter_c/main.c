#include "ui2.h"
#include <stdio.h>
#include <string.h>

typedef struct { int count; } Counter;

static void increment(void *user_data, const ui2_event *event) {
    Counter *app = (Counter *)user_data;
    if (event->kind == UI2_EVENT_CLICK) app->count++;
}

static ui2_node *build(void *user_data) {
    Counter *app = (Counter *)user_data;
    char text[64];
    snprintf(text, sizeof text, "Count: %d", app->count);

    ui2_node *screen = ui2_screen(0xf4f6f8);
    ui2_add(screen, ui2_label("count", text, 20, 16, 240, 30));
    ui2_node *button = ui2_button("increment", "Increment", 20, 56, 240, 40);
    ui2_set_events(button, increment, app);
    ui2_add(screen, button);
    return screen;
}

int main(void) {
    Counter app = {0};
    ui2_config config = {0};
    config.title = "Counter from C";
    config.width = 280;
    config.height = 120;
    config.build = build;
    config.user_data = &app;
    if (ui2_run(&config) != 0) {
        fprintf(stderr, "%s\n", ui2_last_error());
        return 1;
    }
    return 0;
}
