#include "ui2.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

typedef struct { int done; } WindowTest;

static void verify(void *data, const char *id) {
    WindowTest *test = (WindowTest *)data;
    double x, y;
    ui2_get_scroll("scroll", &x, &y);
    if (!test->done && strcmp(id, "scroll") == 0 && x > 0 && y > 0) {
        test->done = 1; /* Updates can emit further scroll notifications. */
        char buffer[64];
        assert(ui2_get_text("name", buffer, sizeof buffer) == 6);
        assert(strcmp(buffer, "start") == 0);
        ui2_update_text("name", "Hello 世界 👋");
        size_t needed = strlen("Hello 世界 👋") + 1;
        assert(ui2_get_text("name", NULL, 0) == needed);
        assert(ui2_get_text("name", buffer, sizeof buffer) == needed);
        assert(strcmp(buffer, "Hello 世界 👋") == 0);
        buffer[2] = 'x';
        assert(ui2_get_text("name", buffer, 2) == needed);
        assert(buffer[0] == 'H' && buffer[1] == '\0' && buffer[2] == 'x');
        assert(ui2_get_checked("checkbox") == 1);
        assert(ui2_get_checked("switch") == 1);
        assert(ui2_get_checked("toggle") == 1);
        ui2_update_checked("checkbox", 0);
        ui2_update_checked("switch", 0);
        ui2_update_checked("toggle", 0);
        assert(ui2_get_checked("checkbox") == 0);
        assert(ui2_get_checked("switch") == 0);
        assert(ui2_get_checked("toggle") == 0);
        assert(ui2_get_value("slider") == 50);
        ui2_update_value("slider", 150);
        assert(ui2_get_value("slider") == 100);
        ui2_scroll_to("scroll", 120, 140);
        ui2_get_scroll("scroll", &x, &y);
        assert(x > 0 && y > 0);
        ui2_bounds(&x, &y);
        assert(x > 0 && y > 0);
        puts("Mounted C controls passed");
        fflush(stdout);
        ui2_quit();
    }
}

static ui2_node *build(void *data) {
    (void)data;
    ui2_node *root = ui2_screen(0xf4f6f8);
    ui2_node *field = ui2_create(UI2_TEXT_FIELD, "name", 20, 20, 240, 36);
    ui2_set_text(field, "start");
    ui2_add(root, field);
    ui2_node *checkbox = ui2_create(UI2_CHECKBOX, "checkbox", 20, 70, 120, 28);
    ui2_set_text(checkbox, "Checked");
    ui2_set_checked(checkbox, 1);
    ui2_add(root, checkbox);
    ui2_node *switch_control = ui2_create(UI2_SWITCH, "switch", 160, 70, 60, 28);
    ui2_set_checked(switch_control, 1);
    ui2_add(root, switch_control);
    ui2_node *toggle = ui2_create(UI2_TOGGLE_BUTTON, "toggle", 20, 110, 120, 32);
    ui2_set_text(toggle, "Toggle");
    ui2_set_checked(toggle, 1);
    ui2_add(root, toggle);
    ui2_node *slider = ui2_create(UI2_SLIDER, "slider", 20, 160, 240, 30);
    ui2_set_slider(slider, 50, 0, 100, 1, 0);
    ui2_add(root, slider);
    ui2_node *scroll = ui2_scroll("scroll", UI2_SCROLL_BOTH, 20, 210, 240, 100);
    ui2_add(scroll, ui2_label("far", "Both axes", 700, 500, 120, 30));
    ui2_add(root, scroll);
    return root;
}

int main(void) {
    WindowTest test = {0};
    ui2_config config = {0};
    config.title = "C API smoke test";
    config.width = 300;
    config.height = 340;
    config.build = build;
    config.user_data = &test;
    config.scroll = verify;
    ui2_scroll_to("scroll", 10, 10); /* Triggers a callback after mounting. */
    assert(ui2_run(&config) == 0);
    assert(test.done);
    return 0;
}
