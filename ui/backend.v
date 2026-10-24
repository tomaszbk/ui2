module ui2

// # Backend contract
//
// Every build compiles exactly one backend. ui2 has two modes:
//
// - native: on macOS, Windows and iOS the controls are the operating
//   system's own (AppKit, Win32, UIKit): NSButton, NSTextField,
//   NSPopUpButton and their equivalents, with layer-backed views for boxes
//   (background, corner radius, borders). ui2 still computes the layout and
//   reconciles the declared tree into those views. This is the default there.
// - custom: the custom backend draws every control itself with one renderer
//   (gg and sokol), and the operating system only hosts it (platform.v).
//   Linux and Android always run it; macOS, Windows and iOS opt in with
//   -d ui2_custom_rendering.
//
// The other backends exist for tests and tools: headless keeps window state
// in memory, and the document library has no window at all. Shared code
// calls the functions listed below and reads the capability constants
// directly; it never tests the compile-time flags that select a backend.
//
// ## Rule
//
// Only a backend's own files may test `ui2_custom_rendering`,
// `ui2_headless`, `ui2_embedder` or `ui2_document_library`, and only in
// their single whole-file guard, spelled exactly as in the tables below. A
// difference between backends that shared code has to know about becomes a
// contract function or a `backend_*` constant that every backend defines.
// Both branches of an `if` on such a constant must compile with every
// backend; a false constant still costs nothing at run time, because it is
// emitted as a C `#define` and the C compiler drops the dead branch.
//
// The few other places that may name a flag are listed in
// backend_guard_test.v, which enforces the rule: ui/embedder_options.v, which
// rejects flag combinations the embedder does not support; the renderer's
// `$if macos && ui2_embedder ? {` branches, which pick the embedder host for a
// few statements; the unsupported-OS check in ui/backend_headless.v; and
// constants of backend_custom.c.v and backend_document.v.
//
// OS host services (menus, tray, clipboard, dialogs, window chrome, key
// modifiers, the safe area and the barcode scanner) are not backends:
// platform.v documents them, both modes use them, and their files keep V's
// OS suffixes and plain `$if macos`-style checks.
//
// ## Selection
//
// The first matching row selects the backend. The guards are mutually
// exclusive and together cover every combination of flags and target OS.
//
// | Flags and target                       | Backend  | Whole-file guard |
// |----------------------------------------|----------|------------------|
// | -d ui2_document_library                | document | `$if ui2_document_library ? {` |
// | -d ui2_headless                        | headless | `$if ui2_headless ? && !ui2_document_library ? {` |
// | -os macos                              | appkit   | `$if macos && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {` |
// | -os windows                            | win32    | `$if windows && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {` |
// | -os ios                                | uikit    | `$if ios && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {` |
// | linux, android, or macos, windows and  | custom   | `$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? && !ui2_document_library ? {` |
// | ios with -d ui2_custom_rendering       |          |                  |
// | any other OS                           | none     | compile error from ui/backend_headless.v; build with -d ui2_headless |
//
// The custom renderer has parts with narrower guards of their own:
//
// | Part                                  | Whole-file guard |
// |---------------------------------------|------------------|
// | desktop text and overlays (vglyph)    | `$if (linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? && !ui2_document_library ? {` |
// | mobile Fontstash text, no overlays    | `$if (android || (ios && ui2_custom_rendering ?)) && !ui2_headless ? && !ui2_document_library ? {` |
// | macOS embedder host (-d ui2_embedder) | `$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? && !ui2_document_library ? {` |
//
// The embedder is a host variant of the custom renderer, not a backend of its
// own: on macOS, -d ui2_custom_rendering -d ui2_embedder replaces the sokol
// window with AppKit windows and Metal surfaces the renderer owns
// (platform.v).
//
// Files of each backend:
//
// - document: ui/backend_document.v. Compiled VML documents loaded by a host
//   (the designer preview), which builds the library with its own backend
//   flags. There is no window: calls that need one panic, and the host
//   provides publishing, refreshes and commands. Components and control
//   insets follow the host's backend so the library lays out as it will show.
// - headless: ui/backend_headless.v. In-memory window state that tests drive
//   through the Window's public fields, headless_frame() and headless_key();
//   no OS dialogs.
// - appkit: appkit/. win32: windows/. uikit: uikit/. Each keeps one NSWindow,
//   HWND or UIWindow per Window and registers it with a process host that
//   maps the OS's context-free callbacks back to their Window. Helpers they
//   share, and the native profile below, are in ui/native_controls.v.
// - custom: ui/backend_custom.c.v, the `*_immediate.c.v` files,
//   draw_context.c.v, image_resources.c.v, menu_custom.c.v and
//   linux_idle_linux.c.v; desktop text in text_backend_vglyph.c.v; overlays
//   in overlay_runtime_immediate.c.v (desktop, with a mobile stub); Android
//   and iOS text in ui_text_fontstash.c.v; the embedder in
//   embedder_*_darwin.c.v.
//
// ## Native profile
//
// A native backend shows what its operating system's controls and
// layer-backed boxes can show. Anything else a declaration asks for is a
// validation error that names the custom renderer as the remedy, never a
// presentation dropped in silence: retained overlays, motion and opacity,
// visual transforms, vector canvases and scaled content, drag and drop
// (backend_supports_* constants below), and the native profile of
// validate_native_element and validate_native_style (interaction styles,
// control paint, outlines, dashed and per-side colored borders, typography
// the controls do not take, image fitting). Kit components that have an OS
// counterpart build it in native mode: Button is the platform's push button
// (kit_button.v), the dropdown is NSPopUpButton or its equivalent, and
// Checkbox, Switch, Slider, TextInput, TextArea and ToggleButton are their
// controls. Other kit components are boxes and labels where their
// presentation allows it and a validation error where it does not.
//
// Motion, visual transform and CPU text measurement code is shared
// (motion_runtime.c.v, visual_transform_runtime.c.v, layout_measure_cpu.c.v):
// backends that support the feature call it.
//
// ## What every backend provides
//
// Each backend defines `pub struct Window`, one window and everything that
// belongs to it, and the methods below on it. Nothing about a window is
// process-wide: a backend reaches its window through the receiver, an
// event's window, or the native callback that names it. App (app.v) is
// shared; it asks the backend to open and run its windows.
//
// Application and window:
//   fn (mut app App) open_backend_window(config WindowConfig) !&Window: makes
//     a window that runs with App.run, or fails when the host runs no more
//   fn (mut app App) run_backend(): runs the app's windows until they close
//   fn (mut w Window) on_close(hook fn ()): runs hook as w closes
//   pub fn (mut w Window) quit(): closes w
//   pub fn (mut w Window) bounds() Rect
//   pub fn (mut w Window) safe_area_top() f64
//
// Rebuilds and layout:
//   pub fn (mut w Window) request_refresh(): schedules a rebuild of w on the UI
//     thread; the only way application code asks for one. It returns at once.
//     An offset that scroll_to_offset or scroll_to_horizontal_offset asks for
//     past the current range while a rebuild is pending is taken up again
//     after its layout.
//   pub fn (mut w Window) refresh_element(id string, element Element)
//   fn (mut w Window) refresh_compiled_element(id string, node &CompiledVmlNode, element Element)
//   fn (mut w Window) begin_compiled_snapshot()
//   fn (mut w Window) end_compiled_snapshot()
//   fn (mut w Window) backend_invalidate(reason RenderReason)
//   pub fn (mut w Window) layout_stats() LayoutStats
//   pub fn (mut w Window) invalidate_layout_environment(environment LayoutEnvironment)
//
// Keyboard and input:
//   pub fn (mut w Window) on_key(handler KeyFn)
//   pub fn (mut w Window) on_key_event(handler KeyEventFn)
//   pub fn (mut w Window) consume_key()
//   pub fn (mut w Window) consume_text_key()
//   pub fn (mut w Window) on_drop(handler DropFn)
//   fn (mut w Window) backend_input_dispatch() T, where T has
//     `fn (T) valid() bool`: false once w closed or delivered newer input
//   fn (mut w Window) backend_own_activation(code KeyCode)
//
// Control state:
//   pub fn (mut w Window) text(id string) string
//   pub fn (mut w Window) set_text(id string, value string)
//   pub fn (mut w Window) slider_value(id string) f64
//   pub fn (mut w Window) set_slider_value(id string, value f64)
//   pub fn (mut w Window) switch_active(id string) bool
//   pub fn (mut w Window) set_switch_active(id string, active bool)
//   pub fn (mut w Window) toggle_button_pressed(id string) bool
//   pub fn (mut w Window) set_toggle_button_pressed(id string, pressed bool)
//   pub fn (mut w Window) toggle_button_group_members(id string) []string
//   pub fn (mut w Window) control_checked(id string) bool
//   pub fn (mut w Window) set_control_checked(id string, value bool)
//   pub fn start_barcode_scan(on_result ScanCallback)
//
// Text areas:
//   pub fn (mut w Window) focused_text_area_id() string
//   pub fn (mut w Window) insert_text_area_text(id string, value string)
//   pub fn (mut w Window) text_area_caret(id string) int
//   pub fn (mut w Window) text_area_selection_length(id string) int
//   pub fn (mut w Window) text_area_set_caret(id string, pos int)
//   pub fn (mut w Window) text_area_set_selection(id string, location int, length int)
//
// Scrolling:
//   pub fn (mut w Window) scroll_offset(id string) f64
//   pub fn (mut w Window) scroll_to_offset(id string, offset f64)
//   pub fn (mut w Window) scroll_horizontal_offset(id string) f64
//   pub fn (mut w Window) scroll_to_horizontal_offset(id string, offset f64)
//   pub fn (mut w Window) scroll_to_rect(id string, x f64, y f64, width f64, height f64)
//
// Focus and semantics:
//   pub fn (mut w Window) focus(id string)
//   pub fn (mut w Window) focused_id() string
//   pub fn (mut w Window) dismiss_keyboard()
//   fn (mut w Window) focus_manager() &FocusManager
//   fn (mut w Window) sync_focus_navigation()
//   fn (mut w Window) live_semantic_nodes(nodes []SemanticNode) []SemanticNode
//   fn (mut w Window) activate_semantic_control(id string, action SemanticAction) bool
//
// Presentation:
//   pub fn control_support(kind Kind) BackendSupport
//   pub fn (mut w Window) set_visual_transform(id string, transform VisualTransform) !
//   pub fn (mut w Window) mounted_geometry(id string) !VisualGeometry
//   pub fn (mut w Window) visual_geometry(id string) !VisualGeometry
//   pub fn (mut w Window) drag_active() bool
//   pub fn (mut w Window) cancel_drag()
//   pub fn (mut w Window) image_resource_stats() ImageResourceStats
//
// Text measurement (measure_layout_text and the layout code call these):
//   fn backend_measure_text(text string, style TextStyle, max_width f64) !LayoutSize
//   fn backend_measure_element_text(element Element, content string, max_width f64) !LayoutSize
//   fn backend_control_insets(element Element) ?LayoutPadding
//   fn backend_layout_environment(environment LayoutEnvironment) LayoutEnvironment
//
// Menu bar and status area (menu.v keeps the declarations; the windowed
// backends forward to the host's host_* functions, platform.v):
//   fn backend_menu_bar_supported() bool
//   fn (mut w Window) backend_set_menu_bar(menus []Menu)
//   fn backend_tray_supported() bool
//   fn (mut w Window) backend_set_tray(cfg TrayConfig)
//   fn (mut w Window) backend_remove_tray()
//
// Window chrome (window_chrome.v passes the handle to the host_* functions):
//   fn (w &Window) backend_native_window() voidptr: w's NSWindow or HWND, or
//     nil where the window has none
//
// Operating system dialogs (file_dialog.v and message_box.v call these; the
// windowed backends forward to the host's host_* functions):
//   fn backend_file_dialog(cfg FileDialogConfig) []string
//   fn backend_file_dialog_supported() bool
//   fn backend_message_box(cfg MessageBoxConfig) MessageBoxResult
//   fn backend_message_box_supported() bool
//
// ## Constants every backend defines
//
//   pub const backend_name string: 'document', 'headless', 'appkit',
//     'win32', 'uikit' or 'custom'.
//   pub const backend_supports_overlays bool: retained overlays (with_overlay).
//   pub const backend_supports_motion bool: element opacity and motion.
//   pub const backend_supports_visual_transforms bool: with_transform.
//   pub const backend_supports_vector_canvas bool: vector canvases and scaled
//     content.
//   pub const backend_supports_drag_drop bool: drag sources and drop targets.
//   pub const backend_native_controls bool: controls are the operating
//     system's, so declarations are checked against the native profile.
//   pub const backend_embedder bool: the custom renderer runs in the macOS
//     embedder host instead of a sokol window.
//   pub const backend_needs_host bool: there is no window; refreshes, element
//     updates and control commands go through the host's handlers.
//
// Backend-specific extensions outside the contract exist only on the
// backends named: rich text editing (appkit, custom), set_window_title
// (appkit, win32), render_stats and the embedder's host API (custom).

// AlwaysValidDispatch is the input dispatch token of backends whose input
// callbacks cannot outlive the window that delivered them.
struct AlwaysValidDispatch {}

fn (_ AlwaysValidDispatch) valid() bool {
	return true
}

// refresh_compiled_by_id is how backends without retained layout patches
// apply a compiled document update: refresh the element when it has an id,
// otherwise reconcile the cached document snapshot, which leaves the
// component builder and its state initializers untouched.
fn (mut w Window) refresh_compiled_by_id(id string, element Element) {
	if id.len > 0 {
		w.refresh_element(id, element)
		return
	}
	w.request_refresh()
}
