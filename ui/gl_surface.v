// vfmt off
@[has_globals]
module ui2

// gl_surface.v is the platform-neutral side of `opengl` elements. The gg renderer
// draws them, and native backends show them as transparent views, so applications
// can call these functions on every platform. Wrapping a GL texture is a feature of
// sokol's OpenGL backends — Linux and Android; custom-rendered desktop builds run
// Metal or D3D11, which have no GL texture to wrap, so a texture handed over there
// draws as an empty quad.

// GlTextureRequest names a GL texture that the application renders into for one
// `opengl` element. The texture stays owned by the application.
pub struct GlTextureRequest {
pub:
	gl_texture u32
	width      int
	height     int
}

__global g_gl_surface_renderer = GlSurfaceFn(unsafe { nil })
__global g_gl_surface_requests = map[string]GlTextureRequest{}

// set_gl_surface_renderer installs the function that renders into each `opengl`
// element. It runs before every frame, on the UI thread, with the GL context current,
// for the elements drawn in the previous frame. A new element is therefore first
// rendered one frame after it appears.
//
// The renderer runs inside the frame sokol is already driving. GL state it changes
// behind sokol's back — a framebuffer or texture it binds — has to be handed back
// with gfx.reset_state_cache() before returning, or sokol may skip reapplying
// bindings and draw the UI with stale ones.
pub fn set_gl_surface_renderer(renderer GlSurfaceFn) {
	g_gl_surface_renderer = renderer
}

// set_gl_surface_texture shows gl_texture, a GL texture of width x height pixels, in
// the `opengl` element with this id. Call it from the surface renderer. Requests for
// elements that are no longer drawn are dropped.
pub fn set_gl_surface_texture(id string, gl_texture u32, width int, height int) {
	g_gl_surface_requests[id] = GlTextureRequest{
		gl_texture: gl_texture
		width:      width
		height:     height
	}
	// The producer usually runs on its own thread, so without this ask the new
	// texture would wait for unrelated work: on GL/D3D the loop re-presents the
	// retained tree each vsync and would pick it up anyway, but on Metal an
	// idle window draws nothing and the update would never reach the screen.
	// The scheduler's queue is mutex guarded, so this is safe off the UI thread.
	request_refresh()
}
