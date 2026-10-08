#ifndef UI2_DRAW_COMMANDS_H
#define UI2_DRAW_COMMANDS_H

/* Included after sokol-gl in its owning translation unit. Shared-live clients
 * import this symbol from the owner, just as they import the SGL entry points. */
#ifndef SOKOL_GL_INCLUDED
#error "ui2 draw commands require sokol-gl"
#endif

SOKOL_GL_API_DECL void ui2_sgl_discard_commands(sgl_context context);

#ifdef SOKOL_GL_IMPL_INCLUDED
SOKOL_API_IMPL void ui2_sgl_discard_commands(sgl_context context) {
    _sgl_context_t* ctx = _sgl_lookup_context(context.id);
    if (ctx) _sgl_rewind(ctx);
}
#endif

#endif
