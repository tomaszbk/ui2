/* A declaration-only SGL consumer must import UI2's source-owned bridge,
 * without depending on SGL's private types or compiling another device. */
#include "sokol_gfx.h"
#include "util/sokol_gl.h"
#include "../../ui/draw_commands.h"

void ui2_test_client_cancel(sgl_context context) {
    ui2_sgl_discard_commands(context);
}
